import Foundation

/// Persists app settings, profiles, `main.py` listener JSON, and the generated Xray config.
final class ConfigStore {
    private let fm = FileManager.default

    private var appSupportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SNISpoofing", isDirectory: true)
    }

    private var settingsFile: URL { appSupportDir.appendingPathComponent("settings.json") }
    private var profilesFile: URL { appSupportDir.appendingPathComponent("profiles.json") }
    private var listenerProjectFile: URL { appSupportDir.appendingPathComponent("listener-project.json") }
    private var generatedXrayFile: URL { appSupportDir.appendingPathComponent("xray.generated.json") }
    private var pingResultsFile: URL { appSupportDir.appendingPathComponent("ping-results.json") }

    init() {
        try? fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings? {
        guard let data = try? Data(contentsOf: settingsFile) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    func saveSettings(_ s: AppSettings) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(s) {
            try? data.write(to: settingsFile, options: .atomic)
        }
    }

    // MARK: - Profiles

    func loadProfiles() -> [Profile] {
        guard let data = try? Data(contentsOf: profilesFile) else { return [] }
        return (try? JSONDecoder().decode([Profile].self, from: data)) ?? []
    }

    func saveProfiles(_ profiles: [Profile]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(profiles) {
            try? data.write(to: profilesFile, options: .atomic)
        }
    }

    // MARK: - Listener project (main.py config.json mirror)

    func loadListenerProjectConfig() -> ListenerProjectConfig? {
        guard let data = try? Data(contentsOf: listenerProjectFile) else { return nil }
        return try? JSONDecoder().decode(ListenerProjectConfig.self, from: data)
    }

    func saveListenerProjectConfig(_ c: ListenerProjectConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(c) {
            try? data.write(to: listenerProjectFile, options: .atomic)
        }
    }

    // MARK: - Generated Xray config

    @discardableResult
    func writeGeneratedXrayConfig(_ json: Data) throws -> URL {
        try json.write(to: generatedXrayFile, options: .atomic)
        return generatedXrayFile
    }

    var generatedXrayConfigPath: String { generatedXrayFile.path }

    // MARK: - Profile ping cache

    func loadPingResults() -> [UUID: RealPingService.Result] {
        guard let data = try? Data(contentsOf: pingResultsFile) else { return [:] }
        let decoded = (try? JSONDecoder().decode([String: PersistedPingResult].self, from: data)) ?? [:]
        var out: [UUID: RealPingService.Result] = [:]
        for (key, value) in decoded {
            guard let id = UUID(uuidString: key) else { continue }
            out[id] = value.result
        }
        return out
    }

    func savePingResults(_ results: [UUID: RealPingService.Result]) {
        var encoded: [String: PersistedPingResult] = [:]
        for (id, result) in results {
            encoded[id.uuidString] = PersistedPingResult(result: result)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(encoded) {
            try? data.write(to: pingResultsFile, options: .atomic)
        }
    }
}

private struct PersistedPingResult: Codable {
    var millis: Int?
    var error: String?

    init(result: RealPingService.Result) {
        millis = result.millis
        error = result.error
    }

    var result: RealPingService.Result {
        RealPingService.Result(millis: millis, error: error)
    }
}
