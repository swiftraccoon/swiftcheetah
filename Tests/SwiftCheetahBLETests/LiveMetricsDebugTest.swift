import XCTest
@testable import SwiftCheetahBLE
import SwiftUI
import Combine

final class LiveMetricsDebugTest: XCTestCase {

    func testLiveMetricsAveragesAccumulation() {
        print("\n=== Testing Live Metrics Averages Accumulation ===\n")

        // Create a real PeripheralManager
        let periph = PeripheralManager()

        // Wait a moment for initial setup
        Thread.sleep(forTimeInterval: 0.5)

        print("Initial stats: Power=\(periph.stats.powerW), Cadence=\(periph.stats.cadenceRpm), Speed=\(periph.stats.speedKmh)")

        // Simulate what LiveMetricsCard does
        var totalPower: Double = 0
        var totalCadence: Double = 0
        var totalSpeed: Double = 0
        var sampleCount: Int = 0

        // Create a timer like LiveMetricsCard does
        let expectation = XCTestExpectation(description: "Averages should accumulate")
        var cancellable: AnyCancellable?

        cancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // This is what updateAverages() does
                totalPower += Double(periph.stats.powerW)
                totalCadence += Double(periph.stats.cadenceRpm)
                totalSpeed += periph.stats.speedKmh
                sampleCount += 1

                let avgPower = sampleCount > 0 ? totalPower / Double(sampleCount) : 0
                let avgCadence = sampleCount > 0 ? totalCadence / Double(sampleCount) : 0
                let avgSpeed = sampleCount > 0 ? totalSpeed / Double(sampleCount) : 0

                print("Sample \(sampleCount):")
                print("  Current: Power=\(periph.stats.powerW), Cadence=\(periph.stats.cadenceRpm), Speed=\(periph.stats.speedKmh)")
                print("  Averages: Power=\(avgPower), Cadence=\(avgCadence), Speed=\(avgSpeed)")

                if sampleCount >= 5 {
                    expectation.fulfill()
                    cancellable?.cancel()
                }
            }

        wait(for: [expectation], timeout: 4)

        print("\n=== RESULT ===")
        print("After 5 samples:")
        print("  Total samples: \(sampleCount)")
        print("  Average power: \(totalPower / Double(sampleCount))")

        // The averages should have accumulated
        XCTAssertGreaterThan(sampleCount, 0, "Should have collected samples")
        XCTAssertGreaterThan(totalPower, 0, "Should have accumulated power")
    }

    func testTimerPublishPattern() {
        print("\n=== Testing Timer.publish Pattern ===\n")

        // Test the exact pattern used in LiveMetricsCard
        var updateCount = 0
        let expectation = XCTestExpectation(description: "Timer should fire")

        let cancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                updateCount += 1
                print("Timer fired: \(updateCount)")

                if updateCount >= 3 {
                    expectation.fulfill()
                }
            }

        wait(for: [expectation], timeout: 2)
        cancellable.cancel()

        XCTAssertGreaterThanOrEqual(updateCount, 3, "Timer should have fired at least 3 times")
    }
}