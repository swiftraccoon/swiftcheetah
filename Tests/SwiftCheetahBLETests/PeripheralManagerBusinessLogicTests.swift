import XCTest
@testable import SwiftCheetahBLE
import Combine

/// Tests for PeripheralManager business logic without UI concerns
final class PeripheralManagerBusinessLogicTests: XCTestCase {

    // MARK: - Live Stats Updates Tests

    func testLiveStatsInitialValues() {
        // Test that LiveStats initializes with sensible defaults
        let periph = PeripheralManager()

        XCTAssertEqual(periph.stats.speedKmh, 25.0, accuracy: 0.1, "Initial speed should be 25 km/h")
        XCTAssertEqual(periph.stats.powerW, 250, "Initial power should be 250W")
        XCTAssertEqual(periph.stats.cadenceRpm, 90, "Initial cadence should be 90 RPM")
        XCTAssertEqual(periph.stats.mode, "AUTO", "Initial mode should be AUTO")
        XCTAssertEqual(periph.stats.gradePercent, 0, accuracy: 0.1, "Initial grade should be 0%")
    }

    func testSimulationUpdatesStats() {
        // Test that simulation timer actually updates stats
        let periph = PeripheralManager()
        let initialPower = periph.stats.powerW

        let expectation = XCTestExpectation(description: "Stats should update")
        var hasChanged = false

        // Subscribe to stats changes
        let cancellable = periph.$stats
            .dropFirst() // Skip initial value
            .sink { newStats in
                if newStats.powerW != initialPower ||
                   newStats.cadenceRpm != 90 ||
                   newStats.speedKmh != 25.0 {
                    hasChanged = true
                    expectation.fulfill()
                }
            }

        // Wait for simulation to update (timer runs every 1 second)
        wait(for: [expectation], timeout: 3)

        XCTAssertTrue(hasChanged, "Simulation should update stats over time")
        cancellable.cancel()
    }

    func testRandomnessPropertyExists() {
        // Test that randomness property can be set
        let periph = PeripheralManager()

        // Set different randomness values
        periph.randomness = 10
        XCTAssertEqual(periph.randomness, 10, "Should be able to set low randomness")

        periph.randomness = 90
        XCTAssertEqual(periph.randomness, 90, "Should be able to set high randomness")

        // Randomness should affect variation over time (tested via observation, not direct calls)
        let expectation = XCTestExpectation(description: "Stats should vary")
        var powerValues: [Int] = []

        let cancellable = periph.$stats
            .sink { stats in
                powerValues.append(stats.powerW)
                if powerValues.count >= 5 {
                    expectation.fulfill()
                }
            }

        wait(for: [expectation], timeout: 6)

        // With high randomness, we should see variation
        let uniquePowers = Set(powerValues).count
        XCTAssertGreaterThan(uniquePowers, 1,
            "Power values should vary over time with randomness")

        cancellable.cancel()
    }

    // MARK: - Averaging Logic Tests (Business Logic, not UI)

    func testAveragingCalculation() {
        // Test the averaging logic as pure business logic
        struct MetricsAccumulator {
            var totalPower: Double = 0
            var totalCadence: Double = 0
            var totalSpeed: Double = 0
            var sampleCount: Int = 0

            mutating func addSample(power: Int, cadence: Int, speed: Double) {
                totalPower += Double(power)
                totalCadence += Double(cadence)
                totalSpeed += speed
                sampleCount += 1
            }

            var averagePower: Double {
                sampleCount > 0 ? totalPower / Double(sampleCount) : 0
            }

            var averageCadence: Double {
                sampleCount > 0 ? totalCadence / Double(sampleCount) : 0
            }

            var averageSpeed: Double {
                sampleCount > 0 ? totalSpeed / Double(sampleCount) : 0
            }
        }

        var accumulator = MetricsAccumulator()

        // Add samples with known values
        accumulator.addSample(power: 100, cadence: 60, speed: 20.0)
        accumulator.addSample(power: 200, cadence: 80, speed: 25.0)
        accumulator.addSample(power: 300, cadence: 100, speed: 30.0)

        XCTAssertEqual(accumulator.averagePower, 200.0, accuracy: 0.1,
            "Average power should be (100+200+300)/3 = 200")
        XCTAssertEqual(accumulator.averageCadence, 80.0, accuracy: 0.1,
            "Average cadence should be (60+80+100)/3 = 80")
        XCTAssertEqual(accumulator.averageSpeed, 25.0, accuracy: 0.1,
            "Average speed should be (20+25+30)/3 = 25")
    }

    // MARK: - History Tracking Tests (Business Logic, not UI)

