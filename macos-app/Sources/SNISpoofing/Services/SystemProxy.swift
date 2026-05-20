import Foundation

/// Toggles the macOS system-wide SOCKS proxy on every active network service.
/// Backed by `/usr/local/bin/cloak-proxy` (installed by `SudoPrivilege.install`).
enum SystemProxy {

    enum Result { case ok, failed(String) }

    /// Routes system proxy-aware traffic through Cloak's HTTP/HTTPS and SOCKS inbounds.
    static func enable(host: String, socksPort: Int, httpPort: Int) -> Result {
        let h = normalizeHost(host)
        guard SudoPrivilege.proxyHelperReady() else {
            return .failed("Proxy helper not installed. Open Settings → Grant permission.")
        }
        let rc = SudoPrivilege.runProxyHelper(["enable", h, String(socksPort), String(httpPort)])
        return rc == 0 ? .ok : .failed("cloak-proxy enable exited \(rc)")
    }

    /// Turns the SOCKS proxy off on all network services.
    static func disable() -> Result {
        guard SudoPrivilege.proxyHelperReady() else {
            return .ok // helper gone — nothing to undo
        }
        let rc = SudoPrivilege.runProxyHelper(["disable"])
        return rc == 0 ? .ok : .failed("cloak-proxy disable exited \(rc)")
    }

    /// Best-effort synchronous disable for app-termination paths.
    static func disableSync() {
        _ = disable()
    }

    /// `scutil --proxy` doesn't need admin and reflects current system state.
    static func isEnabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--proxy"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return false
        }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("SOCKSEnable : 1")
            || out.contains("HTTPEnable : 1")
            || out.contains("HTTPSEnable : 1")
    }

    private static func normalizeHost(_ host: String) -> String {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.isEmpty || h == "0.0.0.0" || h == "*" { return "127.0.0.1" }
        if h == "::" { return "::1" }
        return host.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
