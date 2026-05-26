import Foundation

/// Runs the SNI-spoofing listener. On first start the app installs
/// `/usr/local/bin/cloak-listener` + a NOPASSWD sudoers rule (see
/// `SudoPrivilege`), so here we just invoke `sudo -n /usr/local/bin/cloak-listener`.
final class PythonListener {
    var onLog: ((LogLine) -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?
    private let stateLock = NSLock()
    private var expectedTerminationPIDs = Set<Int32>()

    func isRunning() -> Bool {
        process?.isRunning == true
    }

    func start(config: ListenerProjectConfig) throws {
        stop()

        guard ListenerCore.bundledExecutableURL() != nil else {
            throw NSError(domain: "SNISpoofing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bundled listener binary is missing. Reinstall Cloak from a full release build."])
        }

        // Write config.json next to main.py so the listener can read it.
        var cfg = config
        cfg.CONNECT_IP = config.CONNECT_IP.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.FAKE_SNI = config.FAKE_SNI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cfg.CONNECT_IP.isEmpty, !cfg.FAKE_SNI.isEmpty else {
            throw NSError(domain: "SNISpoofing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Paste your Cloudflare config in the Settings tab first (CONNECT_IP and FAKE_SNI can't be empty)."])
        }

        // Always write config to the shared writable path the sudoers wrapper
        // passes via CLOAK_CONFIG (the frozen listener reads a user-writable file).
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(cfg)
        let cfgPath = SudoPrivilege.appSupportListenerConfigPath()
        try data.write(to: URL(fileURLWithPath: cfgPath), options: .atomic)

        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: SudoPrivilege.wrapperPath) else {
            throw NSError(domain: "SNISpoofing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Background helper not installed. Approve the admin prompt when you press Start."])
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", SudoPrivilege.wrapperPath]

        let out = Pipe()
        p.standardOutput = out
        p.standardError = out

        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            let wasExpected = self.consumeExpectedTermination(pid: proc.processIdentifier)
            if proc.terminationStatus != 0, !wasExpected {
                self.emit("[listener exited with status \(proc.terminationStatus)]\n")
            }
            out.fileHandleForReading.readabilityHandler = nil
            if self.process === proc {
                self.process = nil
                self.outputPipe = nil
            }
        }

        try p.run()
        process = p
        outputPipe = out

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(data: chunk, encoding: .utf8) ?? ""
            self?.emit(text)
        }
    }

    func stop() {
        if let p = process, p.isRunning {
            markExpectedTermination(pid: p.processIdentifier)
            p.terminate()
        }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
    }

    private func markExpectedTermination(pid: Int32) {
        stateLock.lock()
        defer { stateLock.unlock() }
        expectedTerminationPIDs.insert(pid)
    }

    private func consumeExpectedTermination(pid: Int32) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        let found = expectedTerminationPIDs.remove(pid) != nil
        return found
    }

    private func emit(_ text: String) {
        onLog?(LogLine(timestamp: Date(), stream: .stdout, text: text))
    }
}
