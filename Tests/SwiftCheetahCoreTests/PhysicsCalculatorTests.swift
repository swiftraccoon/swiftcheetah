import XCTest
@testable import SwiftCheetahCore

final class PhysicsCalculatorTests: XCTestCase {
    func testReasonablePower() {
        let inputs = PhysicsCalculator.Inputs(
            speedMetersPerSecond: 10.0,
            slopeGrade: 0.0,
            massKg: 80.0
        )
        let p = PhysicsCalculator.estimatePowerWatts(inputs)
        XCTAssertGreaterThan(p, 0)
        XCTAssertLessThan(p, 2000)
    }
}

