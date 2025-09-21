import XCTest
import Combine
@testable import SwiftCheetahBLE
@testable import SwiftCheetahCore

final class SimulationStateManagerTests: XCTestCase {

    var stateManager: SimulationStateManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        stateManager = SimulationStateManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables = nil
        stateManager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertEqual(stateManager.state, .idle)
        XCTAssertFalse(stateManager.isAdvertising)
        XCTAssertEqual(stateManager.subscriberCount, 0)
        XCTAssertNil(stateManager.lastError)
        XCTAssertTrue(stateManager.eventLog.isEmpty)

        // Default simulation parameters
        XCTAssertEqual(stateManager.watts, 250)
        XCTAssertEqual(stateManager.cadenceRpm, 90)
        XCTAssertEqual(stateManager.speedMps, 8.33, accuracy: 0.01)
        XCTAssertEqual(stateManager.gradePercent, 0.0)
        XCTAssertEqual(stateManager.randomness, 0)
        XCTAssertEqual(stateManager.increment, 25)

        // Default configuration
        XCTAssertEqual(stateManager.cadenceMode, .auto)
        XCTAssertEqual(stateManager.localName, "Trainer")
        XCTAssertTrue(stateManager.advertiseFTMS)
        XCTAssertFalse(stateManager.advertiseCPS)
        XCTAssertFalse(stateManager.advertiseRSC)

        // Field toggles
        XCTAssertTrue(stateManager.cpsIncludePower)
        XCTAssertTrue(stateManager.cpsIncludeCadence)
        XCTAssertTrue(stateManager.cpsIncludeSpeed)
        XCTAssertTrue(stateManager.ftmsIncludePower)
        XCTAssertTrue(stateManager.ftmsIncludeCadence)

