import Foundation
import Network
import NetworkExtension
import os

struct TunnelTrafficBridgeStatus {
    var phase: String
    var packetCount: Int
    var bytesUploaded: Int
    var bytesDownloaded: Int
    var detail: String?
    var startedAtISO8601: String?
}

final class TunnelTrafficBridge {
    private let packetFlow: NEPacketTunnelFlow
    private let configuration: TunnelConfiguration
    private let httpProxyPort: Int
    private let socksProxyPort: Int?
    private let logger: Logger
    private let statusHandler: (TunnelTrafficBridgeStatus) -> Void
    private let stateQueue = DispatchQueue(label: "com.local.sni.macos.tunnel.bridge")
    private var tcpSessions: [TCPFlowKey: TCPFlowSession] = [:]
    private var udpSessions: [UDPFlowKey: UDPFlowSession] = [:]
    private var packetCount = 0
    private var bytesUploaded = 0
    private var bytesDownloaded = 0
    private var running = false
    private var startedAt = Date()
    private var lastDetail: String?
    private var lastStatusEmission = Date.distantPast

    init(
        packetFlow: NEPacketTunnelFlow,
        configuration: TunnelConfiguration,
        httpProxyPort: Int,
        socksProxyPort: Int?,
        logger: Logger,
        statusHandler: @escaping (TunnelTrafficBridgeStatus) -> Void
    ) {
        self.packetFlow = packetFlow
        self.configuration = configuration
        self.httpProxyPort = httpProxyPort
        self.socksProxyPort = socksProxyPort
        self.logger = logger
        self.statusHandler = statusHandler
    }

    func start() {
        stateQueue.async {
            guard !self.running else { return }
            self.running = true
            self.startedAt = Date()
            self.packetCount = 0
            self.bytesUploaded = 0
            self.bytesDownloaded = 0
            self.lastDetail = "bridge starting"
            self.emitStatus(detailOverride: nil, force: true)
            self.logger.info("Tunnel bridge starting | proxy=127.0.0.1:\(self.httpProxyPort, privacy: .public)")
            self.readNextPackets()
        }
    }

    func stop() {
        stateQueue.async {
            guard self.running else { return }
            self.running = false
            let tcpSessions = self.tcpSessions.values
            let udpSessions = self.udpSessions.values
            self.tcpSessions.removeAll()
            self.udpSessions.removeAll()
            for session in tcpSessions {
                session.stop()
            }
            for session in udpSessions {
                session.stop()
            }
            self.lastDetail = "bridge stopped"
            self.emitStatus(detailOverride: nil, force: true)
            self.logger.info("Tunnel bridge stopped")
        }
    }

    func currentStatus(detail: String? = nil) -> TunnelTrafficBridgeStatus {
        stateQueue.sync {
            self.makeStatus(detailOverride: detail)
        }
    }

