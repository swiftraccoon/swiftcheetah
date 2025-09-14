import Foundation

/// Centralized random number generation utility for SwiftCheetah
/// Provides consistent implementations of statistical distributions
public struct RandomUtility {

    // MARK: - Normal Distribution

    /// Generate standard normal random variable using Box-Muller transform
    /// - Returns: Sample from N(0,1)
    public static func randn() -> Double {
        var generator = SystemRandomNumberGenerator()
        return randn(using: &generator)
    }

    /// Generate standard normal random variable with custom generator
    /// - Parameter generator: Random number generator to use
    /// - Returns: Sample from N(0,1)
    public static func randn<T: RandomNumberGenerator>(using generator: inout T) -> Double {
        // Box-Muller transform: converts uniform to normal distribution
        let u1 = Double.random(in: 0..<1, using: &generator)
        let u2 = Double.random(in: 0..<1, using: &generator)

        // Avoid log(0) by using small epsilon
        let epsilon = 1e-10
        let safeU1 = max(epsilon, u1)

        return sqrt(-2 * log(safeU1)) * cos(2 * .pi * u2)
    }

    /// Generate normal random variable with specified mean and standard deviation
    /// - Parameters:
    ///   - mean: Mean of the distribution
    ///   - standardDeviation: Standard deviation of the distribution
    /// - Returns: Sample from N(mean, sd²)
    public static func normal(mean: Double = 0.0, standardDeviation: Double = 1.0) -> Double {
        return mean + standardDeviation * randn()
    }

    /// Generate clamped normal random variable
    /// - Parameters:
    ///   - mean: Mean of the distribution
    ///   - standardDeviation: Standard deviation of the distribution
    ///   - min: Minimum allowed value
    ///   - max: Maximum allowed value
    /// - Returns: Clamped sample from N(mean, sd²)
    public static func clampedNormal(mean: Double, standardDeviation: Double, min: Double, max: Double) -> Double {
        let value = normal(mean: mean, standardDeviation: standardDeviation)
        return Swift.max(min, Swift.min(max, value))
    }

    // MARK: - Seeded Generation

    /// Generate standard normal with seeded generator for reproducible tests
    /// - Parameter seed: Seed value for reproducible results
    /// - Returns: Sample from N(0,1)
    public static func seededRandn(seed: UInt64) -> Double {
        var generator = SeededRandomNumberGenerator(seed: seed)
        return randn(using: &generator)
    }
}

// MARK: - Seeded Random Number Generator

/// Seeded random number generator for reproducible tests
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // Linear congruential generator (simple but sufficient for tests)
        state = state &* 1664525 &+ 1013904223
        return state
    }
}