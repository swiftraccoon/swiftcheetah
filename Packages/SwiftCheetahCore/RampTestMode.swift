import Foundation

/// Ramp test mode for systematically probing Zwift's anti-cheat thresholds.
///
/// Two modes:
/// - **Power ramp**: Start low, increment power over time. For finding CPC trigger points.
/// - **Lurking probe**: Start at low power, decrement to find minimum "active" threshold.
///
/// Designed for use with `zwift-mem` monitoring to observe flag state changes.
public final class RampTestMode: @unchecked Sendable {

    public enum RampDirection: String, Sendable {
        /// Increasing power to find upper CPC thresholds.
        case ascending
        /// Decreasing power to find lurking threshold.
        case descending
    }

    public struct Config: Sendable {
        public let direction: RampDirection
        /// Starting power in watts.
        public let startPower: Int
        /// Power increment per step (positive for ascending, negative handled automatically for descending).
        public let stepWatts: Int
        /// Duration of each step in seconds.
        public let stepDuration: TimeInterval
        /// Minimum power (for descending ramp).
        public let minPower: Int
        /// Maximum power (for ascending ramp).
        public let maxPower: Int

        public init(direction: RampDirection = .ascending, startPower: Int = 100,
                    stepWatts: Int = 5, stepDuration: TimeInterval = 30,
                    minPower: Int = 0, maxPower: Int = 1000) {
            self.direction = direction; self.startPower = startPower
            self.stepWatts = stepWatts; self.stepDuration = stepDuration
            self.minPower = minPower; self.maxPower = maxPower
        }

        /// Preset for CPC threshold mapping: 100W start, +5W/30s.
        public static let cpcRamp = Config(direction: .ascending, startPower: 100,
                                           stepWatts: 5, stepDuration: 30, maxPower: 1000)

        /// Preset for lurking threshold probe: 50W start, -1W/10s.
        public static let lurkingProbe = Config(direction: .descending, startPower: 50,
                                                stepWatts: 1, stepDuration: 10, minPower: 0)
    }

    public struct Snapshot: Sendable {
        public let currentPower: Int
        public let currentStep: Int
        public let elapsedInStep: TimeInterval
        public let totalElapsed: TimeInterval
        public let isComplete: Bool
    }

    private let config: Config
    private var elapsed: TimeInterval = 0
    private var isRunning = false

    /// Log of (time, power, step) for CSV export.
    private var log: [(time: TimeInterval, power: Int, step: Int)] = []

    public init(config: Config = .cpcRamp) {
        self.config = config
    }

    /// Advance the ramp test by dt seconds.
    /// - Returns: target power in watts and current snapshot
    public func advance(dt: Double) -> (powerWatts: Int, snapshot: Snapshot) {
        if !isRunning { isRunning = true }
        elapsed += dt

        let step = Int(elapsed / config.stepDuration)
        let elapsedInStep = elapsed.truncatingRemainder(dividingBy: config.stepDuration)

        let power: Int
        switch config.direction {
        case .ascending:
            power = min(config.maxPower, config.startPower + step * config.stepWatts)
        case .descending:
            power = max(config.minPower, config.startPower - step * config.stepWatts)
        }

        let isComplete: Bool
        switch config.direction {
        case .ascending: isComplete = power >= config.maxPower
        case .descending: isComplete = power <= config.minPower
        }

        log.append((time: elapsed, power: power, step: step))

        let snapshot = Snapshot(
            currentPower: power, currentStep: step,
            elapsedInStep: elapsedInStep, totalElapsed: elapsed,
            isComplete: isComplete
        )
        return (power, snapshot)
    }

    /// Export log as CSV string.
    public func exportCSV() -> String {
        var csv = "time_s,power_w,step\n"
        for entry in log {
            csv += "\(String(format: "%.1f", entry.time)),\(entry.power),\(entry.step)\n"
        }
        return csv
    }

    /// Reset the ramp test.
    public func reset() {
        elapsed = 0
        isRunning = false
        log.removeAll()
    }
}