    private func readNextPackets() {
        guard running else { return }
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self else { return }
            self.stateQueue.async {
                self.handlePackets(packets)
                self.readNextPackets()
            }
        }
    }

    private func handlePackets(_ packets: [Data]) {
        guard running else { return }
        packetCount += packets.count
        if packetCount == packets.count {
            logger.info("Tunnel bridge packet intake started | batch=\(packets.count, privacy: .public)")
        } else if packetCount % 50 == 0 {
            logger.debug("Tunnel bridge packet intake | total=\(self.packetCount, privacy: .public) | activeSessions=\(self.tcpSessions.count + self.udpSessions.count, privacy: .public)")
        }

        for packetData in packets {
            if let packet = PacketParser.parseIPv4TCPPacket(packetData) {
                handleTCPPacket(packet)
                continue
            }

            if let packet = PacketParser.parseIPv4UDPPacket(packetData) {
                handleUDPPacket(packet)
                continue
            }

            lastDetail = "ignored non-TCP/UDP packet"
        }

        emitStatus(detailOverride: nil, force: false)
    }

    private func handleTCPPacket(_ packet: ParsedIPv4TCPPacket) {
        let key = TCPFlowKey(
            sourceIP: packet.sourceIP,
            sourcePort: packet.sourcePort,
            destinationIP: packet.destinationIP,
            destinationPort: packet.destinationPort
        )

        if packet.syn && !packet.ack {
            if tcpSessions[key] == nil {
                let session = TCPFlowSession(
                    key: key,
                    initialPacket: packet,
                    packetFlow: packetFlow,
                    httpProxyPort: httpProxyPort,
                    logger: logger,
                    stateQueue: DispatchQueue(label: "com.local.sni.macos.tunnel.bridge.tcp.\(UUID().uuidString)"),
                    onTraffic: { [weak self] uploaded, downloaded in
                        self?.stateQueue.async {
                            self?.bytesUploaded += uploaded
                            self?.bytesDownloaded += downloaded
                            self?.emitStatus(detailOverride: nil, force: false)
                        }
                    },
                    onFinish: { [weak self] finishedKey in
                        self?.stateQueue.async {
                            self?.tcpSessions.removeValue(forKey: finishedKey)
                            self?.emitStatus(detailOverride: "tcp session finished", force: true)
                        }
                    },
                    onActivity: { [weak self] detail in
                        self?.stateQueue.async {
                            self?.lastDetail = detail
                            self?.emitStatus(detailOverride: detail, force: false)
                        }
                    }
                )
                tcpSessions[key] = session
                lastDetail = "new tcp flow \(key.description)"
                session.handle(packet)
            } else {
                tcpSessions[key]?.handle(packet)
            }
            return
        }

        guard let session = tcpSessions[key] else {
            lastDetail = "packet without tcp session \(key.description)"
            return
        }
        session.handle(packet)
    }

    private func handleUDPPacket(_ packet: ParsedIPv4UDPPacket) {
        let key = UDPFlowKey(
            sourceIP: packet.sourceIP,
            sourcePort: packet.sourcePort,
            destinationIP: packet.destinationIP,
            destinationPort: packet.destinationPort
        )

        if udpSessions[key] == nil {
            guard let socksProxyPort else {
                lastDetail = "udp packet dropped | no socks proxy port"
                return
            }

            let session = UDPFlowSession(
                key: key,
                initialPacket: packet,
                packetFlow: packetFlow,
                socksProxyPort: socksProxyPort,
                logger: logger,
                stateQueue: DispatchQueue(label: "com.local.sni.macos.tunnel.bridge.udp.\(UUID().uuidString)"),
                onTraffic: { [weak self] uploaded, downloaded in
                    self?.stateQueue.async {
                        self?.bytesUploaded += uploaded
                        self?.bytesDownloaded += downloaded
                        self?.emitStatus(detailOverride: nil, force: false)
                    }
                },
                onFinish: { [weak self] finishedKey in
                    self?.stateQueue.async {
                        self?.udpSessions.removeValue(forKey: finishedKey)
                        self?.emitStatus(detailOverride: "udp session finished", force: true)
                    }
                },
                onActivity: { [weak self] detail in
                    self?.stateQueue.async {
                        self?.lastDetail = detail
                        self?.emitStatus(detailOverride: detail, force: false)
                    }
                }
            )
            udpSessions[key] = session
            lastDetail = "new udp flow \(key.description)"
            session.handle(packet)
            return
        }

        udpSessions[key]?.handle(packet)
    }

    private func emitStatus(detailOverride: String?, force: Bool) {
        let now = Date()
        if !force, now.timeIntervalSince(lastStatusEmission) < 0.25 {
            return
        }
        lastStatusEmission = now
        statusHandler(makeStatus(detailOverride: detailOverride))
    }

    private func makeStatus(detailOverride: String?) -> TunnelTrafficBridgeStatus {
        TunnelTrafficBridgeStatus(
            phase: running ? "running" : "stopped",
            packetCount: packetCount,
            bytesUploaded: bytesUploaded,
            bytesDownloaded: bytesDownloaded,
            detail: detailOverride ?? lastDetail ?? configuration.connectionMode.rawValue,
            startedAtISO8601: ISO8601DateFormatter().string(from: startedAt)
        )
    }
}

private struct TCPFlowKey: Hashable, CustomStringConvertible {
    let sourceIP: String
    let sourcePort: UInt16
    let destinationIP: String
    let destinationPort: UInt16

    var description: String {
        "\(sourceIP):\(sourcePort)->\(destinationIP):\(destinationPort)"
    }
}

private struct UDPFlowKey: Hashable, CustomStringConvertible {
    let sourceIP: String
    let sourcePort: UInt16
    let destinationIP: String
    let destinationPort: UInt16

    var description: String {
        "\(sourceIP):\(sourcePort)->\(destinationIP):\(destinationPort)"
    }
}

private final class TCPFlowSession {
    private enum State {
        case handshake
        case connecting
        case ready
        case closing
        case closed
    }

    private let key: TCPFlowKey
    private let initialPacket: ParsedIPv4TCPPacket
    private let packetFlow: NEPacketTunnelFlow
    private let httpProxyPort: Int
    private let logger: Logger
    private let stateQueue: DispatchQueue
    private let onTraffic: (Int, Int) -> Void
    private let onFinish: (TCPFlowKey) -> Void
    private let onActivity: (String) -> Void

    private var state: State = .handshake
    private var connection: NWConnection?
    private var pendingClientBytes = Data()
    private var pendingProxyBytes = Data()
    private let handshakeSequence: UInt32
    private var serverSequence: UInt32
    private var clientAck: UInt32
    private let advertisedWindowScale: UInt8?
    private var receivedConnectResponse = false
    private var closed = false

