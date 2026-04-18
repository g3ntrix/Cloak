import Foundation

/// Applies macOS IPv4 split routes so traffic can use Xray's `utun` inbound without
/// routing the Python layer's upstream (`CONNECT_IP`) through the tunnel (avoids loops).
enum TunRoutes {
    static func applyUp(connectIP: String, tunName: String) throws {
        try runSudoRoutes(arguments: ["up", connectIP, tunName])
    }

    /// Best-effort cleanup; ignores failures (routes may already be gone).
    static func applyDownSync(connectIP: String, tunName: String) {
        try? runSudoRoutes(arguments: ["down", connectIP, tunName])
    }

    private static func runSudoRoutes(arguments: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", SudoPrivilege.tunRoutesPath] + arguments
        let err = Pipe()
        p.standardError = err
        p.standardOutput = err
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "route helper failed"
            throw NSError(
                domain: "SNISpoofing",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }
}
