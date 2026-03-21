import Foundation

public struct DIRCONCharProperties: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let read     = DIRCONCharProperties(rawValue: 0x01)
    public static let write    = DIRCONCharProperties(rawValue: 0x02)
    public static let notify   = DIRCONCharProperties(rawValue: 0x04)
    public static let indicate = DIRCONCharProperties(rawValue: 0x08)
}

public final class DIRCONServiceTable: @unchecked Sendable {
    public struct Characteristic: Sendable {
        public let shortUUID: UInt16
        public let properties: DIRCONCharProperties
    }

    public struct Service: Sendable {
        public let shortUUID: UInt16
        public let characteristics: [Characteristic]
    }

    public let services: [Service]

    public init() {
        services = [
            Service(shortUUID: 0x1826, characteristics: [
                Characteristic(shortUUID: 0x2ACC, properties: .read),
                Characteristic(shortUUID: 0x2AD2, properties: .notify),
                Characteristic(shortUUID: 0x2ADA, properties: .notify),
                Characteristic(shortUUID: 0x2AD9, properties: [.write, .indicate]),
                Characteristic(shortUUID: 0x2AD8, properties: .read),
            ]),
            Service(shortUUID: 0x1818, characteristics: [
                Characteristic(shortUUID: 0x2A63, properties: .notify),
                Characteristic(shortUUID: 0x2A65, properties: .read),
                Characteristic(shortUUID: 0x2A5D, properties: .read),
            ]),
            Service(shortUUID: 0x180D, characteristics: [
                Characteristic(shortUUID: 0x2A37, properties: .notify),
                Characteristic(shortUUID: 0x2A38, properties: .read),
            ]),
            Service(shortUUID: 0x1814, characteristics: [
                Characteristic(shortUUID: 0x2A53, properties: .notify),
                Characteristic(shortUUID: 0x2A54, properties: .read),
            ]),
            Service(shortUUID: 0x180A, characteristics: [
                Characteristic(shortUUID: 0x2A29, properties: .read),
                Characteristic(shortUUID: 0x2A24, properties: .read),
                Characteristic(shortUUID: 0x2A25, properties: .read),
                Characteristic(shortUUID: 0x2A26, properties: .read),
                Characteristic(shortUUID: 0x2A27, properties: .read),
            ]),
        ]
    }

    public func discoverServicesPayload() -> Data {
        var data = Data()
        for service in services {
            data.append(contentsOf: DIRCONProtocol.wireUUID(from: service.shortUUID))
        }
        return data
    }

    public func discoverCharacteristicsPayload(forServiceShortUUID uuid: UInt16) -> Data? {
        guard let service = services.first(where: { $0.shortUUID == uuid }) else { return nil }
        var data = Data()
        data.append(contentsOf: DIRCONProtocol.wireUUID(from: service.shortUUID))
        for char in service.characteristics {
            data.append(contentsOf: DIRCONProtocol.wireUUID(from: char.shortUUID))
            data.append(char.properties.rawValue)
        }
        return data
    }

    /// Optional trainer identity for DIS characteristic reads.
    public var trainerIdentity: PeripheralManager.TrainerIdentity = PeripheralManager.TrainerIdentity()

    public func readCharacteristicValue(shortUUID: UInt16) -> Data? {
        switch shortUUID {
        case 0x2ACC: // FTMS Feature
            var buf = Data(count: 8)
            var lower: UInt32 = 0
            lower |= 1 << 1; lower |= 1 << 14
            var upper: UInt32 = 0
            upper |= 1 << 3; upper |= 1 << 13
            buf[0] = UInt8(lower & 0xFF); buf[1] = UInt8((lower >> 8) & 0xFF)
            buf[2] = UInt8((lower >> 16) & 0xFF); buf[3] = UInt8((lower >> 24) & 0xFF)
            buf[4] = UInt8(upper & 0xFF); buf[5] = UInt8((upper >> 8) & 0xFF)
            buf[6] = UInt8((upper >> 16) & 0xFF); buf[7] = UInt8((upper >> 24) & 0xFF)
            return buf
        case 0x2AD8: // Supported Power Range
            return Data([0x00, 0x00, 0xA0, 0x0F, 0x01, 0x00])
        case 0x2A65: // CPS Feature
            var flags: UInt32 = (1 << 2) | (1 << 3)
            return Data(bytes: &flags, count: 4)
        case 0x2A5D: // Sensor Location — rear hub
            return Data([13])
        case 0x2A38: // Body Sensor Location — chest
            return Data([1])
        case 0x2A54: // RSC Feature
            return Data([0x00, 0x00])
        case 0x2A29: // Manufacturer Name
            return Data(trainerIdentity.manufacturer.utf8)
        case 0x2A24: // Model Number
            return Data(trainerIdentity.model.utf8)
        case 0x2A25: // Serial Number
            return Data(trainerIdentity.serial.utf8)
        case 0x2A26: // Firmware Revision
            return Data(trainerIdentity.firmwareRevision.utf8)
        case 0x2A27: // Hardware Revision
            return Data(trainerIdentity.hardwareRevision.utf8)
        default:
            return nil
        }
    }
}
