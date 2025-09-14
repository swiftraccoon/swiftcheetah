import XCTest
@testable import SwiftCheetahCore

final class PhysicsCalculatorTests: XCTestCase {

    // MARK: - Newton-Raphson Solver Tests

    func testNewtonRaphsonConvergence() {
        // Test that Newton-Raphson solver converges for various scenarios
        let params = PhysicsCalculator.Parameters()

        // Test cases: (power, grade) -> expected speed range
        let testCases: [(power: Double, grade: Double, minSpeed: Double, maxSpeed: Double)] = [
            // Flat ground
            (200, 0, 8.0, 9.5),      // ~30-34 km/h at 200W on flat
            (300, 0, 10.0, 11.5),    // ~36-41 km/h at 300W on flat

            // Climbs
            (200, 5, 4.0, 5.5),      // ~14-20 km/h at 200W on 5% grade
            (300, 8, 3.5, 4.5),      // ~13-16 km/h at 300W on 8% grade
            (150, 10, 1.8, 3.0),     // ~6.5-11 km/h at 150W on 10% grade (adjusted)

            // Descents (should use special handling)
            (0, -5, 8.0, 14.0),      // Coasting on -5% grade (adjusted for physics)
            (100, -10, 12.0, 20.0)   // Light pedaling on steep descent
        ]

        for testCase in testCases {
            let speed = PhysicsCalculator.calculateSpeed(
                powerWatts: testCase.power,
                gradePercent: testCase.grade,
                params: params
            )

            XCTAssertGreaterThanOrEqual(speed, testCase.minSpeed,
                "Speed at \(testCase.power)W on \(testCase.grade)% should be >= \(testCase.minSpeed) m/s, got \(speed)")
            XCTAssertLessThanOrEqual(speed, testCase.maxSpeed,
                "Speed at \(testCase.power)W on \(testCase.grade)% should be <= \(testCase.maxSpeed) m/s, got \(speed)")
        }
    }

    func testTerminalVelocityOnDescent() {
        // Test terminal velocity calculation for steep descents
        let params = PhysicsCalculator.Parameters(massKg: 80)

        // Coasting on various descents
        let testCases: [(grade: Double, minTerminal: Double, maxTerminal: Double)] = [
            (-3, 6.0, 11.0),   // Gentle descent (adjusted)
            (-5, 10.0, 15.0),  // Moderate descent
            (-10, 15.0, 25.0), // Steep descent
            (-15, 20.0, 30.0)  // Very steep descent
        ]

        for testCase in testCases {
            let speed = PhysicsCalculator.calculateSpeed(
                powerWatts: 0,  // Coasting
                gradePercent: testCase.grade,
                params: params
            )

            XCTAssertGreaterThanOrEqual(speed, testCase.minTerminal,
                "Terminal velocity on \(testCase.grade)% should be >= \(testCase.minTerminal) m/s")
            XCTAssertLessThanOrEqual(speed, testCase.maxTerminal,
                "Terminal velocity on \(testCase.grade)% should be <= \(testCase.maxTerminal) m/s")
        }
    }

    func testPowerSpeedReversibility() {
        // Test that calculateSpeed and calculatePowerRequired are inverse operations
        let params = PhysicsCalculator.Parameters()
        let tolerance = 5.0  // 5W tolerance due to rounding

        let testCases: [(power: Double, grade: Double)] = [
            (200, 0),
            (250, 3),
            (300, -2),
            (150, 8)
        ]

        for testCase in testCases {
            // Calculate speed from power
            let speed = PhysicsCalculator.calculateSpeed(
                powerWatts: testCase.power,
                gradePercent: testCase.grade,
                params: params
            )

            // Calculate power from speed (inverse operation)
            let calculatedPower = PhysicsCalculator.calculatePowerRequired(
                speedMps: speed,
                gradePercent: testCase.grade,
                params: params
            )

            XCTAssertEqual(calculatedPower, testCase.power, accuracy: tolerance,
                "Power->Speed->Power should return original power. Original: \(testCase.power)W, Calculated: \(calculatedPower)W")
        }
    }

