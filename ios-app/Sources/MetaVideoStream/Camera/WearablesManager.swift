import Foundation
import UIKit
import SwiftUI
import Combine
import MWDATCore
import MWDATCamera

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
    private var streamSession: StreamSession?

    private var stateToken: (any AnyListenerToken)?
    private var frameToken: (any AnyListenerToken)?

    // NDI stream manager — ContentView must not read this directly.
    let ndi: NDIStreamManager

    private let deviceSelector: AutoDeviceSelector

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
        guard appState.allowsConnect else { return }
        if isRegistered {
            await startStream()
        } else {
            await registerThenStream()
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

    // MARK: - Registration

    private func registerThenStream() async {
        appState = .registering
        do {
            try await wearables.startRegistration()
            try await waitForRegistration()
            await startStream()
        } catch {
            appState = .error("Registration failed: \(error.localizedDescription)")
        }
    }

    private func waitForRegistration() async throws {
        let deadline = Date().addingTimeInterval(10)
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

    // MARK: - Stream flow

    private func startStream() async {
        appState = .awaitingPermission
        do {
            try await ensureCameraPermission()
            appState = .connecting(streamName: "NDI")

            let session = try wearables.createSession(deviceSelector: deviceSelector)
            deviceSession = session
            let stateStream = session.stateStream()
            try session.start()

            for await sessionState in stateStream {
                if sessionState == .started { break }
                if sessionState == .stopped { throw WearablesError.sessionFailed }
            }

            let config = StreamSessionConfig(videoCodec: .raw, resolution: .low, frameRate: 30)
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

    private func handleSDKStreamState(_ state: StreamSessionState) {
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
        if let session = deviceSession { session.stop() }
        stateToken = nil
        frameToken = nil
        streamSession = nil
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