    init(
        key: TCPFlowKey,
        initialPacket: ParsedIPv4TCPPacket,
        packetFlow: NEPacketTunnelFlow,
        httpProxyPort: Int,
        logger: Logger,
        stateQueue: DispatchQueue,
        onTraffic: @escaping (Int, Int) -> Void,
        onFinish: @escaping (TCPFlowKey) -> Void,
        onActivity: @escaping (String) -> Void
    ) {
        self.key = key
        self.initialPacket = initialPacket
        self.packetFlow = packetFlow
        self.httpProxyPort = httpProxyPort
        self.logger = logger
        self.stateQueue = stateQueue
        self.onTraffic = onTraffic
        self.onFinish = onFinish
        self.onActivity = onActivity
        let initialServerSequence = Self.randomSequence()
        self.handshakeSequence = initialServerSequence
        self.serverSequence = initialServerSequence &+ 1
        self.clientAck = initialPacket.sequenceNumber &+ Self.segmentLength(for: initialPacket)
        self.advertisedWindowScale = initialPacket.windowScale.map { _ in 7 }
    }

    func handle(_ packet: ParsedIPv4TCPPacket) {
        stateQueue.async {
            guard !self.closed else { return }
            self.onActivity("flow \(self.key.description) flags syn=\(packet.syn) ack=\(packet.ack) fin=\(packet.fin) rst=\(packet.rst) payload=\(packet.payload.count)")

            if packet.rst {
                self.sendRST(responseTo: packet)
                self.close()
                return
            }

            if packet.fin {
                self.clientAck = packet.sequenceNumber &+ Self.segmentLength(for: packet)
                self.sendACKOnly(responseTo: packet)
                self.sendFINACK(responseTo: packet)
                self.close()
                return
            }

            if !packet.payload.isEmpty {
                self.clientAck = packet.sequenceNumber &+ Self.segmentLength(for: packet)
                self.sendACKOnly(responseTo: packet)
                self.ensureConnectionStarted()
                self.appendClientData(packet.payload)
                return
            }

            if packet.syn && !packet.ack {
                self.sendSYNACK(responseTo: packet)
                self.ensureConnectionStarted()
                return
            }

            if packet.ack {
                self.ensureConnectionStarted()
            }
        }
    }

    func stop() {
        stateQueue.async {
            self.close()
        }
    }

