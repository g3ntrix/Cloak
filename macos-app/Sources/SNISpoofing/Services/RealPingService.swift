import Foundation
import Darwin

/// Latency probes for profiles and local endpoints.
enum RealPingService {
    struct Result: Equatable {
        let millis: Int?
        let error: String?
    }

    /// Lightweight HTTP probes through SOCKS. A real HTTP response from any one
    /// endpoint proves the profile can carry traffic; relying on a single
    /// captive-portal host makes healthy profiles look dead in some regions.
    private static let socksProbeURLs = [
        "http://cp.cloudflare.com/generate_204",
        "http://connectivitycheck.gstatic.com/generate_204",
        "http://detectportal.firefox.com/success.txt",
        "http://www.apple.com/library/test/success.html",
    ]

    static func pingViaSocks(
        proxyHost: String,
        proxyPort: Int,
        timeout: TimeInterval = 15
    ) async -> Result {
        let proxy = socksEndpoint(host: proxyHost, port: proxyPort)
        return await Task.detached(priority: .utility) {
            curlTimingThroughSocks(socks: proxy, timeout: timeout)
        }.value
    }

    private static func socksEndpoint(host: String, port: Int) -> String {
        let t = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains(":"), t.filter({ $0 == "." }).count != 3 {
            return "[\(t)]:\(port)"
        }
        return "\(t):\(port)"
    }

    private static func curlTimingThroughSocks(socks: String, timeout: TimeInterval) -> Result {
        // Give the first probe most of the budget — a slow SNI-spoofing path
        // through Cloudflare can take several seconds for the first request, so
        // the old 2-4s per-probe cap reported healthy-but-slow profiles as dead.
        // We bound the *total* time with an overall deadline so a truly dead
        // config still fails promptly after cycling the fallback endpoints.
        let perProbeCap = max(5, Int(timeout.rounded(.up)))
        let deadline = Date().addingTimeInterval(timeout)
        var last = Result(millis: nil, error: "failed")

        for url in socksProbeURLs {
            let remaining = deadline.timeIntervalSinceNow
            if remaining < 1 { break }
            let slice = max(2, min(perProbeCap, Int(remaining.rounded(.up))))
            let result = curlTimingThroughSocks(socks: socks, url: url, timeoutSeconds: slice)
            if result.millis != nil { return result }
            last = result
        }

        return last
    }

    private static func curlTimingThroughSocks(socks: String, url: String, timeoutSeconds: Int) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        let timeoutStr = String(timeoutSeconds)
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
           isSuccessfulProbeHTTPCode(String(fields[0])),
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

    private static func isSuccessfulProbeHTTPCode(_ code: String) -> Bool {
        guard let n = Int(code) else { return false }
        return (200 ... 399).contains(n)
    }

    /// Direct TCP connect to host:port (local bridge reachability).
    static func ping(host: String, port: UInt16, timeout: TimeInterval = 10) async -> Result {
        let targetHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetHost.isEmpty, port > 0 else {
            return Result(millis: nil, error: "no server")
        }

        return await Task.detached(priority: .utility) {
            tcpConnect(host: targetHost, port: port, timeout: timeout)
        }.value
    }

    private static func tcpConnect(host: String, port: UInt16, timeout: TimeInterval) -> Result {
        let start = DispatchTime.now()
        let timeoutSeconds = max(timeout, 0.001)
        let deadline = Date().timeIntervalSinceReferenceDate + timeoutSeconds
        let service = String(port)

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var resolved: UnsafeMutablePointer<addrinfo>?
        let gai = getaddrinfo(host, service, &hints, &resolved)
        guard gai == 0, let first = resolved else {
            return Result(millis: nil, error: "dns")
        }
        defer { freeaddrinfo(first) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var lastError = "failed"

        while let current = cursor {
            if Task.isCancelled {
                return Result(millis: nil, error: "cancelled")
            }

            let remaining = deadline - Date().timeIntervalSinceReferenceDate
            guard remaining > 0 else {
                return Result(millis: nil, error: "timeout")
            }

            let info = current.pointee
            cursor = info.ai_next

            let fd = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            guard fd >= 0 else {
                lastError = shortPOSIXError(errno)
                continue
            }

            let flags = fcntl(fd, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            }

            if connect(fd, info.ai_addr, info.ai_addrlen) == 0 {
                let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                close(fd)
                return Result(millis: max(Int(Double(ns) / 1_000_000), 1), error: nil)
            }

            let connectErr = errno
            guard connectErr == EINPROGRESS || connectErr == EALREADY || connectErr == EINTR else {
                lastError = shortPOSIXError(connectErr)
                close(fd)
                continue
            }

            let wait = waitForConnect(fd: fd, timeout: remaining)
            close(fd)
            switch wait {
            case .success:
                let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                return Result(millis: max(Int(Double(ns) / 1_000_000), 1), error: nil)
            case .failure(let error):
                lastError = error
            }
        }

        return Result(millis: nil, error: lastError)
    }

    private enum ConnectWaitResult {
        case success
        case failure(String)
    }

    private static func waitForConnect(fd: Int32, timeout: TimeInterval) -> ConnectWaitResult {
        var pollDescriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let timeoutMs = Int32(min(Double(Int32.max), max(1, timeout * 1000)))

        while true {
            let ready = poll(&pollDescriptor, 1, timeoutMs)
            if ready == 0 {
                return .failure("timeout")
            }
            if ready < 0 {
                if errno == EINTR { continue }
                return .failure(shortPOSIXError(errno))
            }

            var socketError: Int32 = 0
            var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength) == 0 else {
                return .failure(shortPOSIXError(errno))
            }
            return socketError == 0 ? .success : .failure(shortPOSIXError(socketError))
        }
    }

    private static func shortPOSIXError(_ code: Int32) -> String {
        switch code {
        case ECONNREFUSED:
            return "refused"
        case EHOSTUNREACH, ENETUNREACH:
            return "unreachable"
        case ETIMEDOUT:
            return "timeout"
        case ECANCELED:
            return "cancelled"
        default:
            return "error"
        }
    }
}
