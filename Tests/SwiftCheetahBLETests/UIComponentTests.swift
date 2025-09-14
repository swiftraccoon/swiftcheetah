import XCTest
@testable import SwiftCheetahBLE
import SwiftUI

final class LiveMetricsTests: XCTestCase {
    func testAveragesCalculation() {
        // Create a mock stats object
        var stats = PeripheralManager.LiveStats(
            speedKmh: 0, powerW: 0, cadenceRpm: 0,
            mode: "Manual", gear: "1", targetCadence: 0,
            fatigue: 0, noise: 0, gradePercent: 0
        )

        // Simulate the LiveMetricsCard averaging logic
        var totalPower: Double = 0
        var totalCadence: Double = 0
        var totalSpeed: Double = 0
        var sampleCount: Int = 0

        // Simulate 5 seconds of data
        let testData = [
            (power: 100, cadence: 60, speed: 20.0),
            (power: 150, cadence: 70, speed: 22.0),
            (power: 200, cadence: 80, speed: 24.0),
            (power: 250, cadence: 90, speed: 26.0),
            (power: 300, cadence: 100, speed: 28.0)
        ]

        for data in testData {
            stats.powerW = data.power
            stats.cadenceRpm = data.cadence
            stats.speedKmh = data.speed

            // This simulates updateAverages() function
            totalPower += Double(stats.powerW)
            totalCadence += Double(stats.cadenceRpm)
            totalSpeed += stats.speedKmh
            sampleCount += 1

            print("Sample \(sampleCount): Power=\(stats.powerW), Cadence=\(stats.cadenceRpm), Speed=\(stats.speedKmh)")
        }

        // Calculate averages
        let avgPower = sampleCount > 0 ? totalPower / Double(sampleCount) : 0
        let avgCadence = sampleCount > 0 ? totalCadence / Double(sampleCount) : 0
        let avgSpeed = sampleCount > 0 ? totalSpeed / Double(sampleCount) : 0

        print("Calculated averages: Power=\(avgPower), Cadence=\(avgCadence), Speed=\(avgSpeed)")

        // Expected averages
        let expectedAvgPower = 200.0  // (100+150+200+250+300)/5
        let expectedAvgCadence = 80.0 // (60+70+80+90+100)/5
        let expectedAvgSpeed = 24.0   // (20+22+24+26+28)/5

        XCTAssertEqual(avgPower, expectedAvgPower, accuracy: 0.1,
                      "Average power should be \(expectedAvgPower) but was \(avgPower)")
        XCTAssertEqual(avgCadence, expectedAvgCadence, accuracy: 0.1,
                      "Average cadence should be \(expectedAvgCadence) but was \(avgCadence)")
        XCTAssertEqual(avgSpeed, expectedAvgSpeed, accuracy: 0.1,
                      "Average speed should be \(expectedAvgSpeed) but was \(avgSpeed)")
    }

    func testLiveMetricsTimerUpdates() {
        // This test would check if the Timer actually triggers updates
        // Problem: The Timer in onReceive might not be properly connected

        let expectation = XCTestExpectation(description: "Timer should fire")
        var updateCount = 0

        // Simulate the Timer.publish pattern used in LiveMetricsCard
        let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        let cancellable = timer.sink { _ in
            updateCount += 1
            print("Timer fired, update count: \(updateCount)")
            if updateCount >= 3 {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5)
        XCTAssertGreaterThanOrEqual(updateCount, 3, "Timer should have fired at least 3 times")
        cancellable.cancel()
    }
}

final class PerformanceGraphTests: XCTestCase {
    func testGraphHistoryUpdate() {
        // Simulate the PerformanceGraphCard history update logic
        var powerHistory: [Double] = Array(repeating: 0, count: 60)
        var cadenceHistory: [Double] = Array(repeating: 0, count: 60)
        var speedHistory: [Double] = Array(repeating: 0, count: 60)
        var updateTrigger = false

        // Create mock stats
        var stats = PeripheralManager.LiveStats(
            speedKmh: 0, powerW: 0, cadenceRpm: 0,
            mode: "Manual", gear: "1", targetCadence: 0,
            fatigue: 0, noise: 0, gradePercent: 0
        )

        // Simulate 10 updates with different values
        for i in 1...10 {
            stats.powerW = i * 20
            stats.cadenceRpm = i * 10
            stats.speedKmh = Double(i * 5)

            // This simulates updateHistory() function
            powerHistory.removeFirst()
            powerHistory.append(Double(stats.powerW))

            cadenceHistory.removeFirst()
            cadenceHistory.append(Double(stats.cadenceRpm))

            speedHistory.removeFirst()
            speedHistory.append(stats.speedKmh)

            updateTrigger.toggle()

            print("Update \(i): Power history last 5 values: \(Array(powerHistory.suffix(5)))")
        }

        // Check that the history contains the recent values
        let lastFivePower = Array(powerHistory.suffix(5))
        let expectedLastFive = [120.0, 140.0, 160.0, 180.0, 200.0]

        XCTAssertEqual(lastFivePower, expectedLastFive,
                      "Last 5 power values should be \(expectedLastFive) but were \(lastFivePower)")

        // Check that old values are gone (first 50 should still be 0)
        let firstFifty = Array(powerHistory.prefix(50))
        XCTAssertTrue(firstFifty.allSatisfy { $0 == 0 },
                     "First 50 values should still be 0 after only 10 updates")

        // Verify the graph would show a flat line at the bottom for most of its width
        let nonZeroCount = powerHistory.filter { $0 > 0 }.count
        XCTAssertEqual(nonZeroCount, 10, "Only 10 values should be non-zero")

        print("Power history has \(nonZeroCount) non-zero values out of 60")
        print("This means the graph will be flat for 83% of its width!")
    }

    func testGraphMaxValueCalculation() {
        // Test the maxValueForMetric logic
        var powerHistory: [Double] = Array(repeating: 0, count: 60)

        // Add some power values
        for i in 0..<10 {
            powerHistory[50 + i] = Double((i + 1) * 30)
        }

        let maxPower = max(500, powerHistory.max() ?? 500)
        print("Max power for scaling: \(maxPower)")

        // With mostly zeros, the actual max is 300 but function returns 500
        XCTAssertEqual(maxPower, 500, "Max should be at least 500")

        // This means small values will be scaled against 500, making them appear even smaller
        let value100 = 100.0
        let scaledHeight = value100 / maxPower  // 0.2 - only 20% of graph height
        print("A value of 100W will only use \(scaledHeight * 100)% of the graph height")

        XCTAssertLessThan(scaledHeight, 0.25, "Small values will be nearly invisible on the graph")
    }

    func testTimerInitialization() {
        // Test that the timer actually runs
        let expectation = XCTestExpectation(description: "Timer should update history")
        var updateCount = 0
        var timer: Timer?

        // Simulate onAppear timer setup
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // In the real code, this calls updateHistory() in a Task
            Task { @MainActor in
                updateCount += 1
                print("Timer update \(updateCount)")
                if updateCount >= 3 {
                    expectation.fulfill()
                }
            }
        }

        wait(for: [expectation], timeout: 5)
        timer?.invalidate()

        XCTAssertGreaterThanOrEqual(updateCount, 3, "Timer should have updated at least 3 times")
    }
}
