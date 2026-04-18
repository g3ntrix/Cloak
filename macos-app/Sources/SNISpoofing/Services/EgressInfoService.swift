import Foundation

/// Public-IP lookup — direct (no proxy) or through the local SOCKS5 (Xray).
/// Proxied lookups use `curl --socks5-hostname` because `URLSession` SOCKS support is unreliable for HTTPS on macOS.
enum EgressInfoService {
    struct Egress: Equatable {
        let ip: String
        let country: String?
    }

    enum EgressError: LocalizedError {
        case badResponse
        case decode

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Unexpected response from IP lookup."
            case .decode: return "Could not parse IP lookup response."
            }
        }
    }

    private struct IPInfoPayload: Decodable {
        let ip: String
        let country: String?
    }
    private struct IPApiPayload: Decodable {
        let query: String
        let countryCode: String?
    }

    /// Fetches the egress IP as seen through the local SOCKS proxy (`host` must be usable by curl — not `0.0.0.0`).
    static func fetchEgress(proxyHost: String, proxyPort: Int) async throws -> Egress {
        try await fetchThroughSocks5(proxyHost: proxyHost, proxyPort: proxyPort)
    }

    /// Fetches the machine's public IP directly (no proxy).
    static func fetchDirect() async throws -> Egress {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        return try await fetchHTTPS(using: URLSession(configuration: config))
    }

    // MARK: - Direct HTTPS (URLSession)

    private static func fetchHTTPS(using session: URLSession) async throws -> Egress {
        let url = URL(string: "https://ipinfo.io/json")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw EgressError.badResponse
        }
        let payload = try JSONDecoder().decode(IPInfoPayload.self, from: data)
        guard !payload.ip.isEmpty else { throw EgressError.decode }
        return Egress(ip: payload.ip, country: payload.country)
    }

    // MARK: - Via SOCKS5 (curl)

    private static func fetchThroughSocks5(proxyHost: String, proxyPort: Int) async throws -> Egress {
        let socks = socks5Endpoint(host: proxyHost, port: proxyPort)
        return try await Task.detached(priority: .utility) {
            do {
                let data = try runCurlJSON(
                    socks: socks,
                    url: "https://ipinfo.io/json"
                )
                let payload = try JSONDecoder().decode(IPInfoPayload.self, from: data)
                guard !payload.ip.isEmpty else { throw EgressError.decode }
                return Egress(ip: payload.ip, country: payload.country)
            } catch {
                // Fallback for environments where curl+LibreSSL fails TLS over SOCKS.
                let data = try runCurlJSON(
                    socks: socks,
                    url: "http://ip-api.com/json"
                )
                let payload = try JSONDecoder().decode(IPApiPayload.self, from: data)
                guard !payload.query.isEmpty else { throw EgressError.decode }
                return Egress(ip: payload.query, country: payload.countryCode)
            }
        }.value
    }

    private static func runCurlJSON(socks: String, url: String) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = [
            "-sS", "--max-time", "25",
            "--socks5-hostname", socks,
            url,
        ]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0, !data.isEmpty else {
            let msg = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "SNISpoofing",
                code: 40,
                userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "IP lookup through proxy failed (curl)." : msg]
            )
        }
        return data
    }

    /// `host:port` or `[ipv6]:port` for curl `--socks5-hostname`.
    private static func socks5Endpoint(host: String, port: Int) -> String {
        let t = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains(":"), !isIPv4DottedDecimal(t) {
            return "[\(t)]:\(port)"
        }
        return "\(t):\(port)"
    }

    private static func isIPv4DottedDecimal(_ s: String) -> Bool {
        let p = s.split(separator: ".")
        guard p.count == 4 else { return false }
        return p.allSatisfy { oct in
            guard let n = Int(oct), (0 ... 255).contains(n) else { return false }
            return true
        }
    }
}
