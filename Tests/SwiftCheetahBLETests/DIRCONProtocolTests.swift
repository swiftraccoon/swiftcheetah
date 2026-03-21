import XCTest
@testable import SwiftCheetahBLE

final class DIRCONProtocolTests: XCTestCase {

    func testOpcodeRawValues() {
        XCTAssertEqual(DIRCONOpcode.discoverServices.rawValue, 0x01)
        XCTAssertEqual(DIRCONOpcode.discoverCharacteristics.rawValue, 0x02)
        XCTAssertEqual(DIRCONOpcode.readCharacteristic.rawValue, 0x03)
        XCTAssertEqual(DIRCONOpcode.writeCharacteristic.rawValue, 0x04)
        XCTAssertEqual(DIRCONOpcode.enableNotifications.rawValue, 0x05)
        XCTAssertEqual(DIRCONOpcode.notification.rawValue, 0x06)
    }

    func testShortUUIDToWireBytes() {
        let bytes = DIRCONProtocol.wireUUID(from: 0x1826)
        XCTAssertEqual(bytes.count, 16)
        XCTAssertEqual(bytes[0], 0x00)
        XCTAssertEqual(bytes[1], 0x00)
        XCTAssertEqual(bytes[2], 0x18)
        XCTAssertEqual(bytes[3], 0x26)
        XCTAssertEqual(bytes[4], 0x00)
        XCTAssertEqual(bytes[5], 0x00)
        XCTAssertEqual(bytes[6], 0x10)
        XCTAssertEqual(bytes[7], 0x00)
        XCTAssertEqual(bytes[8], 0x80)
        XCTAssertEqual(bytes[9], 0x00)
        XCTAssertEqual(bytes[10], 0x00)
        XCTAssertEqual(bytes[11], 0x80)
        XCTAssertEqual(bytes[12], 0x5F)
        XCTAssertEqual(bytes[13], 0x9B)
        XCTAssertEqual(bytes[14], 0x34)
        XCTAssertEqual(bytes[15], 0xFB)
    }

    func testWireUUIDRoundTrip() {
        for uuid: UInt16 in [0x1826, 0x1818, 0x180D, 0x1814, 0x180A, 0x2AD2, 0x2AD9, 0x2A63, 0x2A37, 0x2A53] {
            let wire = DIRCONProtocol.wireUUID(from: uuid)
            XCTAssertEqual(DIRCONProtocol.shortUUID(from: wire), uuid,
                           "Round-trip failed for 0x\(String(uuid, radix: 16))")
        }
    }

    func testSerializeDiscoverServicesRequest() {
        let msg = DIRCONMessage(opcode: .discoverServices, sequenceNumber: 1, responseCode: 0, payload: Data())
        let data = msg.serialize()
        XCTAssertEqual(data.count, 6)
        XCTAssertEqual(data[0], 1)
        XCTAssertEqual(data[1], 0x01)
        XCTAssertEqual(data[2], 1)
        XCTAssertEqual(data[3], 0)
        XCTAssertEqual(data[4], 0)
        XCTAssertEqual(data[5], 0)
    }

    func testSerializeNotificationWithPayload() {
        let uuid = DIRCONProtocol.wireUUID(from: 0x2AD2)
        let ftmsPayload = Data([0x44, 0x00, 0xE8, 0x03, 0xB4, 0x00, 0xFA, 0x00])
        var payload = Data(uuid)
        payload.append(ftmsPayload)
        let msg = DIRCONMessage(opcode: .notification, sequenceNumber: 0, responseCode: 0, payload: payload)
        let data = msg.serialize()
        XCTAssertEqual(data.count, 6 + 16 + 8)
        XCTAssertEqual(data[1], 0x06)
        XCTAssertEqual(data[4], 0x00)
        XCTAssertEqual(data[5], 24)
    }

    func testDeserializeValidHeader() {
        let expectedUUID = DIRCONProtocol.wireUUID(from: 0x2AD9)
        var fullData = Data([1, 0x04, 5, 0, 0x00, 0x10])
        fullData.append(contentsOf: expectedUUID)
        let msg = DIRCONMessage.deserialize(from: fullData)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.opcode, .writeCharacteristic)
        XCTAssertEqual(msg?.sequenceNumber, 5)
        XCTAssertEqual(msg?.payload.count, 16)
        // Verify payload bytes match the UUID we sent
        XCTAssertEqual([UInt8](msg!.payload), expectedUUID)
    }

    func testSerializeDeserializeRoundTrip() {
        let original = DIRCONMessage(
            opcode: .writeCharacteristic, sequenceNumber: 42, responseCode: 0,
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        let wire = original.serialize()
        let decoded = DIRCONMessage.deserialize(from: wire)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.opcode, original.opcode)
        XCTAssertEqual(decoded?.sequenceNumber, original.sequenceNumber)
        XCTAssertEqual(decoded?.responseCode, original.responseCode)
        XCTAssertEqual(decoded?.payload, original.payload)
    }

    func testDeserializeRejectsShortData() {
        XCTAssertNil(DIRCONMessage.deserialize(from: Data([1, 0x01, 0, 0, 0])))
    }

    func testDeserializeRejectsWrongVersion() {
        XCTAssertNil(DIRCONMessage.deserialize(from: Data([2, 0x01, 0, 0, 0, 0])))
    }

    func testDeserializeRejectsTruncatedPayload() {
        XCTAssertNil(DIRCONMessage.deserialize(from: Data([1, 0x01, 0, 0, 0x00, 0x10])))
    }

    func testDeserializeRejectsUnknownOpcode() {
        XCTAssertNil(DIRCONMessage.deserialize(from: Data([1, 0xFE, 0, 0, 0, 0])))
    }

    func testDeserializeFromDataSlice() {
        let prefix = Data([0xDE, 0xAD])
        var fullData = prefix
        fullData.append(contentsOf: [1, 0x01, 3, 0, 0, 0])
        let slice = fullData.suffix(from: 2)
        let msg = DIRCONMessage.deserialize(from: Data(slice))
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.opcode, .discoverServices)
        XCTAssertEqual(msg?.sequenceNumber, 3)
    }
}
