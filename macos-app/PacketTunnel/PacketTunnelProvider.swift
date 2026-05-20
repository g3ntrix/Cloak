import Foundation
import NetworkExtension
import os

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.local.sni.macos", category: "PacketTunnel")
    private var configuration = TunnelConfiguration.defaults
    private var startedAt: Date?
    private var bridge: TunnelTrafficBridge?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol
        configuration = TunnelConfiguration(providerConfiguration: tunnelProtocol?.providerConfiguration)
        startedAt = Date()
        logger.info("Packet tunnel starting for \(self.configuration.connectIP, privacy: .public) mode=\(self.configuration.connectionMode.rawValue, privacy: .public)")

        let settings = makeNetworkSettings(using: configuration)
        settings.mtu = 1500
        logger.debug(
            "Tunnel settings prepared | remote=\(self.configuration.connectIP, privacy: .public):\(self.configuration.connectPort, privacy: .public) | upstream=\(self.configuration.upstreamIP, privacy: .public):\(self.configuration.upstreamPort, privacy: .public) | httpProxy=\(self.configuration.httpProxyPort ?? -1, privacy: .public) | socksProxy=\(self.configuration.socksProxyPort ?? -1, privacy: .public)"
        )

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completionHandler(nil)
                return
            }

            if let error {
                self.logger.error("setTunnelNetworkSettings failed: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
                return
            }

            if self.configuration.connectionMode == .tunnel, let httpProxyPort = self.configuration.httpProxyPort {
                let bridge = TunnelTrafficBridge(
                    packetFlow: self.packetFlow,
                    configuration: self.configuration,
                    httpProxyPort: httpProxyPort,
                    socksProxyPort: self.configuration.socksProxyPort,
                    logger: self.logger
                ) { [weak self] status in
                self?.logger.info("Tunnel bridge status | phase=\(status.phase, privacy: .public) | packets=\(status.packetCount, privacy: .public) | detail=\(status.detail ?? "-", privacy: .public)")
                self?.logger.info("Tunnel bridge traffic | up=\(status.bytesUploaded, privacy: .public) | down=\(status.bytesDownloaded, privacy: .public)")
                }
                self.bridge = bridge
                bridge.start()
            }

            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Packet tunnel stopping. reason=\(reason.rawValue)")
        bridge?.stop()
        bridge = nil
        startedAt = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        do {
            let message = try TunnelIPC.decode(TunnelAppMessage.self, from: messageData)
            switch message.command {
            case .getStatus:
                completionHandler?(try TunnelIPC.encode(currentStatus(detail: nil)))
            case .reloadConfiguration:
                let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol
                configuration = TunnelConfiguration(providerConfiguration: tunnelProtocol?.providerConfiguration)
                completionHandler?(try TunnelIPC.encode(currentStatus(detail: "Configuration reloaded")))
            }
        } catch {
            logger.error("Host app message failed: \(error.localizedDescription, privacy: .public)")
            completionHandler?(nil)
        }
    }

    private func currentStatus(detail: String?) -> TunnelProviderStatus {
        let bridgeStatus = bridge?.currentStatus(detail: detail)
        let decoratedDetail: String?
        if let detail, !detail.isEmpty {
            decoratedDetail = detail
        } else if let bridgeDetail = bridgeStatus?.detail, !bridgeDetail.isEmpty {
            decoratedDetail = bridgeDetail
        } else {
            decoratedDetail = nil
        }

        return TunnelProviderStatus(
            phase: bridgeStatus?.phase ?? (startedAt == nil ? "idle" : "running"),
            packetCount: bridgeStatus?.packetCount ?? 0,
            bytesUploaded: bridgeStatus?.bytesUploaded ?? 0,
            bytesDownloaded: bridgeStatus?.bytesDownloaded ?? 0,
            connectIP: configuration.connectIP,
            connectPort: configuration.connectPort,
            fakeSNI: configuration.fakeSNI,
            detail: [
                "mode=\(configuration.connectionMode.rawValue)",
                decoratedDetail,
                configuration.httpProxyPort.map { "httpProxy=\($0)" },
                configuration.socksProxyPort.map { "socksProxy=\($0)" },
                bridgeStatus?.startedAtISO8601.map { "started=\($0)" },
            ]
            .compactMap { $0 }
            .joined(separator: " | "),
            startedAtISO8601: startedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
    }

    private func makeNetworkSettings(using configuration: TunnelConfiguration) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: configuration.connectIP)

        let ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        let dnsServers = configuration.dnsServers
        if configuration.connectionMode == .tunnel {
            ipv4Settings.includedRoutes = [
                NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0"),
            ]
            var excludedRoutes = [
                NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
            ]
            let tunnelBypassRoutes = configuration.excludedIPv4Addresses.compactMap { address -> NEIPv4Route? in
                guard address.isValidIPv4Address else { return nil }
                return NEIPv4Route(destinationAddress: address, subnetMask: "255.255.255.255")
            }
            excludedRoutes.append(contentsOf: tunnelBypassRoutes)
            if configuration.upstreamIP.isValidIPv4Address {
                logger.debug("Tunnel upstream stays local only | upstream=\(configuration.upstreamIP, privacy: .public)")
            }
            ipv4Settings.excludedRoutes = excludedRoutes
            let excludedSummary = excludedRoutes
                .map { $0.destinationAddress }
                .joined(separator: ",")
            logger.debug("Tunnel route config | included=default | excluded=\(excludedSummary, privacy: .public)")
            if !configuration.excludedIPv4Addresses.isEmpty {
                logger.info("Tunnel bypass IPv4s | \(configuration.excludedIPv4Addresses.joined(separator: ", "), privacy: .public)")
            }
            if !dnsServers.isEmpty {
                let dnsSettings = NEDNSSettings(servers: dnsServers)
                dnsSettings.matchDomains = [""]
                settings.dnsSettings = dnsSettings
                logger.debug("Tunnel DNS settings enabled | servers=\(dnsServers.joined(separator: ","), privacy: .public)")
            }
        } else {
            ipv4Settings.includedRoutes = [
                NEIPv4Route(destinationAddress: configuration.connectIP, subnetMask: "255.255.255.255"),
            ]
            logger.debug("Proxy route config | included=\(configuration.connectIP, privacy: .public)/32")
        }
        settings.ipv4Settings = ipv4Settings

        return settings
    }
}

private extension String {
    var isValidIPv4Address: Bool {
        var address = in_addr()
        return withCString { inet_pton(AF_INET, $0, &address) } == 1
    }
}
