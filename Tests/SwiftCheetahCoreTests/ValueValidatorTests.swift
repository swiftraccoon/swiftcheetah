import XCTest
@testable import SwiftCheetahCore

final class ValueValidatorTests: XCTestCase {

    var validator: ValueValidator!

    override func setUp() {
        super.setUp()
        validator = ValueValidator(category: .enthusiast)
    }

    // MARK: - Power Validation Tests

    func testNegativePowerIsInvalid() {
        let result = validator.validatePower(-10)
        XCTAssertEqual(result.level, .error)
        XCTAssertFalse(result.isValid)
    }

    func testNormalPowerIsValid() {
        let result = validator.validatePower(200)
        XCTAssertEqual(result.level, .valid)
        XCTAssertTrue(result.isValid)
    }

    func testWorldRecordPowerIsCritical() {
        let result = validator.validatePower(2700)
        XCTAssertEqual(result.level, .critical)
        XCTAssertFalse(result.isValid)
    }

    func testSprintPowerForCategory() {
        let result = validator.validatePower(1000, duration: 5)
        XCTAssertEqual(result.level, .warning) // Exceeds enthusiast sprint power
    }

    func testSustainedPowerForCategory() {
        let result = validator.validatePower(400, duration: 120)
        XCTAssertEqual(result.level, .warning) // Exceeds enthusiast sustained power
    }

    // MARK: - Speed Validation Tests

    func testNegativeSpeedIsInvalid() {
        let result = validator.validateSpeed(-1, power: 200, grade: 0)
        XCTAssertEqual(result.level, .error)
    }

    func testNormalSpeedOnFlatIsValid() {
        let result = validator.validateSpeed(10, power: 200, grade: 0) // 36 km/h
        XCTAssertEqual(result.level, .valid)
    }

    func testHighSpeedOnSteepClimb() {
        let result = validator.validateSpeed(10, power: 200, grade: 15) // 36 km/h on 15% grade
        XCTAssertEqual(result.level, .warning)
    }

    func testLowSpeedOnSteepDescent() {
        let result = validator.validateSpeed(5, power: 30, grade: -15) // 18 km/h on -15% grade
        XCTAssertEqual(result.level, .warning)
    }

    func testSpeedPowerMismatchOnFlat() {
        // High power but low speed on flat
        let result = validator.validateSpeed(3, power: 350, grade: 0)
        XCTAssertEqual(result.level, .warning)
    }

    // MARK: - Cadence Validation Tests

    func testNegativeCadenceIsInvalid() {
        let result = validator.validateCadence(-10)
        XCTAssertEqual(result.level, .error)
    }

    func testNormalCadenceIsValid() {
        let result = validator.validateCadence(85, power: 200)
        XCTAssertEqual(result.level, .valid)
    }

    func testVeryHighCadence() {
        let result = validator.validateCadence(150)
        XCTAssertEqual(result.level, .warning)
    }

    func testCadenceExceedsHumanLimits() {
        let result = validator.validateCadence(210)
        XCTAssertEqual(result.level, .critical)
    }

    func testLowCadenceHighPower() {
        let result = validator.validateCadence(50, power: 350)
        XCTAssertEqual(result.level, .warning)
    }

    // MARK: - Gradient Validation Tests

    func testNormalGradientIsValid() {
        let result = validator.validateGradient(5)
        XCTAssertEqual(result.level, .valid)
    }

    func testExtremeGradient() {
        let result = validator.validateGradient(35)
        XCTAssertEqual(result.level, .warning)
    }

    func testImpossibleGradient() {
        let result = validator.validateGradient(45)
        XCTAssertEqual(result.level, .critical)
    }

    // MARK: - Heart Rate Validation Tests

    func testNormalHeartRateIsValid() {
        let result = validator.validateHeartRate(140, age: 30)
        XCTAssertEqual(result.level, .valid)
    }

    func testDangerouslyLowHeartRate() {
        let result = validator.validateHeartRate(25)
        XCTAssertEqual(result.level, .critical)
    }

    func testHeartRateExceedsMax() {
        let result = validator.validateHeartRate(205, age: 30)
        XCTAssertEqual(result.level, .critical) // 205 > 190+10, so it's critical
    }

