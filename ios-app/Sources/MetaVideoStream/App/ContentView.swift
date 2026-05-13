import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var wearables: WearablesManager
    @AppStorage("streamUrl") private var streamUrl: String = "srt://192.168.1.X:10000"

    /// Tracks whether the user dismissed the battery-critical alert with "Keep Going".
    /// Resets when the stream ends and batteryWarning drops back to .none.
    @State private var batteryAlertDismissed = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Camera preview ─────────────────────────────────────────
                cameraPreviewArea

                // ── Control strip ──────────────────────────────────────────
                controlStrip
                    .padding(.vertical, 24)
                    .padding(.horizontal, 20)
                    .background(Color(white: 0.08))
            }

            // ── Warning banners (slide in from top) ────────────────────────
            warningBannerStack
                .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        // ── Error alert ────────────────────────────────────────────────────
        .alert(
            "Error",
            isPresented: .constant(wearables.appState.errorMessage != nil),
            actions: {
                Button("Dismiss") {
                    Task { await wearables.disconnect() }
                }
            },
            message: {
                Text(wearables.appState.errorMessage ?? "")
            }
        )
        // ── Thermal critical modal ─────────────────────────────────────────
        // Non-dismissible: user must explicitly Resume or Stop.
        .alert(
            "Stream Paused — Device Overheating",
            isPresented: .constant(wearables.thermalWarning == .critical),
            actions: {
                Button("Resume") {
                    Task { await wearables.resumeAfterThermalPause() }
                }
                Button("Stop Stream", role: .destructive) {
                    Task { await wearables.disconnect() }
                }
            },
            message: {
                Text("The stream was paused to protect your device. Wait for it to cool down, then tap Resume.")
            }
        )
        // ── Battery critical alert ─────────────────────────────────────────
        .alert(
            "Battery Critical",
            isPresented: Binding(
                get: { wearables.batteryWarning == .critical && !batteryAlertDismissed },
                set: { _ in }
            ),
            actions: {
                Button("Stop Streaming", role: .destructive) {
                    Task { await wearables.stopForBattery() }
                }
                Button("Keep Going") {
                    batteryAlertDismissed = true
                }
            },
            message: {
                Text("Battery is below 10%. Stop streaming to protect your device.")
            }
        )
        // Reset "Keep Going" flag when the stream ends and battery warning clears.
        .onChange(of: wearables.batteryWarning) { newValue in
            if newValue == .none { batteryAlertDismissed = false }
        }
    }

    // MARK: - Warning banners

    @ViewBuilder
    private var warningBannerStack: some View {
        VStack(spacing: 4) {
            if wearables.thermalWarning == .serious {
                warningBanner(
                    systemImage: "thermometer.medium",
                    message: "Device is hot — bitrate reduced",
                    color: .orange
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if wearables.batteryWarning == .low {
                warningBanner(
                    systemImage: "battery.25percent",
                    message: "Battery below 20% — plug in soon",
                    color: .yellow
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if wearables.glassesOverheatHint {
                warningBanner(
                    systemImage: "eyeglasses",
                    message: "Glasses may be warm — frame rate may drop",
                    color: .orange.opacity(0.8)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: wearables.thermalWarning)
        .animation(.easeInOut(duration: 0.3), value: wearables.batteryWarning)
        .animation(.easeInOut(duration: 0.3), value: wearables.glassesOverheatHint)
    }

    private func warningBanner(systemImage: String, message: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            color.opacity(0.18)
                .background(.ultraThinMaterial)
        )
    }

    // MARK: - Subviews

    private var cameraPreviewArea: some View {
        Group {
            if let frame = wearables.currentFrame {
                CameraPreviewView(image: frame)
            } else {
                placeholderPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderPreview: some View {
        VStack(spacing: 16) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.3))
            Text(placeholderMessage)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var placeholderMessage: String {
        switch wearables.appState {
        case .idle:
            return "Tap Connect to start the NDI stream over USB."
        case .registering:
            return "Opening Meta AI app to complete registration…"
        case .awaitingPermission:
            return "Waiting for camera permission from the Meta AI app…"
        case .connecting(let name):
            return "Starting NDI: \(name)…"
        case .streaming:
            return "Starting stream…"
        case .paused:
            return "Stream paused due to overheating. Tap Resume when ready."
        case .reconnecting(let n, _):
            return "Reconnecting (\(n))…"
        case .error(let msg):
            return msg
        case .stopped:
            return "Stream stopped. Tap Connect to start again."
        }
    }

    private var controlStrip: some View {
        VStack(spacing: 16) {
            // ── Status badge row ───────────────────────────────────────────
            HStack {
                statusBadge(
                    label: wearables.appState.displayLabel,
                    color: wearables.appState.badgeColor
                )
                Spacer()
                // Device name when paired
                if let deviceName = wearables.connectedDeviceName {
                    HStack(spacing: 4) {
                        Image(systemName: "eyeglasses")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(deviceName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            // ── SRT URL field (editable when idle/stopped, read-only when active) ──
            srtURLRow

            // ── Main action button(s) ──────────────────────────────────────
            actionButton
        }
    }

    @ViewBuilder
    private var srtURLRow: some View {
        if let activeName = wearables.appState.streamName {
            // Show the URL in use when connecting / streaming / paused / reconnecting
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(activeName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        } else {
            // Editable when idle / stopped / error
            // NDI is automatic over USB
            Text("USB Connection Ready")
                .font(.caption.monospaced())
                .foregroundStyle(.green.opacity(0.7))
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if wearables.appState.allowsResume {
            // Paused due to overheating — show Resume + Stop instead of the normal button.
            HStack(spacing: 12) {
                Button {
                    Task { await wearables.resumeAfterThermalPause() }
                } label: {
                    Label("Resume", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    Task { await wearables.disconnect() }
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
            }
        } else {
            Button {
                Task {
                    if wearables.appState.allowsDisconnect {
                        await wearables.disconnect()
                    } else {
                        await wearables.connect()
                    }
                }
            } label: {
                Label(
                    wearables.appState.allowsDisconnect ? "Disconnect" : "Connect",
                    systemImage: wearables.appState.allowsDisconnect
                        ? "stop.circle.fill"
                        : "play.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(wearables.appState.allowsDisconnect ? .red : .blue)
            .disabled(!wearables.appState.allowsConnect && !wearables.appState.allowsDisconnect)
        }
    }

    // MARK: - Helpers

    private func statusBadge(label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(WearablesManager())
}
