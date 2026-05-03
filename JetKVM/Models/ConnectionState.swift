import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case discovering
    case authenticating
    case signaling
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .discovering: "Discovering…"
        case .authenticating: "Authenticating…"
        case .signaling: "Signaling…"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .error(let msg): "Error: \(msg)"
        }
    }

    var isActive: Bool {
        switch self {
        case .connected: true
        default: false
        }
    }
}
