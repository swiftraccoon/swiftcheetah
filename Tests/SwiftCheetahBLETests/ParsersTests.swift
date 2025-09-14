import XCTest
@testable import SwiftCheetahBLE

final class ParsersTests: XCTestCase {
    func testCPSMeasurementCadenceFromCrankData() {
        var state = CPSState()
        // flags: crank data present only (0x0020), power = 200 W, revs=100, time=1024
        let first = Data([0x20, 0x00, 0xC8, 0x00, 0x64, 0x00, 0x00, 0x04])
        let m1 = CPSMeasurement.parse(first, state: &state)
        XCTAssertNotNil(m1)
        XCTAssertEqual(m1?.instantaneousPower, 200)
        XCTAssertNil(m1?.cadenceRpm)

        // Next: +1 rev over +1024 ticks (1s) => 60 rpm
        let second = Data([0x20, 0x00, 0xC8, 0x00, 0x65, 0x00, 0x00, 0x08])
        let m2 = CPSMeasurement.parse(second, state: &state)
        XCTAssertNotNil(m2)
        XCTAssertEqual(m2?.instantaneousPower, 200)
        if let cadence = m2?.cadenceRpm { XCTAssertEqual(Int(round(cadence)), 60) } else { XCTFail("no cadence") }
    }

    func testFTMSIndoorBikeDataParsing() {
        // flags: inst cadence + inst power
        // speed=1000 (10.00 m/s), cadence raw=180 (90 rpm), power=250 W
        let data = Data([0x44, 0x00, 0xE8, 0x03, 0xB4, 0x00, 0xFA, 0x00])
        let m = FTMSIndoorBikeData.parse(data)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.instantaneousPowerWatts, 250)
        if let s = m?.speedMps { XCTAssertEqual(s, 10.0, accuracy: 0.01) } else { XCTFail("no speed") }
        if let c = m?.cadenceRpm { XCTAssertEqual(c, 90.0, accuracy: 0.1) } else { XCTFail("no cadence") }
    }
}
