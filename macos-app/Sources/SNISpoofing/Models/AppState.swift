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
            case .stopped: return "Disconnected"
            case .starting: return "Connecting…"
            case .running: return "Connected"
            case .stopping: return "Disconnecting…"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    @Published var settings: AppSettings
    @Published var profiles: [Profile]
    /// Written to `<pythonProjectPath>/config.json` on Start.
    @Published var listenerProject: ListenerProjectConfig
    /// Whether the one-time admin escalation has installed a sudoers rule.
    @Published var privilegesInstalled: Bool = SudoPrivilege.isInstalled()

    @Published var status: Status = .stopped
    @Published var logs: [LogLine] = []
    @Published var startedAt: Date?

    /// Measured bytes/second through the local SOCKS (updated ~1Hz while running).
    @Published var downloadBytesPerSec: Double = 0
    @Published var uploadBytesPerSec: Double = 0
    /// Cumulative RX/TX since this session’s `startedAt` (same counter source as speed).
    @Published var sessionBytesDown: UInt64 = 0
    @Published var sessionBytesUp: UInt64 = 0

    @Published var egressIP: String?
    @Published var egressCountry: String?
    @Published var egressLookupMessage: String?

    @Published var directIP: String?
    @Published var directCountry: String?
    @Published var directLookupMessage: String?

    private let store = ConfigStore()
    private let python = PythonListener()
    private let xray = XrayCoreManager()
    /// Tracks whether we flipped the system SOCKS proxy on (must be flipped back off on stop).
    private var systemProxyActive = false
    /// True when we started the Python listener only for Profiles ping (not full VPN).
    private var listenerStartedForPingOnly = false
    private var sessionBaselineRx: UInt64 = 0
    private var sessionBaselineTx: UInt64 = 0

    init() {
        self.settings = store.loadSettings() ?? .default
        self.profiles = store.loadProfiles()
        self.listenerProject = store.loadListenerProjectConfig() ?? .default
        seedBundledProfilesIfNeeded()

        python.onLog = { [weak self] line in
            Task { @MainActor in self?.appendLog(line, prefix: "") }
        }
        xray.onLog = { [weak self] line in
            Task { @MainActor in self?.appendLog(line, prefix: "") }
        }

        Task { [weak self] in await self?.runDirectIPLookup() }
    }

    /// Adds bundled example profiles if they are not already present (by server/port/SNI).
    /// Runs on every launch but only appends missing entries — not only on first empty install,
    /// so users who already had other profiles still get these once.
    private func seedBundledProfilesIfNeeded() {
        let seeds = [
            "trojan://humanity@127.0.0.1:40443?security=tls&sni=www.ignitelimit.com&type=ws&path=/assignment&host=www.ignitelimit.com#Amirstar",
            "trojan://humanity@127.0.0.1:40443?security=tls&sni=www.creationlong.org&allowInsecure=1&type=ws&path=/assignment&host=www.creationlong.org#cloud"
        ]
        var appended: [Profile] = []
        for raw in seeds {
            guard let parsed = try? ProfileImporter.importFrom(raw) else { continue }
            let dup = profiles.contains { existing in
                existing.kind == parsed.kind
                    && existing.server == parsed.server
                    && existing.serverPort == parsed.serverPort
                    && existing.tls.serverName == parsed.tls.serverName
            }
            if !dup {
                appended.append(parsed)
            }
        }
        guard !appended.isEmpty else { return }
        profiles.append(contentsOf: appended)
        if settings.activeProfileID == nil {
            settings.activeProfileID = profiles.first?.id
            saveSettings()
        }
        saveProfiles()
    }

    private func appendLog(_ line: LogLine, prefix: String) {
        guard settings.logsEnabled else { return }
        let l = LogLine(timestamp: line.timestamp, stream: line.stream, text: prefix + line.text)
        if logs.count > 5000 { logs.removeFirst(1000) }
        logs.append(l)
    }

    /// Synchronous best-effort shutdown for app termination paths where async
    /// `stop()` would race the process exit. Tears down xray + python and
    /// removes TUN routes if they were applied.
    func terminateSync() {
        if systemProxyActive {
            SystemProxy.disableSync()
            systemProxyActive = false
        }
        xray.stopSync()
        python.stop()
        // Belt-and-suspenders: kill any orphaned listener spawned via sudo
        // wrapper (the user's macOS reported a leftover python heating up
        // the machine after a previous version's window was closed).
        SudoPrivilege.killLeftoverListener()
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
        listenerStartedForPingOnly = false
        saveSettings()
        saveProfiles()
        saveListenerProject()

        guard let profile = activeProfile else {
            status = .error("No profile selected — import one in Profiles.")
            return
        }

        switch profile.kind {
        case .vless, .trojan:
            break
        case .vmess, .shadowsocks:
            status = .error("This profile type isn't supported yet — use a VLESS or Trojan config.")
            return
        }

        let projectURL = URL(fileURLWithPath: settings.resolvedPythonProjectPath, isDirectory: true)

        let want = settings.listenPort
        let free = PortAvailability.firstAvailable(
            preferred: want,
            host: settings.listenHost,
            range: 2079 ... 21_999
        )
        if free != want {
            settings.listenPort = free
            saveSettings()
        }

        status = .starting

        do {
            // One admin prompt installs both helpers (listener + proxy toggle).
            if !SudoPrivilege.isInstalled() {
                try SudoPrivilege.install()
                privilegesInstalled = true
            }

            try python.start(
                projectDirectory: projectURL,
                config: listenerProject
            )

            try await awaitListenerReady()

            let xdata = try XrayOutboundBuilder.generate(
                settings: settings,
                profile: profile,
                bridge: listenerProject
            )
            let cfgURL = try store.writeGeneratedXrayConfig(xdata)

            try xray.start(configURL: cfgURL)

            // Give xray a beat to open its SOCKS port before flipping the
            // system proxy onto it — otherwise the first wave of system
            // traffic races the listener coming up and looks like a failure.
            try await Task.sleep(nanoseconds: 400_000_000)

            if settings.useSystemProxy {
                let host = settings.resolvedSocksHostForLocalClient
                switch SystemProxy.enable(host: host, port: settings.listenPort) {
                case .ok:
                    systemProxyActive = true
                case .failed(let msg):
                    throw NSError(
                        domain: "SNISpoofing",
                        code: 23,
                        userInfo: [NSLocalizedDescriptionKey: "Couldn't flip the system proxy on: \(msg)"]
                    )
                }
            }

            startedAt = Date()
            if let c = NetworkCounters.totalRXTXBytes() {
                sessionBaselineRx = c.rx
                sessionBaselineTx = c.tx
            } else {
                sessionBaselineRx = 0
                sessionBaselineTx = 0
            }
            sessionBytesDown = 0
            sessionBytesUp = 0
            status = .running
            scheduleEgressRefresh()
            startBandwidthSampler()
        } catch {
            if systemProxyActive {
                SystemProxy.disableSync()
                systemProxyActive = false
            }
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
        downloadBytesPerSec = 0
        uploadBytesPerSec = 0
        sessionBytesDown = 0
        sessionBytesUp = 0
        bandwidthTimer?.invalidate()
        bandwidthTimer = nil
        status = .stopped
    }

    private func stopInternal() async {
        if systemProxyActive {
            SystemProxy.disableSync()
            systemProxyActive = false
        }
        await xray.stop()
        python.stop()
    }

    // MARK: - Bandwidth sampler

    private var bandwidthTimer: Timer?
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastSampleAt: Date?

    private func startBandwidthSampler() {
        bandwidthTimer?.invalidate()
        lastBytesIn = 0
        lastBytesOut = 0
        lastSampleAt = nil
        bandwidthTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleBandwidth() }
        }
    }

    private func sampleBandwidth() {
        guard status.isRunning else { return }
        // We sample the total bytes in/out of our Swift process as a proxy for
        // traffic through the local SOCKS — Xray is a child so its throughput
        // rolls up. Good enough for a "speed" display; exact per-flow stats
        // would require enabling Xray's Stats API.
        guard let counters = NetworkCounters.totalRXTXBytes() else { return }
        sessionBytesDown = counters.rx >= sessionBaselineRx ? counters.rx - sessionBaselineRx : 0
        sessionBytesUp = counters.tx >= sessionBaselineTx ? counters.tx - sessionBaselineTx : 0
        let now = Date()
        if let last = lastSampleAt {
            let dt = max(0.2, now.timeIntervalSince(last))
            let dIn = counters.rx > lastBytesIn ? Double(counters.rx - lastBytesIn) : 0
            let dOut = counters.tx > lastBytesOut ? Double(counters.tx - lastBytesOut) : 0
            downloadBytesPerSec = dIn / dt
            uploadBytesPerSec = dOut / dt
        }
        lastBytesIn = counters.rx
        lastBytesOut = counters.tx
        lastSampleAt = now
    }

    // MARK: - Profiles ping (listener-only)

    /// TCP target for probing `LISTEN_HOST` (NWConnection cannot use `0.0.0.0`).
    static func resolvedPingHost(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty || t == "0.0.0.0" || t == "*" { return "127.0.0.1" }
        if t == "localhost" { return "127.0.0.1" }
        if t == "::" { return "::1" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Starts the Python listener if needed so ping can reach `LISTEN_HOST`/`LISTEN_PORT`.
    func prepareListenerForPing() async throws {
        if status.isRunning { return }
        saveListenerProject()
        if !SudoPrivilege.isInstalled() {
            try SudoPrivilege.install()
            privilegesInstalled = true
        }
        let projectURL = URL(fileURLWithPath: settings.resolvedPythonProjectPath, isDirectory: true)
        let startedNow: Bool
        if python.isRunning() {
            startedNow = false
        } else {
            try python.start(projectDirectory: projectURL, config: listenerProject)
            listenerStartedForPingOnly = true
            startedNow = true
        }
        try await awaitListenerReady()
        if startedNow {
            python.stop()
            listenerStartedForPingOnly = false
        }
        throw NSError(
            domain: "SNISpoofing",
            code: 30,
            userInfo: [NSLocalizedDescriptionKey: "Listener did not accept connections in time. Check Settings → Cloudflare JSON (LISTEN_HOST / LISTEN_PORT)."]
        )
    }

    /// Stops the listener if this session started it for ping only.
    func endPingListenerIfNeeded() {
        guard listenerStartedForPingOnly else { return }
        listenerStartedForPingOnly = false
        if !status.isRunning {
            python.stop()
        }
    }

    private func awaitListenerReady() async throws {
        let host = Self.resolvedPingHost(listenerProject.LISTEN_HOST)
        let port = UInt16(clamping: listenerProject.LISTEN_PORT)
        for _ in 0 ..< 30 {
            if !python.isRunning() {
                throw NSError(
                    domain: "SNISpoofing",
                    code: 31,
                    userInfo: [NSLocalizedDescriptionKey: "Python listener exited before becoming ready. Open Logs for the first traceback."]
                )
            }
            let r = await RealPingService.ping(host: host, port: port, timeout: 1)
            if r.millis != nil { return }
            try await Task.sleep(nanoseconds: 350_000_000)
        }
        throw NSError(
            domain: "SNISpoofing",
            code: 30,
            userInfo: [NSLocalizedDescriptionKey: "Listener did not accept connections in time. Check Settings → Cloudflare JSON (LISTEN_HOST / LISTEN_PORT)."]
        )
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
        let host = settings.resolvedSocksHostForLocalClient
        let port = settings.listenPort
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await self?.runEgressLookup(proxyHost: host, proxyPort: port)
        }
    }

    /// Restart the stack to pick up a settings change (port, proxy toggle, etc.).
    func reconnectIfRunning() async {
        guard status.isRunning else { return }
        await stop()
        await start()
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