    // MARK: - Complete State Validation Tests

    func testValidSimulationState() {
        let results = validator.validateSimulationState(
            power: 200,
            speed: 10,
            cadence: 85,
            grade: 2,
            heartRate: 140
        )
        XCTAssertTrue(results.isEmpty) // No warnings/errors
    }

    func testInconsistentSimulationState() {
        let results = validator.validateSimulationState(
            power: 300,
            speed: 2,  // Very low speed for high power
            cadence: 110,
            grade: 0,
            heartRate: 120
        )
        XCTAssertFalse(results.isEmpty)

        // Print actual results for debugging
        for result in results {
            print("Parameter: \(result.parameter), Level: \(result.level), Message: \(result.message)")
        }

        // Should have at least one warning about the inconsistency
        XCTAssertFalse(results.isEmpty)
    }

    // MARK: - Safety Limits Tests

    func testGetSafetyLimits() {
        let powerLimits = validator.getSafetyLimits(for: "power")
        XCTAssertNotNil(powerLimits)
        XCTAssertEqual(powerLimits?.min, 0)
        XCTAssertEqual(powerLimits?.max, 2000)

        let speedLimits = validator.getSafetyLimits(for: "speed")
        XCTAssertNotNil(speedLimits)
        XCTAssertEqual(speedLimits?.min, 0)
        XCTAssertEqual(speedLimits?.max, 30)
    }

    func testClampToSafeLimits() {
        let clampedPower = validator.clampToSafeLimits(3000, parameter: "power")
        XCTAssertEqual(clampedPower, 2000)

        let clampedCadence = validator.clampToSafeLimits(-10, parameter: "cadence")
        XCTAssertEqual(clampedCadence, 0)

        let clampedGrade = validator.clampToSafeLimits(50, parameter: "grade")
        XCTAssertEqual(clampedGrade, 30)
    }

    // MARK: - Category-Based Validation Tests

    func testProfessionalCategory() {
        let proValidator = ValueValidator(category: .professional)

        // 1800W sprint should be OK for pro
        let sprintResult = proValidator.validatePower(1800, duration: 5)
        XCTAssertEqual(sprintResult.level, .valid)

        // 600W sustained should be OK for pro
        let sustainedResult = proValidator.validatePower(600, duration: 120)
        XCTAssertEqual(sustainedResult.level, .valid)
    }

    func testRecreationalCategory() {
        let recValidator = ValueValidator(category: .recreational)

        // 700W sprint exceeds recreational
        let sprintResult = recValidator.validatePower(700, duration: 5)
        XCTAssertEqual(sprintResult.level, .warning)

        // 300W sustained exceeds recreational
        let sustainedResult = recValidator.validatePower(300, duration: 120)
        XCTAssertEqual(sustainedResult.level, .warning)
    }

    // MARK: - Edge Cases

    func testZeroValues() {
        XCTAssertEqual(validator.validatePower(0).level, .valid)
        XCTAssertEqual(validator.validateSpeed(0, power: 0, grade: 0).level, .valid)
        XCTAssertEqual(validator.validateCadence(0).level, .valid)
        XCTAssertEqual(validator.validateGradient(0).level, .valid)
    }

    func testBoundaryValues() {
        // Test right at warning boundaries
        // Use power=200 to avoid the "high cadence for low power" warning
        XCTAssertEqual(validator.validateCadence(141, power: 200).level, .warning)  // >140 is warning
        XCTAssertEqual(validator.validateCadence(140, power: 200).level, .valid)    // 140 is still valid

        // For gradient, abs(grade) > 30 is warning, grade > 20 is warning
        XCTAssertEqual(validator.validateGradient(31).level, .warning)  // abs(31) > 30
        XCTAssertEqual(validator.validateGradient(21).level, .warning)  // 21 > 20, so it's "very steep climb"
        XCTAssertEqual(validator.validateGradient(20).level, .valid)    // 20 is exactly the boundary
        XCTAssertEqual(validator.validateGradient(19).level, .valid)    // 19 < 20, valid
    }
}
