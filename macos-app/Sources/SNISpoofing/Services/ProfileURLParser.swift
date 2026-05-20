import Foundation

/// Parses proxy subscription URLs into Profiles.
///
/// Parses common Xray share URLs into `Profile`.
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
        case "vless": return try parseStandard(url, kind: .vless, defaultSecurity: "none")
        case "trojan": return try parseStandard(url, kind: .trojan, defaultSecurity: "tls")
        case "vmess": return try parseVMess(trimmed)
        case "ss", "shadowsocks": return try parseShadowsocks(trimmed)
        default:
            throw ParseError.unknownScheme(url.scheme ?? "?")
        }
    }

    private static func parseStandard(_ url: URL, kind: Profile.Kind, defaultSecurity: String) throws -> Profile {
        guard var host = url.host, !host.isEmpty else { throw ParseError.missingField("host") }
        host = Self.normalizeHostname(host)
        guard let port = url.port else { throw ParseError.missingField("port") }
        guard let user = url.user, !user.isEmpty else {
            throw ParseError.missingField(kind == .trojan ? "password" : "uuid")
        }

        let name = url.fragment?.removingPercentEncoding?
            .trimmingCharacters(in: .whitespaces) ?? host
        let q = queryMap(url)

        var p = Profile(name: name.isEmpty ? host : name,
                        kind: kind,
                        server: host,
                        serverPort: port)
        if kind == .trojan {
            p.password = user.removingPercentEncoding ?? user
        } else {
            p.uuid = user.removingPercentEncoding ?? user
            p.vlessURLHost = host
            p.flow = q["flow"] ?? ""
            p.packetEncoding = q["packetencoding"]
        }

        let security = normalizeSecurity(q["security"] ?? q["tls"] ?? defaultSecurity, defaultSecurity)
        p.tls.enabled = (security == "tls" || security == "reality" || security == "xtls")
        p.tls.security = security
        if let sni = q["sni"], !sni.isEmpty {
            p.tls.serverName = Self.normalizeHostname(sni)
        } else if let sni = q["servername"], !sni.isEmpty {
            p.tls.serverName = Self.normalizeHostname(sni)
        } else if let sni = q["peer"], !sni.isEmpty {
            p.tls.serverName = Self.normalizeHostname(sni)
        }
        p.tls.allowInsecure = truthy(q["allowinsecure"] ?? q["allow_insecure"] ?? q["insecure"])
        if let fp = q["fp"], !fp.isEmpty { p.tls.fingerprint = fp }
        if let fp = q["fingerprint"], !fp.isEmpty { p.tls.fingerprint = fp }
        if let alpn = q["alpn"], !alpn.isEmpty {
            p.tls.alpn = alpn.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        p.tls.publicKey = q["pbk"]
        p.tls.shortID = q["sid"]
        p.tls.spiderX = q["spx"]

        let tType = (q["type"] ?? "tcp").lowercased()
        p.transport.kind = Profile.Transport.Kind(rawValue: tType) ?? .tcp
        p.transport.path = (q["path"] ?? "").removingPercentEncoding ?? q["path"] ?? ""
        if let h = q["host"], !h.isEmpty {
            p.transport.host = Self.normalizeHostname(h)
        }
        p.transport.serviceName = q["servicename"] ?? ""
        p.transport.authority = q["authority"]
        p.transport.headerType = q["headertype"]
        p.transport.mode = q["mode"]

        return p
    }

    private static func parseVMess(_ raw: String) throws -> Profile {
        guard let payload = stripScheme(raw, scheme: "vmess") else { throw ParseError.malformedURL }
        let encoded = payload.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? payload
        let json = decodeBase64URLString(encoded) ?? encoded.removingPercentEncoding ?? encoded
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.malformedURL
        }

        func string(_ keys: [String], default fallback: String = "") -> String {
            for key in keys {
                if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let value = object[key] as? NSNumber {
                    return value.stringValue
                }
            }
            return fallback
        }
        func int(_ keys: [String]) -> Int? {
            for key in keys {
                if let value = object[key] as? Int { return value }
                if let value = object[key] as? NSNumber { return value.intValue }
                if let value = object[key] as? String, let parsed = Int(value) { return parsed }
            }
            return nil
        }

        var host = string(["add", "address"])
        host = Self.normalizeHostname(host)
        guard !host.isEmpty else { throw ParseError.missingField("host") }
        guard let port = int(["port"]) else { throw ParseError.missingField("port") }

        var p = Profile(name: string(["ps"], default: "VMess"),
                        kind: .vmess,
                        server: host,
                        serverPort: port)
        p.uuid = string(["id"])
        let security = normalizeSecurity(string(["tls"], default: ""), "none")
        p.tls.enabled = security == "tls" || security == "reality"
        p.tls.security = security
        p.tls.serverName = normalizeHostname(string(["sni", "serverName", "peer"], default: host))
        p.tls.allowInsecure = truthy(string(["allowInsecure", "insecure"], default: "0"))
        let fp = string(["fp", "fingerprint"])
        if !fp.isEmpty { p.tls.fingerprint = fp }
        let alpn = string(["alpn"])
        if !alpn.isEmpty {
            p.tls.alpn = alpn.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        p.tls.publicKey = emptyToNil(string(["pbk"]))
        p.tls.shortID = emptyToNil(string(["sid"]))
        p.tls.spiderX = emptyToNil(string(["spx"]))
        p.transport.kind = Profile.Transport.Kind(rawValue: string(["net", "type"], default: "tcp").lowercased()) ?? .tcp
        p.transport.host = normalizeHostname(string(["host"], default: host))
        p.transport.path = string(["path"], default: "/")
        p.transport.serviceName = string(["serviceName"])
        p.transport.authority = emptyToNil(string(["authority"]))
        p.transport.headerType = emptyToNil(string(["headerType"]))
        p.transport.mode = emptyToNil(string(["mode"]))
        return p
    }

    private static func parseShadowsocks(_ raw: String) throws -> Profile {
        guard let payload = stripScheme(raw, scheme: raw.lowercased().hasPrefix("shadowsocks://") ? "shadowsocks" : "ss") else {
            throw ParseError.malformedURL
        }
        let parts = payload.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let body = String(parts.first ?? "")
        let remark = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? "Shadowsocks") : "Shadowsocks"
        let querySplit = body.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let authorityOrEncoded = String(querySplit.first ?? "")
        let querySuffix = querySplit.count > 1 ? "?\(querySplit[1])" : ""
        let decodedAuthority = authorityOrEncoded.contains("@")
            ? authorityOrEncoded
            : (decodeBase64URLString(authorityOrEncoded) ?? authorityOrEncoded)
        guard let components = URLComponents(string: "ss://\(decodedAuthority)\(querySuffix)"),
              let host = components.host,
              let port = components.port else {
            throw ParseError.missingField("host/port")
        }

        var p = Profile(name: remark, kind: .shadowsocks, server: normalizeHostname(host), serverPort: port)
        let rawUser = components.user?.removingPercentEncoding ?? ""
        let rawPassword = components.password?.removingPercentEncoding ?? ""
        if rawPassword.isEmpty, let decodedCredentials = decodeBase64URLString(rawUser), decodedCredentials.contains(":") {
            let pieces = decodedCredentials.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            p.method = String(pieces.first ?? "")
            p.password = pieces.count > 1 ? String(pieces[1]) : ""
        } else {
            p.method = rawUser
            p.password = rawPassword
        }
        p.tls.enabled = false
        p.tls.security = "none"
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

    private static func normalizeSecurity(_ raw: String, _ defaultValue: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return defaultValue }
        switch value {
        case "1", "true", "tls": return "tls"
        case "reality": return "reality"
        case "0", "false", "none": return "none"
        default: return value
        }
    }

    private static func stripScheme(_ raw: String, scheme: String) -> String? {
        let prefix = "\(scheme)://"
        guard raw.lowercased().hasPrefix(prefix) else { return nil }
        return String(raw.dropFirst(prefix.count))
    }

    private static func decodeBase64URLString(_ input: String) -> String? {
        var normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        normalized = normalized.replacingOccurrences(of: "-", with: "+")
        normalized = normalized.replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
