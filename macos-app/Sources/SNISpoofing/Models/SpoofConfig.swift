import Foundation

/// Global app settings. Per-profile details live in `Profile`.
struct AppSettings: Codable, Equatable {
    /// Optional override — normally unused; the app auto-detects the bundled
    /// Python source or falls back to `~/Documents/Projects/SNI-Spoofing`.
    var pythonProjectPath: String?

    /// Local SOCKS inbound — Xray listens here. Apps/browsers point at this.
    var listenHost: String = "127.0.0.1"
    var listenPort: Int = 2080

    /// When enabled, Xray also opens a TUN (`utun*`) and the app installs split
    /// IPv4 routes so system traffic can use the tunnel (requires admin helper).
    var useTunMode: Bool = false
    /// Must match `utunN` scheme on macOS; pick a high N to avoid clashes.
    var tunInterfaceName: String = "utun199"
    var tunMTU: Int = 1492

    var activeProfileID: UUID?
    var logLevel: LogLevel = .info

    enum LogLevel: String, Codable, CaseIterable, Identifiable {
        case trace, debug, info, warn, error, fatal, panic
        var id: String { rawValue }
    }

    static let `default` = AppSettings()

    init(
        pythonProjectPath: String? = nil,
        listenHost: String = "127.0.0.1",
        listenPort: Int = 2080,
        useTunMode: Bool = false,
        tunInterfaceName: String = "utun199",
        tunMTU: Int = 1492,
        activeProfileID: UUID? = nil,
        logLevel: LogLevel = .info
    ) {
        self.pythonProjectPath = pythonProjectPath
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.useTunMode = useTunMode
        self.tunInterfaceName = tunInterfaceName
        self.tunMTU = tunMTU
        self.activeProfileID = activeProfileID
        self.logLevel = logLevel
    }

    enum CodingKeys: String, CodingKey {
        case pythonProjectPath, listenHost, listenPort
        case useTunMode, tunInterfaceName, tunMTU
        case activeProfileID, logLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pythonProjectPath = try c.decodeIfPresent(String.self, forKey: .pythonProjectPath)
        listenHost = try c.decodeIfPresent(String.self, forKey: .listenHost) ?? "127.0.0.1"
        listenPort = try c.decodeIfPresent(Int.self, forKey: .listenPort) ?? 2080
        useTunMode = try c.decodeIfPresent(Bool.self, forKey: .useTunMode) ?? false
        tunInterfaceName = try c.decodeIfPresent(String.self, forKey: .tunInterfaceName) ?? "utun199"
        tunMTU = try c.decodeIfPresent(Int.self, forKey: .tunMTU) ?? 1492
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        logLevel = try c.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .info
    }

    /// Host the **app** uses to talk to the local SOCKS (never `0.0.0.0` / “all interfaces”).
    var resolvedSocksHostForLocalClient: String {
        let h = listenHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.isEmpty || h == "0.0.0.0" || h == "*" { return "127.0.0.1" }
        if h == "::" { return "::1" }
        return listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
