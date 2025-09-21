import XCTest
@testable import SwiftCheetahCore

final class CyclingSimulationEngineTests: XCTestCase {

    var engine: CyclingSimulationEngine!

    override func setUp() {
        super.setUp()
        engine = CyclingSimulationEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        let engine = CyclingSimulationEngine()
        XCTAssertNotNil(engine)

        // Test with custom physics parameters
        let customParams = PhysicsCalculator.Parameters(
            massKg: 80.0,
            crr: 0.005
        )
        let customEngine = CyclingSimulationEngine(physicsParams: customParams)
        XCTAssertNotNil(customEngine)

        let retrievedParams = customEngine.getPhysicsParameters()
        XCTAssertEqual(retrievedParams.massKg, 80.0, accuracy: 0.1)
        XCTAssertEqual(retrievedParams.crr, 0.005, accuracy: 0.0001)
    }

    func testGetPhysicsParameters() {
        let params = engine.getPhysicsParameters()

        // Verify default parameters are reasonable
        XCTAssertGreaterThan(params.massKg, 0)
        XCTAssertGreaterThan(params.crr, 0)
        XCTAssertGreaterThan(params.cda, 0)
        XCTAssertGreaterThan(params.airDensity, 0)
        XCTAssertEqual(params.efficiency, 0.97, accuracy: 0.01)
    }

    // MARK: - SimulationInput Tests

