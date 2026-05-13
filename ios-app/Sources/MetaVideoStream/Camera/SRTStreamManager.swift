import Foundation
import Combine
import AVFoundation
@preconcurrency import HaishinKit
@preconcurrency import SRTHaishinKit
import VideoToolbox

@MainActor
final class SRTStreamManager: ObservableObject {

    @Published var isStreaming = false
    @Published var connectionStatus: String = "Disconnected"

    /// The URL currently in use (set when start(url:) is called).
    private(set) var currentURL: String? = nil

    private let connection = SRTConnection()
    private let stream: SRTStream

    // Background task that polls connection health after publish().
    // NOTE: uses `connection.connected` from HaishinKit 1.9.9.
    // If that property is renamed in a future version, this is the only place to update.
    private var monitorTask: Task<Void, Never>?

    // ── Performance Logging ────────────────────────────────────────────────────
    private var srtFrameCount: Int = 0
    private var lastLogDate: Date = Date()

    init() {
        stream = SRTStream(connection: connection)

        // Configure standard local microphone capture
        stream.attachAudio(AVCaptureDevice.default(for: .audio))

        // Configure SRT video settings — 848x480 (16:9) is the efficiency sweet spot.
        var videoSettings = VideoCodecSettings()
        videoSettings.videoSize = .init(width: 360, height: 640)
        videoSettings.profileLevel = kVTProfileLevel_H264_Main_AutoLevel as String
        videoSettings.bitRate = 1_500_000 // 1.5 Mbps
        videoSettings.maxKeyFrameIntervalDuration = 2  // 2-second GOP for better stability
        stream.videoSettings = videoSettings
    }

    // MARK: - Start / Stop

    /// Start publishing to the given SRT URL.
    func start(url: String) async {
        let urlWithLatency = url + (url.contains("?") ? "&" : "?") + "latency=200000"
        guard let srtURL = URL(string: urlWithLatency) else { return }
        currentURL = url
        connectionStatus = "Connecting…"
        do {
            try await connection.open(srtURL)
            connectionStatus = "Live"
            isStreaming = true
            stream.videoSettings.isHardwareEncoderEnabled = true
            stream.publish()
            startConnectionMonitor()
        } catch {
            connectionStatus = "Failed: \(error.localizedDescription)"
            isStreaming = false
        }
    }

    func stop() async {
        monitorTask?.cancel()
        monitorTask = nil
        await connection.close()
        isStreaming = false
        connectionStatus = "Disconnected"
        currentURL = nil
    }

    // MARK: - Reconnect

    /// Re-establishes the SRT layer without touching the glasses session.
    ///
    /// Called by WearablesManager's reconnect loop. Throws if the connection
    /// cannot be re-opened (e.g. OBS is not running).
    func reconnect(url: String) async throws {
        monitorTask?.cancel()
        monitorTask = nil

        // Close the old connection cleanly before reopening.
        await connection.close()

        let urlWithLatency = url + (url.contains("?") ? "&" : "?") + "latency=200000"
        guard let srtURL = URL(string: urlWithLatency) else { return }
        connectionStatus = "Reconnecting…"
        isStreaming = false

        // Throws SRTError if OBS isn't listening — caller handles the backoff.
        try await connection.open(srtURL)
        stream.publish()
        currentURL = url
        connectionStatus = "Live"
        isStreaming = true
        startConnectionMonitor()
    }

    // MARK: - Connection monitor

    /// Polls `connection.connected` every 2 seconds. Sets `isStreaming = false`
    /// if the connection has dropped, which the WearablesManager Combine observer
    /// picks up to trigger the reconnect loop.
    private func startConnectionMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 s
                guard !Task.isCancelled, let self else { break }
                if !self.connection.connected {
                    self.isStreaming = false
                    self.connectionStatus = "Disconnected"
                    break
                }
            }
        }
    }

    // MARK: - Video quality

    /// Adjust the encoding bitrate on the fly.
    /// Safe to call while streaming; HaishinKit applies the change to the next keyframe interval.
    func adjustBitrate(_ bitsPerSecond: Int) {
        var settings = stream.videoSettings
        settings.bitRate = bitsPerSecond
        stream.videoSettings = settings
    }

    /// Drop encoding quality to shed thermal load:
    /// 500 kbps bitrate + tighter 3-second GOP for fewer encoder pressure spikes.
    /// Called by WearablesManager when `thermalState == .serious`.
    func reduceThermalLoad() {
        var settings = stream.videoSettings
        settings.bitRate = 500_000
        settings.maxKeyFrameIntervalDuration = 3
        stream.videoSettings = settings
    }

    /// Restore full encoding quality after the thermal state has cleared.
    /// Called by WearablesManager when `thermalState` returns to `.nominal` or `.fair`.
    func restoreDefaultQuality() {
        var settings = stream.videoSettings
        settings.bitRate = 1_000_000
        settings.maxKeyFrameIntervalDuration = 1
        stream.videoSettings = settings
    }

    // MARK: - Video input

    /// Append a CoreMedia sample buffer directly into the HaishinKit encoding pipeline.
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        if srtFrameCount == 0, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            print("📹 [SRT] First frame received: \(dims.width)x\(dims.height)")
        }
        stream.append(sampleBuffer)
        srtFrameCount &+= 1

        // Log SRT performance every 150 frames
        if srtFrameCount % 150 == 0 {
            let now = Date()
            let duration = now.timeIntervalSince(lastLogDate)
            let srtFps = Double(150) / duration
            print("🚀 [SRT] Output FPS: \(String(format: "%.1f", srtFps)) | Bitrate: \(stream.videoSettings.bitRate / 1000) kbps")
            lastLogDate = now
        }
    }
}
