import XCTest
@testable import SwiftCheetahBLE
import SwiftUI
import Combine

/// Tests to ensure UI components receive live updates, not captured values
final class ValueCaptureTest: XCTestCase {

    func testStructValueCaptureBug() {
        print("\n=== Testing the struct value capture bug ===\n")

        // This test demonstrates the bug where passing a struct to a view
        // causes the view to capture the initial value and never see updates

        class MockPeripheralManager: ObservableObject {
            @Published var stats = PeripheralManager.LiveStats(
                speedKmh: 20.0, powerW: 200, cadenceRpm: 90,
                mode: "Manual", gear: "1", targetCadence: 0,
                fatigue: 0, noise: 0, gradePercent: 0
            )
        }

        let periph = MockPeripheralManager()

        // Simulate what happens when you pass stats as a let constant
        let capturedStats = periph.stats  // This captures the CURRENT value

        print("Initial stats power: \(periph.stats.powerW)")
        print("Captured stats power: \(capturedStats.powerW)")

        // Now change the stats
        periph.stats = PeripheralManager.LiveStats(
            speedKmh: 30.0, powerW: 300, cadenceRpm: 100,
            mode: "Manual", gear: "2", targetCadence: 0,
            fatigue: 0, noise: 0, gradePercent: 0
        )

        print("\nAfter update:")
        print("Current stats power: \(periph.stats.powerW)")
        print("Captured stats power: \(capturedStats.powerW)")

        // The bug: capturedStats still has the old value!
        XCTAssertEqual(capturedStats.powerW, 200, "Captured value doesn't change")
        XCTAssertEqual(periph.stats.powerW, 300, "Published value does change")

        print("\n=== This is why passing 'stats' to a view doesn't work! ===")
        print("The view captures the initial value and never sees updates.")
        print("Solution: Pass the @ObservedObject periph instead.")
    }

    func testTimerWithCapturedValue() {
        print("\n=== Testing timer with captured value bug ===\n")

        class MockPeripheralManager: ObservableObject {
            @Published var stats = PeripheralManager.LiveStats(
                speedKmh: 20.0, powerW: 200, cadenceRpm: 90,
                mode: "Manual", gear: "1", targetCadence: 0,
                fatigue: 0, noise: 0, gradePercent: 0
            )
        }

        let periph = MockPeripheralManager()
        var cancellables = Set<AnyCancellable>()

        // Simulate a view that captures stats
        let capturedStats = periph.stats

        var totalPowerFromCaptured: Double = 0
        var totalPowerFromLive: Double = 0
        var sampleCount = 0

        let expectation = XCTestExpectation(description: "Timer updates")

        // This simulates what LiveMetricsCard does wrong
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                sampleCount += 1

                // Using captured value (BUG)
                totalPowerFromCaptured += Double(capturedStats.powerW)

                // Using live value (CORRECT)
                totalPowerFromLive += Double(periph.stats.powerW)

                print("Sample \(sampleCount):")
                print("  Captured power: \(capturedStats.powerW)")
                print("  Live power: \(periph.stats.powerW)")

                // Change stats after 2 samples
                if sampleCount == 2 {
                    print("\n>>> Changing power from 200 to 300 <<<\n")
                    periph.stats.powerW = 300
                }

                if sampleCount >= 4 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 3)

        let avgPowerCaptured = totalPowerFromCaptured / Double(sampleCount)
        let avgPowerLive = totalPowerFromLive / Double(sampleCount)

        print("\n=== RESULTS ===")
        print("Average from captured value: \(avgPowerCaptured)")
        print("Average from live value: \(avgPowerLive)")

        // The bug: captured value gives wrong average (always 200)
        XCTAssertEqual(avgPowerCaptured, 200, "Captured value never changes")
        XCTAssertEqual(avgPowerLive, 250, "Live value shows correct average (200*2 + 300*2)/4")
    }

    func testCorrectPatternWithObservedObject() {
        print("\n=== Testing correct pattern with @ObservedObject ===\n")

        class MockPeripheralManager: ObservableObject {
            @Published var stats = PeripheralManager.LiveStats(
                speedKmh: 20.0, powerW: 200, cadenceRpm: 90,
                mode: "Manual", gear: "1", targetCadence: 0,
                fatigue: 0, noise: 0, gradePercent: 0
            )
        }

        let periph = MockPeripheralManager()
        var cancellables = Set<AnyCancellable>()

        var totalPower: Double = 0
        var sampleCount = 0

        let expectation = XCTestExpectation(description: "Timer updates")

        // Correct pattern: access periph.stats directly in the timer
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                sampleCount += 1

                // Always get current value from periph.stats
                totalPower += Double(periph.stats.powerW)

                print("Sample \(sampleCount): Power = \(periph.stats.powerW)")

                if sampleCount == 2 {
                    print("\n>>> Changing power from 200 to 300 <<<\n")
                    periph.stats.powerW = 300
                }

                if sampleCount >= 4 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 3)

        let avgPower = totalPower / Double(sampleCount)

        print("\n=== RESULT ===")
        print("Average power: \(avgPower)")
        print("Expected: 250 (200*2 + 300*2)/4")

        XCTAssertEqual(avgPower, 250, accuracy: 0.1, "Correct pattern gives right average")
    }
}