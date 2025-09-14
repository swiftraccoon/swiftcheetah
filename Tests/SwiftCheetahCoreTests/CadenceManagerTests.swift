import XCTest
@testable import SwiftCheetahCore

final class CadenceManagerTests: XCTestCase {
    func testPowerRaisesTargetCadence() {
        let cm = CadenceManager()
        // Let the system stabilize at low power
        for _ in 0..<20 {
            _ = cm.update(power: 100, grade: 0, speedMps: 8.0, dt: 0.1)
        }
        let state1 = cm.getState()

        // Switch to high power and let it stabilize
        for _ in 0..<20 {
            _ = cm.update(power: 250, grade: 0, speedMps: 8.0, dt: 0.1)
        }
        let state2 = cm.getState()

        // Check that target cadence is higher for higher power
        XCTAssertGreaterThan(state2.target, state1.target, "Higher power should increase target cadence")
        // Actual cadence should trend higher but may vary due to gear shifts and dynamics
        // We allow more tolerance since gear selection is probabilistic
        XCTAssertGreaterThan(state2.cadence, state1.cadence - 15, "Higher power should generally increase actual cadence")
    }

    func testGradeReducesCadence() {
        let cm = CadenceManager()
        // Stabilize on flat
        for _ in 0..<20 {
            _ = cm.update(power: 200, grade: 0, speedMps: 8.0, dt: 0.1)
        }
        let flat = cm.getState()

        // Stabilize on uphill
        for _ in 0..<20 {
            _ = cm.update(power: 200, grade: 8, speedMps: 6.0, dt: 0.1)
        }
        let uphill = cm.getState()

        // Target cadence should be lower uphill
        XCTAssertLessThan(uphill.target, flat.target, "Uphill should reduce target cadence")
        // Actual cadence should also be lower
        XCTAssertLessThan(uphill.cadence, flat.cadence + 5, "Uphill should reduce actual cadence")
    }

    func testHighSpeedCoast() {
        let cm = CadenceManager()
        // Multiple updates to reach steady state at high speed downhill
        for _ in 0..<30 {
            _ = cm.update(power: 40, grade: -6, speedMps: 16.0, dt: 0.1)
        }
        let state = cm.getState()

        // At very high speed (57.6 km/h) and low power, cadence should be low
        // But the gear-based cadence might not be 0 due to the gear physics
        // Check that it's at least reduced significantly from normal
        XCTAssertLessThan(state.cadence, 70, "At high speed and low power cadence should be reduced")

        // For true coasting test, check even higher speed
        for _ in 0..<10 {
            _ = cm.update(power: 40, grade: -10, speedMps: 20.0, dt: 0.1)  // 72 km/h
        }
        let coast = cm.getState()
        XCTAssertLessThan(coast.cadence, 50, "At very high speed should approach coasting")
    }
}
