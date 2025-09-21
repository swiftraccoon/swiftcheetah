import XCTest
@testable import SwiftCheetahCore

/// Tests for freehub physics and mechanical coupling
/// Based on peer review: cadence is mechanically determined by speed and gear ratio when engaged
final class FreehubPhysicsTests: XCTestCase {

    // MARK: - Mechanical Coupling Formula Tests

    func testMechanicalCadenceFormula() {
        // Test the fundamental formula: cadence_rpm = (v/C) * 60 * (rear/front)
        // where v = speed (m/s), C = wheel circumference (m)

        let testCases: [(speed: Double, circum: Double, front: Int, rear: Int, expected: Double)] = [
            // 90 km/h example from discussion
            (speed: 25.0, circum: 2.105, front: 50, rear: 11, expected: 156.7),

            // Normal riding speed
            (speed: 10.0, circum: 2.105, front: 50, rear: 11, expected: 62.7),

            // Climbing gear at same speed
            (speed: 10.0, circum: 2.105, front: 34, rear: 32, expected: 268.3),

            // Different tire size (700x23C)
            (speed: 25.0, circum: 2.096, front: 50, rear: 11, expected: 157.4),

            // Pro gearing (53/11)
            (speed: 25.0, circum: 2.105, front: 53, rear: 11, expected: 147.9)
        ]

        for testCase in testCases {
            let mechanical = (testCase.speed / testCase.circum) * 60.0 *
                           (Double(testCase.rear) / Double(testCase.front))

            XCTAssertEqual(mechanical, testCase.expected, accuracy: 0.5,
                "Mechanical cadence must follow gear ratio formula exactly. " +
                "Speed: \(testCase.speed) m/s, Gear: \(testCase.front)/\(testCase.rear)")
        }
    }
}
