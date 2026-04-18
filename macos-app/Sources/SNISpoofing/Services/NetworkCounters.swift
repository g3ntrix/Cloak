import Foundation
import Darwin

/// Sums RX/TX bytes across non-loopback interfaces via `getifaddrs`.
/// Used for a lightweight "speed" display; not precise per-connection.
enum NetworkCounters {
    struct Counters { let rx: UInt64; let tx: UInt64 }

    static func totalRXTXBytes() -> Counters? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let start = ifap else { return nil }
        defer { freeifaddrs(ifap) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var seen: Set<String> = []

        var cur: UnsafeMutablePointer<ifaddrs>? = start
        while let p = cur {
            defer { cur = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let saP = p.pointee.ifa_addr else { continue }
            guard saP.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let dataP = p.pointee.ifa_data else { continue }

            let name = String(cString: p.pointee.ifa_name)
            if seen.contains(name) { continue }
            seen.insert(name)

            let d = dataP.assumingMemoryBound(to: if_data.self).pointee
            rx &+= UInt64(d.ifi_ibytes)
            tx &+= UInt64(d.ifi_obytes)
        }
        return Counters(rx: rx, tx: tx)
    }
}
