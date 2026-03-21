import XCTest
@testable import SwiftCheetahBLE

final class DIRCONServiceTableTests: XCTestCase {

    func testDiscoverServicesPayloadIsMultipleOf16() {
        let table = DIRCONServiceTable()
        let payload = table.discoverServicesPayload()
        XCTAssertTrue(payload.count >= 16)
        XCTAssertEqual(payload.count % 16, 0)
    }

    func testDiscoverServicesContainsAllExpectedServices() {
        let table = DIRCONServiceTable()
        let payload = table.discoverServicesPayload()
        let uuids = extractServiceUUIDs(from: payload)
        XCTAssertTrue(uuids.contains(0x1826), "Missing FTMS")
        XCTAssertTrue(uuids.contains(0x1818), "Missing CPS")
        XCTAssertTrue(uuids.contains(0x180D), "Missing HRS")
        XCTAssertTrue(uuids.contains(0x1814), "Missing RSC")
    }

    func testDiscoverCharacteristicsForFTMS() {
        let table = DIRCONServiceTable()
        let payload = table.discoverCharacteristicsPayload(forServiceShortUUID: 0x1826)
        XCTAssertNotNil(payload)
        guard let p = payload else { return }
        let serviceUUID = DIRCONProtocol.shortUUID(from: p)
        XCTAssertEqual(serviceUUID, 0x1826)
        let remaining = p.count - 16
        XCTAssertTrue(remaining > 0)
        XCTAssertEqual(remaining % 17, 0, "Each characteristic record is 17 bytes")
    }

    func testDiscoverCharacteristicsForUnknownService() {
        let table = DIRCONServiceTable()
        XCTAssertNil(table.discoverCharacteristicsPayload(forServiceShortUUID: 0xFFFF))
    }

    func testFTMSIndoorBikeDataHasNotify() {
        let chars = ftmsCharacteristics()
        let ibd = chars.first { $0.uuid == 0x2AD2 }
        XCTAssertNotNil(ibd)
        XCTAssertTrue(ibd!.props & 0x04 != 0, "Indoor Bike Data must have NOTIFY")
    }

    func testFTMSControlPointHasWriteAndIndicate() {
        let chars = ftmsCharacteristics()
        let cp = chars.first { $0.uuid == 0x2AD9 }
        XCTAssertNotNil(cp)
        XCTAssertTrue(cp!.props & 0x02 != 0, "Control Point must have WRITE")
        XCTAssertTrue(cp!.props & 0x08 != 0, "Control Point must have INDICATE")
    }

    func testHRSMeasurementHasNotify() {
        let table = DIRCONServiceTable()
        let payload = table.discoverCharacteristicsPayload(forServiceShortUUID: 0x180D)!
        let chars = parseChars(from: payload)
        let hrm = chars.first { $0.uuid == 0x2A37 }
        XCTAssertNotNil(hrm)
        XCTAssertTrue(hrm!.props & 0x04 != 0, "HR Measurement must have NOTIFY")
    }

    func testRSCMeasurementHasNotify() {
        let table = DIRCONServiceTable()
        let payload = table.discoverCharacteristicsPayload(forServiceShortUUID: 0x1814)!
        let chars = parseChars(from: payload)
        let rsc = chars.first { $0.uuid == 0x2A53 }
        XCTAssertNotNil(rsc)
        XCTAssertTrue(rsc!.props & 0x04 != 0, "RSC Measurement must have NOTIFY")
    }

    func testReadFTMSFeatureReturns8Bytes() {
        let table = DIRCONServiceTable()
        let value = table.readCharacteristicValue(shortUUID: 0x2ACC)
        XCTAssertNotNil(value)
        XCTAssertEqual(value!.count, 8)
    }

    func testReadSupportedPowerRangeReturns6Bytes() {
        let table = DIRCONServiceTable()
        let value = table.readCharacteristicValue(shortUUID: 0x2AD8)
        XCTAssertNotNil(value)
        XCTAssertEqual(value!.count, 6)
    }

    func testReadBodySensorLocationReturns1Byte() {
        let table = DIRCONServiceTable()
        let value = table.readCharacteristicValue(shortUUID: 0x2A38)
        XCTAssertNotNil(value)
        XCTAssertEqual(value!.count, 1)
    }

    func testReadUnknownCharacteristicReturnsNil() {
        let table = DIRCONServiceTable()
        XCTAssertNil(table.readCharacteristicValue(shortUUID: 0xBEEF))
    }

    // MARK: - Helpers

    private func extractServiceUUIDs(from payload: Data) -> [UInt16] {
        let bytes = [UInt8](payload)
        var uuids: [UInt16] = []
        for i in stride(from: 0, to: bytes.count, by: 16) {
            let chunk = Array(bytes[i..<min(i+16, bytes.count)])
            uuids.append(DIRCONProtocol.shortUUID(from: chunk))
        }
        return uuids
    }

    private struct CharInfo { let uuid: UInt16; let props: UInt8 }

    private func parseChars(from payload: Data) -> [CharInfo] {
        let bytes = [UInt8](payload)
        var result: [CharInfo] = []
        var offset = 16
        while offset + 17 <= bytes.count {
            let uuidBytes = Array(bytes[offset..<offset+16])
            let props = bytes[offset + 16]
            result.append(CharInfo(uuid: DIRCONProtocol.shortUUID(from: uuidBytes), props: props))
            offset += 17
        }
        return result
    }

    private func ftmsCharacteristics() -> [CharInfo] {
        let table = DIRCONServiceTable()
        let payload = table.discoverCharacteristicsPayload(forServiceShortUUID: 0x1826)!
        return parseChars(from: payload)
    }
}
