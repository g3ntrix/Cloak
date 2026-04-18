import Foundation

/// Builds Xray JSON: SOCKS inbound → VLESS or Trojan outbound, dial address forced to the Python listener (`bridge`).
enum XrayOutboundBuilder {
    enum BuildError: LocalizedError {
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let s): return s
            }
        }
    }

    static func generate(settings: AppSettings, profile: Profile, bridge: ListenerProjectConfig) throws -> Data {
        let dialHost = bridge.LISTEN_HOST.trimmingCharacters(in: .whitespacesAndNewlines)
        let dialPort = bridge.LISTEN_PORT
        guard !dialHost.isEmpty, dialPort > 0, dialPort <= 65_535 else {
            throw BuildError.unsupported("Listener config: invalid LISTEN_HOST or LISTEN_PORT.")
        }

        var outbound: [String: Any] = [
            "tag": "proxy",
            "streamSettings": try streamSettings(for: profile),
        ]

        switch profile.kind {
        case .vless:
            outbound["protocol"] = "vless"
            var user: [String: Any] = [
                "id": profile.uuid,
                "encryption": "none",
            ]
            if !profile.flow.isEmpty {
                user["flow"] = profile.flow
            }
            outbound["settings"] = [
                "vnext": [
                    [
                        "address": dialHost,
                        "port": dialPort,
                        "users": [user],
                    ],
                ],
            ]
        case .trojan:
            outbound["protocol"] = "trojan"
            outbound["settings"] = [
                "servers": [
                    [
                        "address": dialHost,
                        "port": dialPort,
                        "password": profile.password,
                    ],
                ],
            ]
        case .vmess, .shadowsocks:
            throw BuildError.unsupported("Outbound kind \(profile.kind.display) is not supported yet — use VLESS or Trojan.")
        }

        let socksInbound: [String: Any] = [
            "tag": "socks-in",
            "listen": settings.listenHost,
            "port": settings.listenPort,
            "protocol": "socks",
            "settings": ["udp": true],
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls"],
            ],
        ]

        var inbounds: [[String: Any]] = [socksInbound]
        if settings.useTunMode {
            let tunName = settings.tunInterfaceName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tunName.isEmpty else {
                throw BuildError.unsupported("TUN: set a non-empty interface name (e.g. utun199).")
            }
            let mtu = max(576, min(settings.tunMTU, 9000))
            inbounds.append([
                "tag": "tun-in",
                "port": 0,
                "protocol": "tun",
                "settings": [
                    "name": tunName,
                    "MTU": mtu,
                ],
            ])
        }

        var inboundTags = ["socks-in"]
        if settings.useTunMode {
            inboundTags.append("tun-in")
        }
        let route: [String: Any] = [
            "domainStrategy": "AsIs",
            "rules": [
                [
                    "type": "field",
                    "inboundTag": inboundTags,
                    "outboundTag": "proxy",
                ],
            ],
        ]

        let root: [String: Any] = [
            "log": ["loglevel": xrayLogLevel(settings.logLevel)],
            "inbounds": inbounds,
            "outbounds": [
                outbound,
                [
                    "protocol": "freedom",
                    "tag": "direct",
                    "settings": [:],
                ],
            ],
            "routing": route,
        ]

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func xrayLogLevel(_ l: AppSettings.LogLevel) -> String {
        switch l {
        case .trace, .debug: return "debug"
        case .info: return "info"
        case .warn: return "warning"
        case .error, .fatal, .panic: return "error"
        }
    }

    private static func streamSettings(for p: Profile) throws -> [String: Any] {
        let sec = securityMode(p)
        var ss: [String: Any] = [:]

        switch p.transport.kind {
        case .tcp:
            ss["network"] = "tcp"
        case .ws:
            ss["network"] = "ws"
            var ws: [String: Any] = [:]
            if !p.transport.path.isEmpty { ws["path"] = p.transport.path }
            if !p.transport.host.isEmpty { ws["headers"] = ["Host": p.transport.host] }
            ss["wsSettings"] = ws
        case .grpc:
            ss["network"] = "grpc"
            ss["grpcSettings"] = [
                "serviceName": p.transport.serviceName,
                "multiMode": false,
            ]
        case .http:
            throw BuildError.unsupported("HTTP/2 transport is not wired in Xray generator yet.")
        case .httpupgrade:
            ss["network"] = "httpupgrade"
            var hu: [String: Any] = [:]
            if !p.transport.path.isEmpty { hu["path"] = p.transport.path }
            if !p.transport.host.isEmpty { hu["host"] = p.transport.host }
            ss["httpupgradeSettings"] = hu
        }

        if sec == "tls" {
            ss["security"] = "tls"
            ss["tlsSettings"] = tlsSettings(p)
        } else if sec == "none" {
            ss["security"] = "none"
        } else {
            throw BuildError.unsupported("Only TLS (or none) security is supported for this build — found “\(sec)”.")
        }

        return ss
    }

    private static func securityMode(_ p: Profile) -> String {
        if p.kind == .trojan { return "tls" }
        return p.tls.enabled ? "tls" : "none"
    }

    private static func tlsSettings(_ p: Profile) -> [String: Any] {
        let serverName: String = {
            if !p.tls.serverName.isEmpty { return p.tls.serverName }
            if !p.transport.host.isEmpty { return p.transport.host }
            return p.server
        }()
        var t: [String: Any] = [
            "allowInsecure": p.tls.allowInsecure,
        ]
        if !serverName.isEmpty {
            t["serverName"] = serverName
        }
        if !p.tls.alpn.isEmpty {
            t["alpn"] = p.tls.alpn
        }
        if !p.tls.fingerprint.isEmpty {
            t["fingerprint"] = p.tls.fingerprint
        }
        return t
    }
}
