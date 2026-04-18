import Foundation

/// A proxy-client profile. One is active at a time; Xray outbound is built from it (dial rewritten to the listener).
/// Phase 1 focuses on VLESS (the protocol the user pasted). VMess/Trojan/Shadowsocks
/// are modelled but only VLESS is fully wired into the generator.
struct Profile: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var kind: Kind = .vless
    var server: String = ""
    var serverPort: Int = 443

    /// Host from the `vless://…@HOST:port` URL (even when that host is `127.0.0.1`).
    /// Used to recover the real CDN entry hostname (often differs from `tls.serverName` / SNI).
    var vlessURLHost: String? = nil

    // VLESS / VMess share a UUID; Trojan / Shadowsocks use a password.
    var uuid: String = ""
    var password: String = ""
    var method: String = ""       // shadowsocks cipher
    var flow: String = ""         // vless flow (e.g. xtls-rprx-vision)
    /// VLESS `packetEncoding` for Xray (e.g. xudp). Empty = generator default.
    var packetEncoding: String?

    var tls: TLS = .init()
    var transport: Transport = .init()

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case vless, vmess, trojan, shadowsocks
        var id: String { rawValue }
        var display: String {
            switch self {
            case .vless: return "VLESS"
            case .vmess: return "VMess"
            case .trojan: return "Trojan"
            case .shadowsocks: return "Shadowsocks"
            }
        }
    }

    struct TLS: Codable, Equatable {
        var enabled: Bool = true
        var serverName: String = ""
        var allowInsecure: Bool = false
        var fingerprint: String = "chrome"   // utls fingerprint
        var alpn: [String] = []

        /// When enabled, the Python layer prepends a forged ClientHello using `fakeSNI`
        /// (see listener `config.json` / Settings). Distinct from TLS serverName on the wire.
        var enableSpoof: Bool = false
        var fakeSNI: String = ""
        var spoofMethod: SpoofMethod = .wrongSequence

        enum SpoofMethod: String, Codable, CaseIterable, Identifiable {
            case wrongSequence = "wrong-sequence"
            case wrongChecksum = "wrong-checksum"
            var id: String { rawValue }
            var display: String {
                switch self {
                case .wrongSequence: return "Wrong Sequence (default)"
                case .wrongChecksum: return "Wrong Checksum"
                }
            }
        }
    }

    struct Transport: Codable, Equatable {
        var kind: Kind = .tcp
        var path: String = ""
        var host: String = ""
        var serviceName: String = ""   // grpc

        enum Kind: String, Codable, CaseIterable, Identifiable {
            case tcp, ws, grpc, http, httpupgrade
            var id: String { rawValue }
            var display: String {
                switch self {
                case .tcp: return "TCP"
                case .ws: return "WebSocket"
                case .grpc: return "gRPC"
                case .http: return "HTTP/2"
                case .httpupgrade: return "HTTPUpgrade"
                }
            }
        }
    }
}