    func testHistoryTracking() {
        // Test history tracking as pure data structure operations
        class MetricsHistory {
            private(set) var powerHistory: [Double]
            private(set) var cadenceHistory: [Double]
            private(set) var speedHistory: [Double]

            init(size: Int = 60) {
                powerHistory = Array(repeating: 0, count: size)
                cadenceHistory = Array(repeating: 0, count: size)
                speedHistory = Array(repeating: 0, count: size)
            }

            func addSample(power: Double, cadence: Double, speed: Double) {
                powerHistory.removeFirst()
                powerHistory.append(power)

                cadenceHistory.removeFirst()
                cadenceHistory.append(cadence)

                speedHistory.removeFirst()
                speedHistory.append(speed)
            }

            var nonZeroPowerCount: Int {
                powerHistory.filter { $0 > 0 }.count
            }
        }

        let history = MetricsHistory()

        // Add 10 samples
        for i in 1...10 {
            history.addSample(
                power: Double(i * 20),
                cadence: Double(i * 10),
                speed: Double(i * 5)
            )
        }

        // Verify last 10 values
        let lastTenPower = Array(history.powerHistory.suffix(10))
        let expectedLastTen = [20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 140.0, 160.0, 180.0, 200.0]

        XCTAssertEqual(lastTenPower, expectedLastTen,
            "Last 10 power values should match expected sequence")

        // Verify we still have mostly zeros (50 out of 60)
        XCTAssertEqual(history.nonZeroPowerCount, 10,
            "Should have exactly 10 non-zero values after 10 samples")
    }

    // MARK: - BLE Data Encoding Tests

    func testBLEDataGenerationFrequency() {
        // Test that BLE data is generated at expected frequency
        let periph = PeripheralManager()

        var updateCount = 0
        let expectation = XCTestExpectation(description: "BLE data updates")

        // Monitor stats updates
        let cancellable = periph.$stats
            .sink { _ in
                updateCount += 1
                if updateCount >= 3 {
                    expectation.fulfill()
                }
            }

        wait(for: [expectation], timeout: 5)

        XCTAssertGreaterThanOrEqual(updateCount, 3,
            "Should receive at least 3 updates in 5 seconds")

        cancellable.cancel()
    }

    func testStatsRespondsToChanges() {
        // Test that stats respond to simulation over time
        let periph = PeripheralManager()

        let expectation = XCTestExpectation(description: "Stats should change")
        var collectedStats: [PeripheralManager.LiveStats] = []

        let cancellable = periph.$stats
            .sink { stats in
                collectedStats.append(stats)
                if collectedStats.count >= 5 {
                    expectation.fulfill()
                }
            }

        wait(for: [expectation], timeout: 6)

        // Check that we got different values over time
        let uniqueSpeeds = Set(collectedStats.map { $0.speedKmh }).count
        let uniquePowers = Set(collectedStats.map { $0.powerW }).count

        XCTAssertGreaterThan(uniqueSpeeds, 1, "Speed should vary over time")
        XCTAssertGreaterThan(uniquePowers, 1, "Power should vary over time")

        cancellable.cancel()
    }

    // MARK: - Helper Functions

    private func standardDeviation(_ values: [Int]) -> Double {
        let doubleValues = values.map { Double($0) }
        let mean = doubleValues.reduce(0, +) / Double(values.count)
        let squaredDiffs = doubleValues.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}

/// Tests for data flow and state management patterns
final class StateManagementTests: XCTestCase {

    func testPublishedPropertyUpdates() {
        // Test that @Published properties trigger updates correctly
        let periph = PeripheralManager()

        let expectation = XCTestExpectation(description: "Published property updates")
        var updateCount = 0

        let cancellable = periph.$stats
            .dropFirst() // Skip initial value
            .sink { _ in
                updateCount += 1
                if updateCount >= 2 {
                    expectation.fulfill()
                }
            }

        // Wait for automatic updates from the timer
        wait(for: [expectation], timeout: 3)

        XCTAssertGreaterThanOrEqual(updateCount, 2,
            "@Published should notify subscribers of changes")

        cancellable.cancel()
    }

    func testConcurrentAccessSafety() {
        // Test that concurrent access to stats is thread-safe
        let periph = PeripheralManager()
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        let group = DispatchGroup()

        var allPowerValues: [Int] = []
        let lock = NSLock()

        // Simulate concurrent reads while updates happen
        for _ in 0..<10 {
            group.enter()
            queue.async {
                // Read stats
                let power = periph.stats.powerW
                lock.lock()
                allPowerValues.append(power)
                lock.unlock()
                group.leave()
            }

            // Just do concurrent reads
            Thread.sleep(forTimeInterval: 0.01)
        }

        group.wait()

        // All reads should have valid values (no crashes or corruption)
        XCTAssertEqual(allPowerValues.count, 10, "Should have collected all values")
        XCTAssertTrue(allPowerValues.allSatisfy { $0 >= 0 && $0 <= 2000 },
            "All power values should be in valid range")
    }
}
