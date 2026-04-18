import Darwin

/// Best-effort primary IPv4 on a typical LAN interface (for “bind all interfaces” SOCKS).
enum LanAddress {
    static func primaryIPv4String() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let iface = p.pointee
            guard let sa = iface.ifa_addr else {
                ptr = iface.ifa_next
                continue
            }
            guard sa.pointee.sa_family == UInt8(AF_INET) else {
                ptr = iface.ifa_next
                continue
            }
            let name = String(cString: iface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else {
                ptr = iface.ifa_next
                continue
            }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let salen = socklen_t(MemoryLayout<sockaddr_in>.size)
            if getnameinfo(sa, salen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) != 0 {
                ptr = iface.ifa_next
                continue
            }
            let s = String(cString: buf)
            if s != "127.0.0.1", !s.hasPrefix("169.254.") {
                return s
            }
            ptr = iface.ifa_next
        }
        return nil
    }
}