    private func ensureConnectionStarted() {
        guard connection == nil, state != .closing, state != .closed else {
            flushPendingClientDataIfNeeded()
            return
        }

        state = .connecting
        guard let proxyPort = Network.NWEndpoint.Port(rawValue: UInt16(httpProxyPort)) else {
            logger.error("Invalid HTTP proxy port: \(self.httpProxyPort, privacy: .public)")
            sendRST(responseTo: initialPacket)
            close()
            return
        }

        let proxyHost: Network.NWEndpoint.Host = "127.0.0.1"
        let connection = Network.NWConnection(host: proxyHost, port: proxyPort, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            self.stateQueue.async {
                switch newState {
                case .ready:
                    self.logger.info("Upstream proxy ready for \(self.key.description, privacy: .public)")
                    self.onActivity("upstream ready")
                    self.sendConnectRequest()
                case .failed(let error):
                    self.logger.error("Upstream proxy failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.sendRST(responseTo: self.initialPacket)
                    self.close()
                case .cancelled:
                    self.close()
                default:
                    break
                }
            }
        }

        connection.start(queue: stateQueue)
        onActivity("connecting to local xray proxy")
    }

    private func sendConnectRequest() {
        guard let connection, state == .connecting else {
            return
        }

        let request = [
            "CONNECT \(key.destinationIP):\(key.destinationPort) HTTP/1.1",
            "Host: \(key.destinationIP):\(key.destinationPort)",
            "Proxy-Connection: keep-alive",
            "Connection: keep-alive",
            "",
            ""
        ].joined(separator: "\r\n")
        logger.debug("CONNECT request prepared for \(self.key.description, privacy: .public) | bytes=\(request.utf8.count, privacy: .public)")
        let requestData = Data(request.utf8)
        connection.send(content: requestData, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("CONNECT send failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.sendRST(responseTo: self.initialPacket)
                    self.close()
                    return
                }
                self.readConnectResponse()
            }
        })
    }

    private func readConnectResponse() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("CONNECT response error for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.sendRST(responseTo: self.initialPacket)
                    self.close()
                    return
                }

                if let data, !data.isEmpty {
                    self.pendingProxyBytes.append(data)
                    if let responseEnd = self.pendingProxyBytes.range(of: Data("\r\n\r\n".utf8)) {
                        let headerData = self.pendingProxyBytes.subdata(in: 0 ..< responseEnd.upperBound)
                        let headerText = String(data: headerData, encoding: .utf8) ?? ""
                        guard headerText.contains(" 200 ") || headerText.hasPrefix("HTTP/1.1 200") || headerText.hasPrefix("HTTP/1.0 200") else {
                            self.logger.error("Proxy CONNECT rejected for \(self.key.description, privacy: .public): \(headerText, privacy: .public)")
                            self.sendRST(responseTo: self.initialPacket)
                            self.close()
                            return
                        }
                        self.receivedConnectResponse = true
                        self.state = .ready
                        self.pendingProxyBytes.removeSubrange(0 ..< responseEnd.upperBound)
                        self.onActivity("proxy tunnel established")
                        self.sendACKOnly(responseTo: self.initialPacket)
                        self.flushPendingClientDataIfNeeded()
                        if !self.pendingProxyBytes.isEmpty {
                            let leftover = self.pendingProxyBytes
                            self.pendingProxyBytes.removeAll(keepingCapacity: true)
                            self.deliverUpstreamBytes(leftover)
                        }
                        self.receiveUpstreamDataLoop()
                        return
                    }
                }

                if isComplete {
                    self.close()
                    return
                }

                self.readConnectResponse()
            }
        }
    }

    private func receiveUpstreamDataLoop() {
        guard let connection, state == .ready else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("Upstream receive failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                    return
                }
                if let data, !data.isEmpty {
                    self.deliverUpstreamBytes(data)
                }
                if isComplete {
                    self.close()
                    return
                }
                self.receiveUpstreamDataLoop()
            }
        }
    }

    private func appendClientData(_ payload: Data) {
        pendingClientBytes.append(payload)
        flushPendingClientDataIfNeeded()
    }

    private func flushPendingClientDataIfNeeded() {
        guard state == .ready, let connection, !pendingClientBytes.isEmpty else { return }
        let data = pendingClientBytes
        pendingClientBytes.removeAll(keepingCapacity: true)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("Upstream send failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                    return
                }
                self.onTraffic(data.count, 0)
                self.onActivity("client data forwarded \(data.count) bytes")
            }
        })
    }

    private func deliverUpstreamBytes(_ bytes: Data) {
        guard !closed else { return }
        var offset = 0
        while offset < bytes.count {
            let chunkSize = min(1300, bytes.count - offset)
            let chunk = bytes.subdata(in: offset ..< (offset + chunkSize))
            let packet = IPv4TCPPacketBuilder.buildPacket(
                sourceIP: key.destinationIP,
                sourcePort: key.destinationPort,
                destinationIP: key.sourceIP,
                destinationPort: key.sourcePort,
                sequenceNumber: serverSequence,
                acknowledgementNumber: clientAck,
                flags: 0x18,
                payload: chunk
            )
            packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
            serverSequence &+= UInt32(chunk.count)
            offset += chunkSize
        }
        onTraffic(0, bytes.count)
        onActivity("upstream delivered \(bytes.count) bytes")
    }

    private func sendSYNACK(responseTo packet: ParsedIPv4TCPPacket) {
        let options = tcpOptionsForSYNACK()
        let response = IPv4TCPPacketBuilder.buildPacket(
            sourceIP: packet.destinationIP,
            sourcePort: packet.destinationPort,
            destinationIP: packet.sourceIP,
            destinationPort: packet.sourcePort,
            sequenceNumber: handshakeSequence,
            acknowledgementNumber: packet.sequenceNumber &+ Self.segmentLength(for: packet),
            flags: 0x12,
            payload: Data(),
            options: options
        )
        packetFlow.writePackets([response], withProtocols: [NSNumber(value: AF_INET)])
        if let advertisedWindowScale {
            onActivity("syn-ack sent | ws=\(advertisedWindowScale)")
        } else {
            onActivity("syn-ack sent")
        }
    }

    private func sendACKOnly(responseTo packet: ParsedIPv4TCPPacket) {
        let response = IPv4TCPPacketBuilder.buildPacket(
            sourceIP: packet.destinationIP,
            sourcePort: packet.destinationPort,
            destinationIP: packet.sourceIP,
            destinationPort: packet.sourcePort,
            sequenceNumber: serverSequence,
            acknowledgementNumber: clientAck,
            flags: 0x10,
            payload: Data()
        )
        packetFlow.writePackets([response], withProtocols: [NSNumber(value: AF_INET)])
    }

    private func sendFINACK(responseTo packet: ParsedIPv4TCPPacket) {
        let response = IPv4TCPPacketBuilder.buildPacket(
            sourceIP: packet.destinationIP,
            sourcePort: packet.destinationPort,
            destinationIP: packet.sourceIP,
            destinationPort: packet.sourcePort,
            sequenceNumber: serverSequence,
            acknowledgementNumber: packet.sequenceNumber &+ Self.segmentLength(for: packet),
            flags: 0x11,
            payload: Data()
        )
        packetFlow.writePackets([response], withProtocols: [NSNumber(value: AF_INET)])
        serverSequence &+= 1
    }

    private func sendRST(responseTo packet: ParsedIPv4TCPPacket) {
        let response = IPv4TCPPacketBuilder.buildPacket(
            sourceIP: packet.destinationIP,
            sourcePort: packet.destinationPort,
            destinationIP: packet.sourceIP,
            destinationPort: packet.sourcePort,
            sequenceNumber: serverSequence,
            acknowledgementNumber: packet.sequenceNumber &+ Self.segmentLength(for: packet),
            flags: 0x14,
            payload: Data()
        )
        packetFlow.writePackets([response], withProtocols: [NSNumber(value: AF_INET)])
    }

    private func close() {
        guard !closed else { return }
        closed = true
        state = .closed
        pendingClientBytes.removeAll(keepingCapacity: false)
        pendingProxyBytes.removeAll(keepingCapacity: false)
        connection?.cancel()
        connection = nil
        onFinish(key)
    }

    private static func randomSequence() -> UInt32 {
        UInt32.random(in: 1 ... UInt32.max)
    }

    private static func segmentLength(for packet: ParsedIPv4TCPPacket) -> UInt32 {
        UInt32(packet.payload.count) + (packet.syn ? 1 : 0) + (packet.fin ? 1 : 0)
    }

    private func tcpOptionsForSYNACK() -> Data {
        guard let advertisedWindowScale else { return Data() }
        return Data([0x01, 0x03, 0x03, advertisedWindowScale])
    }
}

