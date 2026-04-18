import Foundation

/// Spawns the bundled `xray` binary from `Resources/` (geoip/geosite beside it).
final class XrayCoreManager {
    var onLog: ((LogLine) -> Void)?

    private var process: Process?
    private var pipe: Pipe?

    private var binaryURL: URL? {
        Bundle.main.url(forResource: "xray", withExtension: nil)
    }

    var isRunning: Bool { process?.isRunning == true }

    func start(configURL: URL) throws {
        stopSync()
        guard let binary = binaryURL, FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw NSError(domain: "SNISpoofing", code: 10, userInfo: [NSLocalizedDescriptionKey: "xray not bundled — rebuild the app so Resources contains the xray binary."])
        }

        let p = Process()
        p.executableURL = binary
        p.arguments = ["run", "-c", configURL.path]
        if let res = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: res.appendingPathComponent("geoip.dat").path)
        {
            p.currentDirectoryURL = res
        }

        let out = Pipe()
        p.standardOutput = out
        p.standardError = out

        p.terminationHandler = { [weak self] proc in
            self?.pipe?.fileHandleForReading.readabilityHandler = nil
            self?.process = nil
            self?.pipe = nil
            if proc.terminationStatus != 0 {
                let msg = "[xray exited with status \(proc.terminationStatus)]"
                self?.onLog?(LogLine(timestamp: Date(), stream: .stderr, text: msg))
            }
        }

        try p.run()
        process = p
        pipe = out

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(data: chunk, encoding: .utf8) ?? ""
            self?.onLog?(LogLine(timestamp: Date(), stream: .stdout, text: text))
        }
    }

    func stop() async {
        stopSync()
        for _ in 0 ..< 30 {
            if process == nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func stopSync() {
        if let p = process, p.isRunning {
            p.terminate()
        }
        pipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        pipe = nil
    }
}
