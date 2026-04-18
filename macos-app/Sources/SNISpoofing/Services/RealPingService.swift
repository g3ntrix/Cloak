import Foundation
import Network

/// Measures real round-trip latency for a profile: we open a TCP connection
/// to `profile.server:profile.serverPort` and time the handshake. This is
/// what other VPN GUIs call "ping" — it's the meaningful number for "which
/// of my servers is fastest right now".
///
/// A 10-second hard ceiling is enforced per attempt.
enum RealPingService {
    struct Result: Equatable {
        /// Round-trip time in milliseconds, nil if unreachable within `timeout`.
        let millis: Int?
        /// Short human-friendly label ("timeout", "refused", …). nil on success.
        let error: String?
    }

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
        // NWError keeps gaining cases across SDKs (e.g. `.wifiAware`). Use a
        // lossy string match so we stay warning-free on both old and new SDKs.
        let desc = "\(err)"
        if desc.contains("ECONNREFUSED") || desc.contains("Connection refused") { return "refused" }
        if desc.contains("EHOSTUNREACH") || desc.contains("unreachable")       { return "unreachable" }
        if desc.contains("ETIMEDOUT") || desc.localizedStandardContains("time") { return "timeout" }
        if desc.lowercased().contains("dns")                                    { return "dns" }
        if desc.lowercased().contains("tls")                                    { return "tls" }
        return "error"
    }

    /// Tiny reference container so the continuation + deadline closures can
    /// share a single "resumed" flag without going through `DispatchQueue.sync`.
    private final class _Box<T> {
        var value: T
        init(_ v: T) { value = v }
    }
}
