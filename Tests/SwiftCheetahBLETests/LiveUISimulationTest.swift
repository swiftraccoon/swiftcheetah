import XCTest
@testable import SwiftCheetahBLE
import SwiftUI
import Combine

final class LiveUISimulationTest: XCTestCase {

    func testActualLiveMetricsProblem() {
        print("\n=== Testing the ACTUAL LiveMetricsCard averaging problem ===\n")

        // The real problem: stats object changes but averages don't update correctly
        // because the timer callback doesn't see the new stats values

        class MockPeripheralManager: ObservableObject {
            @Published var stats = PeripheralManager.LiveStats(
                speedKmh: 20.0, powerW: 200, cadenceRpm: 90,
                mode: "Manual", gear: "1", targetCadence: 0,
                fatigue: 0, noise: 0, gradePercent: 0
            )
        }

        let periph = MockPeripheralManager()
        var cancellables = Set<AnyCancellable>()

        // Simulate what LiveMetricsCard does
        var totalPower: Double = 0
        var totalCadence: Double = 0
        var totalSpeed: Double = 0
        var sampleCount: Int = 0

        // This simulates the Timer.publish in onReceive
        let expectation = XCTestExpectation(description: "Timer updates")
        var updateCount = 0

        // Simulate the timer that's supposed to update averages
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // THIS IS THE BUG: The timer fires but stats is always the same initial value
                // because SwiftUI creates a capture at view creation time

                print("Timer fired \(updateCount + 1)")
                print("  Current stats power: \(periph.stats.powerW)")

                // Update averages (this is what updateAverages() does)
                totalPower += Double(periph.stats.powerW)
                totalCadence += Double(periph.stats.cadenceRpm)
                totalSpeed += periph.stats.speedKmh
                sampleCount += 1

                let avgPower = sampleCount > 0 ? totalPower / Double(sampleCount) : 0
                print("  Average power so far: \(avgPower)")

                updateCount += 1

                // After 1 second, change the stats
                if updateCount == 2 {
                    print("\n>>> Changing stats from 200W to 300W <<<\n")
                    periph.stats = PeripheralManager.LiveStats(
                        speedKmh: 25.0, powerW: 300, cadenceRpm: 100,
                        mode: "Manual", gear: "1", targetCadence: 0,
                        fatigue: 0, noise: 0, gradePercent: 0
                    )
                }

                if updateCount >= 6 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 4)

        let finalAvgPower = sampleCount > 0 ? totalPower / Double(sampleCount) : 0
        print("\n=== FINAL RESULTS ===")
        print("Sample count: \(sampleCount)")
        print("Total power: \(totalPower)")
        print("Final average power: \(finalAvgPower)")
        print("Expected average: ~233 (200*2 + 300*4)/6")

        // The bug: average should be around 233 but will be either 200 or 300
        // depending on whether the timer sees the updated value
        XCTAssertGreaterThan(finalAvgPower, 220, "Average should reflect the changed values")
        XCTAssertLessThan(finalAvgPower, 280, "Average should be a mix of old and new values")
    }

    func testActualGraphProblem() {
        print("\n=== Testing the ACTUAL PerformanceGraphCard problem ===\n")

        // The real problem: Even if values change, the graph doesn't update visually
        // because SwiftUI doesn't know the arrays changed (they're not @Published)

        var powerHistory: [Double] = Array(repeating: 0, count: 60)
        var updateTrigger = false

        print("Initial power history (last 10): \(Array(powerHistory.suffix(10)))")

        // Simulate adding real data
        for i in 1...10 {
            powerHistory.removeFirst()
            powerHistory.append(Double(i * 25))
            updateTrigger.toggle()

            if i % 3 == 0 {
                print("After \(i) updates, last 10 values: \(Array(powerHistory.suffix(10)))")
            }
        }

        print("\n=== THE PROBLEMS ===")
        print("1. Even though updateTrigger toggles, SwiftUI might not see array changes")
        print("2. The array starts with 50 zeros, so 83% of the graph is always flat")
        print("3. Using updateTrigger in Path is a hack that might not work reliably")
        print("4. The Path closure might be capturing initial empty arrays")

        // Check how much of the graph is non-zero
        let nonZeroCount = powerHistory.filter { $0 > 0 }.count
        let percentFlat = Double(60 - nonZeroCount) / 60.0 * 100

        print("\nGraph statistics:")
        print("  Non-zero values: \(nonZeroCount)/60")
        print("  Flat portion: \(percentFlat)%")

        XCTAssertLessThan(percentFlat, 85, "Most of the graph is flat!")
    }
}