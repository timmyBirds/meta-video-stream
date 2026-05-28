import Foundation
import UIKit
import SwiftUI
import Combine
import MWDATCore
import MWDATCamera
import MWDATDisplay
import CoreBluetooth

// MARK: - WearablesManager

/// Manages the full Meta Wearables SDK lifecycle.
///
/// All connection state is exposed through a single `appState: AppState` property.
/// Thermal and battery health are exposed as separate `thermalWarning` and
/// `batteryWarning` properties so ContentView can layer banners/alerts independently.
///
/// Public API:
///   connect()            — full flow: register → permission → NDI
///   disconnect()                — tears down everything; moves to .stopped
///   resumeAfterThermalPause()   — restarts SRT after a .critical thermal pause
///   stopForBattery()            — user-confirmed stop from battery critical alert
@MainActor
final class WearablesManager: ObservableObject {

    // ── Single source of truth ─────────────────────────────────────────────────
    @Published private(set) var appState: AppState = .idle

    /// Decoded frame for the camera preview.
    @Published var currentFrame: UIImage? = nil

    /// Name/ID of the currently paired glasses device.
    @Published var connectedDeviceName: String? = nil

    // ── Health overlays (independent of appState) ──────────────────────────────
    @Published private(set) var thermalWarning: ThermalWarning = .none
    @Published private(set) var batteryWarning: BatteryWarning = .none
    /// True when frame delivery from the glasses has stalled >5 s — soft overheat hint.
    @Published private(set) var glassesOverheatHint: Bool = false

    // ── Private SDK objects ────────────────────────────────────────────────────
    private var deviceSession: DeviceSession?
    private var streamSession: MWDATCamera.Stream?
    private var display: MWDATDisplay.Display?

    private var stateToken: (any AnyListenerToken)?
    private var frameToken: (any AnyListenerToken)?
    private var displayStateToken: (any AnyListenerToken)?

    // NDI stream manager — ContentView must not read this directly.
    let ndi: NDIStreamManager

    private let deviceSelector: AutoDeviceSelector
    private let bluetoothMonitor = BluetoothMonitor()

    // ── Background tasks ───────────────────────────────────────────────────────
    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    private var activeDeviceTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var frameStallTask: Task<Void, Never>?

    // ── Combine subscriptions ──────────────────────────────────────────────────
    private var ndiCancellable: AnyCancellable?

    // ── System notification observers ─────────────────────────────────────────
    // nonisolated(unsafe) lets deinit (which is nonisolated) remove the observers
    // without a Swift 6 concurrency violation. These are written once on the main
    // actor during init and read once in deinit, so the access is safe in practice.
    nonisolated(unsafe) private var thermalObserver: NSObjectProtocol?
    nonisolated(unsafe) private var batteryObserver: NSObjectProtocol?

    // ── Wearables SDK ─────────────────────────────────────────────────────────
    private var wearables: WearablesInterface { Wearables.shared }
    private var isRegistered: Bool = false

    // ── Thermal pause state ────────────────────────────────────────────────
    /// When true, the SRT connection was stopped deliberately (thermal critical).
    /// The SRT observer skips reconnect while this flag is set.
    /// The paused URL is stored in `appState` (.paused(srtURL:)), not separately.
    private var streamingPausedIntentionally = false

    // ── Thermal frame throttle ─────────────────────────────────────────────────
    /// Pass 1-in-N frames to the SRT encoder. 1 = all frames, 2 = every other, etc.
    private var thermalFrameDropRatio: Int = 1
    private var frameCounter: Int = 0

    // ── Glasses thermal proxy ──────────────────────────────────────────────────
    private var lastFrameDate: Date? = nil

    // ── Performance Logging ────────────────────────────────────────────────────
    private var sdkFrameCount: Int = 0
    private var ndiFrameCount: Int = 0
    private var lastLogDate: Date = Date()

    // MARK: - Debug Logger
    private func logDebug(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        print("🔍 [DEBUG] [\(timestamp)] \(message)")
    }

