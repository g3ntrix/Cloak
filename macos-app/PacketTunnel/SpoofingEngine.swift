import Foundation

struct PacketEngineStatus {
    let trackedConnections: Int
    let lastConnectionID: String?
    let lastEvent: String?
    let lastFakeClientHelloSize: Int?
}

final class SpoofingEngine {
    private struct ConnectionState {
        var synSeen = false
        var synAckSeen = false
        var established = false
    }

    private let configuration: TunnelConfiguration
    private var states: [String: ConnectionState] = [:]
    private(set) var inspectedPacketCount = 0
    private(set) var lastConnectionID: String?
    private(set) var lastEvent: String?
    private(set) var lastFakeClientHelloSize: Int?

    init(configuration: TunnelConfiguration) {
        self.configuration = configuration
    }

    func reload(configuration: TunnelConfiguration) {
        states.removeAll()
        inspectedPacketCount = 0
        lastConnectionID = nil
        lastEvent = "configuration reloaded"
        lastFakeClientHelloSize = nil
    }

    func observeOutboundPacket(_ packetData: Data) {
        guard let packet = PacketParser.parseIPv4TCPPacket(packetData) else {
            return
        }

        inspectedPacketCount += 1
        let connectionID = "\(packet.sourceIP):\(packet.sourcePort)->\(packet.destinationIP):\(packet.destinationPort)"
        lastConnectionID = connectionID

        var state = states[connectionID] ?? ConnectionState()

        if packet.destinationPort == UInt16(configuration.connectPort) {
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
        } else {
            lastEvent = "non-target packet observed"
        }

        states[connectionID] = state
    }

    func observeInboundPacket(_ packetData: Data) {
        guard let packet = PacketParser.parseIPv4TCPPacket(packetData) else {
            return
        }

        inspectedPacketCount += 1
        let connectionID = "\(packet.destinationIP):\(packet.destinationPort)->\(packet.sourceIP):\(packet.sourcePort)"
        lastConnectionID = connectionID

        var state = states[connectionID] ?? ConnectionState()
        if packet.syn, packet.ack {
            state.synAckSeen = true
            lastEvent = "inbound syn-ack seen"
        } else if packet.rst {
            lastEvent = "rst observed"
        } else if packet.fin {
            lastEvent = "fin observed"
        } else if packet.ack, !packet.payload.isEmpty {
            lastEvent = "inbound payload observed size=\(packet.payload.count)"
        }
        states[connectionID] = state
    }

    func status() -> PacketEngineStatus {
        PacketEngineStatus(
            trackedConnections: states.count,
            lastConnectionID: lastConnectionID,
            lastEvent: lastEvent,
            lastFakeClientHelloSize: lastFakeClientHelloSize
        )
    }

    private func randomData(length: Int) -> Data {
        Data((0 ..< length).map { _ in UInt8.random(in: 0 ... 255) })
    }
}
