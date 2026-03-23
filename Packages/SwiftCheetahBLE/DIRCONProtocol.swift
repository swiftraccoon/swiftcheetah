import Foundation

public enum DIRCONOpcode: UInt8, Sendable {
    case discoverServices = 0x01
    case discoverCharacteristics = 0x02
    case readCharacteristic = 0x03
    case writeCharacteristic = 0x04
    case enableNotifications = 0x05
    case notification = 0x06
}

public enum DIRCONResponseCode: UInt8, Sendable {
    case success = 0x00
    case invalidMessageType = 0x01
    case unexpectedError = 0x02
    case serviceNotFound = 0x03
    case characteristicNotFound = 0x04
    case operationNotSupported = 0x05
    case writeFailed = 0x06
    case unknownVersion = 0x07
}

public struct DIRCONMessage: Sendable {
    public static let headerSize = 6
    public static let protocolVersion: UInt8 = 1

    public let opcode: DIRCONOpcode
    public let sequenceNumber: UInt8
    public let responseCode: UInt8
    public let payload: Data

    public init(opcode: DIRCONOpcode, sequenceNumber: UInt8, responseCode: UInt8, payload: Data) {
        self.opcode = opcode
        self.sequenceNumber = sequenceNumber
        self.responseCode = responseCode
        self.payload = payload
    }

    public func serialize() -> Data {
        let len = UInt16(payload.count)
        var data = Data(capacity: DIRCONMessage.headerSize + payload.count)
        data.append(DIRCONMessage.protocolVersion)
        data.append(opcode.rawValue)
        data.append(sequenceNumber)
        data.append(responseCode)
        data.append(UInt8(len >> 8))
        data.append(UInt8(len & 0xFF))
        data.append(payload)
        return data
    }

    public static func deserialize(from data: Data) -> DIRCONMessage? {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize else { return nil }
        guard bytes[0] == protocolVersion else { return nil }
        guard let opcode = DIRCONOpcode(rawValue: bytes[1]) else { return nil }
        let seq = bytes[2]
        let resp = bytes[3]
        let dataLen = Int(UInt16(bytes[4]) << 8 | UInt16(bytes[5]))
        guard bytes.count >= headerSize + dataLen else { return nil }
        let payload = Data(bytes[headerSize ..< headerSize + dataLen])
        return DIRCONMessage(opcode: opcode, sequenceNumber: seq, responseCode: resp, payload: payload)
    }
}

public enum DIRCONProtocol {
    private static let baseTail: [UInt8] = [
        0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB
    ]

    public static func wireUUID(from shortUUID: UInt16) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[2] = UInt8(shortUUID >> 8)
        bytes[3] = UInt8(shortUUID & 0xFF)
        for i in 0..<12 { bytes[4 + i] = baseTail[i] }
        return bytes
    }

    public static func shortUUID(from wireBytes: [UInt8]) -> UInt16 {
        guard wireBytes.count >= 4 else { return 0 }
        return UInt16(wireBytes[2]) << 8 | UInt16(wireBytes[3])
    }

    public static func shortUUID(from data: Data) -> UInt16 {
        return shortUUID(from: [UInt8](data))
    }

    public static let defaultPort: UInt16 = 36866
}