    // MARK: - Init / deinit

    init() {
        self.deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
        self.ndi = NDIStreamManager()
        startObservingRegistration()
        startObservingDevices()
        startObservingActiveDevice()
        startObservingNDI()
        startThermalMonitoring()
        startBatteryMonitoring()
    }

    deinit {
        registrationTask?.cancel()
        devicesTask?.cancel()
        activeDeviceTask?.cancel()
        reconnectTask?.cancel()
        frameStallTask?.cancel()
        if let obs = thermalObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = batteryObserver { NotificationCenter.default.removeObserver(obs) }
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    // MARK: - Public API

    func connect() async {
        logDebug("Connect button clicked. Current appState: \(appState)")
        guard appState.allowsConnect else {
            logDebug("Connect not allowed in current appState.")
            return
        }
        
        logDebug("Awaiting Bluetooth central manager power status...")
        await bluetoothMonitor.waitUntilPoweredOn()
        logDebug("Bluetooth Central Manager powered on.")
        
        logDebug("Checking registration status (isRegistered: \(isRegistered))")
        if isRegistered {
            await startDeviceSession()
        } else {
            logDebug("Device is not registered. Initiating registration flow...")
            await registerThenConnect()
        }
    }

    func disconnect() async {
        await teardown(nextState: .stopped)
    }

    /// Restart SRT after a thermal-critical pause. Valid any time `appState.isPaused`.
    /// Transitions through `.connecting` so the SRT observer resumes normal state tracking.
    func resumeAfterThermalPause() async {
        guard appState.isPaused else { return }
        // Throttle at .serious while the phone continues to cool.
        thermalWarning = .serious
        thermalFrameDropRatio = 2
        streamingPausedIntentionally = false
        appState = .connecting(streamName: "NDI")
        ndi.start()
    }

    /// User-confirmed stop triggered by the battery-critical alert.
    func stopForBattery() async {
        await disconnect()
    }

    /// Pushes a video player layout to the glasses' display.
    func playVideoOnGlasses(url: String) async throws {
        guard let display = display else {
            throw NSError(
                domain: "WearablesManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Display capability is not active or not supported on this device."]
            )
        }
        let videoPlayer = VideoPlayer(provider: .uri(url), codec: .mp4)
        try await display.send(videoPlayer)
    }

    // MARK: - Registration

    private func registerThenConnect() async {
        logDebug("registerThenConnect() invoked. Changing state to .registering")
        appState = .registering
        do {
            logDebug("Calling wearables.startRegistration()...")
            try await wearables.startRegistration()
            logDebug("wearables.startRegistration() completed. Waiting for registration...")
            try await waitForRegistration()
            logDebug("waitForRegistration() completed. Starting device session...")
            await startDeviceSession()
        } catch {
            logDebug("Error caught in registerThenConnect(): \(error.localizedDescription)")
            appState = .error("Registration failed: \(error.localizedDescription)")
        }
    }

    private func waitForRegistration() async throws {
        let deadline = Date().addingTimeInterval(60) // 60 seconds to allow user to complete Meta AI app registration
        while !isRegistered, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard isRegistered else { throw WearablesError.registrationTimedOut }
    }

    private func startObservingRegistration() {
        registrationTask = Task { [weak self] in
            guard let self else { return }
            for await state in wearables.registrationStateStream() {
                await MainActor.run {
                    switch state {
                    case .registered:
                        self.isRegistered = true
                    default:
                        self.isRegistered = false
                        if case .registering = self.appState { /* leave it */ }
                        else if !self.appState.isActive { self.appState = .idle }
                    }
                }
            }
        }
    }

    // MARK: - Session & Features flow

