import XCTest
@testable import SwiftCheetahCore

final class PhysicsPerformanceTests: XCTestCase {

    // MARK: - Newton-Raphson Solver Performance

    func testNewtonRaphsonPerformanceFlat() {
        let params = PhysicsCalculator.Parameters()

        measure {
            // Test 1000 calculations on flat terrain
            for power in stride(from: 50, to: 550, by: 5) {
                _ = PhysicsCalculator.calculateSpeed(
                    powerWatts: Double(power),
                    gradePercent: 0,
                    params: params
                )
            }
        }
    }

    func testNewtonRaphsonPerformanceClimb() {
        let params = PhysicsCalculator.Parameters()

        measure {
            // Test 1000 calculations on climbs
            for power in stride(from: 100, to: 600, by: 5) {
                for grade in stride(from: 2, to: 12, by: 2) {
                    _ = PhysicsCalculator.calculateSpeed(
                        powerWatts: Double(power),
                        gradePercent: Double(grade),
                        params: params
                    )
                }
            }
        }
    }

    func testNewtonRaphsonPerformanceDescent() {
        let params = PhysicsCalculator.Parameters()

        measure {
            // Test 1000 calculations on descents
            for power in stride(from: 0, to: 200, by: 2) {
                for grade in stride(from: -15, to: -2, by: 1) {
                    _ = PhysicsCalculator.calculateSpeed(
                        powerWatts: Double(power),
                        gradePercent: Double(grade),
                        params: params
                    )
                }
            }
        }
    }

    func testNewtonRaphsonConvergenceSpeed() {
        // Test that Newton-Raphson converges quickly (within expected iterations)
        let params = PhysicsCalculator.Parameters()

        // Test convergence speed directly by timing

        // Test various power/grade combinations
        let testCases: [(power: Double, grade: Double)] = [
            (200, 0),    // Flat
            (300, 5),    // Moderate climb
            (400, 10),   // Steep climb
            (100, -5),   // Moderate descent
            (50, -10),   // Steep descent
            (500, 2),    // High power, slight climb
            (150, 8)     // Low power, steep climb
        ]

        for (power, grade) in testCases {
            let startTime = CFAbsoluteTimeGetCurrent()
            _ = PhysicsCalculator.calculateSpeed(
                powerWatts: power,
                gradePercent: grade,
                params: params
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Should converge very quickly (< 1ms per calculation)
            XCTAssertLessThan(elapsed, 0.001, "Slow convergence for power=\(power), grade=\(grade)")
        }
    }

    func testBulkCalculationPerformance() {
        // Test performance of bulk calculations (simulating real-time usage)
        let params = PhysicsCalculator.Parameters()

        measure {
            // Simulate 60 seconds of real-time calculations at 4Hz
            for _ in 0..<240 {
                let power = Double.random(in: 100...350)
                let grade = Double.random(in: -5...10)

                _ = PhysicsCalculator.calculateSpeed(
                    powerWatts: power,
                    gradePercent: grade,
                    params: params
                )
            }
        }
    }

    // MARK: - Terminal Velocity Performance

    func testTerminalVelocityCalculationPerformance() {
        let params = PhysicsCalculator.Parameters()

        measure {
            // Test terminal velocity calculations for various descents
            for grade in stride(from: -20, to: -2, by: 1) {
                for power in stride(from: 0, to: 100, by: 10) {
                    _ = PhysicsCalculator.calculateSpeed(
                        powerWatts: Double(power),
                        gradePercent: Double(grade),
                        params: params
                    )
                }
            }
        }
    }

    // MARK: - Comparison with Simple Physics

    func testPerformanceVsSimplePhysics() {
        let params = PhysicsCalculator.Parameters()

        // Time Newton-Raphson approach
        let newtonStart = CFAbsoluteTimeGetCurrent()
        for power in stride(from: 100, to: 400, by: 50) {
            for grade in stride(from: -5, to: 10, by: 5) {
                _ = PhysicsCalculator.calculateSpeed(
                    powerWatts: Double(power),
                    gradePercent: Double(grade),
                    params: params
                )
            }
        }
        let newtonTime = CFAbsoluteTimeGetCurrent() - newtonStart

        // Time simple physics approach (for comparison)
        let simpleStart = CFAbsoluteTimeGetCurrent()
        for power in stride(from: 100, to: 400, by: 50) {
            for grade in stride(from: -5, to: 10, by: 5) {
                // Simple physics: v = sqrt(P / resistance)
                // Using approximate values for quick calculation
                let gradeDecimal = Double(grade) / 100.0
                let dragCoeff = 0.3  // Approximate CdA
                let rollingCoeff = 0.004  // Approximate Crr
                let mass = 80.0  // kg
                let totalResistance = dragCoeff * 1.2 + rollingCoeff + gradeDecimal * mass * 9.81
                _ = sqrt(Double(power) / max(0.1, totalResistance))
            }
        }
        let simpleTime = CFAbsoluteTimeGetCurrent() - simpleStart

        // Newton-Raphson is iterative and more accurate, so it's expected to be slower
        // Accept up to 50x slower as reasonable for the accuracy gain
        XCTAssertLessThan(newtonTime / simpleTime, 50.0,
                         "Newton-Raphson is too slow compared to simple physics")
    }

    // MARK: - Memory Performance

    func testMemoryFootprint() {
        let params = PhysicsCalculator.Parameters()

        // Ensure no memory leaks or excessive allocations
        measure(metrics: [XCTMemoryMetric()]) {
            for _ in 0..<1000 {
                let power = Double.random(in: 50...500)
                let grade = Double.random(in: -15...15)

                _ = PhysicsCalculator.calculateSpeed(
                    powerWatts: power,
                    gradePercent: grade,
                    params: params
                )
            }
        }
    }

    // MARK: - Worst Case Performance

    func testWorstCaseScenarios() {
        let params = PhysicsCalculator.Parameters()

        // Test edge cases that might cause convergence issues
        let worstCases: [(power: Double, grade: Double, description: String)] = [
            (0.1, 20, "Near-zero power on steep climb"),
            (1000, -20, "High power on steep descent"),
            (1, 0, "Minimal power on flat"),
            (2000, 15, "Maximum power on steep climb"),
            (0, -15, "Zero power on steep descent")
        ]

        for (power, grade, description) in worstCases {
            let startTime = CFAbsoluteTimeGetCurrent()
            let speed = PhysicsCalculator.calculateSpeed(
                powerWatts: power,
                gradePercent: grade,
                params: params
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Even worst cases should complete quickly
            XCTAssertLessThan(elapsed, 0.01, "Slow calculation for \(description)")

            // Result should be valid (not NaN or infinite)
            XCTAssertFalse(speed.isNaN, "NaN result for \(description)")
            XCTAssertFalse(speed.isInfinite, "Infinite result for \(description)")
            XCTAssertGreaterThanOrEqual(speed, 0, "Negative speed for \(description)")
        }
    }

    // MARK: - Concurrent Performance

    func testConcurrentCalculations() {
        let params = PhysicsCalculator.Parameters()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        measure {
            // Simulate multiple threads calculating simultaneously
            for _ in 0..<10 {
                group.enter()
                queue.async {
                    for _ in 0..<100 {
                        let power = Double.random(in: 100...400)
                        let grade = Double.random(in: -10...10)

                        _ = PhysicsCalculator.calculateSpeed(
                            powerWatts: power,
                            gradePercent: grade,
                            params: params
                        )
                    }
                    group.leave()
                }
            }

            group.wait()
        }
    }
}
