import Foundation

/// Builds Xray JSON: local SOCKS/HTTP inbounds → profile outbound, with the dial
/// address forced to the SNI bridge.
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
        let dialHost = bridge.resolvedDialHost
        let dialPort = bridge.LISTEN_PORT
        guard dialPort > 0, dialPort <= 65_535 else {
            throw BuildError.unsupported("Listener config: invalid LISTEN_HOST or LISTEN_PORT.")
        }

        var outbound: [String: Any] = [
            "tag": "proxy",
            "streamSettings": try streamSettings(for: profile),
        ]

        switch profile.kind {
        case .vless, .vmess:
            guard !profile.uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BuildError.unsupported("\(profile.kind.display) profile is missing a UUID.")
            }
            outbound["protocol"] = "vless"
            var user: [String: Any] = [
                "id": profile.uuid,
                "encryption": "none",
            ]
            if profile.kind == .vmess {
                outbound["protocol"] = "vmess"
                user = [
                    "id": profile.uuid,
                    "security": "auto",
                ]
            }
            if !profile.flow.isEmpty {
                user["flow"] = profile.flow
            }
            if profile.kind == .vless,
               let packetEncoding = profile.packetEncoding?.trimmingCharacters(in: .whitespacesAndNewlines),
               !packetEncoding.isEmpty {
                user["packetEncoding"] = packetEncoding
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
            guard !profile.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BuildError.unsupported("Trojan profile is missing a password.")
            }
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
        case .shadowsocks:
            guard !profile.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !profile.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BuildError.unsupported("Shadowsocks profile is missing method or password.")
            }
            outbound["protocol"] = "shadowsocks"
            outbound["settings"] = [
                "servers": [
                    [
                        "address": dialHost,
                        "port": dialPort,
                        "method": profile.method,
                        "password": profile.password,
                    ],
                ],
            ]
            outbound.removeValue(forKey: "streamSettings")
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

        let httpInbound: [String: Any] = [
            "tag": "http-in",
            "listen": settings.listenHost,
            "port": settings.httpPort,
            "protocol": "http",
            "settings": ["allowTransparent": false],
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls"],
            ],
        ]

        let inbounds: [[String: Any]] = [socksInbound, httpInbound]
        let route: [String: Any] = [
            "domainStrategy": "AsIs",
            "rules": [
                [
                    "type": "field",
                    "inboundTag": ["socks-in", "http-in"],
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
            var grpc: [String: Any] = [
                "serviceName": p.transport.serviceName,
                "multiMode": p.transport.mode == "multi",
            ]
            if let authority = p.transport.authority, !authority.isEmpty {
                grpc["authority"] = authority
            }
            ss["grpcSettings"] = grpc
        case .http:
            ss["network"] = "http"
            var http: [String: Any] = [:]
            if !p.transport.path.isEmpty { http["path"] = p.transport.path }
            if !p.transport.host.isEmpty { http["host"] = [p.transport.host] }
            ss["httpSettings"] = http
        case .httpupgrade:
            ss["network"] = "httpupgrade"
            var hu: [String: Any] = [:]
            if !p.transport.path.isEmpty { hu["path"] = p.transport.path }
            if !p.transport.host.isEmpty { hu["host"] = p.transport.host }
            ss["httpupgradeSettings"] = hu
        case .xhttp, .splithttp:
            ss["network"] = p.transport.kind.rawValue
            var xhttp: [String: Any] = [:]
            if !p.transport.path.isEmpty { xhttp["path"] = p.transport.path }
            if !p.transport.host.isEmpty { xhttp["host"] = p.transport.host }
            if let mode = p.transport.mode, !mode.isEmpty { xhttp["mode"] = mode }
            ss["xhttpSettings"] = xhttp
        }

        if sec == "tls" {
            ss["security"] = "tls"
            ss["tlsSettings"] = tlsSettings(p)
        } else if sec == "reality" {
            ss["security"] = "reality"
            ss["realitySettings"] = realitySettings(p)
        } else if sec == "none" {
            ss["security"] = "none"
        } else {
            throw BuildError.unsupported("Unsupported security mode: \(sec).")
        }

        return ss
    }

    private static func securityMode(_ p: Profile) -> String {
        if let explicit = p.tls.security?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !explicit.isEmpty {
            return explicit
        }
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

    private static func realitySettings(_ p: Profile) -> [String: Any] {
        var r = tlsSettings(p)
        if let publicKey = p.tls.publicKey, !publicKey.isEmpty {
            r["publicKey"] = publicKey
        }
        if let shortID = p.tls.shortID, !shortID.isEmpty {
            r["shortId"] = shortID
        }
        if let spiderX = p.tls.spiderX, !spiderX.isEmpty {
            r["spiderX"] = spiderX
        }
        return r
    }
}
