import XCTest
@testable import SwiftCheetahCore

final class OrnsteinUhlenbeckVarianceTests: XCTestCase {

    var variance: OrnsteinUhlenbeckVariance!

    override func setUp() {
        super.setUp()
        variance = OrnsteinUhlenbeckVariance()
    }

    func testInitialState() {
        // Initial variation should be zero
        let variation = variance.update(randomness: 50, targetPower: 200, dt: 0.25)
        XCTAssertEqual(variation, 0, accuracy: 0.1)
    }

    func testUpdateGeneratesVariance() {
        let basePower = 200.0
        let randomness = 50.0  // Normal randomness
        var powers: [Double] = []

        // Generate many samples
        for _ in 0..<100 {
            let variation = variance.update(randomness: randomness, targetPower: basePower, dt: 0.25)
            let variedPower = basePower * (1 + variation)
            powers.append(variedPower)
        }

        // Check that we get variation
        let mean = powers.reduce(0, +) / Double(powers.count)
        let stdDev = sqrt(powers.map { pow($0 - mean, 2) }.reduce(0, +) / Double(powers.count))

        // Should be close to base power on average
        XCTAssertEqual(mean, basePower, accuracy: 10.0)

        // Should have some variation (more than 0, less than 20W typically)
        XCTAssertGreaterThan(stdDev, 0.5)
        XCTAssertLessThan(stdDev, 20.0)
    }

    func testMeanReversion() {
        let basePower = 200.0
        let randomness = 50.0
        var variations: [Double] = []

        // Run many updates
        for _ in 0..<200 {
            let variation = variance.update(randomness: randomness, targetPower: basePower, dt: 0.25)
            variations.append(variation)
        }

        // Check that variations center around zero
        let mean = variations.reduce(0, +) / Double(variations.count)
        XCTAssertEqual(mean, 0, accuracy: 0.05)
    }

    func testBudgetAllocation() {
        // Test that variance budget is properly allocated
        let basePower = 200.0
        let randomness = 100.0  // Max randomness = ~10% CV

        var maxVariation = 0.0
        for _ in 0..<1000 {
            let variation = variance.update(randomness: randomness, targetPower: basePower, dt: 0.25)
            maxVariation = max(maxVariation, abs(variation))
        }

        // Should rarely exceed 30% variation (3x the 10% CV)
        XCTAssertLessThan(maxVariation, 0.3)
    }

    func testDifferentTimeSteps() {
        let basePower = 200.0
        let randomness = 50.0

        // Test with different dt values
        let timeSteps = [0.01, 0.1, 0.25, 1.0, 2.0]

        for dt in timeSteps {
            variance = OrnsteinUhlenbeckVariance() // Reset
            var powers: [Double] = []

            for _ in 0..<100 {
                let variation = variance.update(randomness: randomness, targetPower: basePower, dt: dt)
                powers.append(basePower * (1 + variation))
            }

            let mean = powers.reduce(0, +) / Double(powers.count)

            // Should maintain reasonable behavior at all time steps
            XCTAssertEqual(mean, basePower, accuracy: 15.0,
                          "Failed for dt=\(dt)")
        }
    }

    func testReset() {
        let randomness = 75.0

        // Generate some variance
        var beforeReset: Double = 0
        for _ in 0..<10 {
            beforeReset = variance.update(randomness: randomness, targetPower: 200, dt: 0.25)
        }

        // Reset
        variance.reset()

        // After reset, variation should be back to near zero
        let afterReset = variance.update(randomness: randomness, targetPower: 200, dt: 0.25)
        XCTAssertEqual(afterReset, 0, accuracy: 0.1)
    }

    func testVariationPatterns() {
        // Test that variations show realistic patterns
        let basePower = 200.0
        let randomness = 50.0
        var variations: [Double] = []

        for _ in 0..<200 {
            let variation = variance.update(randomness: randomness, targetPower: basePower, dt: 0.25)
            variations.append(variation)
        }

        // Calculate autocorrelation to verify temporal structure
        let mean = variations.reduce(0, +) / Double(variations.count)
        var autocorr = 0.0
        var variance = 0.0

        for i in 0..<(variations.count - 1) {
            let dev = variations[i] - mean
            let devNext = variations[i + 1] - mean
            autocorr += dev * devNext
            variance += dev * dev
        }

        let correlation = autocorr / variance

        // Should have some temporal correlation (not white noise)
        XCTAssertGreaterThan(correlation, 0.3)
        XCTAssertLessThan(correlation, 0.95)
    }

    func testPowerNeverNegative() {
        // Even with low base power, result should never be negative
        let basePower = 10.0
        let randomness = 100.0  // Max randomness

        for _ in 0..<1000 {
            let variation = variance.update(randomness: randomness, targetPower: basePower, dt: 0.25)
            let power = basePower * (1 + variation)
            XCTAssertGreaterThanOrEqual(power, 0)
        }
    }

    func testHighPowerScaling() {
        // Test that variance scales appropriately with power
        let lowPower = 100.0
        let highPower = 400.0
        let randomness = 50.0

        var lowPowers: [Double] = []
        var highPowers: [Double] = []

        variance = OrnsteinUhlenbeckVariance()
        for _ in 0..<100 {
            let variation = variance.update(randomness: randomness, targetPower: lowPower, dt: 0.25)
            lowPowers.append(lowPower * (1 + variation))
        }

        variance = OrnsteinUhlenbeckVariance()
        for _ in 0..<100 {
            let variation = variance.update(randomness: randomness, targetPower: highPower, dt: 0.25)
            highPowers.append(highPower * (1 + variation))
        }

        let lowStdDev = sqrt(lowPowers.map { pow($0 - lowPower, 2) }.reduce(0, +) / Double(lowPowers.count))
        let highStdDev = sqrt(highPowers.map { pow($0 - highPower, 2) }.reduce(0, +) / Double(highPowers.count))

        // Higher power should have proportionally similar or slightly higher variance
        let lowCV = lowStdDev / lowPower  // Coefficient of variation
        let highCV = highStdDev / highPower

        // CVs should be in similar range
        XCTAssertEqual(lowCV, highCV, accuracy: 0.05)
    }

    func testStatisticalProperties() {
        // Test that the output has expected statistical properties
        let basePower = 200.0
        let randomness = 50.0
        var powers: [Double] = []

        // Generate large sample
        for _ in 0..<1000 {
            let variation = variance.update(randomness: randomness, targetPower: basePower, dt: 0.25)
            powers.append(basePower * (1 + variation))
        }

        // Calculate statistics
        let mean = powers.reduce(0, +) / Double(powers.count)
        let variance = powers.map { pow($0 - mean, 2) }.reduce(0, +) / Double(powers.count)
        let stdDev = sqrt(variance)

        // Count how many are within 1, 2, and 3 standard deviations
        let within1SD = powers.filter { abs($0 - mean) <= stdDev }.count
        let within2SD = powers.filter { abs($0 - mean) <= 2 * stdDev }.count
        let within3SD = powers.filter { abs($0 - mean) <= 3 * stdDev }.count

        let pct1SD = Double(within1SD) / Double(powers.count)
        let pct2SD = Double(within2SD) / Double(powers.count)
        let pct3SD = Double(within3SD) / Double(powers.count)

        // Should roughly follow normal distribution
        // (68-95-99.7 rule, with some tolerance)
        XCTAssertEqual(pct1SD, 0.68, accuracy: 0.15)
        XCTAssertEqual(pct2SD, 0.95, accuracy: 0.10)
        XCTAssertEqual(pct3SD, 0.997, accuracy: 0.05)
    }
}