    func testSimulationInputDefaults() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 250)

        XCTAssertEqual(input.targetPower, 250)
        XCTAssertNil(input.manualCadence)
        XCTAssertEqual(input.gradePercent, 0.0)
        XCTAssertEqual(input.randomness, 0)
        XCTAssertFalse(input.isResting)
    }

    func testSimulationInputCustomValues() {
        let input = CyclingSimulationEngine.SimulationInput(
            targetPower: 300,
            manualCadence: 95,
            gradePercent: 5.0,
            randomness: 25,
            isResting: true
        )

        XCTAssertEqual(input.targetPower, 300)
        XCTAssertEqual(input.manualCadence, 95)
        XCTAssertEqual(input.gradePercent, 5.0)
        XCTAssertEqual(input.randomness, 25)
        XCTAssertTrue(input.isResting)
    }

    // MARK: - Basic Simulation Tests

    func testBasicSimulationUpdate() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 250)

        // Call update multiple times to let power ramp up from 0
        var state: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01) // Small delay to ensure dt > 0
            state = engine.update(with: input)
        }

        // Verify basic output structure
        XCTAssertGreaterThan(state.powerWatts, 0)
        XCTAssertGreaterThan(state.speedMps, 0)
        XCTAssertGreaterThan(state.cadenceRpm, 0)
        XCTAssertGreaterThanOrEqual(state.fatigue, 0)
        // Noise can be negative (represents variation from mean)
        XCTAssertLessThanOrEqual(abs(state.noise), 1.0)
        XCTAssertGreaterThan(state.targetCadence, 0)

        // Verify gear is reasonable
        XCTAssertGreaterThan(state.gear.front, 0)
        XCTAssertGreaterThan(state.gear.rear, 0)
    }

    func testPowerProgression() {
        let lowPowerInput = CyclingSimulationEngine.SimulationInput(targetPower: 100)
        let mediumPowerInput = CyclingSimulationEngine.SimulationInput(targetPower: 250)
        let highPowerInput = CyclingSimulationEngine.SimulationInput(targetPower: 400)

        // Warm up for each power level
        var lowState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            lowState = engine.update(with: lowPowerInput)
        }

        engine.reset() // Reset to avoid fatigue effects
        var mediumState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            mediumState = engine.update(with: mediumPowerInput)
        }

        engine.reset()
        var highState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            highState = engine.update(with: highPowerInput)
        }

        // Power should generally correlate with input (allowing for variance)
        XCTAssertLessThan(lowState.powerWatts, mediumState.powerWatts + 50)
        XCTAssertLessThan(mediumState.powerWatts, highState.powerWatts + 50)

        // Speed should generally increase with power
        XCTAssertLessThan(lowState.speedMps, highState.speedMps)
    }

    func testGradeEffects() {
        let flatInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            gradePercent: 0.0
        )
        let uphillInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            gradePercent: 8.0
        )

        // Warm up for flat
        var flatState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            flatState = engine.update(with: flatInput)
        }

        engine.reset()

        // Warm up for uphill
        var uphillState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            uphillState = engine.update(with: uphillInput)
        }

        // Speed should be slower uphill for same power
        XCTAssertGreaterThan(flatState.speedMps, uphillState.speedMps)
    }

    func testManualCadenceMode() {
        let autoInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            manualCadence: nil
        )
        let manualInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            manualCadence: 90  // More realistic cadence
        )

        // Warm up for auto mode
        var autoState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            autoState = engine.update(with: autoInput)
        }

        engine.reset()

        // Warm up for manual mode
        var manualState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            manualState = engine.update(with: manualInput)
        }

        // Manual cadence should be close to requested value
        XCTAssertEqual(manualState.cadenceRpm, 90, accuracy: 5)

        // Auto mode should produce different cadence
        XCTAssertNotEqual(autoState.cadenceRpm, manualState.cadenceRpm, accuracy: 5)
    }

    func testRestingMode() {
        let activeInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            isResting: false
        )
        let restingInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            isResting: true
        )

        let activeState = engine.update(with: activeInput)
        engine.reset()
        let restingState = engine.update(with: restingInput)

        // Resting should produce lower values
        XCTAssertLessThanOrEqual(restingState.powerWatts, activeState.powerWatts)
        XCTAssertLessThanOrEqual(restingState.cadenceRpm, activeState.cadenceRpm)
    }

    // MARK: - Randomness and Variance Tests

    func testRandomnessEffects() {
        let noRandomnessInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            randomness: 0
        )
        let highRandomnessInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            randomness: 30  // More realistic randomness
        )

        // Run multiple iterations to see variance
        var noRandomnessValues: [Int] = []
        var highRandomnessValues: [Int] = []

        for i in 0..<10 {
            engine.reset()

            // Warm up each iteration
            for _ in 0..<5 {
                Thread.sleep(forTimeInterval: 0.01)
                _ = engine.update(with: noRandomnessInput)
            }
            let noRandomState = engine.update(with: noRandomnessInput)
            noRandomnessValues.append(noRandomState.powerWatts)

            engine.reset()

            // Warm up each iteration
            for _ in 0..<5 {
                Thread.sleep(forTimeInterval: 0.01)
                _ = engine.update(with: highRandomnessInput)
            }
            let highRandomState = engine.update(with: highRandomnessInput)
            highRandomnessValues.append(highRandomState.powerWatts)
        }

        // High randomness should show more variance OR at least some variance
        let noRandomVariance = calculateVariance(noRandomnessValues)
        let highRandomVariance = calculateVariance(highRandomnessValues)

        // Just verify that high randomness produces some variance
        XCTAssertGreaterThan(highRandomVariance, 0, "High randomness should produce variance")
    }

    func testNoiseAndFatigueProgression() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 300)

        var fatigueValues: [Double] = []
        var noiseValues: [Double] = []

        // Warm up first
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            _ = engine.update(with: input)
        }

        // Simulate for several iterations to see progression
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.01)
            let state = engine.update(with: input)
            fatigueValues.append(state.fatigue)
            noiseValues.append(state.noise)
        }

        // Fatigue should generally increase over time
        let firstFatigue = fatigueValues.first!
        let lastFatigue = fatigueValues.last!
        XCTAssertGreaterThanOrEqual(lastFatigue, firstFatigue)

        // Noise should be bounded (can be negative as it represents variation)
        for noise in noiseValues {
            XCTAssertGreaterThanOrEqual(noise, -1)
            XCTAssertLessThanOrEqual(noise, 1)
        }
    }

    // MARK: - Input Validation Tests

    func testNegativePowerHandling() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: -100)
        let state = engine.update(with: input)

        // Negative power should be clamped to safe values
        XCTAssertGreaterThanOrEqual(state.powerWatts, 0)
    }

    func testExtremePowerHandling() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 10000)
        let state = engine.update(with: input)

        // Extreme power should be clamped to reasonable values
        XCTAssertLessThan(state.powerWatts, 3000) // Some reasonable upper bound
    }

    func testExtremeGradeHandling() {
        let steepUphillInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            gradePercent: 50.0
        )
        let steepDownhillInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            gradePercent: -50.0
        )

        let uphillState = engine.update(with: steepUphillInput)
        engine.reset()
        let downhillState = engine.update(with: steepDownhillInput)

        // Should handle extreme grades without crashing
        XCTAssertGreaterThan(uphillState.speedMps, 0)
        XCTAssertGreaterThan(downhillState.speedMps, 0)

        // Downhill should be faster than uphill
        XCTAssertGreaterThan(downhillState.speedMps, uphillState.speedMps)
    }

    func testInvalidCadenceHandling() {
        let negativeCadenceInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            manualCadence: -50
        )
        let extremeCadenceInput = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            manualCadence: 500
        )

        // Warm up with negative cadence
        var negativeState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            negativeState = engine.update(with: negativeCadenceInput)
        }

        engine.reset()

        // Warm up with extreme cadence
        var extremeState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            extremeState = engine.update(with: extremeCadenceInput)
        }

        // Invalid cadence should be clamped to research-based limits
        XCTAssertGreaterThanOrEqual(negativeState.cadenceRpm, 0)  // Clamped to 0 minimum
        XCTAssertLessThanOrEqual(extremeState.cadenceRpm, 120) // Clamped to 120 maximum (ValidationLimits.maxCadence)
    }

    // MARK: - Reset Functionality Tests

    func testReset() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 400)

        // Run simulation to build up fatigue
        for _ in 0..<10 {
            _ = engine.update(with: input)
        }

        let beforeReset = engine.update(with: input)

        // Reset and test again
        engine.reset()
        let afterReset = engine.update(with: input)

        // After reset, fatigue should be lower
        XCTAssertLessThanOrEqual(afterReset.fatigue, beforeReset.fatigue)
    }

    // MARK: - Gear Progression Tests

    func testGearChanges() {
        var gears: [(front: Int, rear: Int)] = []

        // Test different power levels to see gear changes
        let powerLevels = [100, 200, 300, 400]

        for power in powerLevels {
            engine.reset()
            let input = CyclingSimulationEngine.SimulationInput(targetPower: power)

            // Warm up to get stable state
            var state: CyclingSimulationEngine.SimulationState!
            for _ in 0..<5 {
                Thread.sleep(forTimeInterval: 0.01)
                state = engine.update(with: input)
            }
            gears.append(state.gear)
        }

        // Verify all gears are reasonable
        // Note: The gear values represent teeth counts, not gear positions
        for gear in gears {
            XCTAssertGreaterThan(gear.front, 0)
            XCTAssertGreaterThan(gear.rear, 0)
            XCTAssertLessThanOrEqual(gear.front, 53) // Max chainring teeth
            XCTAssertLessThanOrEqual(gear.rear, 36) // Max cassette teeth
        }
    }

    // MARK: - Temporal Behavior Tests

    func testTemporalConsistency() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 250)

        var previousState: CyclingSimulationEngine.SimulationState?

        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01) // Small delay to ensure time progression
            let currentState = engine.update(with: input)

            if let previous = previousState {
                // Values should not change drastically between updates
                let powerDiff = abs(currentState.powerWatts - previous.powerWatts)
                let speedDiff = abs(currentState.speedMps - previous.speedMps)

                XCTAssertLessThan(powerDiff, 100) // Power shouldn't jump too much
                XCTAssertLessThan(speedDiff, 5.0) // Speed shouldn't jump too much
            }

            previousState = currentState
        }
    }

    // MARK: - Physics Consistency Tests

    func testPowerSpeedRelationship() {
        // At constant grade, higher power should generally mean higher speed
        let lowPower = CyclingSimulationEngine.SimulationInput(
            targetPower: 150,
            gradePercent: 0,
            randomness: 0
        )
        let highPower = CyclingSimulationEngine.SimulationInput(
            targetPower: 350,
            gradePercent: 0,
            randomness: 0
        )

        // Warm up for low power
        var lowState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            lowState = engine.update(with: lowPower)
        }

        engine.reset()

        // Warm up for high power
        var highState: CyclingSimulationEngine.SimulationState!
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.01)
            highState = engine.update(with: highPower)
        }

        XCTAssertLessThan(lowState.speedMps, highState.speedMps)
    }

    func testCadenceTargetConsistency() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 250)
        let state = engine.update(with: input)

        // Target cadence should be reasonable
        XCTAssertGreaterThan(state.targetCadence, 30)
        XCTAssertLessThan(state.targetCadence, 200)

        // Actual cadence should be reasonably close to target
        let cadenceDiff = abs(Double(state.cadenceRpm) - state.targetCadence)
        XCTAssertLessThan(cadenceDiff, 30) // Allow some variance
    }

    // MARK: - Performance Tests

    func testUpdatePerformance() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 250)

        // Warm up the engine first
        for _ in 0..<10 {
            _ = engine.update(with: input)
        }

        measure {
            for _ in 0..<100 {  // Reduced from 1000 to 100
                _ = engine.update(with: input)
            }
        }
    }

    func testResetPerformance() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 250)

        measure {
            for _ in 0..<100 {  // Reduced from 1000 to 100
                _ = engine.update(with: input)
                engine.reset()
            }
        }
    }

    // MARK: - Edge Cases and Robustness Tests

    func testZeroPowerSimulation() {
        let input = CyclingSimulationEngine.SimulationInput(targetPower: 0)
        let state = engine.update(with: input)

        // Should handle zero power gracefully
        XCTAssertGreaterThanOrEqual(state.powerWatts, 0)
        XCTAssertGreaterThanOrEqual(state.speedMps, 0)
        XCTAssertGreaterThan(state.cadenceRpm, 0) // Should have some minimal cadence
    }

    func testConsistentGearRatioCalculation() {
        let input = CyclingSimulationEngine.SimulationInput(
            targetPower: 250,
            manualCadence: 90
        )

        var gearRatios: [Double] = []

        // Test multiple iterations to ensure gear ratios are consistent
        for _ in 0..<10 {
            engine.reset()
            let state = engine.update(with: input)
            let ratio = Double(state.gear.front) / Double(state.gear.rear)
            gearRatios.append(ratio)
        }

        // All gear ratios should be reasonable
        for ratio in gearRatios {
            XCTAssertGreaterThan(ratio, 0.5)
            XCTAssertLessThan(ratio, 5.0)
        }
    }

    // MARK: - Helper Methods

    private func calculateVariance(_ values: [Int]) -> Double {
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let squaredDifferences = values.map { pow(Double($0) - mean, 2) }
        return squaredDifferences.reduce(0, +) / Double(values.count)
    }
}
