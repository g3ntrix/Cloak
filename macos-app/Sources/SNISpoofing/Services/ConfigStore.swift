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
}
