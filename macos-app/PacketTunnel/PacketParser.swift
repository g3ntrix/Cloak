import Foundation
import Network

struct ParsedIPv4TCPPacket {
    let sourceIP: String
    let destinationIP: String
    let sourcePort: UInt16
    let destinationPort: UInt16
    let sequenceNumber: UInt32
    let acknowledgementNumber: UInt32
    let windowSize: UInt16
    let windowScale: UInt8?
    let syn: Bool
    let ack: Bool
    let fin: Bool
    let rst: Bool
    let psh: Bool
    let payload: Data
}

struct ParsedIPv4UDPPacket {
    let sourceIP: String
    let destinationIP: String
    let sourcePort: UInt16
    let destinationPort: UInt16
    let payload: Data
}

enum PacketParser {
    static func parseIPv4TCPPacket(_ packetData: Data) -> ParsedIPv4TCPPacket? {
        guard packetData.count >= 40 else {
            return nil
        }

        let version = packetData[0] >> 4
        guard version == 4 else {
            return nil
        }

        let ipHeaderLength = Int(packetData[0] & 0x0f) * 4
        guard packetData.count >= ipHeaderLength + 20 else {
            return nil
        }

        let protocolNumber = packetData[9]
        guard protocolNumber == 6 else {
            return nil
        }

        let sourceIP = ipv4String(from: packetData[12 ..< 16])
        let destinationIP = ipv4String(from: packetData[16 ..< 20])

        let tcpStart = ipHeaderLength
        let sourcePort = uint16(from: packetData, at: tcpStart)
        let destinationPort = uint16(from: packetData, at: tcpStart + 2)
        let sequenceNumber = uint32(from: packetData, at: tcpStart + 4)
        let acknowledgementNumber = uint32(from: packetData, at: tcpStart + 8)
        let tcpHeaderLength = Int((packetData[tcpStart + 12] >> 4) * 4)
        let windowSize = uint16(from: packetData, at: tcpStart + 14)
        guard packetData.count >= tcpStart + tcpHeaderLength else {
            return nil
        }

        let flags = packetData[tcpStart + 13]
        let optionsRange = (tcpStart + 20) ..< (tcpStart + tcpHeaderLength)
        let windowScale = tcpHeaderLength > 20 ? parseWindowScaleOption(from: packetData[optionsRange]) : nil
        let payloadStart = tcpStart + tcpHeaderLength
        let payload = payloadStart < packetData.count ? packetData.subdata(in: payloadStart ..< packetData.count) : Data()

        return ParsedIPv4TCPPacket(
            sourceIP: sourceIP,
            destinationIP: destinationIP,
            sourcePort: sourcePort,
            destinationPort: destinationPort,
            sequenceNumber: sequenceNumber,
            acknowledgementNumber: acknowledgementNumber,
            windowSize: windowSize,
            windowScale: windowScale,
            syn: flags & 0x02 != 0,
            ack: flags & 0x10 != 0,
            fin: flags & 0x01 != 0,
            rst: flags & 0x04 != 0,
            psh: flags & 0x08 != 0,
            payload: payload
        )
    }

    static func parseIPv4UDPPacket(_ packetData: Data) -> ParsedIPv4UDPPacket? {
        guard packetData.count >= 28 else {
            return nil
        }

        let version = packetData[0] >> 4
        guard version == 4 else {
            return nil
        }

        let ipHeaderLength = Int(packetData[0] & 0x0f) * 4
        guard packetData.count >= ipHeaderLength + 8 else {
            return nil
        }

        let protocolNumber = packetData[9]
        guard protocolNumber == 17 else {
            return nil
        }

        let sourceIP = ipv4String(from: packetData[12 ..< 16])
        let destinationIP = ipv4String(from: packetData[16 ..< 20])

        let udpStart = ipHeaderLength
        let sourcePort = uint16(from: packetData, at: udpStart)
        let destinationPort = uint16(from: packetData, at: udpStart + 2)
        let udpLength = Int(uint16(from: packetData, at: udpStart + 4))
        let payloadStart = udpStart + 8
        let payloadEnd = min(packetData.count, udpStart + max(udpLength, 8))
        let payload = payloadStart < payloadEnd ? packetData.subdata(in: payloadStart ..< payloadEnd) : Data()

        return ParsedIPv4UDPPacket(
            sourceIP: sourceIP,
            destinationIP: destinationIP,
            sourcePort: sourcePort,
            destinationPort: destinationPort,
            payload: payload
        )
    }