    private func startDeviceSession() async {
        logDebug("startDeviceSession() invoked. Changing state to .awaitingPermission")
        appState = .awaitingPermission
        do {
            logDebug("Checking and ensuring camera permission...")
            try await ensureCameraPermission()
            logDebug("Camera permission checked/granted.")

            logDebug("Creating session using deviceSelector...")
            let session = try wearables.createSession(deviceSelector: deviceSelector)
            deviceSession = session
            let stateStream = session.stateStream()
            
            logDebug("Starting session...")
            try session.start()
            logDebug("Session start command completed. Awaiting stateStream .started...")

            for await sessionState in stateStream {
                logDebug("stateStream received sessionState: \(sessionState)")
                if sessionState == .started {
                    logDebug("Session successfully reached .started state.")
                    break
                }
                if sessionState == .stopped {
                    logDebug("Session reached unexpected state: .stopped")
                    throw WearablesError.sessionFailed
                }
            }

            logDebug("Attaching display capability to session...")
            let displayCap = try session.addDisplay()
            
            logDebug("Starting display capability...")
            await displayCap.start()
            self.display = displayCap
            logDebug("Display capability start command finished. Awaiting displayCap.state to become .started...")

            // Wait for display state to become .started
            var count = 0
            while displayCap.state != .started && count < 50 {
                logDebug("Waiting for display... Attempt \(count + 1)/50. Current displayCap.state: \(displayCap.state)")
                try await Task.sleep(nanoseconds: 100_000_000)
                count += 1
            }

            logDebug("Finished waiting. Final displayCap.state: \(displayCap.state)")
            if displayCap.state == .started {
                logDebug("Display capability successfully reached .started. Sending ConnectedStandbyView...")
                await sendConnectedStandbyView()
                logDebug("ConnectedStandbyView sent. Setting appState to .connected.")
                appState = .connected
            } else {
                logDebug("Display capability failed to start. Current displayCap.state is \(displayCap.state)")
                throw NSError(
                    domain: "WearablesManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Display capability failed to start. State: \(displayCap.state)"]
                )
            }
        } catch {
            logDebug("Error caught in startDeviceSession(): \(error.localizedDescription) (Raw: \(error))")
            appState = .error(error.localizedDescription)
            await teardown(nextState: appState)
        }
    }

    func startStreaming() async {
        guard appState == .connected else { return }
        appState = .connecting(streamName: "NDI")
        do {
            guard let session = deviceSession else {
                throw NSError(domain: "WearablesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active device session."])
            }

            let config = StreamConfiguration(videoCodec: .raw, resolution: .low, frameRate: 30)
            guard let stream = try? session.addStream(config: config) else {
                throw WearablesError.streamCreationFailed
            }
            streamSession = stream

            stateToken = stream.statePublisher.listen { [weak self] state in
                Task { @MainActor [weak self] in self?.handleSDKStreamState(state) }
            }

            frameToken = stream.videoFramePublisher.listen { [weak self] frame in
                let buffer = frame.sampleBuffer
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let now = Date()
                    self.lastFrameDate = now
                    self.frameCounter &+= 1
                    self.sdkFrameCount &+= 1

                    if self.frameCounter % self.thermalFrameDropRatio == 0 {
                        self.ndiFrameCount &+= 1
                        self.ndi.appendVideo(buffer)
                    }

                    // Log performance every 150 frames (~5 seconds at 30fps)
                    if self.sdkFrameCount % 150 == 0 {
                        let duration = now.timeIntervalSince(self.lastLogDate)
                        let sdkFps = Double(150) / duration
                        let thermal = ProcessInfo.processInfo.thermalState
                        print("📊 [Wearables] SDK FPS: \(String(format: "%.1f", sdkFps)) | Thermal: \(thermal.rawValue) | DropRatio: \(self.thermalFrameDropRatio)")
                        self.lastLogDate = now
                    }
                }
                guard let image = frame.makeUIImage() else { return }
                Task { @MainActor [weak self] in self?.currentFrame = image }
            }

            await stream.start()
            ndi.start()
            startFrameStallMonitor()
        } catch {
            appState = .error(error.localizedDescription)
            await teardown(nextState: appState)
        }
    }

    func stopStreaming() async {
        switch appState {
        case .streaming, .connecting:
            break
        default:
            return
        }
        
        frameStallTask?.cancel()
        frameStallTask = nil

        if let stream = streamSession { await stream.stop() }
        stateToken = nil
        frameToken = nil
        streamSession = nil
        currentFrame = nil
        lastFrameDate = nil
        ndi.stop()

        await sendConnectedStandbyView()
        appState = .connected
    }

    func startWatchingVideo(url: String) async {
        guard appState == .connected else { return }
        appState = .watchingVideo
        do {
            guard let displayCap = display else {
                throw NSError(domain: "WearablesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Display capability not active."])
            }

            // 1. Send loading/wake view to the glasses screen to make sure it wakes up
            let loadingView = FlexBox(direction: .column, spacing: 16, alignment: .center, crossAlignment: .center, padding: EdgeInsets(all: 16)) {
                Icon(name: .videoCamera, style: .filled)
                Text("Starting Video...", style: .body)
            }
            try? await displayCap.send(loadingView)

            // 2. Wait 300ms for screen to wake up and process visual layout
            try? await Task.sleep(nanoseconds: 300_000_000)

            // 3. Send video player
            print("📺 [Wearables] Sending video player layout to glasses...")
            let videoPlayer = VideoPlayer(provider: .uri(url), codec: .mp4)
            try await displayCap.send(videoPlayer)
        } catch {
            appState = .error("Failed to start video: \(error.localizedDescription)")
            await teardown(nextState: appState)
        }
    }

    func stopWatchingVideo() async {
        guard case .watchingVideo = appState else { return }
        if let displayCap = display {
            await displayCap.sendVideoStop()
            await sendConnectedStandbyView()
        }
        appState = .connected
    }

    private func sendConnectedStandbyView() async {
        guard let display = display, display.state == .started else { return }
        let view = FlexBox(direction: .column, spacing: 16, alignment: .center, crossAlignment: .center, padding: EdgeInsets(all: 16)) {
            Icon(name: .smartGlasses, style: .filled)
            Text("Connected", style: .heading)
            Text("Select a mode on your phone", style: .body, color: .secondary)
        }
        try? await display.send(view)
    }

    // MARK: - NDI observation
    private func startObservingNDI() {
        ndiCancellable = ndi.$isStreaming
            .receive(on: RunLoop.main)
            .sink { [weak self] isNDIStreaming in
                guard let self else { return }
                switch self.appState {
                case .connecting:
                    if isNDIStreaming { self.appState = .streaming(streamName: "NDI") }
                default:
                    break
                }
            }
    }



    // MARK: - SDK stream state

    private func handleSDKStreamState(_ state: StreamState) {
        switch state {
        case .stopped: currentFrame = nil
        default: break
        }
    }

    // MARK: - Thermal monitoring

    private func startThermalMonitoring() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleThermalChange()
            }
        }
        handleThermalChange()
    }

    private func handleThermalChange() {
        let active = appState.isActive
        let paused = appState.isPaused
        guard active || paused else { return }

        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair:
            guard thermalWarning != .none else { return }
            thermalWarning = .none
            thermalFrameDropRatio = 1
            // Only touch SRT settings while actually streaming (not while paused).
            if active { /* NDI handles quality automatically */ }

        case .serious:
            guard thermalWarning != .serious else { return }
            thermalWarning = .serious
            thermalFrameDropRatio = 2   // drop every other frame to the encoder
            if active { /* NDI handles thermal load by dropping frames naturally */ }
            // If device cooled from critical → serious while we were paused, the
            // thermal modal will auto-dismiss (thermalWarning is no longer .critical).
            // The user sees Resume / Stop controls — no auto-resume.

        case .critical:
            guard thermalWarning != .critical else { return }
            thermalWarning = .critical
            // Pause SRT only — glasses session stays alive.
            // Transition to .paused so the state machine owns the URL.
            if case .streaming = appState {
                streamingPausedIntentionally = true
                appState = .paused(streamName: "NDI")
                self.ndi.stop()
            }

        @unknown default:
            break
        }
    }

    // MARK: - Battery monitoring

    private func startBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleBatteryChange()
            }
        }
        handleBatteryChange()
    }

    private func handleBatteryChange() {
        guard appState.isActive else { return }
        let level = UIDevice.current.batteryLevel // -1.0 if monitoring not yet active
        guard level >= 0 else { return }
        switch level {
        case ..<0.10: batteryWarning = .critical
        case ..<0.20: batteryWarning = .low
        default:      batteryWarning = .none
        }
    }

    // MARK: - Glasses thermal proxy (frame-stall detection)

    private func startFrameStallMonitor() {
        frameStallTask?.cancel()
        frameStallTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // check every 5 s
                guard !Task.isCancelled, let self else { break }
                guard case .streaming = self.appState else {
                    self.glassesOverheatHint = false
                    continue
                }
                let stalled = self.lastFrameDate.map {
                    Date().timeIntervalSince($0) > 5.0
                } ?? false
                self.glassesOverheatHint = stalled
            }
        }
    }

    // MARK: - Camera permission

    private func ensureCameraPermission() async throws {
        let status = try await wearables.checkPermissionStatus(.camera)
        if status == .granted { return }
        let requested = try await wearables.requestPermission(.camera)
        guard requested == .granted else { throw WearablesError.permissionDenied }
    }

    // MARK: - Teardown

    private func teardown(nextState: AppState) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        frameStallTask?.cancel()
        frameStallTask = nil

        if let stream = streamSession { await stream.stop() }
        if let displayCap = display { await displayCap.stop() }
        if let session = deviceSession { session.stop() }
        stateToken = nil
        frameToken = nil
        displayStateToken = nil
        streamSession = nil
        display = nil
        deviceSession = nil
        currentFrame = nil
        lastFrameDate = nil
        ndi.stop()

        // Reset health overlays
        thermalWarning = .none
        batteryWarning = .none
        glassesOverheatHint = false
        streamingPausedIntentionally = false
        thermalFrameDropRatio = 1
        frameCounter = 0

        appState = nextState
    }

    // MARK: - Device observation

    private func startObservingDevices() {
        devicesTask = Task { [weak self] in
            guard let self else { return }
            for await devices in wearables.devicesStream() {
                await MainActor.run { self.connectedDeviceName = devices.first }
            }
        }
    }

    private func startObservingActiveDevice() {
        activeDeviceTask = Task { [weak self] in
            guard let self else { return }
            for await _ in deviceSelector.activeDeviceStream() { }
        }
    }
}

