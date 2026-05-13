import Foundation
import CoreMedia
import VideoToolbox
import CoreImage

/// Manages a high-performance NDI (Network Device Interface) stream over the USB-tethered connection.
class NDIStreamManager: ObservableObject {
    private var sendInstance: NDIlib_send_instance_t?
    
    @Published var isStreaming = false
    @Published var connectionStatus = "Ready"
    
    private var frameCount: Int = 0
    private var lastLogDate = Date()
    
    init() {
        // Initialize the NDI library
        if !NDIlib_initialize() {
            print("❌ [NDI] Failed to initialize NDI library")
            connectionStatus = "Init Failed"
        }
    }
    
    deinit {
        stop()
    }
    
    func start(sourceName: String = "Meta Glasses") {
        print("🚀 [NDI] Starting stream: \(sourceName)")
        
        var sendSettings = NDIlib_send_create_t(
            p_ndi_name: (sourceName as NSString).utf8String,
            p_groups: nil,
            clock_video: true,
            clock_audio: false
        )
        
        sendInstance = NDIlib_send_create(&sendSettings)
        
        if sendInstance != nil {
            isStreaming = true
            connectionStatus = "Streaming: \(sourceName)"
            print("✅ [NDI] Stream is live and discoverable on Mac")
        } else {
            connectionStatus = "Start Failed"
            print("❌ [NDI] Failed to create NDI send instance")
        }
    }
    
    func stop() {
        if let instance = sendInstance {
            NDIlib_send_destroy(instance)
            sendInstance = nil
        }
        isStreaming = false
        connectionStatus = "Disconnected"
        print("🛑 [NDI] Stream stopped")
    }
    
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var bgraPixelBuffer: CVPixelBuffer?
    
    /// Sends a video frame from the glasses directly into the NDI pipeline.
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let instance = sendInstance else { return }
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        
        // Ensure we have a destination buffer for the BGRA conversion
        if bgraPixelBuffer == nil {
            let attrs = [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
            ] as [CFString: Any]
            
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &bgraPixelBuffer)
        }
        
        guard let targetBuffer = bgraPixelBuffer else { return }
        
        // Convert YUV/NV12 to BGRA using Core Image (GPU accelerated)
        let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
        context.render(ciImage, to: targetBuffer)
        
        CVPixelBufferLockBaseAddress(targetBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(targetBuffer, .readOnly) }
        
        let stride = CVPixelBufferGetBytesPerRow(targetBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(targetBuffer)
        
        // Map BGRA PixelBuffer to NDI Video Frame
        var videoFrame = NDIlib_video_frame_v2_t()
        videoFrame.xres = Int32(width)
        videoFrame.yres = Int32(height)
        videoFrame.FourCC = NDIlib_FourCC_video_type_BGRA
        videoFrame.line_stride_in_bytes = Int32(stride)
        videoFrame.p_data = baseAddress?.assumingMemoryBound(to: UInt8.self)
        
        // Push frame to NDI
        NDIlib_send_send_video_v2(instance, &videoFrame)
        
        frameCount += 1
        if Date().timeIntervalSince(lastLogDate) >= 5.0 {
            let fps = Double(frameCount) / 5.0
            print("📤 [NDI] Sending: \(width)x\(height) | \(String(format: "%.1f", fps)) FPS")
            frameCount = 0
            lastLogDate = Date()
        }
    }
}
