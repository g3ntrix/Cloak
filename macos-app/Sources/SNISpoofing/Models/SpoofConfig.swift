import Foundation
import SwiftUI

/// Global app settings. Per-profile details live in `Profile`.
struct AppSettings: Codable, Equatable {
    /// Optional override — normally unused; the app auto-detects the bundled
    /// Python source or falls back to `~/Documents/Projects/SNI-Spoofing`.
    var pythonProjectPath: String?

    /// Local SOCKS inbound — Xray listens here. Apps/browsers point at this.
    var listenHost: String = "127.0.0.1"
    var listenPort: Int = 2080

    /// When enabled, Cloak toggles the macOS system SOCKS proxy so all apps
    /// route through Xray automatically without manual per-app configuration.
    var useSystemProxy: Bool = true

    var activeProfileID: UUID?
    var logLevel: LogLevel = .warn
    /// When false, the in-app Logs viewer doesn't collect xray/listener output.
    /// User can opt-in from Settings → Diagnostics.
    var logsEnabled: Bool = false

    /// Light/dark appearance override. `.system` follows macOS.
    var appearanceMode: AppearanceMode = .system

    enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    enum LogLevel: String, Codable, CaseIterable, Identifiable {
        case trace, debug, info, warn, error, fatal, panic
        var id: String { rawValue }
    }

    static let `default` = AppSettings()

    init(
        pythonProjectPath: String? = nil,
        listenHost: String = "127.0.0.1",
        listenPort: Int = 2080,
        useSystemProxy: Bool = true,
        activeProfileID: UUID? = nil,
        logLevel: LogLevel = .warn,
        logsEnabled: Bool = false,
        appearanceMode: AppearanceMode = .system
    ) {
        self.pythonProjectPath = pythonProjectPath
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.useSystemProxy = useSystemProxy
        self.activeProfileID = activeProfileID
        self.logLevel = logLevel
        self.logsEnabled = logsEnabled
        self.appearanceMode = appearanceMode
    }

    /// `true` when the SOCKS listener is exposed on all interfaces (LAN).
    var exposesToLAN: Bool {
        let h = listenHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return h == "0.0.0.0" || h == "*"
    }

    mutating func setExposesToLAN(_ enabled: Bool) {
        listenHost = enabled ? "0.0.0.0" : "127.0.0.1"
    }

    enum CodingKeys: String, CodingKey {
        case pythonProjectPath, listenHost, listenPort
        case useSystemProxy
        case activeProfileID, logLevel, logsEnabled, appearanceMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pythonProjectPath = try c.decodeIfPresent(String.self, forKey: .pythonProjectPath)
        listenHost = try c.decodeIfPresent(String.self, forKey: .listenHost) ?? "127.0.0.1"
        listenPort = try c.decodeIfPresent(Int.self, forKey: .listenPort) ?? 2080
        useSystemProxy = try c.decodeIfPresent(Bool.self, forKey: .useSystemProxy) ?? true
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        logLevel = try c.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .warn
        logsEnabled = try c.decodeIfPresent(Bool.self, forKey: .logsEnabled) ?? false
        appearanceMode = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
    }

    /// Host the **app** uses to talk to the local SOCKS (never `0.0.0.0` / “all interfaces”).
    var resolvedSocksHostForLocalClient: String {
        let h = listenHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.isEmpty || h == "0.0.0.0" || h == "*" { return "127.0.0.1" }
        if h == "::" { return "::1" }
        return listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Legacy dev override for an external Python tree (unused by the shipped frozen listener).
    var resolvedPythonProjectPath: String {
        if let p = pythonProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        if let res = Bundle.main.resourcePath {
            return res
        }
        return "\(NSHomeDirectory())/Documents/Projects/Cloak"
    }

    /// SwiftUI color scheme override, or `nil` to follow the system.
    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
