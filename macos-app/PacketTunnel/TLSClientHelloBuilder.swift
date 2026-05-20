import Foundation

enum TLSClientHelloBuilder {
    private static let templateHex =
        "1603010200010001fc030341d5b549d9cd1adfa7296c8418d157dc7b624c842824ff493b9375bb48d34f2b20bf018bcc90a7c89a230094815ad0c15b736e38c01209d72d282cb5e2105328150024130213031301c02cc030c02bc02fcca9cca8c024c028c023c027009f009e006b006700ff0100018f0000000b00090000066d63692e6972000b000403000102000a00160014001d0017001e0019001801000101010201030104002300000010000e000c02683208687474702f312e310016000000170000000d002a0028040305030603080708080809080a080b080408050806040105010601030303010302040205020602002b00050403040303002d00020101003300260024001d0020435bacc4d05f9d41fef44ab3ad55616c36e0613473e2338770efdaa98693d217001500d5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    private static let templateSNI = Data("mci.ir".utf8)
    private static let static1 = Data(hex: templateHex).prefix(11)
    private static let static2 = Data([0x20])
    private static let static3 = Data(hex: templateHex).subdata(in: 76 ..< 120)
    private static let static4 = Data(hex: templateHex).subdata(in: (127 + templateSNI.count) ..< (262 + templateSNI.count))
    private static let static5 = Data([0x00, 0x15])

    static func build(
        random: Data,
        sessionID: Data,
        targetSNI: String,
        keyShare: Data
    ) -> Data {
        let targetSNIData = Data(targetSNI.utf8)
        var serverName = Data()
        serverName.append(uint16be(UInt16(targetSNIData.count + 5)))
        serverName.append(uint16be(UInt16(targetSNIData.count + 3)))
        serverName.append(Data([0x00]))
        serverName.append(uint16be(UInt16(targetSNIData.count)))
        serverName.append(targetSNIData)

        let paddingLength = max(0, 219 - targetSNIData.count)
        var padding = Data()
        padding.append(uint16be(UInt16(paddingLength)))
        padding.append(Data(repeating: 0, count: paddingLength))

        var result = Data()
        result.append(static1)
        result.append(random)
        result.append(static2)
        result.append(sessionID)
        result.append(static3)
        result.append(serverName)
        result.append(static4)
        result.append(keyShare)
        result.append(static5)
        result.append(padding)
        return result
    }

    private static func uint16be(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}

private extension Data {
    init(hex: String) {
        self.init(capacity: hex.count / 2)
        var current = ""
        for character in hex {
            current.append(character)
            if current.count == 2 {
                append(UInt8(current, radix: 16) ?? 0)
                current.removeAll(keepingCapacity: true)
            }
        }
    }
}
