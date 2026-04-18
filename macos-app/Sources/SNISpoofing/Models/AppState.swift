import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case error(String)

        var isRunning: Bool {
            if case .running = self { return true } else { return false }
        }
        var isTransitioning: Bool {
            switch self {
            case .starting, .stopping: return true
            default: return false
            }
        }
        var label: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting…"
            case .running: return "Running"
            case .stopping: return "Stopping…"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    @Published var settings: AppSettings
    @Published var profiles: [Profile]
    /// Written to `<pythonProjectPath>/config.json` on Start.
    @Published var listenerProject: ListenerProjectConfig
    /// macOS login password for `sudo` (never persisted).
    @Published var sudoPassword: String = ""

    @Published var status: Status = .stopped
    @Published var logs: [LogLine] = []
    @Published var startedAt: Date?

    @Published var egressIP: String?
    @Published var egressCountry: String?
    @Published var egressLookupMessage: String?

    @Published var directIP: String?
    @Published var directCountry: String?
    @Published var directLookupMessage: String?

    private let store = ConfigStore()
    private let python = PythonListener()
    private let xray = XrayCoreManager()

    init() {
        self.settings = store.loadSettings() ?? .default
        self.profiles = store.loadProfiles()
        self.listenerProject = store.loadListenerProjectConfig() ?? .default

        python.onLog = { [weak self] line in
            Task { @MainActor in
                self?.appendLog(line, prefix: "[L1] ")
            }
        }
        xray.onLog = { [weak self] line in
            Task { @MainActor in
                self?.appendLog(line, prefix: "[L2] ")
            }
        }

        Task { [weak self] in await self?.runDirectIPLookup() }
    }

    private func appendLog(_ line: LogLine, prefix: String) {
        let l = LogLine(timestamp: line.timestamp, stream: line.stream, text: prefix + line.text)
        if logs.count > 5000 { logs.removeFirst(1000) }
        logs.append(l)
    }

    func refreshDirectIP() {
        Task { [weak self] in await self?.runDirectIPLookup() }
    }

    private func runDirectIPLookup() async {
        directLookupMessage = "Looking up public IP…"
        do {
            let r = try await EgressInfoService.fetchDirect()
            directIP = r.ip
            directCountry = r.country
            directLookupMessage = nil
        } catch {
            directLookupMessage = error.localizedDescription
        }
    }

    func saveSettings() { store.saveSettings(settings) }
    func saveProfiles() { store.saveProfiles(profiles) }
    func saveListenerProject() { store.saveListenerProjectConfig(listenerProject) }

    var activeProfile: Profile? {
        guard let id = settings.activeProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    func upsert(_ profile: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
            if settings.activeProfileID == nil {
                settings.activeProfileID = profile.id
                saveSettings()
            }
        }
        saveProfiles()
    }

    func delete(profileID id: UUID) {
        profiles.removeAll { $0.id == id }
        if settings.activeProfileID == id {
            settings.activeProfileID = profiles.first?.id
            saveSettings()
        }
        saveProfiles()
    }

    func setActive(_ id: UUID) {
        settings.activeProfileID = id
        saveSettings()
    }

    @discardableResult
    func importFromURL(_ raw: String) throws -> Profile {
        let p = try ProfileImporter.importFrom(raw)
        upsert(p)
        return p
    }

    func start() async {
        saveSettings()
        saveProfiles()
        saveListenerProject()

        guard let profile = activeProfile else {
            status = .error("No profile selected — add one in Profiles.")
            return
        }

        switch profile.kind {
        case .vless, .trojan:
            break
        case .vmess, .shadowsocks:
            status = .error("Use a VLESS or Trojan profile for this stack.")
            return
        }

        let projectURL = URL(fileURLWithPath: settings.resolvedPythonProjectPath, isDirectory: true)

        if settings.mode == .proxy {
            let want = settings.listenPort
            let free = PortAvailability.firstAvailable(
                preferred: want,
                host: settings.listenHost,
                range: 2079 ... 21_999
            )
            if free != want {
                logs.append(LogLine(
                    timestamp: Date(),
                    stream: .system,
                    text: "Port \(want) busy — using \(free) for local SOCKS (Xray)."
                ))
                settings.listenPort = free
                saveSettings()
            }
        }

        status = .starting

        do {
            try python.start(
                projectDirectory: projectURL,
                password: sudoPassword,
                config: listenerProject
            )

            try await Task.sleep(nanoseconds: 500_000_000)

            let xdata = try XrayOutboundBuilder.generate(
                settings: settings,
                profile: profile,
                bridge: listenerProject
            )
            let cfgURL = try store.writeGeneratedXrayConfig(xdata)

            logs.append(LogLine(
                timestamp: Date(),
                stream: .system,
                text: "Xray dials \(listenerProject.LISTEN_HOST):\(listenerProject.LISTEN_PORT) (from listener config). SOCKS at \(settings.listenHost):\(settings.listenPort)."
            ))

            try xray.start(configURL: cfgURL)

            startedAt = Date()
            status = .running
            scheduleEgressRefresh()
        } catch {
            await stopInternal()
            status = .error(error.localizedDescription)
            startedAt = nil
            clearEgress()
        }
    }

    func stop() async {
        status = .stopping
        await stopInternal()
        startedAt = nil
        clearEgress()
        status = .stopped
    }

    private func stopInternal() async {
        await xray.stop()
        python.stop()
    }

    func clearLogs() { logs.removeAll() }

    func refreshEgressNow() {
        scheduleEgressRefresh()
    }

    private func clearEgress() {
        egressIP = nil
        egressCountry = nil
        egressLookupMessage = nil
    }

    private func scheduleEgressRefresh() {
        egressLookupMessage = "Resolving egress…"
        egressIP = nil
        egressCountry = nil
        let host = settings.listenHost
        let port = settings.listenPort
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await self?.runEgressLookup(proxyHost: host, proxyPort: port)
        }
    }

    private func runEgressLookup(proxyHost: String, proxyPort: Int) async {
        for attempt in 0 ..< 3 {
            guard status.isRunning else { return }
            do {
                let r = try await EgressInfoService.fetchEgress(proxyHost: proxyHost, proxyPort: proxyPort)
                guard status.isRunning else { return }
                egressIP = r.ip
                egressCountry = r.country
                egressLookupMessage = nil
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                } else if status.isRunning {
                    egressLookupMessage = error.localizedDescription
                }
            }
        }
    }
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let stream: Stream
    let text: String
    enum Stream { case stdout, stderr, system }
}
