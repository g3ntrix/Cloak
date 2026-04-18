import Foundation

/// Combines a VLESS-style URL with the legacy 5-field spoof JSON into a single Profile.
///
/// The user's legacy flow had two inputs:
///   1. A `vless://…@real-host:443?sni=…` URL they would paste into v2rayN.
///   2. A JSON file with {LISTEN_HOST, LISTEN_PORT, CONNECT_IP, CONNECT_PORT, FAKE_SNI}
///      that told `main.py` where to relay traffic and which SNI to forge.
///
/// Cloak collapses both into one Profile:
///   - The URL provides server, port, UUID, real SNI, transport, etc.
///   - The JSON provides FAKE_SNI (→ `tls.spoof`) and optional CONNECT_HOST / CONNECT_IP / PORT
///     (→ dial domain or pin a specific edge IP, e.g. Cloudflare).
///   - LISTEN_HOST/PORT from the legacy JSON are deliberately ignored — Cloak's
///     own settings (Settings → listenHost/listenPort) own that now.
enum ProfileImporter {

    struct SpoofJSON: Decodable {
        let LISTEN_HOST: String?
        let LISTEN_PORT: Int?
        /// Optional dial hostname (e.g. CDN entry `k4.example.com`) when you do not use CONNECT_IP.
        let CONNECT_HOST: String?
        let CONNECT_IP: String?
        let CONNECT_PORT: Int?
        let FAKE_SNI: String?
    }

    enum ImportError: LocalizedError {
        case noInput
        case noURL
        case parseFailed(String)
        var errorDescription: String? {
            switch self {
            case .noInput: return "Paste a vless:// or trojan:// link (and optionally the JSON block below it)."
            case .noURL: return "No vless:// / trojan:// URL found in the input."
            case .parseFailed(let s): return s
            }
        }
    }

    /// Returns a fully-wired Profile from mixed user paste.
    /// Accepts: just a URL, just a JSON block, or both (in any order, on any lines).
    static func importFrom(_ raw: String) throws -> Profile {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.noInput }

        // Pull the first v2ray-style URL from the text.
        let url = firstProxyURL(in: trimmed)
        let jsonBlob = firstJSONBlock(in: trimmed)

        var profile: Profile
        if let urlText = url {
            do {
                profile = try ProfileURLParser.parse(urlText)
            } catch {
                throw ImportError.parseFailed(error.localizedDescription)
            }
        } else {
            throw ImportError.noURL
        }

        // Merge JSON overrides (same keys as repo `config.json` for main.py).
        if let blob = jsonBlob, let data = blob.data(using: .utf8) {
            do {
                let spoof = try JSONDecoder().decode(SpoofJSON.self, from: data)
                applySpoofJSON(spoof, to: &profile)
            } catch {
                throw ImportError.parseFailed("Invalid JSON: \(error.localizedDescription)")
            }
        }

        // Loopback `@127.0.0.1` URLs are OK: layer-2 Xray dials `LISTEN_HOST:LISTEN_PORT` from Settings → listener JSON.
        return profile
    }

    private static func applySpoofJSON(_ j: SpoofJSON, to p: inout Profile) {
        if var fake = j.FAKE_SNI?.trimmingCharacters(in: .whitespacesAndNewlines), !fake.isEmpty {
            while fake.hasSuffix(".") { fake.removeLast() }
            p.tls.enabled = true
            p.tls.enableSpoof = true
            p.tls.fakeSNI = fake
        }
        // Optional dial domain (e.g. real vless `address` / CDN entry), then optional IP pin.
        if let ch = j.CONNECT_HOST?.trimmingCharacters(in: .whitespacesAndNewlines), !ch.isEmpty {
            var h = ch
            while h.hasSuffix(".") { h.removeLast() }
            p.server = h
        }
        if let ip = j.CONNECT_IP?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty {
            if p.tls.serverName.isEmpty, !p.server.isEmpty {
                p.tls.serverName = p.server
            }
            p.server = ip
        }
        if let port = j.CONNECT_PORT, port > 0 {
            p.serverPort = port
        }
    }

    // MARK: - tokenising helpers

    private static let schemes = ["vless://", "vmess://", "trojan://", "ss://"]

    private static func firstProxyURL(in text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            for scheme in schemes where t.lowercased().hasPrefix(scheme) {
                return t
            }
        }
        // Also search within a line (paste might be a blob).
        for scheme in schemes {
            if let range = text.range(of: scheme, options: .caseInsensitive) {
                let tail = text[range.lowerBound...]
                let endIdx = tail.firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? tail.endIndex
                return String(tail[..<endIdx])
            }
        }
        return nil
    }

    /// Returns the substring between the first `{` and its matching `}`.
    private static func firstJSONBlock(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < text.endIndex {
            switch text[idx] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    let next = text.index(after: idx)
                    return String(text[start..<next])
                }
            default: break
            }
            idx = text.index(after: idx)
        }
        return nil
    }
}
