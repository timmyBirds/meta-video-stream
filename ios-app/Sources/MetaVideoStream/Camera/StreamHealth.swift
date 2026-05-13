import Foundation

// MARK: - ThermalWarning
//
// Derived from ProcessInfo.thermalState while streaming.
// .serious  → non-blocking banner; bitrate and effective framerate reduced.
// .critical → stream paused; modal shown; user must tap Resume.

enum ThermalWarning: Equatable {
    case none
    case serious
    case critical
}

// MARK: - BatteryWarning
//
// Derived from UIDevice.batteryLevel while streaming.
// .low      → non-blocking banner (<20%).
// .critical → modal prompt offering to stop (<10%).

enum BatteryWarning: Equatable {
    case none
    case low
    case critical
}
