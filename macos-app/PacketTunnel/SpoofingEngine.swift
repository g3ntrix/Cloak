import Foundation

struct PacketEngineStatus {
    let trackedConnections: Int
    let lastConnectionID: String?
    let lastEvent: String?
    let lastFakeClientHelloSize: Int?
}

final class SpoofingEngine {
    private struct SpoofFlowKey: Hashable, CustomStringConvertible {
        let sourceIP: String
        let sourcePort: UInt16
        let destinationIP: String
        let destinationPort: UInt16

        var description: String {
            "\(sourceIP):\(sourcePort)->\(destinationIP):\(destinationPort)"
        }
    }

    private struct ConnectionState {
        var synSeen = false
        var synAckSeen = false
        var established = false
    }

    private let configuration: TunnelConfiguration
    private var states: [SpoofFlowKey: ConnectionState] = [:]
    private var lastConnectionKey: SpoofFlowKey?
    private(set) var inspectedPacketCount = 0
    private(set) var lastEvent: String?
    private(set) var lastFakeClientHelloSize: Int?

    init(configuration: TunnelConfiguration) {
        self.configuration = configuration
    }

    func reload(configuration: TunnelConfiguration) {
        states.removeAll()
        inspectedPacketCount = 0
        lastConnectionKey = nil
        lastEvent = "configuration reloaded"
        lastFakeClientHelloSize = nil
    }

    func observeOutboundPacket(_ packetData: Data) {
        guard let packet = PacketParser.parseIPv4TCPPacket(packetData) else {
            return
        }

        inspectedPacketCount += 1
        let key = SpoofFlowKey(
            sourceIP: packet.sourceIP,
            sourcePort: packet.sourcePort,
            destinationIP: packet.destinationIP,
            destinationPort: packet.destinationPort
        )
        lastConnectionKey = key

        if packet.rst || packet.fin {
            states.removeValue(forKey: key)
            lastEvent = packet.rst ? "outbound rst observed" : "outbound fin observed"
            return
        }

        guard packet.destinationPort == UInt16(configuration.connectPort) else {
            lastEvent = "non-target packet observed"
            return
        }

        var state = states[key] ?? ConnectionState()

        if packet.syn, !packet.ack {
            state.synSeen = true
            lastEvent = "outbound syn seen"
        } else if packet.ack, !packet.syn, state.synSeen, !state.established {
            state.established = true
            let fakeClientHello = TLSClientHelloBuilder.build(
                random: randomData(length: 32),
                sessionID: randomData(length: 32),
                targetSNI: configuration.fakeSNI,
                keyShare: randomData(length: 32)
            )
            lastFakeClientHelloSize = fakeClientHello.count
            lastEvent = "connection established candidate; fake hello prepared"
        } else if !packet.payload.isEmpty {
            lastEvent = "payload observed size=\(packet.payload.count)"
        }

        states[key] = state
    }

    func observeInboundPacket(_ packetData: Data) {
        guard let packet = PacketParser.parseIPv4TCPPacket(packetData) else {
            return
        }

        inspectedPacketCount += 1
        let key = SpoofFlowKey(
            sourceIP: packet.destinationIP,
            sourcePort: packet.destinationPort,
            destinationIP: packet.sourceIP,
            destinationPort: packet.sourcePort
        )
        lastConnectionKey = key

        if packet.rst || packet.fin {
            states.removeValue(forKey: key)
            lastEvent = packet.rst ? "rst observed" : "fin observed"
            return
        }

        guard packet.sourcePort == UInt16(configuration.connectPort) else {
            lastEvent = "non-target inbound packet observed"
            return
        }

        var state = states[key] ?? ConnectionState()
        if packet.syn, packet.ack {
            state.synAckSeen = true
            lastEvent = "inbound syn-ack seen"
        } else if packet.ack, !packet.payload.isEmpty {
            lastEvent = "inbound payload observed size=\(packet.payload.count)"
        }
        states[key] = state
    }

    func status() -> PacketEngineStatus {
        PacketEngineStatus(
            trackedConnections: states.count,
            lastConnectionID: lastConnectionKey?.description,
            lastEvent: lastEvent,
            lastFakeClientHelloSize: lastFakeClientHelloSize
        )
    }

    private func randomData(length: Int) -> Data {
        Data((0 ..< length).map { _ in UInt8.random(in: 0 ... 255) })
    }
}
