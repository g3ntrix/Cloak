import Foundation

/// Global app settings. Per-profile details live in `Profile`.
struct AppSettings: Codable, Equatable {
    /// Optional override — normally unused; the app auto-detects the bundled
    /// Python source or falls back to `~/Documents/Projects/SNI-Spoofing`.
    var pythonProjectPath: String?

    /// Local SOCKS inbound — Xray listens here. Apps/browsers point at this.
    var listenHost: String = "127.0.0.1"
    var listenPort: Int = 10_808

    var activeProfileID: UUID?
    var logLevel: LogLevel = .info

    enum LogLevel: String, Codable, CaseIterable, Identifiable {
        case trace, debug, info, warn, error, fatal, panic
        var id: String { rawValue }
    }

    static let `default` = AppSettings()

    /// Auto-detects the Python source directory: bundled first, then fallback.
    var resolvedPythonProjectPath: String {
        if let p = pythonProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        // Prefer Python source bundled inside the app.
        if let res = Bundle.main.resourcePath {
            let bundled = (res as NSString).appendingPathComponent("python")
            if FileManager.default.fileExists(atPath: (bundled as NSString).appendingPathComponent("main.py")) {
                return bundled
            }
        }
        // Dev fallback.
        return "\(NSHomeDirectory())/Documents/Projects/SNI-Spoofing"
    }
}