        // Live stats defaults
        XCTAssertEqual(stateManager.liveStats.speedKmh, 25.0)
        XCTAssertEqual(stateManager.liveStats.powerW, 250)
        XCTAssertEqual(stateManager.liveStats.cadenceRpm, 90)
        XCTAssertEqual(stateManager.liveStats.mode, "AUTO")
        XCTAssertEqual(stateManager.liveStats.gear, "2x5")
    }

    // MARK: - State Management Tests

    func testBroadcastStateChanges() {
        let expectation = XCTestExpectation(description: "State change observed")
        var observedStates: [SimulationStateManager.BroadcastState] = []

        stateManager.$state
            .sink { state in
                observedStates.append(state)
                if observedStates.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        stateManager.state = .starting
        stateManager.state = .advertising

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(observedStates, [.idle, .starting, .advertising])
    }

    func testAdvertisingStateTracking() {
        let expectation = XCTestExpectation(description: "Advertising changes observed")
        var advertisingStates: [Bool] = []

        stateManager.$isAdvertising
            .sink { isAdvertising in
                advertisingStates.append(isAdvertising)
                if advertisingStates.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        stateManager.isAdvertising = true
        stateManager.isAdvertising = false

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(advertisingStates, [false, true, false])
    }

    func testSubscriberCountTracking() {
        let expectation = XCTestExpectation(description: "Subscriber count changes")
        var counts: [Int] = []

        stateManager.$subscriberCount
            .sink { count in
                counts.append(count)
                if counts.count == 4 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        stateManager.subscriberCount = 1
        stateManager.subscriberCount = 3
        stateManager.subscriberCount = 0

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(counts, [0, 1, 3, 0])
    }

    // MARK: - Event Logging Tests

    func testEventLogging() {
        XCTAssertTrue(stateManager.eventLog.isEmpty)

        stateManager.log("First event")
        XCTAssertEqual(stateManager.eventLog.count, 1)
        XCTAssertEqual(stateManager.eventLog[0], "First event")

        stateManager.log("Second event")
        XCTAssertEqual(stateManager.eventLog.count, 2)
        XCTAssertEqual(stateManager.eventLog[1], "Second event")
    }

    func testEventLogClearing() {
        stateManager.log("Event 1")
        stateManager.log("Event 2")
        XCTAssertEqual(stateManager.eventLog.count, 2)

        stateManager.clearEventLog()
        XCTAssertTrue(stateManager.eventLog.isEmpty)
    }

    func testEventLogPublishing() {
        let expectation = XCTestExpectation(description: "Event log changes observed")
        var logCounts: [Int] = []

        stateManager.$eventLog
            .sink { log in
                logCounts.append(log.count)
                if logCounts.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        stateManager.log("Event 1")
        stateManager.log("Event 2")

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(logCounts, [0, 1, 2])
    }

    // MARK: - Error Management Tests

    func testErrorHandling() {
        XCTAssertNil(stateManager.lastError)

        stateManager.setError("Test error")
        XCTAssertEqual(stateManager.lastError, "Test error")

        stateManager.setError(nil)
        XCTAssertNil(stateManager.lastError)
    }

    func testErrorPublishing() {
        let expectation = XCTestExpectation(description: "Error changes observed")
        var errors: [String?] = []

        stateManager.$lastError
            .sink { error in
                errors.append(error)
                if errors.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        stateManager.setError("Error message")
        stateManager.setError(nil)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(errors[0], nil)
        XCTAssertEqual(errors[1], "Error message")
        XCTAssertEqual(errors[2], nil)
    }

    // MARK: - Live Statistics Tests

    func testLiveStatsUpdate() {
        let simulationState = CyclingSimulationEngine.SimulationState(
            powerWatts: 300,
            speedMps: 10.0,
            cadenceRpm: 95,
            fatigue: 0.2,
            noise: 0.1,
            gear: (front: 3, rear: 7),
            targetCadence: 95.0
        )

        stateManager.updateLiveStats(from: simulationState)

        XCTAssertEqual(stateManager.liveStats.speedKmh, 36.0, accuracy: 0.1)
        XCTAssertEqual(stateManager.liveStats.powerW, 300)
        XCTAssertEqual(stateManager.liveStats.cadenceRpm, 95)
        XCTAssertEqual(stateManager.liveStats.gear, "3x7")
        XCTAssertEqual(stateManager.liveStats.targetCadence, 95)
        XCTAssertEqual(stateManager.liveStats.fatigue, 0.2, accuracy: 0.01)
        XCTAssertEqual(stateManager.liveStats.noise, 0.1, accuracy: 0.01)
    }

    func testLiveStatsPublishing() {
        let expectation = XCTestExpectation(description: "Live stats changes observed")
        var statsCounts: [Int] = []

        stateManager.$liveStats
            .sink { stats in
                statsCounts.append(stats.powerW)
                if statsCounts.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let simulationState = CyclingSimulationEngine.SimulationState(
            powerWatts: 350,
            speedMps: 10.0,
            cadenceRpm: 100,
            fatigue: 0.0,
            noise: 0.0,
            gear: (front: 2, rear: 6),
            targetCadence: 100.0
        )

        stateManager.updateLiveStats(from: simulationState)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(statsCounts, [250, 350])
    }

    // MARK: - Service Configuration Tests

    func testServiceOptions() {
        stateManager.advertiseFTMS = true
        stateManager.advertiseCPS = false
        stateManager.advertiseRSC = true

        let options = stateManager.getServiceOptions()

        XCTAssertTrue(options.advertiseFTMS)
        XCTAssertFalse(options.advertiseCPS)
        XCTAssertTrue(options.advertiseRSC)
    }

    func testServiceOptionsValues() {
        stateManager.advertiseFTMS = false
        stateManager.advertiseCPS = true
        stateManager.advertiseRSC = false

        let options = stateManager.getServiceOptions()

        XCTAssertFalse(options.advertiseFTMS)
        XCTAssertTrue(options.advertiseCPS)
        XCTAssertFalse(options.advertiseRSC)
    }

    // MARK: - FTMS Integration Tests

    func testControlStateUpdate() {
        let controlState = FTMSControlPointHandler.ControlState(
            hasControl: true,
            isStarted: false,
            targetPower: 400,
            simWindSpeedMps: 2.0,
            simCrr: 0.005,
            simCw: 0.6,
            gradePercent: 5.0
        )

        stateManager.updateFromControlState(controlState)

        XCTAssertEqual(stateManager.watts, 400)
        XCTAssertEqual(stateManager.gradePercent, 5.0)
    }

    // MARK: - Validated Parameter Setting Tests

    func testSetValidatedWatts() {
        // Valid value
        stateManager.setValidatedWatts(300)
        XCTAssertEqual(stateManager.watts, 300)

        // Clamped to minimum
        stateManager.setValidatedWatts(-50)
        XCTAssertEqual(stateManager.watts, 0)

        // Clamped to maximum (realistic limit is 2000W)
        stateManager.setValidatedWatts(10000)
        XCTAssertEqual(stateManager.watts, 2000)
    }

    func testSetValidatedCadenceRpm() {
        // Valid value
        stateManager.setValidatedCadenceRpm(100)
        XCTAssertEqual(stateManager.cadenceRpm, 100)

        // Clamped to minimum
        stateManager.setValidatedCadenceRpm(-10)
        XCTAssertEqual(stateManager.cadenceRpm, 0)

        // Clamped to maximum (research-based limit is 120 RPM)
        stateManager.setValidatedCadenceRpm(500)
        XCTAssertEqual(stateManager.cadenceRpm, 120)
    }

    func testSetValidatedGradePercent() {
        // Valid value
        stateManager.setValidatedGradePercent(8.0)
        XCTAssertEqual(stateManager.gradePercent, 8.0, accuracy: 0.01)

        // Clamped to minimum (realistic limit is -30%)
        stateManager.setValidatedGradePercent(-50.0)
        XCTAssertEqual(stateManager.gradePercent, -30.0, accuracy: 0.01)

        // Clamped to maximum (realistic limit is 30%)
        stateManager.setValidatedGradePercent(50.0)
        XCTAssertEqual(stateManager.gradePercent, 30.0, accuracy: 0.01)
    }

    func testSetValidatedRandomness() {
        // Valid value
        stateManager.setValidatedRandomness(50)
        XCTAssertEqual(stateManager.randomness, 50)

        // Clamped to minimum
        stateManager.setValidatedRandomness(-10)
        XCTAssertEqual(stateManager.randomness, 0)

        // Clamped to maximum
        stateManager.setValidatedRandomness(150)
        XCTAssertEqual(stateManager.randomness, 100)
    }

    func testValidatedParameterPublishing() {
        let expectation = XCTestExpectation(description: "Parameter changes observed")
        var wattsValues: [Int] = []

        stateManager.$watts
            .sink { watts in
                wattsValues.append(watts)
                if wattsValues.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        stateManager.setValidatedWatts(200)
        stateManager.setValidatedWatts(400)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(wattsValues, [250, 200, 400])
    }

    // MARK: - State Validation Tests

    func testValidateCurrentState() {
        stateManager.watts = 500
        stateManager.cadenceRpm = 120
        stateManager.gradePercent = 15.0
        stateManager.randomness = 75

        let results = stateManager.validateCurrentState()

        // Should have validation results
        XCTAssertFalse(results.isEmpty)

        // Check that results have proper structure
        for result in results {
            XCTAssertNotNil(result.level)
            XCTAssertNotNil(result.message)
            XCTAssertNotNil(result.parameter)
        }
    }

    func testValidateCurrentStateWithInvalidValues() {
        stateManager.watts = -100  // Invalid
        stateManager.cadenceRpm = 300  // Invalid
        stateManager.gradePercent = 60.0  // Invalid
        stateManager.randomness = -50  // Invalid

        let results = stateManager.validateCurrentState()

        // Should have validation issues
        let invalidResults = results.filter { !$0.isValid }
        XCTAssertGreaterThan(invalidResults.count, 0)
    }

    // MARK: - Combine Integration Tests

    func testMultiplePropertyChanges() {
        let expectation = XCTestExpectation(description: "Multiple property changes")
        var changeCount = 0

        // Subscribe to multiple properties
        Publishers.CombineLatest4(
            stateManager.$watts,
            stateManager.$cadenceRpm,
            stateManager.$gradePercent,
            stateManager.$state
        )
        .sink { _, _, _, _ in
            changeCount += 1
            if changeCount == 5 { // Initial + 4 changes
                expectation.fulfill()
            }
        }
        .store(in: &cancellables)

        stateManager.setValidatedWatts(300)
        stateManager.setValidatedCadenceRpm(95)
        stateManager.setValidatedGradePercent(3.0)
        stateManager.state = .advertising

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(changeCount, 5)
    }

    // MARK: - Configuration State Tests

    func testCadenceModeChanges() {
        XCTAssertEqual(stateManager.cadenceMode, .auto)

        stateManager.cadenceMode = .manual
        XCTAssertEqual(stateManager.cadenceMode, .manual)

        stateManager.cadenceMode = .auto
        XCTAssertEqual(stateManager.cadenceMode, .auto)
    }

    func testLocalNameConfiguration() {
        XCTAssertEqual(stateManager.localName, "Trainer")

        stateManager.localName = "Custom Trainer"
        XCTAssertEqual(stateManager.localName, "Custom Trainer")
    }

    func testServiceAdvertisingToggles() {
        XCTAssertTrue(stateManager.advertiseFTMS)
        XCTAssertFalse(stateManager.advertiseCPS)
        XCTAssertFalse(stateManager.advertiseRSC)

        stateManager.advertiseFTMS = false
        stateManager.advertiseCPS = true
        stateManager.advertiseRSC = true

        XCTAssertFalse(stateManager.advertiseFTMS)
        XCTAssertTrue(stateManager.advertiseCPS)
        XCTAssertTrue(stateManager.advertiseRSC)
    }

    // MARK: - Performance Tests

    // Disabled: Performance test may cause issues
    func disabled_testParameterValidationPerformance() {
        measure {
            for _ in 0..<1000 {
                stateManager.setValidatedWatts(Int.random(in: 0...500))
                stateManager.setValidatedCadenceRpm(Int.random(in: 60...120))
                stateManager.setValidatedGradePercent(Double.random(in: -10...10))
                stateManager.setValidatedRandomness(Int.random(in: 0...100))
            }
        }
    }

    // Disabled: Performance test may cause issues
    func disabled_testLiveStatsUpdatePerformance() {
        measure {
            for _ in 0..<1000 {
                let simulationState = CyclingSimulationEngine.SimulationState(
                    powerWatts: Int.random(in: 100...400),
                    speedMps: Double.random(in: 5...15),
                    cadenceRpm: Int.random(in: 60...120),
                    fatigue: Double.random(in: 0...1),
                    noise: Double.random(in: 0...1),
                    gear: (front: 2, rear: 5),
                    targetCadence: Double.random(in: 60...120)
                )
                stateManager.updateLiveStats(from: simulationState)
            }
        }
    }

    // MARK: - Edge Cases and Robustness Tests

    func testSequentialParameterUpdates() {
        // Test sequential updates to ensure state consistency
        for i in 0..<10 {
            stateManager.setValidatedWatts(200 + i * 10)
            stateManager.log("Update \(i)")
        }

        // Verify final state is consistent
        XCTAssertEqual(stateManager.watts, 290)
        XCTAssertEqual(stateManager.eventLog.count, 10)
    }

    func testStateValidationWithExtremeCases() {
        // Test extreme values
        stateManager.watts = Int.max
        stateManager.cadenceRpm = Int.max
        stateManager.gradePercent = Double.infinity
        stateManager.randomness = Int.min

        let results = stateManager.validateCurrentState()

        // Should handle extreme values gracefully
        XCTAssertFalse(results.isEmpty)

        // Check that validation doesn't crash with extreme values
        for result in results {
            XCTAssertNotNil(result.level)
            XCTAssertNotNil(result.message)
            XCTAssertNotNil(result.parameter)
        }
    }

    func testMemoryManagement() {
        weak var weakStateManager: SimulationStateManager?

        autoreleasepool {
            let localStateManager = SimulationStateManager()
            weakStateManager = localStateManager

            // Create some subscriptions
            localStateManager.$watts
                .sink { _ in }
                .store(in: &cancellables)

            XCTAssertNotNil(weakStateManager)
        }

        // Clear all subscriptions
        cancellables.removeAll()

        // StateManager should be deallocated
        XCTAssertNil(weakStateManager)
    }
}
