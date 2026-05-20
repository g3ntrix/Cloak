import Foundation

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
