import Foundation

/// Sliding-window variance/mean helper used to stabilize noisy sensor streams.
public final class VarianceManager: @unchecked Sendable {
    /// Configuration for the sliding window and variance threshold.
    public struct Config: Sendable {
        /// Number of recent samples to keep in the window (>=1).
        public var windowSize: Int
        /// Maximum acceptable variance relative to mean for `isStable`.
        public var maxVariance: Double
        public init(windowSize: Int = 5, maxVariance: Double = 0.05) {
            self.windowSize = max(1, windowSize)
            self.maxVariance = max(0.0, maxVariance)
        }
    }

    private let config: Config
    private var samples: [Double] = []

    /// Create a new variance manager with the provided configuration.
    public init(config: Config = Config()) {
        self.config = config
    }

    /// Add a new sample to the window, evicting oldest entries if needed.
    public func push(_ value: Double) {
        samples.append(value)
        if samples.count > config.windowSize {
            samples.removeFirst(samples.count - config.windowSize)
        }
    }

    /// Arithmetic mean of the current window (0 if empty).
    public var mean: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    /// Population variance of the current window (0 if empty).
    public var variance: Double {
        guard !samples.isEmpty else { return 0 }
        let m = mean
        let sumSq = samples.reduce(0) { $0 + pow($1 - m, 2) }
        return sumSq / Double(samples.count)
    }

    /// Returns true when the window is full and variance is below the configured threshold.
    public var isStable: Bool {
        if samples.count < config.windowSize { return false }
        return variance <= config.maxVariance * max(1.0, mean == 0 ? 1.0 : abs(mean))
    }
}
