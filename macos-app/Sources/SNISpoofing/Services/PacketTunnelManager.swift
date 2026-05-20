import Foundation
import NetworkExtension

final class PacketTunnelManager {
    private var manager: NETunnelProviderManager?

    func start(configuration: TunnelConfiguration) async throws -> TunnelProviderStatus? {
        let manager = try await configuredManager(for: configuration)
        let session = manager.connection as? NETunnelProviderSession
        do {
            try session?.startTunnel()
        } catch {
            throw NSError(
                domain: "SNISpoofing",
                code: 71,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't start the packet tunnel. Make sure Cloak.app includes a signed PacketTunnel extension."]
            )
        }
        return try await waitForConnected(session: session, timeout: 18)
    }

    func stop() async {
        let manager: NETunnelProviderManager?
        if let cached = self.manager {
            manager = cached
        } else {
            manager = try? await Self.loadManagedManager()
        }
        manager?.connection.stopVPNTunnel()
    }

    func stopSync() {
        let semaphore = DispatchSemaphore(value: 0)
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            let managed = (managers ?? []).first { manager in
                let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
                return proto?.providerBundleIdentifier == TunnelConfiguration.providerBundleIdentifier
                    || manager.localizedDescription == "Cloak Tunnel"
            }
            managed?.connection.stopVPNTunnel()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    func status() async -> TunnelProviderStatus? {
        let manager: NETunnelProviderManager?
        if let cached = self.manager {
            manager = cached
        } else {
            manager = try? await Self.loadManagedManager()
        }
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected else {
            return nil
        }
        return try? await send(.getStatus, session: session)
    }

    private func configuredManager(for configuration: TunnelConfiguration) async throws -> NETunnelProviderManager {
        let manager = try await Self.loadManagedManager() ?? NETunnelProviderManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = TunnelConfiguration.providerBundleIdentifier
        tunnelProtocol.serverAddress = configuration.connectIP
        tunnelProtocol.providerConfiguration = configuration.providerConfigurationDictionary()

        manager.localizedDescription = "Cloak Tunnel"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true

        try await Self.save(manager)
        try await Self.load(manager)
        self.manager = manager
        return manager
    }

    private func waitForConnected(
        session: NETunnelProviderSession?,
        timeout: TimeInterval
    ) async throws -> TunnelProviderStatus? {
        guard let session else {
            throw NSError(domain: "SNISpoofing", code: 72, userInfo: [NSLocalizedDescriptionKey: "Packet tunnel session is unavailable."])
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch session.status {
            case .connected:
                return try? await send(.getStatus, session: session)
            case .invalid:
                throw NSError(domain: "SNISpoofing", code: 73, userInfo: [NSLocalizedDescriptionKey: "Packet tunnel configuration is invalid."])
            case .disconnected:
                break
            default:
                break
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw NSError(domain: "SNISpoofing", code: 74, userInfo: [NSLocalizedDescriptionKey: "Packet tunnel did not connect in time."])
    }

    private func send(_ command: TunnelCommand, session: NETunnelProviderSession) async throws -> TunnelProviderStatus? {
        let data = try TunnelIPC.encode(TunnelAppMessage(command: command))
        let response = try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { data in
                    continuation.resume(returning: data)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard let response else { return nil }
        return try TunnelIPC.decode(TunnelProviderStatus.self, from: response)
    }

    private static func loadManagedManager() async throws -> NETunnelProviderManager? {
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
        return managers.first { manager in
            let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
            return proto?.providerBundleIdentifier == TunnelConfiguration.providerBundleIdentifier
                || manager.localizedDescription == "Cloak Tunnel"
        }
    }

    private static func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func load(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
