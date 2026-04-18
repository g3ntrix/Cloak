import Foundation

/// Global app settings. Per-profile details live in `Profile`.
struct AppSettings: Codable, Equatable {
    /// Directory containing `main.py`, `.venv`, and `config.json` (written on Start). Nil = default path.
    var pythonProjectPath: String?

    /// Local SOCKS inbound — Xray listens here (layer 2). Point browsers/apps at this.
    var listenHost: String = "127.0.0.1"
    var listenPort: Int = 10_808

    /// How traffic is exposed (TUN not used with the Python+Xray stack).
    var mode: Mode = .proxy

    var activeProfileID: UUID?
    var logLevel: LogLevel = .info

    enum Mode: String, Codable, CaseIterable, Identifiable {
        case proxy, tun
        var id: String { rawValue }
        var display: String {
            switch self {
            case .proxy: return "SOCKS5 + HTTP Proxy"
            case .tun: return "TUN (System-wide)"
            }
        }
        var shortDisplay: String {
            switch self {
            case .proxy: return "Proxy"
            case .tun: return "TUN"
            }
        }
    }

    enum LogLevel: String, Codable, CaseIterable, Identifiable {
        case trace, debug, info, warn, error, fatal, panic
        var id: String { rawValue }
    }

    static let `default` = AppSettings()

    var resolvedPythonProjectPath: String {
        if let p = pythonProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        return "\(NSHomeDirectory())/Documents/Projects/SNI-Spoofing"
    }
}
