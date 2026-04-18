import Foundation

/// Runs `sudo -S .venv/bin/python main.py` in the SNI-Spoofing project directory after writing `config.json`.
final class PythonListener {
    var onLog: ((LogLine) -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?

    func isRunning() -> Bool {
        process?.isRunning == true
    }

    func start(projectDirectory: URL, password: String, config: ListenerProjectConfig) throws {
        stop()

        let fm = FileManager.default
        guard fm.fileExists(atPath: projectDirectory.path) else {
            throw NSError(domain: "SNISpoofing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project folder not found."])
        }
        let py = projectDirectory.appendingPathComponent(".venv/bin/python")
        guard fm.isExecutableFile(atPath: py.path) else {
            throw NSError(domain: "SNISpoofing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing .venv/bin/python — create the venv in the SNI-Spoofing project first."])
        }
        let mainPy = projectDirectory.appendingPathComponent("main.py")
        guard fm.fileExists(atPath: mainPy.path) else {
            throw NSError(domain: "SNISpoofing", code: 2, userInfo: [NSLocalizedDescriptionKey: "main.py not found in project folder."])
        }

        guard !password.isEmpty else {
            throw NSError(domain: "SNISpoofing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Enter your macOS password (sudo) to run the listener."])
        }

        var cfg = config
        cfg.CONNECT_IP = config.CONNECT_IP.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.FAKE_SNI = config.FAKE_SNI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cfg.CONNECT_IP.isEmpty, !cfg.FAKE_SNI.isEmpty else {
            throw NSError(domain: "SNISpoofing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Set CONNECT_IP and FAKE_SNI in the listener config (Settings → JSON)."])
        }

        let cfgURL = projectDirectory.appendingPathComponent("config.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(cfg)
        try data.write(to: cfgURL, options: .atomic)
        emit("Wrote config.json → \(cfgURL.path)")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-S", ".venv/bin/python", "main.py"]
        p.currentDirectoryURL = projectDirectory

        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        let inPipe = Pipe()
        p.standardInput = inPipe

        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            self?.process = nil
            self?.outputPipe = nil
            self?.emit("[listener exited with status \(proc.terminationStatus)]")
        }

        try p.run()
        if let d = (password + "\n").data(using: .utf8) {
            inPipe.fileHandleForWriting.write(d)
        }
        inPipe.fileHandleForWriting.closeFile()

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
