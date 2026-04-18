import Foundation

/// Parses proxy subscription URLs into Profiles.
///
/// Parses `vless://` and `trojan://` share URLs into `Profile`.
enum ProfileURLParser {
    enum ParseError: LocalizedError {
        case empty
        case malformedURL
        case unknownScheme(String)
        case missingField(String)

        var errorDescription: String? {
            switch self {
            case .empty: return "URL is empty."
            case .malformedURL: return "URL is not valid."
            case .unknownScheme(let s): return "\(s):// is not supported yet."
            case .missingField(let f): return "Missing \(f) in URL."
            }
        }
    }

    static func parse(_ raw: String) throws -> Profile {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }
        guard let url = URL(string: trimmed) else { throw ParseError.malformedURL }
        switch (url.scheme ?? "").lowercased() {
        case "vless": return try parseVLESS(url)
        case "trojan": return try parseTrojan(url)
        case "vmess", "ss", "shadowsocks":
            throw ParseError.unknownScheme(url.scheme ?? "?")
        default:
            throw ParseError.unknownScheme(url.scheme ?? "?")
        }
    }

    // trojan://password@host:port?security=tls&type=ws&path=...&host=...&sni=...
    private static func parseTrojan(_ url: URL) throws -> Profile {
        guard var host = url.host, !host.isEmpty else { throw ParseError.missingField("host") }
        host = Self.normalizeHostname(host)
        guard let port = url.port else { throw ParseError.missingField("port") }
        guard let pass = url.user, !pass.isEmpty else { throw ParseError.missingField("password") }

        let name = url.fragment?.removingPercentEncoding?
            .trimmingCharacters(in: .whitespaces) ?? host
        let q = queryMap(url)

        var p = Profile(name: name.isEmpty ? host : name,
                        kind: .trojan,
                        server: host,
                        serverPort: port,
                        password: pass)
        p.vlessURLHost = nil

        let security = (q["security"] ?? "tls").lowercased()
        p.tls.enabled = (security == "tls" || security == "reality" || security == "xtls")
        if let sni = q["sni"], !sni.isEmpty {
            p.tls.serverName = Self.normalizeHostname(sni)
        }
        p.tls.allowInsecure = truthy(q["allowinsecure"] ?? q["allow_insecure"])
        if let fp = q["fp"], !fp.isEmpty { p.tls.fingerprint = fp }
        if let alpn = q["alpn"], !alpn.isEmpty {
            p.tls.alpn = alpn.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }

        let tType = (q["type"] ?? "tcp").lowercased()
        p.transport.kind = Profile.Transport.Kind(rawValue: tType) ?? .tcp
        p.transport.path = (q["path"] ?? "").removingPercentEncoding ?? q["path"] ?? ""
        if let h = q["host"], !h.isEmpty {
            p.transport.host = Self.normalizeHostname(h)
        }
        p.transport.serviceName = q["servicename"] ?? q["serviceName"] ?? ""

        return p
    }

    // vless://<uuid>@<host>:<port>?security=tls&sni=...&alpn=...&type=ws&path=...&host=...#<name>
    private static func parseVLESS(_ url: URL) throws -> Profile {
        guard var host = url.host, !host.isEmpty else { throw ParseError.missingField("host") }
        host = Self.normalizeHostname(host)
        guard let port = url.port else { throw ParseError.missingField("port") }
        guard let uuid = url.user, !uuid.isEmpty else { throw ParseError.missingField("uuid") }

        let name = url.fragment?.removingPercentEncoding?
            .trimmingCharacters(in: .whitespaces) ?? host
        let q = queryMap(url)

        var p = Profile(name: name.isEmpty ? host : name,
                        kind: .vless,
                        server: host,
                        serverPort: port,
                        uuid: uuid)
        p.vlessURLHost = host

        // TLS
        let security = (q["security"] ?? "none").lowercased()
        p.tls.enabled = (security == "tls" || security == "reality" || security == "xtls")
        if let sni = q["sni"], !sni.isEmpty {
            p.tls.serverName = Self.normalizeHostname(sni)
        }
        p.tls.allowInsecure = truthy(q["allowinsecure"] ?? q["allow_insecure"])
        if let fp = q["fp"], !fp.isEmpty { p.tls.fingerprint = fp }
        if let alpn = q["alpn"], !alpn.isEmpty {
            p.tls.alpn = alpn.split(separator: ",").map { String($0) }
        }
        p.flow = q["flow"] ?? ""
        if let pe = q["packetencoding"], !pe.isEmpty { p.packetEncoding = pe }

        // Transport
        let tType = (q["type"] ?? "tcp").lowercased()
        p.transport.kind = Profile.Transport.Kind(rawValue: tType) ?? .tcp
        p.transport.path = (q["path"] ?? "").removingPercentEncoding ?? q["path"] ?? ""
        if let h = q["host"], !h.isEmpty {
            p.transport.host = Self.normalizeHostname(h)
        }
        p.transport.serviceName = q["servicename"] ?? q["serviceName"] ?? ""

        return p
    }

    private static func queryMap(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for item in comps?.queryItems ?? [] {
            out[item.name.lowercased()] = item.value
        }
        return out
    }

    private static func truthy(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(s)
    }

    /// Strip trailing `.` from FQDNs (`chosan2.example.net.` → same as main.py / DNS clients).
    private static func normalizeHostname(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix(".") { t.removeLast() }
        return t
    }
}
