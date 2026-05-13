import SwiftUI

/// Renders a single decoded glasses camera frame, filling the available space
/// while preserving the glasses camera's 9:16 aspect ratio.
struct CameraPreviewView: View {

    let image: UIImage

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(overlayBadge, alignment: .bottomTrailing)
        }
    }

    /// Small "LIVE" badge so it's obvious the feed is real-time.
    private var overlayBadge: some View {
        Text("LIVE")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.red, in: Capsule())
            .padding(12)
    }
}

#Preview {
    CameraPreviewView(image: UIImage(systemName: "camera.fill")!)
        .frame(height: 400)
        .background(Color.black)
}