private final class UDPFlowSession {
    private enum State {
        case idle
        case associating
        case ready
        case closing
        case closed
    }

    private let key: UDPFlowKey
    private let initialPacket: ParsedIPv4UDPPacket
    private let packetFlow: NEPacketTunnelFlow
    private let socksProxyPort: Int
    private let logger: Logger
    private let stateQueue: DispatchQueue
    private let onTraffic: (Int, Int) -> Void
    private let onFinish: (UDPFlowKey) -> Void
    private let onActivity: (String) -> Void

    private var state: State = .idle
    private var controlConnection: NWConnection?
    private var relayConnection: NWConnection?
    private var pendingClientPayloads: [Data] = []
    private var closed = false

    init(
        key: UDPFlowKey,
        initialPacket: ParsedIPv4UDPPacket,
        packetFlow: NEPacketTunnelFlow,
        socksProxyPort: Int,
        logger: Logger,
        stateQueue: DispatchQueue,
        onTraffic: @escaping (Int, Int) -> Void,
        onFinish: @escaping (UDPFlowKey) -> Void,
        onActivity: @escaping (String) -> Void
    ) {
        self.key = key
        self.initialPacket = initialPacket
        self.packetFlow = packetFlow
        self.socksProxyPort = socksProxyPort
        self.logger = logger
        self.stateQueue = stateQueue
        self.onTraffic = onTraffic
        self.onFinish = onFinish
        self.onActivity = onActivity
    }

    func handle(_ packet: ParsedIPv4UDPPacket) {
        stateQueue.async {
            guard !self.closed else { return }

            if packet.payload.isEmpty {
                self.onActivity("udp keepalive \(self.key.description)")
                return
            }

            self.onActivity("udp flow \(self.key.description) payload=\(packet.payload.count)")
            if self.state == .ready {
                self.sendUDPDatagram(packet.payload)
            } else {
                self.pendingClientPayloads.append(packet.payload)
                self.ensureAssociateStarted()
            }
        }
    }

    func stop() {
        stateQueue.async {
            self.close()
        }
    }

    private func ensureAssociateStarted() {
        guard controlConnection == nil, state != .closing, state != .closed else {
            flushPendingIfNeeded()
            return
        }

        state = .associating
        guard let proxyPort = Network.NWEndpoint.Port(rawValue: UInt16(socksProxyPort)) else {
            logger.error("Invalid SOCKS proxy port: \(self.socksProxyPort, privacy: .public)")
            close()
            return
        }

        let connection = NWConnection(host: "127.0.0.1", port: proxyPort, using: .tcp)
        controlConnection = connection
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            self.stateQueue.async {
                switch newState {
                case .ready:
                    self.logger.info("UDP SOCKS control ready for \(self.key.description, privacy: .public)")
                    self.onActivity("udp socks control ready")
                    self.sendGreeting()
                case .failed(let error):
                    self.logger.error("UDP SOCKS control failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                case .cancelled:
                    self.close()
                default:
                    break
                }
            }
        }
        connection.start(queue: stateQueue)
        onActivity("connecting to local xray socks proxy")
    }

