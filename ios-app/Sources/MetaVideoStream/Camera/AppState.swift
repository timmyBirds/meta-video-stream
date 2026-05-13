import SwiftUI

// MARK: - AppState
//
// Single source of truth for the full connection lifecycle:
//
//   idle
//     → registering          (user taps Connect; not yet registered with Meta AI)
//     → awaitingPermission   (registered; camera permission handoff in flight)
//     → connecting           (SRT handshake underway to OBS)
//     → streaming            (frames flowing)
//     → paused               (SRT stopped due to thermal critical; glasses session alive)
//     → reconnecting         (transient SRT drop; Phase 5.2 logic)
//     → error                (unrecoverable; message inline)
//     → stopped              (user-initiated clean stop)
//
// All UI in ContentView derives from this enum — no ad-hoc booleans.

enum AppState: Equatable {
    case idle
    case registering
    case awaitingPermission
    case connecting(streamName: String)
    case streaming(streamName: String)
    /// NDI paused due to `.critical` thermal state. Glasses session stays alive.
    /// Distinct from `.stopped` (user-initiated) so Resume can restart NDI without
    /// going through the full connect flow again.
    case paused(streamName: String)
    case reconnecting(attempt: Int, streamName: String)
    case error(String)
    case stopped

    // MARK: - Display

    var displayLabel: String {
        switch self {
        case .idle:                          return "Not connected"
        case .registering:                   return "Registering…"
        case .awaitingPermission:            return "Awaiting permission…"
        case .connecting:                    return "Starting NDI…"
        case .streaming:                     return "Live"
        case .paused:                        return "Paused — Overheating"
        case .reconnecting(let n, _):        return "Reconnecting (\(n))…"
        case .error:                         return "Error"
        case .stopped:                       return "Stopped"
        }
    }

    var badgeColor: Color {
        switch self {
        case .idle:                          return .gray
        case .registering, .awaitingPermission, .connecting, .reconnecting:
                                             return .orange
        case .streaming:                     return .green
        case .paused:                        return .orange
        case .error:                         return .red
        case .stopped:                       return .gray
        }
    }

    // MARK: - Button control

    /// The Connect button should be enabled in these states.
    var allowsConnect: Bool {
        switch self {
        case .idle, .stopped, .error: return true
        default:                      return false
        }
    }

    /// The Disconnect button should be enabled in these states.
    var allowsDisconnect: Bool {
        switch self {
        case .connecting, .streaming, .reconnecting: return true
        default:                                      return false
        }
    }

    /// True when the stream is thermally paused and the user can choose to Resume or Stop.
    var allowsResume: Bool {
        if case .paused = self { return true }
        return false
    }

    // MARK: - Associated value accessors

    /// The NDI stream name in play, if any.
    var streamName: String? {
        switch self {
        case .connecting(let name):        return name
        case .streaming(let name):         return name
        case .paused(let name):            return name
        case .reconnecting(_, let name):   return name
        default:                          return nil
        }
    }

    /// True while frames should be flowing (or trying to).
    var isActive: Bool {
        switch self {
        case .connecting, .streaming, .reconnecting: return true
        default:                                      return false
        }
    }

    /// True when SRT is intentionally paused due to overheating.
    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    /// Inline error message, if the state carries one.
    var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }
}
