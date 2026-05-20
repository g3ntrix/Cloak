import Foundation

/// Drives a root-owned utun + tun2socks bridge via the `cloak-tun` sudo helper.
///
/// This replaces an earlier NEPacketTunnelProvider implementation that needed
/// an Apple Developer ID and provisioning profile (NetworkExtension entitlements
/// can't be satisfied by ad-hoc signing). The new path:
///   1. Helper script (NOPASSWD sudo) spawns the bundled tun2socks binary,
///      creates a utun device, and rewrites the default route through it.
///   2. tun2socks bridges utun traffic to the local SOCKS proxy that xray
///      already exposes — so packets still go through the SNI-spoofed path.
///
/// No NetworkExtension entitlements required. No signing identity required.
final class PacketTunnelManager {
    struct StartParameters {
        var connectIP: String
        var socksHost: String
        var socksPort: Int
        var logLevel: String
    }

    private static var bundledTun2socksPath: String? {
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #else
        arch = "x86_64"
        #endif
        let name = "tun2socks-\(arch)"
        if let url = Bundle.main.url(forResource: name, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url.path
        }
        return nil
    }

    func start(parameters: StartParameters) throws {
        guard let binPath = Self.bundledTun2socksPath else {
            throw NSError(
                domain: "SNISpoofing",
                code: 75,
                userInfo: [NSLocalizedDescriptionKey: "tun2socks binary is missing from the app bundle. Rebuild Cloak so Resources/tun2socks-<arch> is present."]
            )
        }
        let args: [String] = [
            "start",
            "--connect-ip", parameters.connectIP,
            "--socks-host", parameters.socksHost,
            "--socks-port", String(parameters.socksPort),
            "--bin", binPath,
            "--loglevel", parameters.logLevel,
        ]
        let (status, output) = SudoPrivilege.runTunHelper(args)
        if status != 0 {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = trimmed.isEmpty ? "exit \(status)" : trimmed
            throw NSError(
                domain: "SNISpoofing",
                code: 76,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't bring up the packet tunnel: \(detail)"]
            )
        }
    }

    func stop() {
        _ = SudoPrivilege.runTunHelper(["stop"])
    }

    /// Synchronous teardown for app-termination paths.
    func stopSync() {
        _ = SudoPrivilege.runTunHelper(["stop"])
    }

    /// Best-effort check whether the helper still has tun2socks alive.
    func isRunning() -> Bool {
        let (status, output) = SudoPrivilege.runTunHelper(["status"])
        guard status == 0 else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "running"
    }
}