    private func sendGreeting() {
        guard let controlConnection else { return }
        let greeting = Data([0x05, 0x01, 0x00])
        controlConnection.send(content: greeting, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("UDP SOCKS greeting failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                    return
                }
                self.readGreetingResponse()
            }
        })
    }

    private func readGreetingResponse() {
        guard let controlConnection else { return }
        controlConnection.receive(minimumIncompleteLength: 2, maximumLength: 64) { [weak self] data, _, _, error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("UDP SOCKS greeting response failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                    return
                }
                guard let data, data.count >= 2, data[0] == 0x05, data[1] == 0x00 else {
                    self.logger.error("UDP SOCKS greeting rejected for \(self.key.description, privacy: .public)")
                    self.close()
                    return
                }
                self.sendUDPAssociateRequest()
            }
        }
    }

    private func sendUDPAssociateRequest() {
        guard let controlConnection else { return }
        let request = Data([0x05, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        controlConnection.send(content: request, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("UDP SOCKS associate send failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                    return
                }
                self.readUDPAssociateResponse()
            }
        })
    }

    private func readUDPAssociateResponse() {
        guard let controlConnection else { return }
        controlConnection.receive(minimumIncompleteLength: 10, maximumLength: 256) { [weak self] data, _, _, error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("UDP SOCKS associate response failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                    return
                }
                guard let data, let endpoint = Self.parseSOCKSAssociateResponse(data) else {
                    self.logger.error("UDP SOCKS associate response invalid for \(self.key.description, privacy: .public)")
                    self.close()
                    return
                }
                let relayDescription = "\(endpoint.host):\(endpoint.port)"
                self.logger.info("UDP SOCKS associate response for \(self.key.description, privacy: .public) | relay=\(relayDescription, privacy: .public) | bytes=\(data.count, privacy: .public)")
                let relayConnection = NWConnection(host: endpoint.host, port: endpoint.port, using: .udp)
                self.relayConnection = relayConnection
                relayConnection.stateUpdateHandler = { [weak self] newState in
                    guard let self else { return }
                    self.stateQueue.async {
                        switch newState {
                        case .ready:
                            self.state = .ready
                            self.logger.info("UDP relay ready for \(self.key.description, privacy: .public)")
                            self.onActivity("udp relay ready")
                            self.flushPendingIfNeeded()
                            self.receiveRelayLoop()
                        case .failed(let error):
                            self.logger.error("UDP relay failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            self.close()
                        case .cancelled:
                            self.close()
                        default:
                            break
                        }
                    }
                }
                relayConnection.start(queue: self.stateQueue)
            }
        }
    }

    private func sendUDPDatagram(_ payload: Data) {
        guard state == .ready, let relayConnection else {
            pendingClientPayloads.append(payload)
            return
        }

        guard let datagram = Self.makeSOCKSUDPDatagram(
            destinationIP: key.destinationIP,
            destinationPort: key.destinationPort,
            payload: payload
        ) else {
            logger.error("Failed to build SOCKS UDP datagram for \(self.key.description, privacy: .public)")
            close()
            return
        }
        logger.debug("UDP datagram prepared for \(self.key.description, privacy: .public) | target=\(self.key.destinationIP):\(self.key.destinationPort, privacy: .public) | payload=\(payload.count, privacy: .public) | bytes=\(datagram.count, privacy: .public)")

        relayConnection.send(content: datagram, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("UDP relay send failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                    return
                }
                self.onTraffic(payload.count, 0)
                self.onActivity("udp payload forwarded \(payload.count) bytes")
            }
        })
    }

    private func receiveRelayLoop() {
        guard let relayConnection, state == .ready else { return }
        relayConnection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            self.stateQueue.async {
                if let error {
                    self.logger.error("UDP relay receive failed for \(self.key.description, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.close()
                    return
                }
                if let data, !data.isEmpty {
                    self.handleRelayResponse(data)
                }
                self.receiveRelayLoop()
            }
        }
    }

    private func handleRelayResponse(_ data: Data) {
        guard let response = Self.parseSOCKSUDPDatagram(data) else {
            let prefix = data.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
            logger.debug("Ignoring non-SOCKS UDP datagram for \(self.key.description, privacy: .public) | bytes=\(data.count, privacy: .public) | prefix=\(prefix, privacy: .public)")
            return
        }
        logger.debug("UDP relay response parsed for \(self.key.description, privacy: .public) | source=\(response.sourceIP):\(response.sourcePort, privacy: .public) | payload=\(response.payload.count, privacy: .public)")

        let packet = IPv4UDPPacketBuilder.buildPacket(
            sourceIP: response.sourceIP,
            sourcePort: response.sourcePort,
            destinationIP: key.sourceIP,
            destinationPort: key.sourcePort,
            payload: response.payload
        )
        guard !packet.isEmpty else {
            return
        }
        packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
        onTraffic(0, response.payload.count)
        onActivity("udp upstream delivered \(response.payload.count) bytes")
    }

    private func flushPendingIfNeeded() {
        guard state == .ready, !pendingClientPayloads.isEmpty else { return }
        let payloads = pendingClientPayloads
        pendingClientPayloads.removeAll(keepingCapacity: true)
        for payload in payloads {
            sendUDPDatagram(payload)
        }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        state = .closed
        pendingClientPayloads.removeAll(keepingCapacity: false)
        relayConnection?.cancel()
        controlConnection?.cancel()
        relayConnection = nil
        controlConnection = nil
        onFinish(key)
    }

    private static func parseSOCKSAssociateResponse(_ data: Data) -> (host: Network.NWEndpoint.Host, port: Network.NWEndpoint.Port)? {
        guard data.count >= 10, data[0] == 0x05, data[1] == 0x00 else {
            return nil
        }
        let atyp = data[3]
        var offset = 4
        let hostString: String
        switch atyp {
        case 0x01:
            guard data.count >= offset + 4 + 2 else { return nil }
            hostString = "\(data[offset]).\(data[offset + 1]).\(data[offset + 2]).\(data[offset + 3])"
            offset += 4
        case 0x03:
            guard data.count >= offset + 1 else { return nil }
            let length = Int(data[offset])
            offset += 1
            guard data.count >= offset + length + 2 else { return nil }
            hostString = String(data: data[offset ..< (offset + length)], encoding: .utf8) ?? ""
            offset += length
        case 0x04:
            guard data.count >= offset + 16 + 2 else { return nil }
            let bytes = Array(data[offset ..< (offset + 16)])
            hostString = stride(from: 0, to: bytes.count, by: 2).map { index in
                let value = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
                return String(value, radix: 16)
            }.joined(separator: ":")
            offset += 16
        default:
            return nil
        }

        guard data.count >= offset + 2 else {
            return nil
        }
        let port = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        let normalizedHost = hostString.isEmpty || hostString == "0.0.0.0" || hostString == "::" ? "127.0.0.1" : hostString
        guard let nwPort = Network.NWEndpoint.Port(rawValue: port) else {
            return nil
        }
        return (Network.NWEndpoint.Host(normalizedHost), nwPort)
    }

    private static func makeSOCKSUDPDatagram(destinationIP: String, destinationPort: UInt16, payload: Data) -> Data? {
        guard let ipBytes = ipv4Bytes(from: destinationIP) else {
            return nil
        }

        var bytes = [UInt8]()
        bytes.append(0x00)
        bytes.append(0x00)
        bytes.append(0x00)
        bytes.append(0x01)
        bytes.append(contentsOf: ipBytes)
        bytes.append(UInt8(destinationPort >> 8))
        bytes.append(UInt8(destinationPort & 0xff))
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    private static func parseSOCKSUDPDatagram(_ data: Data) -> (sourceIP: String, sourcePort: UInt16, payload: Data)? {
        guard data.count >= 10, data[0] == 0x00, data[1] == 0x00, data[2] == 0x00 else {
            return nil
        }

        let atyp = data[3]
        var offset = 4
        let sourceIP: String
        switch atyp {
        case 0x01:
            guard data.count >= offset + 4 + 2 else { return nil }
            sourceIP = "\(data[offset]).\(data[offset + 1]).\(data[offset + 2]).\(data[offset + 3])"
            offset += 4
        case 0x03:
            guard data.count >= offset + 1 else { return nil }
            let length = Int(data[offset])
            offset += 1
            guard data.count >= offset + length + 2 else { return nil }
            sourceIP = String(data: data[offset ..< (offset + length)], encoding: .utf8) ?? ""
            offset += length
        case 0x04:
            guard data.count >= offset + 16 + 2 else { return nil }
            let bytes = Array(data[offset ..< (offset + 16)])
            sourceIP = stride(from: 0, to: bytes.count, by: 2).map { index in
                let value = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
                return String(value, radix: 16)
            }.joined(separator: ":")
            offset += 16
        default:
            return nil
        }

        guard data.count >= offset + 2 else {
            return nil
        }
        let sourcePort = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        offset += 2
        guard offset <= data.count else {
            return nil
        }
        return (sourceIP, sourcePort, data[offset ..< data.count])
    }

    private static func ipv4Bytes(from string: String) -> [UInt8]? {
        var address = in_addr()
        guard string.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else {
            return nil
        }
        return withUnsafeBytes(of: address) { Array($0) }
    }
}

