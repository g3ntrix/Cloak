import Foundation
import CFNetwork

/// Public-IP lookup — either directly (no proxy, for showing the user's raw egress)
/// or through the local mixed proxy (to show the proxied egress).
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

    /// ipinfo.io JSON (no API key for basic fields).
    private struct IPInfoPayload: Decodable {
        let ip: String
        let country: String?
    }

    /// Fetches the egress IP as seen through the local proxy.
    static func fetchEgress(proxyHost: String, proxyPort: Int) async throws -> Egress {
        let session = makeProxiedSession(host: proxyHost, port: proxyPort)
        return try await fetch(using: session)
    }

    /// Fetches the machine's public IP directly (no proxy).
    static func fetchDirect() async throws -> Egress {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        return try await fetch(using: URLSession(configuration: config))
    }

    // MARK: - shared

    private static func fetch(using session: URLSession) async throws -> Egress {
        let url = URL(string: "https://ipinfo.io/json")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw EgressError.badResponse
        }
        let payload = try JSONDecoder().decode(IPInfoPayload.self, from: data)
        guard !payload.ip.isEmpty else { throw EgressError.decode }
        return Egress(ip: payload.ip, country: payload.country)
    }

    private static func makeProxiedSession(host: String, port: Int) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        let portNum = NSNumber(value: port)
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: portNum,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: host,
            kCFNetworkProxiesHTTPSPort as String: portNum
        ]
        return URLSession(configuration: config)
    }
}