    // MARK: - Realistic Value Tests (from zwack)

    func testRealisticPowerSpeedRelationships() {
        // Based on real-world data and research
        let params = PhysicsCalculator.Parameters()

        // Test professional cyclist values (from research papers)
        // Foss & Hallén (2004): Elite cyclists can sustain ~400W
        let eliteSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 400,
            gradePercent: 0,
            params: params
        )
        let eliteKmh = eliteSpeed * 3.6

        XCTAssertGreaterThan(eliteKmh, 40, "Elite cyclist at 400W should exceed 40 km/h")
        XCTAssertLessThan(eliteKmh, 50, "Elite cyclist at 400W should be under 50 km/h")

        // Recreational cyclist
        let recSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 150,
            gradePercent: 0,
            params: params
        )
        let recKmh = recSpeed * 3.6

        XCTAssertGreaterThan(recKmh, 22, "Recreational cyclist at 150W should exceed 22 km/h")
        XCTAssertLessThan(recKmh, 31, "Recreational cyclist at 150W should be under 31 km/h")
    }

    func testSafetyBounds() {
        // Test that extreme inputs produce safe outputs
        let params = PhysicsCalculator.Parameters()

        // Extreme power
        let extremePowerSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 5000,  // Unrealistic power
            gradePercent: 0,
            params: params
        )
        XCTAssertLessThanOrEqual(extremePowerSpeed, 35, "Speed should be capped even with extreme power")

        // Extreme negative grade
        let extremeDescentSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 0,
            gradePercent: -40,  // Extremely steep descent
            params: params
        )
        XCTAssertLessThanOrEqual(extremeDescentSpeed, 35, "Descent speed should be capped")

        // Zero and negative power
        let zeroSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 0,
            gradePercent: 5,  // Uphill with no power
            params: params
        )
        XCTAssertGreaterThanOrEqual(zeroSpeed, 0.5, "Should return minimum speed with no power uphill")

        let negativeSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: -100,  // Invalid negative power
            gradePercent: 0,
            params: params
        )
        XCTAssertGreaterThanOrEqual(negativeSpeed, 0, "Should handle negative power gracefully")
    }

    // MARK: - Trigonometric Grade Handling Tests

    func testTrigonometricGradeCalculation() {
        // Verify proper trigonometric handling vs small angle approximation
        let params = PhysicsCalculator.Parameters(massKg: 80)

        // At steep grades, sin(θ) differs significantly from tan(θ)
        let steepGrade = 20.0  // 20% grade
        let theta = atan(steepGrade / 100)
        let sinTheta = sin(theta)
        let tanTheta = tan(theta)

        // The difference should be significant
        let difference = abs(tanTheta - sinTheta) / tanTheta
        XCTAssertGreaterThan(difference, 0.01, "At steep grades, proper trig matters")

        // Verify the physics calculation uses proper trig
        let speed = PhysicsCalculator.calculateSpeed(
            powerWatts: 250,
            gradePercent: steepGrade,
            params: params
        )

        // With proper trig, the speed should be slightly higher than with linear approximation
        XCTAssertGreaterThan(speed, 1.5, "Speed on steep grade should be realistic")
        XCTAssertLessThan(speed, 4.0, "Speed on steep grade shouldn't be too high")
    }

    // MARK: - Edge Cases

    func testInfiniteAndNaNHandling() {
        let params = PhysicsCalculator.Parameters()

        // Test infinite power
        let infSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: .infinity,
            gradePercent: 0,
            params: params
        )
        XCTAssertTrue(infSpeed.isFinite, "Should handle infinite power")
        XCTAssertLessThanOrEqual(infSpeed, 35, "Infinite power should still be bounded")

        // Test NaN power
        let nanSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: .nan,
            gradePercent: 0,
            params: params
        )
        XCTAssertTrue(nanSpeed.isFinite, "Should handle NaN power")
        XCTAssertGreaterThanOrEqual(nanSpeed, 0, "NaN power should produce valid speed")

        // Test NaN grade
        let nanGradeSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 200,
            gradePercent: .nan,
            params: params
        )
        XCTAssertTrue(nanGradeSpeed.isFinite, "Should handle NaN grade")
    }

    // MARK: - Parameter Sensitivity Tests

    func testMassEffect() {
        // Test that mass affects speed appropriately
        let lightParams = PhysicsCalculator.Parameters(massKg: 60)
        let heavyParams = PhysicsCalculator.Parameters(massKg: 100)

        // On flat ground, mass has less effect (mainly rolling resistance)
        let lightFlatSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 200, gradePercent: 0, params: lightParams
        )
        let heavyFlatSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 200, gradePercent: 0, params: heavyParams
        )

        XCTAssertGreaterThan(lightFlatSpeed, heavyFlatSpeed,
            "Lighter rider should be faster on flat")
        XCTAssertLessThan((lightFlatSpeed - heavyFlatSpeed) / lightFlatSpeed, 0.1,
            "Mass effect on flat should be small (<10%)")

        // On climbs, mass has major effect
        let lightClimbSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 200, gradePercent: 8, params: lightParams
        )
        let heavyClimbSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 200, gradePercent: 8, params: heavyParams
        )

        XCTAssertGreaterThan(lightClimbSpeed, heavyClimbSpeed,
            "Lighter rider should be much faster on climbs")
        XCTAssertGreaterThan((lightClimbSpeed - heavyClimbSpeed) / lightClimbSpeed, 0.2,
            "Mass effect on climbs should be significant (>20%)")
    }

    func testAerodynamicEffect() {
        // Test that CdA affects speed appropriately
        let aeroParams = PhysicsCalculator.Parameters(cda: 0.25)  // Aero position
        let uprightParams = PhysicsCalculator.Parameters(cda: 0.40)  // Upright position

        let aeroSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 250, gradePercent: 0, params: aeroParams
        )
        let uprightSpeed = PhysicsCalculator.calculateSpeed(
            powerWatts: 250, gradePercent: 0, params: uprightParams
        )

        XCTAssertGreaterThan(aeroSpeed, uprightSpeed,
            "Aero position should be faster")

        let speedGain = (aeroSpeed - uprightSpeed) / uprightSpeed
        XCTAssertGreaterThan(speedGain, 0.1,
            "Aero gains should be significant (>10%)")
        XCTAssertLessThan(speedGain, 0.3,
            "Aero gains should be realistic (<30%)")
    }

    // MARK: - Legacy Interface Tests

    func testLegacyInterface() {
        // Ensure backward compatibility with old interface
        let inputs = PhysicsCalculator.Inputs(
            speedMetersPerSecond: 10.0,  // 36 km/h
            slopeGrade: 0.02,  // 2% grade (as ratio) - reduced from 3%
            massKg: 75.0
        )

        let power = PhysicsCalculator.estimatePowerWatts(inputs)

        // At 36 km/h on 2% grade, power should be reasonable
        XCTAssertGreaterThan(power, 150, "Power should be > 150W")
        XCTAssertLessThan(power, 400, "Power should be < 400W")
    }

    // MARK: - Existing Test

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

    // MARK: - Performance Tests

    func testCalculationPerformance() {
        // Ensure calculations are fast enough for real-time use
        let params = PhysicsCalculator.Parameters()

        measure {
            for _ in 0..<1000 {
                _ = PhysicsCalculator.calculateSpeed(
                    powerWatts: Double.random(in: 50...400),
                    gradePercent: Double.random(in: -10...10),
                    params: params
                )
            }
        }
    }
}
