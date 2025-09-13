import XCTest
@testable import SwiftCheetahBLE

final class EncodingParityTests: XCTestCase {
    func testFTMSIndoorBikeDataEncoding() {
        let d = BLEEncoding.ftmsIndoorBikeData(cadenceRpm: 90, powerW: 250)
        // flags: cadence+power = 0x0044, speed u16=0x0000, cadence raw=180 (0x00B4), power=250 (0x00FA)
        let expected: [UInt8] = [0x44, 0x00, 0x00, 0x00, 0xB4, 0x00, 0xFA, 0x00]
        XCTAssertEqual(Array(d), expected)
    }

    func testCPSMeasurementEncoding() {
        let d = BLEEncoding.cpsMeasurement(powerW: 250, wheelCount: 0x01020304, wheelTime2048: 0x1122, crankRevs: 0x3344, crankTime1024: 0x5566)
        // flags 0x30, power 250 LE, wheel count/time LE, crank revs/time LE
        let expectedPrefix: [UInt8] = [0x30, 0x00, 0xFA, 0x00, 0x04, 0x03, 0x02, 0x01, 0x22, 0x11, 0x44, 0x33, 0x66, 0x55]
        XCTAssertEqual(Array(d), expectedPrefix)
    }
}
