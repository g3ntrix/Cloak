import Foundation
import Darwin

/// Finds a free TCP listen port on the given bind address (for the mixed inbound).
enum PortAvailability {

    /// Returns `preferred` if bind succeeds, otherwise the first free port in `range`.
    static func firstAvailable(preferred: Int, host: String, range: ClosedRange<Int>) -> Int {
        if isAvailable(port: preferred, host: host) { return preferred }
        for p in range where p != preferred {
            if isAvailable(port: p, host: host) { return p }
        }
        return preferred
    }

    /// Whether Cloak can bind `host:port` for a TCP listener right now.
    static func isAvailable(port: Int, host: String) -> Bool {
        guard port > 0, port < 65536 else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian

        let bindIP: String
        switch host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "0.0.0.0", "*":
            bindIP = "0.0.0.0"
        case "localhost", "127.0.0.1":
            bindIP = "127.0.0.1"
        default:
            bindIP = "0.0.0.0"
        }
        bindIP.withCString { cstr in
            _ = inet_pton(AF_INET, cstr, &addr.sin_addr)
        }

        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }
}
