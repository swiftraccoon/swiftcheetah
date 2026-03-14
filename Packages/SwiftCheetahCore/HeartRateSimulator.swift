import Foundation

/// Simulates realistic heart rate response to cycling power output.
///
/// Model: HR lags power with ~30s time constant, drifts upward during sustained
/// effort above FTP (cardiac drift), and recovers exponentially when power drops.
public final class HeartRateSimulator: @unchecked Sendable {

    public struct Config: Sendable {
        public var restingHR: Double
        public var maxHR: Double
        public var ftp: Double
        public var lagTau: Double       // first-order lag time constant (seconds)
        public var driftRate: Double    // bpm/min above FTP

        public init(
            restingHR: Double = 60,
            maxHR: Double = 190,
            ftp: Double = 250,
            lagTau: Double = 30,
            driftRate: Double = 0.5
        ) {
            self.restingHR = restingHR
            self.maxHR = maxHR
            self.ftp = ftp
            self.lagTau = lagTau
            self.driftRate = driftRate
        }
    }

    private let config: Config
    private var currentHR: Double
    private var driftAccumulator: Double = 0

    public init(config: Config = Config()) {
        self.config = config
        self.currentHR = config.restingHR
    }

    /// Target HR from power using a linear model capped to [resting, max].
    private func targetHR(power: Double) -> Double {
        let intensity = power / max(1, config.ftp)
        // At FTP (intensity=1.0), HR is ~85% of max; at rest, HR is resting
        let hrRange = config.maxHR - config.restingHR
        let raw = config.restingHR + intensity * hrRange * 0.85
        return max(config.restingHR, min(config.maxHR, raw))
    }

    /// Update heart rate based on current power output.
    /// - Parameters:
    ///   - power: instantaneous power in watts
    ///   - dt: time step in seconds
    /// - Returns: current heart rate in bpm (integer)
    public func update(power: Double, dt: Double) -> Int {
        let dt = max(0.01, min(5.0, dt))
        let target = targetHR(power: power)

        // First-order lag toward target
        let alpha = 1 - exp(-dt / config.lagTau)
        currentHR += alpha * (target - currentHR)

        // Cardiac drift: accumulates above FTP
        let intensity = power / max(1, config.ftp)
        if intensity > 1.0 {
            driftAccumulator += config.driftRate * (intensity - 1.0) * (dt / 60.0)
        } else {
            // Drift recovers slowly below FTP
            driftAccumulator *= exp(-dt / 120.0)
        }
        driftAccumulator = min(15, max(0, driftAccumulator))

        let finalHR = min(config.maxHR, currentHR + driftAccumulator)
        return Int(max(config.restingHR, finalHR).rounded())
    }

    /// Reset to resting state
    public func reset() {
        currentHR = config.restingHR
        driftAccumulator = 0
    }
}