// MARK: - Errors

enum WearablesError: LocalizedError {
    case permissionDenied
    case sessionFailed
    case streamCreationFailed
    case registrationTimedOut

    var errorDescription: String? {
        switch self {
        case .permissionDenied:     return "Camera permission was denied. Grant it in the Meta AI app."
        case .sessionFailed:        return "Device session failed to start."
        case .streamCreationFailed: return "Could not create a camera stream."
        case .registrationTimedOut: return "Registration timed out. Make sure the Meta AI app is installed."
        }
    }
}

// MARK: - Bluetooth Monitor

@MainActor
final class BluetoothMonitor: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager?
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Required protocol method. The state is updated on CB's internal queue
        // and KVO-observed, so we can poll the central manager's state.
    }
    
    func waitUntilPoweredOn() async {
        guard let manager = centralManager else { return }
        if manager.state == .poweredOn { return }
        if manager.state == .poweredOff || manager.state == .unauthorized || manager.state == .unsupported {
            return
        }
        
        // Wait up to 2 seconds (20 iterations * 100ms) for CoreBluetooth to power on
        for _ in 0..<20 {
            if manager.state == .poweredOn {
                print("🔵 [CoreBluetooth] Central Manager is powered on and ready.")
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        print("⚠️ [CoreBluetooth] Timed out waiting for powered on state. Current state: \(manager.state.rawValue)")
    }
}
