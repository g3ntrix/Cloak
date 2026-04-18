import Foundation

/// Same keys as `config.json` next to `main.py` in your listener project (editable in Settings).
struct ListenerProjectConfig: Codable, Equatable {
    var LISTEN_HOST: String = "127.0.0.1"
    var LISTEN_PORT: Int = 40443
    var CONNECT_IP: String = ""
    var CONNECT_PORT: Int = 443
    var FAKE_SNI: String = ""

    static let `default` = ListenerProjectConfig()

    /// Values used by **Restore default** in Settings (full example config).
    static let factoryRestore = ListenerProjectConfig(
        LISTEN_HOST: "127.0.0.1",
        LISTEN_PORT: 40443,
        CONNECT_IP: "104.19.229.21",
        CONNECT_PORT: 443,
        FAKE_SNI: "hcaptcha.com"
    )

    /// Pretty JSON for the editor (empty CONNECT/FAKE placeholders).
    static func defaultJSONString() -> String {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(ListenerProjectConfig.default)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    /// JSON for **Restore default** (factory example).
    static func factoryRestoreJSONString() -> String {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(factoryRestore)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    static func decode(from string: String) throws -> ListenerProjectConfig {
        let data = Data(string.utf8)
        return try JSONDecoder().decode(ListenerProjectConfig.self, from: data)
    }

    func encodeJSONString() throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
