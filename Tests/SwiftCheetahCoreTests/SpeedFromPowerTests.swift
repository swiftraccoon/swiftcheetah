import XCTest
@testable import SwiftCheetahCore

final class SpeedFromPowerTests: XCTestCase {
    func testFlatSpeedReasonable() {
        let v = SpeedFromPower.calculateSpeed(power: 250, gradePercent: 0)
        XCTAssertGreaterThan(v, 3.0)
        XCTAssertLessThan(v, 15.0)
    }
    func testClimbSlowerThanFlat() {
        let flat = SpeedFromPower.calculateSpeed(power: 250, gradePercent: 0)
        let climb = SpeedFromPower.calculateSpeed(power: 250, gradePercent: 8)
        XCTAssertLessThan(climb, flat)
    }
    func testDescentFasterThanFlat() {
        let flat = SpeedFromPower.calculateSpeed(power: 200, gradePercent: 0)
        let down = SpeedFromPower.calculateSpeed(power: 200, gradePercent: -8)
        XCTAssertGreaterThan(down, flat)
    }
}

