import Foundation

enum ProxyLogLevel: String, Codable, Equatable {
    case debug
    case info
    case error

    static func parse(_ rawValue: String?) -> ProxyLogLevel {
        guard let rawValue else { return .info }
        return ProxyLogLevel(rawValue: rawValue.lowercased()) ?? .info
    }
}

enum AppConnectionMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case proxy
    case tunnel

    var id: String { rawValue }

    static func parse(_ rawValue: String?) -> AppConnectionMode {
        guard let rawValue else { return .proxy }
        return AppConnectionMode(rawValue: rawValue.lowercased()) ?? .proxy
    }
}

struct TunnelConfiguration: Codable, Equatable {
    static let providerBundleIdentifier = "io.github.snispoofinggui.cloak.PacketTunnel"
    static let defaults = TunnelConfiguration(
        listenHost: "127.0.0.1",
        listenPort: 40443,
        connectIP: "127.0.0.1",
        connectPort: 40443,
        upstreamIP: "127.0.0.1",
        upstreamPort: 40443,
        fakeSNI: "hcaptcha.com",
        logLevel: .info,
        connectionMode: .proxy,
        httpProxyPort: nil,
        socksProxyPort: nil,
        dnsServers: [],
        excludedIPv4Addresses: []
    )

    var listenHost: String
    var listenPort: Int
    var connectIP: String
    var connectPort: Int
    var upstreamIP: String
    var upstreamPort: Int
    var fakeSNI: String
    var logLevel: ProxyLogLevel
    var connectionMode: AppConnectionMode
    var httpProxyPort: Int?
    var socksProxyPort: Int?
    var dnsServers: [String]
    var excludedIPv4Addresses: [String]

    init(
        listenHost: String,
        listenPort: Int,
        connectIP: String,
        connectPort: Int,
        upstreamIP: String,
        upstreamPort: Int,
        fakeSNI: String,
        logLevel: ProxyLogLevel,
        connectionMode: AppConnectionMode,
        httpProxyPort: Int?,
        socksProxyPort: Int?,
        dnsServers: [String],
        excludedIPv4Addresses: [String]
    ) {
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.connectIP = connectIP
        self.connectPort = connectPort
        self.upstreamIP = upstreamIP
        self.upstreamPort = upstreamPort
        self.fakeSNI = fakeSNI
        self.logLevel = logLevel
        self.connectionMode = connectionMode
        self.httpProxyPort = httpProxyPort
        self.socksProxyPort = socksProxyPort
        self.dnsServers = dnsServers
        self.excludedIPv4Addresses = excludedIPv4Addresses
    }

    init(providerConfiguration: [String: Any]?) {
        let defaults = Self.defaults
        listenHost = providerConfiguration?["listenHost"] as? String ?? defaults.listenHost
        listenPort = (providerConfiguration?["listenPort"] as? NSNumber)?.intValue ?? defaults.listenPort
        connectIP = providerConfiguration?["connectIP"] as? String ?? defaults.connectIP
        connectPort = (providerConfiguration?["connectPort"] as? NSNumber)?.intValue ?? defaults.connectPort
        upstreamIP = providerConfiguration?["upstreamIP"] as? String ?? defaults.upstreamIP
        upstreamPort = (providerConfiguration?["upstreamPort"] as? NSNumber)?.intValue ?? defaults.upstreamPort
        fakeSNI = providerConfiguration?["fakeSNI"] as? String ?? defaults.fakeSNI
        logLevel = ProxyLogLevel.parse(providerConfiguration?["logLevel"] as? String)
        connectionMode = AppConnectionMode.parse(providerConfiguration?["connectionMode"] as? String)
        httpProxyPort = (providerConfiguration?["httpProxyPort"] as? NSNumber)?.intValue
        socksProxyPort = (providerConfiguration?["socksProxyPort"] as? NSNumber)?.intValue
        dnsServers = providerConfiguration?["dnsServers"] as? [String] ?? defaults.dnsServers
        excludedIPv4Addresses = providerConfiguration?["excludedIPv4Addresses"] as? [String] ?? defaults.excludedIPv4Addresses
    }

    func providerConfigurationDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "listenHost": listenHost as NSString,
            "listenPort": NSNumber(value: listenPort),
            "connectIP": connectIP as NSString,
            "connectPort": NSNumber(value: connectPort),
            "upstreamIP": upstreamIP as NSString,
            "upstreamPort": NSNumber(value: upstreamPort),
            "fakeSNI": fakeSNI as NSString,
            "logLevel": logLevel.rawValue as NSString,
            "connectionMode": connectionMode.rawValue as NSString,
        ]
        if let httpProxyPort { dictionary["httpProxyPort"] = NSNumber(value: httpProxyPort) }
        if let socksProxyPort { dictionary["socksProxyPort"] = NSNumber(value: socksProxyPort) }
        if !dnsServers.isEmpty { dictionary["dnsServers"] = dnsServers as NSArray }
        if !excludedIPv4Addresses.isEmpty { dictionary["excludedIPv4Addresses"] = excludedIPv4Addresses as NSArray }
        return dictionary
    }
}

enum TunnelCommand: String, Codable {
    case getStatus
    case reloadConfiguration
}

struct TunnelAppMessage: Codable {
    let command: TunnelCommand
}

struct TunnelProviderStatus: Codable, Equatable {
    var phase: String
    var packetCount: Int
    var bytesUploaded: Int
    var bytesDownloaded: Int
    var connectIP: String
    var connectPort: Int
    var fakeSNI: String
    var detail: String?
    var startedAtISO8601: String?
}

enum TunnelIPC {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
