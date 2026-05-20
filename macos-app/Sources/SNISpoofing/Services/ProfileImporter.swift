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
            case .noInput: return "Paste a vless://, vmess://, trojan://, or ss:// link (and optionally the JSON block below it)."
            case .noURL: return "No vless:// / vmess:// / trojan:// / ss:// URL found in the input."
            case .parseFailed(let s): return s
            }
        }
    }

    /// Pre-flight scan of pasted text: returns the count of distinct profile URIs
    /// found, without parsing them. Used by the import sheet to show "Detected X
    /// links" before the user commits.
    static func countCandidates(in raw: String) -> Int {
        allProxyURLs(in: raw).count
    }

    /// Bulk import: extract every supported URI from `raw`, parse each one, and
    /// return the successes alongside any per-URI errors. Designed for pasting
    /// the contents of a subscription file (one URI per line, blank lines OK).
    static func importMany(from raw: String) -> (profiles: [Profile], errors: [String]) {
        let uris = allProxyURLs(in: raw)
        var profiles: [Profile] = []
        var errors: [String] = []
        for (i, uri) in uris.enumerated() {
            do {
                let p = try ProfileURLParser.parse(uri)
                profiles.append(p)
            } catch {
                let label = uri.count > 40 ? "\(uri.prefix(40))…" : uri
                errors.append("Line \(i + 1) (\(label)): \(error.localizedDescription)")
            }
        }
        return (profiles, errors)
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

    private static let schemes = ["vless://", "vmess://", "trojan://", "ss://", "shadowsocks://"]

    private static func firstProxyURL(in text: String) -> String? {
        allProxyURLs(in: text).first
    }

    /// Every supported URI in `text`, in order, de-duplicated by exact match.
    /// Handles subscription files that put one URI per line, multiple on a
    /// single line, or sprinkle them inside other prose.
    static func allProxyURLs(in text: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        // Scan line by line first (the common subscription-file layout).
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let scheme = schemes.first(where: { trimmed.lowercased().hasPrefix($0) }),
               !scheme.isEmpty {
                if seen.insert(trimmed).inserted { out.append(trimmed) }
            } else {
                // Search inside the line for any embedded URIs.
                appendURIs(in: trimmed, into: &out, seen: &seen)
            }
        }
        // If nothing came out (one giant line, no newlines), scan the whole blob.
        if out.isEmpty {
            appendURIs(in: text, into: &out, seen: &seen)
        }
        return out
    }

    private static func appendURIs(in text: String, into out: inout [String], seen: inout Set<String>) {
        var rest = Substring(text)
        while let range = rest.range(of: schemes.joined(separator: "|"), options: [.regularExpression, .caseInsensitive]) {
            let tail = rest[range.lowerBound...]
            // URI ends at the next whitespace; the `#fragment` part can contain
            // unusual chars but never whitespace.
            let endIdx = tail.firstIndex(where: { $0.isWhitespace }) ?? tail.endIndex
            let uri = String(tail[..<endIdx]).trimmingCharacters(in: .whitespaces)
            if !uri.isEmpty, seen.insert(uri).inserted {
                out.append(uri)
            }
            rest = tail[endIdx...]
        }
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
