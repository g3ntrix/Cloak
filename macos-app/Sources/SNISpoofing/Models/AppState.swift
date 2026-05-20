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

    @Published var profilePingResults: [UUID: RealPingService.Result] = [:]
    @Published var profilePingingIDs: Set<UUID> = []
    @Published var isPingBatchRunning = false

    private let store = ConfigStore()
    private let python = PythonListener()
    private let xray = XrayCoreManager()
    private let packetTunnel = PacketTunnelManager()
    /// Tracks whether we flipped the system SOCKS proxy on (must be flipped back off on stop).
    private var systemProxyActive = false
    /// Tracks whether we started the NetworkExtension packet tunnel.
    private var tunnelActive = false
    /// True when we started the Python listener only for Profiles ping (not full VPN).
    private var listenerStartedForPingOnly = false
    private var sessionBaselineRx: UInt64 = 0
    private var sessionBaselineTx: UInt64 = 0
    private var pingBatchToken: UUID?
    private var pingBatchTask: Task<Void, Never>?

    init() {
        self.settings = store.loadSettings() ?? .default
        self.profiles = store.loadProfiles()
        self.listenerProject = store.loadListenerProjectConfig() ?? .default
        self.profilePingResults = store.loadPingResults()
        seedBundledProfilesIfNeeded()

        python.onLog = { [weak self] line in
            Task { @MainActor in self?.appendLog(line, prefix: "") }
        }
        xray.onLog = { [weak self] line in
            Task { @MainActor in self?.appendLog(line, prefix: "") }
        }
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
        if tunnelActive {
            packetTunnel.stopSync()
            tunnelActive = false
        }
        xray.stopSync()
        python.stop()
        // Belt-and-suspenders: kill any orphaned listener spawned via sudo
        // wrapper (the user's macOS reported a leftover python heating up
        // the machine after a previous version's window was closed).
        SudoPrivilege.killLeftoverListener()
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
        profilePingResults.removeValue(forKey: id)
        persistPingResults()
        if settings.activeProfileID == id {
            settings.activeProfileID = profiles.first?.id
            saveSettings()
        }
        saveProfiles()
    }

    /// Profiles with no successful ping (failed, untested, or missing ms).
    var profilesWithoutSuccessfulPing: [Profile] {
        profiles.filter { profilePingResults[$0.id]?.millis == nil }
    }

    @discardableResult
    func deleteProfilesWithoutSuccessfulPing() -> Int {
        let doomed = profilesWithoutSuccessfulPing.map(\.id)
        guard !doomed.isEmpty else { return 0 }
        for id in doomed {
            delete(profileID: id)
        }
        return doomed.count
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

    struct ImportSummary {
        var added: Int
        var duplicates: Int
        var failed: [String]
        var firstAddedID: UUID?
        var totalParsed: Int { added + duplicates }
    }

    /// Bulk-import every URI we can find in `raw`, skipping ones that are
    /// already in the library (same kind + server + port + secret + SNI).
    /// The first imported profile becomes active if no profile is set yet.
    @discardableResult
    func importMany(from raw: String) -> ImportSummary {
        let parse = ProfileImporter.importMany(from: raw)
        var added = 0
        var duplicates = 0
        var firstAddedID: UUID?
        for parsed in parse.profiles {
            let isDuplicate = profiles.contains { existing in
                existing.kind == parsed.kind
                    && existing.server == parsed.server
                    && existing.serverPort == parsed.serverPort
                    && existing.tls.serverName == parsed.tls.serverName
                    && existing.uuid == parsed.uuid
                    && existing.password == parsed.password
            }
            if isDuplicate {
                duplicates += 1
                continue
            }
            profiles.append(parsed)
            if firstAddedID == nil { firstAddedID = parsed.id }
            added += 1
        }
        if added > 0 {
            if settings.activeProfileID == nil, let id = firstAddedID {
                settings.activeProfileID = id
                saveSettings()
            }
            saveProfiles()
        }
        return ImportSummary(
            added: added,
            duplicates: duplicates,
            failed: parse.errors,
            firstAddedID: firstAddedID
        )
    }

    /// Inline rename — keeps focus and existing selection state in the view.
    func rename(profileID id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = profiles.firstIndex(where: { $0.id == id }), !trimmed.isEmpty else { return }
        profiles[idx].name = trimmed
        saveProfiles()
    }

    func start() async {
        listenerStartedForPingOnly = false
        saveSettings()
        saveProfiles()
        saveListenerProject()

        guard let profile = activeProfile else {
            status = .error("No profile selected. Import one in Profiles.")
            return
        }

        let wantedSocks = settings.listenPort
        let freeSocks = PortAvailability.firstAvailable(
            preferred: wantedSocks,
            host: settings.listenHost,
            range: 2079 ... 21_999
        )
        if freeSocks != wantedSocks {
            settings.listenPort = freeSocks
            saveSettings()
        }
        let wantedHTTP = settings.httpPort == settings.listenPort ? settings.listenPort + 1000 : settings.httpPort
        let freeHTTP = PortAvailability.firstAvailable(
            preferred: wantedHTTP,
            host: settings.listenHost,
            range: 3079 ... 31_999
        )
        if freeHTTP != settings.httpPort {
            settings.httpPort = freeHTTP
            saveSettings()
        }

        status = .starting

        do {
            // One admin prompt installs both helpers (listener + proxy toggle).
            if !SudoPrivilege.isInstalled() {
                try SudoPrivilege.install()
                privilegesInstalled = true
            }

            try python.start(config: listenerProject)

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

            if settings.connectionMode == .tunnel {
                let tunnelConfig = makeTunnelConfiguration()
                _ = try await packetTunnel.start(configuration: tunnelConfig)
                tunnelActive = true
            } else if settings.useSystemProxy {
                let host = settings.resolvedSocksHostForLocalClient
                switch SystemProxy.enable(host: host, socksPort: settings.listenPort, httpPort: settings.httpPort) {
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
            if tunnelActive {
                await packetTunnel.stop()
                tunnelActive = false
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
        if tunnelActive {
            await packetTunnel.stop()
            tunnelActive = false
        }
        if systemProxyActive {
            SystemProxy.disableSync()
            systemProxyActive = false
        }
        await xray.stop()
        python.stop()
    }

    private func makeTunnelConfiguration() -> TunnelConfiguration {
        let excluded = [listenerProject.CONNECT_IP]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return TunnelConfiguration(
            listenHost: listenerProject.resolvedDialHost,
            listenPort: listenerProject.LISTEN_PORT,
            connectIP: listenerProject.CONNECT_IP,
            connectPort: listenerProject.CONNECT_PORT,
            upstreamIP: listenerProject.resolvedDialHost,
            upstreamPort: listenerProject.LISTEN_PORT,
            fakeSNI: listenerProject.FAKE_SNI,
            logLevel: settings.logLevel == .debug || settings.logLevel == .trace ? .debug : .info,
            connectionMode: .tunnel,
            httpProxyPort: settings.httpPort,
            socksProxyPort: settings.listenPort,
            dnsServers: ["1.1.1.1", "8.8.8.8"],
            excludedIPv4Addresses: excluded
        )
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
        
        // Only sample and display data exchange activity if the connection is actually healthy (egress IP is resolved)
        guard egressIP != nil else {
            downloadBytesPerSec = 0
            uploadBytesPerSec = 0
            if let counters = NetworkCounters.totalRXTXBytes() {
                sessionBaselineRx = counters.rx
                sessionBaselineTx = counters.tx
                lastBytesIn = counters.rx
                lastBytesOut = counters.tx
            }
            sessionBytesDown = 0
            sessionBytesUp = 0
            lastSampleAt = Date()
            return
        }

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

    // MARK: - Profile ping (listener + xray through SOCKS)

    /// TCP target for probing `LISTEN_HOST` (NWConnection cannot use `0.0.0.0`).
    static func resolvedPingHost(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty || t == "0.0.0.0" || t == "*" { return "127.0.0.1" }
        if t == "localhost" { return "127.0.0.1" }
        if t == "::" { return "::1" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func persistPingResults() {
        store.savePingResults(profilePingResults)
    }

    func cancelPingBatch() {
        pingBatchToken = nil
        pingBatchTask?.cancel()
        pingBatchTask = nil
        isPingBatchRunning = false
        profilePingingIDs.removeAll()
    }

    /// Tests every profile. Uses one shared listener between probes (faster than
    /// restarting from scratch each time). Xray still runs one profile at a time
    /// because the app has a single local SOCKS port.
    func startPingAllProfiles() {
        cancelPingBatch()
        let token = UUID()
        pingBatchToken = token
        isPingBatchRunning = true
        profilePingingIDs = Set(profiles.map(\.id))

        pingBatchTask = Task { @MainActor in
            defer {
                if pingBatchToken == token {
                    isPingBatchRunning = false
                    profilePingingIDs.removeAll()
                    pingBatchToken = nil
                }
            }

            let list = profiles
            guard !list.isEmpty else { return }

            if status.isRunning {
                for p in list {
                    guard pingBatchToken == token, !Task.isCancelled else { break }
                    let r = await pingProfile(p)
                    profilePingResults[p.id] = r
                    profilePingingIDs.remove(p.id)
                    persistPingResults()
                }
                return
            }

            var listenerStarted = false
            defer {
                if listenerStarted, !status.isRunning {
                    python.stop()
                    listenerStartedForPingOnly = false
                }
            }

            do {
                try prepareListenerForPingBatch()
                listenerStarted = true
                try await awaitListenerReady()
            } catch {
                let err = RealPingService.Result(millis: nil, error: shortPingError(error))
                for p in list {
                    profilePingResults[p.id] = err
                    profilePingingIDs.remove(p.id)
                }
                persistPingResults()
                return
            }

            for p in list {
                guard pingBatchToken == token, !Task.isCancelled else { break }
                let r = await pingProfileViaBatch(p)
                profilePingResults[p.id] = r
                profilePingingIDs.remove(p.id)
                persistPingResults()
            }
        }
    }

    func pingSingleProfile(_ profile: Profile) async {
        guard !profilePingingIDs.contains(profile.id) else { return }
        profilePingingIDs.insert(profile.id)
        let r = await pingProfile(profile)
        profilePingResults[profile.id] = r
        profilePingingIDs.remove(profile.id)
        persistPingResults()
    }

    private func prepareListenerForPingBatch() throws {
        saveListenerProject()
        if !SudoPrivilege.isInstalled() {
            try SudoPrivilege.install()
            privilegesInstalled = true
        }
        if !python.isRunning() {
            try python.start(config: listenerProject)
            listenerStartedForPingOnly = true
        }
    }

    /// Ping while listener is already up (batch path): only cycle Xray per profile.
    private func pingProfileViaBatch(_ profile: Profile) async -> RealPingService.Result {
        let socksHost = settings.resolvedSocksHostForLocalClient
        let socksPort = settings.listenPort

        do {
            try await awaitListenerReady()
            let xdata = try XrayOutboundBuilder.generate(
                settings: settings,
                profile: profile,
                bridge: listenerProject
            )
            let cfgURL = try store.writeGeneratedXrayConfig(xdata)
            try xray.start(configURL: cfgURL)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let result = await RealPingService.pingViaSocks(proxyHost: socksHost, proxyPort: socksPort)
            xray.stopSync()
            return result
        } catch {
            xray.stopSync()
            return RealPingService.Result(millis: nil, error: shortPingError(error))
        }
    }

    /// Brings up the Python listener and Xray for `profile`, measures latency through
    /// the local SOCKS hop, then tears down anything started only for this probe.
    func pingProfile(_ profile: Profile) async -> RealPingService.Result {
        let socksHost = settings.resolvedSocksHostForLocalClient
        let socksPort = settings.listenPort

        if status.isRunning {
            guard activeProfile?.id == profile.id else {
                return RealPingService.Result(millis: nil, error: "disconnect first")
            }
            return await RealPingService.pingViaSocks(proxyHost: socksHost, proxyPort: socksPort)
        }

        var startedListener = false
        var startedXray = false
        defer {
            if startedXray { xray.stopSync() }
            if startedListener {
                python.stop()
                listenerStartedForPingOnly = false
            }
        }

        do {
            saveListenerProject()
            if !SudoPrivilege.isInstalled() {
                try SudoPrivilege.install()
                privilegesInstalled = true
            }
            if !python.isRunning() {
                try python.start(config: listenerProject)
                listenerStartedForPingOnly = true
                startedListener = true
            }
            try await awaitListenerReady()

            let xdata = try XrayOutboundBuilder.generate(
                settings: settings,
                profile: profile,
                bridge: listenerProject
            )
            let cfgURL = try store.writeGeneratedXrayConfig(xdata)
            try xray.start(configURL: cfgURL)
            startedXray = true
            try await Task.sleep(nanoseconds: 1_200_000_000)

            return await RealPingService.pingViaSocks(proxyHost: socksHost, proxyPort: socksPort)
        } catch {
            return RealPingService.Result(millis: nil, error: shortPingError(error))
        }
    }

    private func shortPingError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.count > 48 { return String(msg.prefix(45)) + "…" }
        return msg.isEmpty ? "failed" : msg
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
