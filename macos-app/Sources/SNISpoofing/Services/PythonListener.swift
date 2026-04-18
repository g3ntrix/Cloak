import Foundation

/// Runs the SNI-spoofing listener. On first start the app installs
/// `/usr/local/bin/cloak-listener` + a NOPASSWD sudoers rule (see
/// `SudoPrivilege`), so here we just invoke `sudo -n /usr/local/bin/cloak-listener`.
final class PythonListener {
    var onLog: ((LogLine) -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?

    func isRunning() -> Bool {
        process?.isRunning == true
    }

    func start(projectDirectory: URL, config: ListenerProjectConfig) throws {
        stop()

        let fm = FileManager.default
        guard fm.fileExists(atPath: projectDirectory.path) else {
            throw NSError(domain: "SNISpoofing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Internal error: Python listener source not found. Reinstall the app."])
        }
        let mainPy = projectDirectory.appendingPathComponent("main.py")
        guard fm.fileExists(atPath: mainPy.path) else {
            throw NSError(domain: "SNISpoofing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Internal error: main.py missing. Reinstall the app."])
        }

        // Write config.json next to main.py so the listener can read it.
        var cfg = config
        cfg.CONNECT_IP = config.CONNECT_IP.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.FAKE_SNI = config.FAKE_SNI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cfg.CONNECT_IP.isEmpty, !cfg.FAKE_SNI.isEmpty else {
            throw NSError(domain: "SNISpoofing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Paste your Cloudflare config in the Settings tab first (CONNECT_IP and FAKE_SNI can't be empty)."])
        }

        // Always write config to the shared writable path the sudoers wrapper
        // passes via CLOAK_CONFIG. This is required when the Python source
        // lives inside the read-only app bundle.
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(cfg)
        let cfgPath = SudoPrivilege.appSupportListenerConfigPath()
        try data.write(to: URL(fileURLWithPath: cfgPath), options: .atomic)

        guard fm.isExecutableFile(atPath: SudoPrivilege.wrapperPath) else {
            throw NSError(domain: "SNISpoofing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Background helper not installed. Approve the admin prompt when you press Start."])
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", SudoPrivilege.wrapperPath]

        let out = Pipe()
        p.standardOutput = out
        p.standardError = out

        p.terminationHandler = { [weak self] _ in
            if let proc = self?.process, proc.terminationStatus != 0 {
                self?.emit("[listener exited with status \(proc.terminationStatus)]\n")
            }
            out.fileHandleForReading.readabilityHandler = nil
            self?.process = nil
            self?.outputPipe = nil
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
            p.terminate()
        }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
    }

    private func emit(_ text: String) {
        onLog?(LogLine(timestamp: Date(), stream: .stdout, text: text))
    }
}
