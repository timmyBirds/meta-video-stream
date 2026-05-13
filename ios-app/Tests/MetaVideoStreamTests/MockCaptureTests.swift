import XCTest
import MWDATCore
import MWDATCamera
import MWDATMockDevice

/// Phase 1 exit criterion tests using the Mock Device Kit.
///
/// These run entirely without physical glasses — they validate that the SDK
/// integration plumbing works end-to-end: pair mock device → grant permission →
/// create session → receive video frames.
final class MockCaptureTests: XCTestCase {

    private var mockDevice: MockRaybanMeta?

    // MARK: - Setup / teardown

    override func setUp() async throws {
        try await super.setUp()

        // configure() must run on the main actor, same as App.init().
        // Ignore "already configured" errors on repeated test runs.
        try await MainActor.run {
            do { try Wearables.configure() }
            catch { print("Wearables.configure: \(error)") }
        }

        // Pair a mock Ray-Ban Meta device (no hardware needed)
        mockDevice = await MainActor.run { MockDeviceKit.shared.pairRaybanMeta() }
        XCTAssertNotNil(mockDevice, "Failed to pair mock device — is MockDeviceKit available?")
    }

    override func tearDown() async throws {
        await MainActor.run {
            MockDeviceKit.shared.pairedDevices.forEach { device in
                MockDeviceKit.shared.unpairDevice(device)
            }
        }
        mockDevice = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Verify the mock device appears in devicesStream after pairing.
    func testMockDeviceAppearsInStream() async throws {
        let devices = try await firstValue(from: Wearables.shared.devicesStream())
        XCTAssertFalse(devices.isEmpty, "Expected at least one mock device")
    }

    /// Verify camera permission can be granted on the mock device.
    func testCameraPermissionCanBeGranted() async throws {
        let status = try await Wearables.shared.requestPermission(.camera)
        XCTAssertEqual(status, .granted)
    }

    /// Full end-to-end: create a session, add a stream, receive at least one frame.
    ///
    /// This is the Phase 1 exit criterion expressed as an automated test.
    func testReceivesVideoFramesFromMockDevice() async throws {
        // Grant camera permission
        let permStatus = try await Wearables.shared.requestPermission(.camera)
        XCTAssertEqual(permStatus, .granted, "Camera permission must be granted")

        // Create session
        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        let session = try Wearables.shared.createSession(deviceSelector: selector)
        let stateStream = session.stateStream()
        try session.start()

        // Wait for session to start (5s timeout)
        var sessionStarted = false
        for await state in stateStream {
            if state == .started { sessionStarted = true; break }
            if state == .stopped { break }
        }
        XCTAssertTrue(sessionStarted, "Device session did not reach .started")

        // Add stream
        let config = StreamSessionConfig(videoCodec: .raw, resolution: .low, frameRate: 24)
        guard let stream = try? session.addStream(config: config) else {
            XCTFail("Could not create stream"); return
        }

        // Collect the first frame (10s timeout)
        let frameExpectation = XCTestExpectation(description: "Received first video frame")
        let token = stream.videoFramePublisher.listen { frame in
            if frame.makeUIImage() != nil {
                frameExpectation.fulfill()
            }
        }
        defer { _ = token } // keep token alive

        await stream.start()
        await fulfillment(of: [frameExpectation], timeout: 10)
    }

    // MARK: - Helpers

    /// Pulls the first value emitted by an AsyncSequence, with a 5s timeout.
    private func firstValue<S: AsyncSequence & Sendable>(from sequence: S) async throws -> S.Element
        where S.Element: Sendable
    {
        try await withThrowingTaskGroup(of: S.Element.self) { group in
            group.addTask {
                for try await value in sequence { return value }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw XCTestError(.timeoutWhileWaiting)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
