import Foundation
import Network

/// Latency probes for profiles and local endpoints.
enum RealPingService {
    struct Result: Equatable {
        let millis: Int?
        let error: String?
    }

    /// HTTP probe through SOCKS — measures end-to-end time for traffic routed by Xray.
    /// A ping only succeeds when the probe returns the expected 204 response.
    private static let socksProbeURL = "http://connectivitycheck.gstatic.com/generate_204"

    static func pingViaSocks(
        proxyHost: String,
        proxyPort: Int,
        timeout: TimeInterval = 15
    ) async -> Result {
        let proxy = socksEndpoint(host: proxyHost, port: proxyPort)
        return await Task.detached(priority: .utility) {
            curlTimingThroughSocks(socks: proxy, url: socksProbeURL, timeout: timeout)
        }.value
    }

    private static func socksEndpoint(host: String, port: Int) -> String {
        let t = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains(":"), t.filter({ $0 == "." }).count != 3 {
            return "[\(t)]:\(port)"
        }
        return "\(t):\(port)"
    }

    private static func curlTimingThroughSocks(socks: String, url: String, timeout: TimeInterval) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        let timeoutStr = String(Int(timeout))
        p.arguments = [
            "-sS", "-o", "/dev/null",
            "--connect-timeout", timeoutStr,
            "--max-time", timeoutStr,
            "--socks5-hostname", socks,
            "-w", "%{http_code} %{time_total}",
            url,
        ]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return Result(millis: nil, error: "curl")
        }
        p.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        let fields = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        if p.terminationStatus == 0,
           fields.count == 2,
           fields[0] == "204",
           let seconds = Double(fields[1]),
           seconds > 0 {
            let ms = Int((seconds * 1000).rounded())
            return Result(millis: max(ms, 1), error: nil)
        }

        let httpCode = fields.first.map(String.init)
        return Result(millis: nil, error: shortCurlError(stderr, exitCode: p.terminationStatus, httpCode: httpCode))
    }

    private static func shortCurlError(_ stderr: String, exitCode: Int32, httpCode: String? = nil) -> String {
        let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.localizedCaseInsensitiveContains("timeout") || msg.contains("28") { return "timeout" }
        if msg.localizedCaseInsensitiveContains("refused") || msg.contains("7") { return "refused" }
        if msg.localizedCaseInsensitiveContains("socks") { return "proxy" }
        if exitCode == 7 { return "refused" }
        if exitCode == 28 { return "timeout" }
        if let httpCode, httpCode != "000", httpCode != "204" { return "http \(httpCode)" }
        if httpCode == "000" { return "no response" }
        return msg.isEmpty ? "failed" : "failed"
    }

    /// Direct TCP connect to host:port (local bridge reachability).
    static func ping(host: String, port: UInt16, timeout: TimeInterval = 10) async -> Result {
        guard !host.isEmpty, port > 0 else {
            return Result(millis: nil, error: "no server")
        }
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return Result(millis: nil, error: "bad port")
        }

        return await withCheckedContinuation { cont in
            let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
            let start = DispatchTime.now()
            let resumed = _Box(false)
            let q = DispatchQueue(label: "cloak.ping.\(host):\(port)")

            let deadline = DispatchWorkItem {
                guard !resumed.value else { return }
                resumed.value = true
                conn.cancel()
                cont.resume(returning: Result(millis: nil, error: "timeout"))
            }
            q.asyncAfter(deadline: .now() + timeout, execute: deadline)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !resumed.value else { return }
                    resumed.value = true
                    deadline.cancel()
                    let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    conn.cancel()
                    cont.resume(returning: Result(millis: Int(Double(ns) / 1_000_000), error: nil))
                case .failed(let err):
                    guard !resumed.value else { return }
                    resumed.value = true
                    deadline.cancel()
                    conn.cancel()
                    cont.resume(returning: Result(millis: nil, error: shortError(err)))
                case .cancelled:
                    guard !resumed.value else { return }
                    resumed.value = true
                    deadline.cancel()
                    cont.resume(returning: Result(millis: nil, error: "cancelled"))
                default:
                    break
                }
            }
            conn.start(queue: q)
        }
    }

    private static func shortError(_ err: NWError) -> String {
        let desc = "\(err)"
        if desc.contains("ECONNREFUSED") || desc.contains("Connection refused") { return "refused" }
        if desc.contains("EHOSTUNREACH") || desc.contains("unreachable")       { return "unreachable" }
        if desc.contains("ETIMEDOUT") || desc.localizedStandardContains("time") { return "timeout" }
        if desc.lowercased().contains("dns")                                    { return "dns" }
        if desc.lowercased().contains("tls")                                    { return "tls" }
        return "error"
    }

    private final class _Box<T> {
        var value: T
        init(_ v: T) { value = v }
    }
}
