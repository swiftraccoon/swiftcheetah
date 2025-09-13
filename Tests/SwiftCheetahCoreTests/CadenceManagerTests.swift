import XCTest
@testable import SwiftCheetahCore

final class CadenceManagerTests: XCTestCase {
    func testPowerRaisesTargetCadence() {
        let cm = CadenceManager()
        let c1 = cm.update(power: 100, grade: 0, speedMps: 8.0, dt: 0.25)
        let c2 = cm.update(power: 250, grade: 0, speedMps: 8.0, dt: 0.25)
        XCTAssertGreaterThan(c2, c1 - 1, "Higher power should not reduce cadence")
    }

    func testGradeReducesCadence() {
        let cm = CadenceManager()
        let flat = cm.update(power: 200, grade: 0, speedMps: 8.0, dt: 0.25)
        let up = cm.update(power: 200, grade: 8, speedMps: 6.0, dt: 0.25)
        XCTAssertLessThan(up, flat + 1, "Uphill should reduce cadence target")
    }

    func testHighSpeedCoast() {
        let cm = CadenceManager()
        let fast = cm.update(power: 40, grade: -6, speedMps: 16.0, dt: 0.25) // ~57.6 km/h
        XCTAssertLessThanOrEqual(fast, 5, "At high speed and low power cadence should approach coasting")
    }
}

