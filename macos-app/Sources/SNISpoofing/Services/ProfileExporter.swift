import Foundation

/// Reconstructs share links from stored profiles for export.
enum ProfileExporter {
    enum ExportError: LocalizedError {
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let message): return message
            }
        }
    }

    static func exportText(_ profiles: [Profile]) throws -> String {
        let lines = try profiles.map(uri(for:))
        return lines.joined(separator: "\n") + "\n"
    }

    static func uri(for profile: Profile) throws -> String {
        switch profile.kind {
        case .vless:
            return try standardURI(profile, scheme: "vless", user: profile.uuid)
        case .trojan:
            return try standardURI(profile, scheme: "trojan", user: profile.password)
        case .vmess:
            return try vmessURI(profile)
        case .shadowsocks:
            return try shadowsocksURI(profile)
        }
    }

    private static func standardURI(_ profile: Profile, scheme: String, user: String) throws -> String {
        guard !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.unsupported("\(profile.name) is missing credentials.")
        }
        guard !profile.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.serverPort > 0 else {
            throw ExportError.unsupported("\(profile.name) is missing server details.")
        }

        var components = URLComponents()
        components.scheme = scheme
        components.user = user
        components.host = profile.server
        components.port = profile.serverPort
        components.queryItems = queryItems(for: profile)
        components.fragment = profile.name

        guard let url = components.url?.absoluteString else {
            throw ExportError.unsupported("Couldn't export \(profile.name).")
        }
        return url
    }

    private static func queryItems(for profile: Profile) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        let security = securityValue(for: profile)
        items.append(URLQueryItem(name: "security", value: security))

        if !profile.tls.serverName.isEmpty {
            items.append(URLQueryItem(name: "sni", value: profile.tls.serverName))
        }
        if profile.tls.allowInsecure {
            items.append(URLQueryItem(name: "allowInsecure", value: "1"))
        }
        if !profile.tls.fingerprint.isEmpty {
            items.append(URLQueryItem(name: "fp", value: profile.tls.fingerprint))
        }
        if !profile.tls.alpn.isEmpty {
            items.append(URLQueryItem(name: "alpn", value: profile.tls.alpn.joined(separator: ",")))
        }
        if let publicKey = profile.tls.publicKey, !publicKey.isEmpty {
            items.append(URLQueryItem(name: "pbk", value: publicKey))
        }
        if let shortID = profile.tls.shortID, !shortID.isEmpty {
            items.append(URLQueryItem(name: "sid", value: shortID))
        }
        if let spiderX = profile.tls.spiderX, !spiderX.isEmpty {
            items.append(URLQueryItem(name: "spx", value: spiderX))
        }

        items.append(URLQueryItem(name: "type", value: profile.transport.kind.rawValue))
        if !profile.transport.path.isEmpty {
            items.append(URLQueryItem(name: "path", value: profile.transport.path))
        }
        if !profile.transport.host.isEmpty {
            items.append(URLQueryItem(name: "host", value: profile.transport.host))
        }
        if !profile.transport.serviceName.isEmpty {
            items.append(URLQueryItem(name: "serviceName", value: profile.transport.serviceName))
        }
        if let authority = profile.transport.authority, !authority.isEmpty {
            items.append(URLQueryItem(name: "authority", value: authority))
        }
        if let headerType = profile.transport.headerType, !headerType.isEmpty {
            items.append(URLQueryItem(name: "headerType", value: headerType))
        }
        if let mode = profile.transport.mode, !mode.isEmpty {
            items.append(URLQueryItem(name: "mode", value: mode))
        }
        if !profile.flow.isEmpty {
            items.append(URLQueryItem(name: "flow", value: profile.flow))
        }
        if let packetEncoding = profile.packetEncoding, !packetEncoding.isEmpty {
            items.append(URLQueryItem(name: "packetEncoding", value: packetEncoding))
        }

        return items
    }

    private static func securityValue(for profile: Profile) -> String {
        if let security = profile.tls.security?.trimmingCharacters(in: .whitespacesAndNewlines),
           !security.isEmpty {
            return security
        }
        if profile.kind == .trojan { return "tls" }
        return profile.tls.enabled ? "tls" : "none"
    }

    private static func vmessURI(_ profile: Profile) throws -> String {
        guard !profile.uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.unsupported("\(profile.name) is missing UUID.")
        }
        let payload: [String: Any] = [
            "v": "2",
            "ps": profile.name,
            "add": profile.server,
            "port": String(profile.serverPort),
            "id": profile.uuid,
            "aid": "0",
            "scy": "auto",
            "net": profile.transport.kind.rawValue,
            "type": profile.transport.headerType ?? "none",
            "host": profile.transport.host,
            "path": profile.transport.path,
            "tls": securityValue(for: profile) == "none" ? "" : securityValue(for: profile),
            "sni": profile.tls.serverName,
            "alpn": profile.tls.alpn.joined(separator: ","),
            "fp": profile.tls.fingerprint,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return "vmess://\(data.base64EncodedString())"
    }

    private static func shadowsocksURI(_ profile: Profile) throws -> String {
        guard !profile.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !profile.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.unsupported("\(profile.name) is missing Shadowsocks credentials.")
        }
        guard !profile.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.serverPort > 0 else {
            throw ExportError.unsupported("\(profile.name) is missing server details.")
        }

        let credentials = "\(profile.method):\(profile.password)"
            .data(using: .utf8)?
            .base64EncodedString() ?? ""
        var components = URLComponents()
        components.scheme = "ss"
        components.host = profile.server
        components.port = profile.serverPort
        components.user = credentials
        components.fragment = profile.name

        guard let url = components.url?.absoluteString else {
            throw ExportError.unsupported("Couldn't export \(profile.name).")
        }
        return url
    }
}