    private static func uint16(from data: Data, at index: Int) -> UInt16 {
        let slice = data[index ..< (index + 2)]
        return slice.reduce(0) { ($0 << 8) | UInt16($1) }
    }

    private static func uint32(from data: Data, at index: Int) -> UInt32 {
        let slice = data[index ..< (index + 4)]
        return slice.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func parseWindowScaleOption(from data: Data.SubSequence) -> UInt8? {
        var index = data.startIndex
        while index < data.endIndex {
            let kind = data[index]
            if kind == 0 {
                break
            }
            if kind == 1 {
                index = data.index(after: index)
                continue
            }

            let lengthIndex = data.index(after: index)
            guard lengthIndex < data.endIndex else { break }
            let length = Int(data[lengthIndex])
            guard length >= 2 else { break }
            let nextIndex = data.index(index, offsetBy: length, limitedBy: data.endIndex) ?? data.endIndex

            if kind == 3, length == 3 {
                let valueIndex = data.index(index, offsetBy: 2)
                guard valueIndex < data.endIndex else { break }
                return data[valueIndex]
            }

            index = nextIndex
        }
        return nil
    }

    private static func ipv4String(from bytes: Data.SubSequence) -> String {
        bytes.map(String.init).joined(separator: ".")
    }
}

enum IPv4UDPPacketBuilder {
    static func buildPacket(
        sourceIP: String,
        sourcePort: UInt16,
        destinationIP: String,
        destinationPort: UInt16,
        payload: Data
    ) -> Data {
        let ipHeaderLength = 20
        let udpHeaderLength = 8
        let totalLength = ipHeaderLength + udpHeaderLength + payload.count
        var bytes = [UInt8](repeating: 0, count: totalLength)

        bytes[0] = 0x45
        bytes[1] = 0x00
        writeUInt16(UInt16(totalLength), into: &bytes, offset: 2)
        writeUInt16(UInt16.random(in: 0 ... UInt16.max), into: &bytes, offset: 4)
        writeUInt16(0, into: &bytes, offset: 6)
        bytes[8] = 64
        bytes[9] = 17

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
        writeUInt16(UInt16(udpHeaderLength + payload.count), into: &bytes, offset: ipHeaderLength + 4)
        writeUInt16(0, into: &bytes, offset: ipHeaderLength + 6)

        if !payload.isEmpty {
            bytes.replaceSubrange((ipHeaderLength + udpHeaderLength) ..< totalLength, with: payload)
        }

        let udpChecksum = udpChecksum(
            sourceIPBytes: srcIP,
            destinationIPBytes: dstIP,
            udpBytes: Data(bytes[ipHeaderLength ..< totalLength])
        )
        writeUInt16(udpChecksum == 0 ? 0xffff : udpChecksum, into: &bytes, offset: ipHeaderLength + 6)

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

    private static func udpChecksum(sourceIPBytes: [UInt8], destinationIPBytes: [UInt8], udpBytes: Data) -> UInt16 {
        var pseudoHeader = [UInt8]()
        pseudoHeader.append(contentsOf: sourceIPBytes)
        pseudoHeader.append(contentsOf: destinationIPBytes)
        pseudoHeader.append(0)
        pseudoHeader.append(17)
        let length = UInt16(udpBytes.count)
        pseudoHeader.append(UInt8(length >> 8))
        pseudoHeader.append(UInt8(length & 0xff))
        pseudoHeader.append(contentsOf: udpBytes)
        return checksum(Data(pseudoHeader))
    }

    private static func writeUInt16(_ value: UInt16, into bytes: inout [UInt8], offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xff)
        bytes[offset + 1] = UInt8(value & 0xff)
    }
}