private enum IPv4TCPPacketBuilder {
    static func buildPacket(
        sourceIP: String,
        sourcePort: UInt16,
        destinationIP: String,
        destinationPort: UInt16,
        sequenceNumber: UInt32,
        acknowledgementNumber: UInt32,
        flags: UInt8,
        payload: Data,
        windowSize: UInt16 = 65535,
        options: Data = Data()
    ) -> Data {
        let ipHeaderLength = 20
        let paddedOptionsLength = ((options.count + 3) / 4) * 4
        let tcpHeaderLength = 20 + paddedOptionsLength
        let totalLength = ipHeaderLength + tcpHeaderLength + payload.count
        var bytes = [UInt8](repeating: 0, count: totalLength)

        bytes[0] = 0x45
        bytes[1] = 0x00
        writeUInt16(UInt16(totalLength), into: &bytes, offset: 2)
        writeUInt16(UInt16.random(in: 0 ... UInt16.max), into: &bytes, offset: 4)
        writeUInt16(0, into: &bytes, offset: 6)
        bytes[8] = 64
        bytes[9] = 6

        guard let srcIP = ipv4Bytes(from: sourceIP), let dstIP = ipv4Bytes(from: destinationIP) else {
            return Data()
        }
        for index in 0 ..< 4 {
            bytes[12 + index] = srcIP[index]
            bytes[16 + index] = dstIP[index]
        }

        writeUInt16(0, into: &bytes, offset: 10)
        let ipChecksum = checksum(Data(bytes[0 ..< ipHeaderLength]))
        writeUInt16(ipChecksum, into: &bytes, offset: 10)

        writeUInt16(sourcePort, into: &bytes, offset: ipHeaderLength)
        writeUInt16(destinationPort, into: &bytes, offset: ipHeaderLength + 2)
        writeUInt32(sequenceNumber, into: &bytes, offset: ipHeaderLength + 4)
        writeUInt32(acknowledgementNumber, into: &bytes, offset: ipHeaderLength + 8)
        bytes[ipHeaderLength + 12] = UInt8((tcpHeaderLength / 4) << 4)
        bytes[ipHeaderLength + 13] = flags
        writeUInt16(windowSize, into: &bytes, offset: ipHeaderLength + 14)
        writeUInt16(0, into: &bytes, offset: ipHeaderLength + 16)
        writeUInt16(0, into: &bytes, offset: ipHeaderLength + 18)

        if !options.isEmpty {
            bytes.replaceSubrange((ipHeaderLength + 20) ..< (ipHeaderLength + 20 + options.count), with: options)
        }

        if !payload.isEmpty {
            bytes.replaceSubrange((ipHeaderLength + tcpHeaderLength) ..< totalLength, with: payload)
        }

        let tcpChecksum = tcpChecksum(
            sourceIPBytes: srcIP,
            destinationIPBytes: dstIP,
            tcpBytes: Data(bytes[ipHeaderLength ..< totalLength])
        )
        writeUInt16(tcpChecksum, into: &bytes, offset: ipHeaderLength + 16)

        return Data(bytes)
    }

    private static func ipv4Bytes(from string: String) -> [UInt8]? {
        var address = in_addr()
        guard string.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else {
            return nil
        }
        return withUnsafeBytes(of: address) { Array($0) }
    }

    private static func checksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        let bytes = Array(data)

        while index < bytes.count {
            let high = UInt32(bytes[index])
            let low = UInt32(index + 1 < bytes.count ? bytes[index + 1] : 0)
            sum += (high << 8) | low
            while (sum >> 16) != 0 {
                sum = (sum & 0xffff) + (sum >> 16)
            }
            index += 2
        }

        return ~UInt16(sum & 0xffff)
    }

    private static func tcpChecksum(sourceIPBytes: [UInt8], destinationIPBytes: [UInt8], tcpBytes: Data) -> UInt16 {
        var pseudoHeader = [UInt8]()
        pseudoHeader.append(contentsOf: sourceIPBytes)
        pseudoHeader.append(contentsOf: destinationIPBytes)
        pseudoHeader.append(0)
        pseudoHeader.append(6)
        let length = UInt16(tcpBytes.count)
        pseudoHeader.append(UInt8(length >> 8))
        pseudoHeader.append(UInt8(length & 0xff))
        pseudoHeader.append(contentsOf: tcpBytes)
        return checksum(Data(pseudoHeader))
    }

    private static func writeUInt16(_ value: UInt16, into bytes: inout [UInt8], offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xff)
        bytes[offset + 1] = UInt8(value & 0xff)
    }

    private static func writeUInt32(_ value: UInt32, into bytes: inout [UInt8], offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xff)
        bytes[offset + 1] = UInt8((value >> 16) & 0xff)
        bytes[offset + 2] = UInt8((value >> 8) & 0xff)
        bytes[offset + 3] = UInt8(value & 0xff)
    }
}
