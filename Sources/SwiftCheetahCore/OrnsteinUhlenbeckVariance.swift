import Foundation

/// OrnsteinUhlenbeckVariance - Manages power variation using Ornstein-Uhlenbeck process
///
/// Implements realistic power variations using:
/// - One-pole filters for mean-reverting noise (Ornstein-Uhlenbeck process)
/// - Variance budget allocation across micro, macro, and event components
/// - Proper statistical scaling to achieve target coefficient of variation (CV)
///
/// Theory:
/// - Total variance = sum of independent variances
/// - CV allocation: CV_component = CV_total * sqrt(weight_component)
/// - One-pole filter: dx/dt = -k*x + σ*sqrt(2k)*dW/dt
/// - Steady-state variance: Var(x) = σ²
///
/// References:
/// - Ornstein-Uhlenbeck process for realistic noise generation
/// - Box-Muller transform for normal distribution sampling
public final class OrnsteinUhlenbeckVariance: @unchecked Sendable {

    // MARK: - Properties

    /// Variance budget allocation weights (must sum to 1.0)
    private struct Weights {
        let micro: Double = 0.50   // 50% - High-frequency pedaling variations (0.5-2 Hz)
        let macro: Double = 0.35   // 35% - Low-frequency effort changes (0.02-0.2 Hz)
        let events: Double = 0.15  // 15% - Discrete events (gear shifts, position changes)

        init() {
            let total = micro + macro + events
            assert(abs(total - 1.0) < 0.001, "Variance weights must sum to 1.0, got \(total)")
        }
    }

    private let weights = Weights()

    /// One-pole filter states tracking current value of each noise component
    private var xMicro: Double = 0   // Micro variation state
    private var xMacro: Double = 0   // Macro variation state

    /// Event state management for discrete occurrences
    private var eventActive: Bool = false
    private var eventTimer: Double = 0      // Seconds remaining in current event
    private var eventValue: Double = 0      // Current event magnitude (fraction)

    /// Filter time constants in seconds
    private let tauMicro: Double = 0.167    // ~0.17s time constant (fast variations)
    private let tauMacro: Double = 3.33     // ~3.3s time constant (slow variations)

    /// Thread-safe access
    private let lock = NSLock()

    // MARK: - Initialization

    public init() {
        // Initialize with default values
    }

    // MARK: - Public Methods

    /// Update variance manager and get current power variation
    /// - Parameters:
    ///   - randomness: User setting 0-100 (0=robot, 50=normal, 100=race)
    ///   - targetPower: Target power in watts
    ///   - dt: Time step in seconds
    /// - Returns: Power variation as fraction (-0.2 to +0.2 typically)
    public func update(randomness: Double, targetPower: Double, dt: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }

        // Safeguard against invalid dt
        let safeDt = (dt > 0 && dt <= 10) ? dt : 0.25  // Default to 4Hz

        // Convert randomness to target coefficient of variation
        // 0 = 0% CV (robot mode), 100 = 10% CV (race simulation)
        let cvTarget = randomness / 1000.0

        // Calculate individual component CVs using variance budget
        // CV_component = CV_total * sqrt(weight)
        let cvMicro = cvTarget * sqrt(weights.micro)
        let cvMacro = cvTarget * sqrt(weights.macro)
        let cvEvent = cvTarget * sqrt(weights.events)

        // Update micro variations (high-frequency pedaling noise)
        // Using exponential decay with proper scaling for dt-independence
        // x[n+1] = x[n] * exp(-dt/tau) + sigma * sqrt(1 - exp(-2*dt/tau)) * N(0,1)
        let alphaMicro = exp(-safeDt / tauMicro)
        let noiseMicro = RandomUtility.randn()
        xMicro = xMicro * alphaMicro +
                 cvMicro * sqrt(1 - alphaMicro * alphaMicro) * noiseMicro

        // Update macro variations (low-frequency effort changes)
        // Same exponential decay formula with longer time constant
        let alphaMacro = exp(-safeDt / tauMacro)
        let noiseMacro = RandomUtility.randn()
        xMacro = xMacro * alphaMacro +
                 cvMacro * sqrt(1 - alphaMacro * alphaMacro) * noiseMacro

        // Handle discrete events (Poisson process)
        // Rate increases with randomness: 0.2-2.0 events/minute
        let eventsPerMinute = 0.2 + 1.8 * (randomness / 100.0)
        let lambda = eventsPerMinute / 60.0  // Convert to events per second
        let pEvent = 1.0 - exp(-lambda * safeDt)  // Probability of event in dt

        // Trigger new event if not already active
        if !eventActive && Double.random(in: 0..<1) < pEvent {
            // Event magnitude scales with CV but caps based on power
            // Low power: larger relative variations allowed
            // High power: smaller relative variations (safety)
            let fracCap = min(0.10, 25.0 / max(100.0, targetPower))

            // Sample event value from truncated normal distribution
            eventValue = clampNormal(mean: 0, sd: cvEvent * 2, min: -fracCap, max: fracCap)

            // Event duration: 0.5-2.0 seconds (gear shifts are quick)
            eventTimer = 0.5 + Double.random(in: 0..<1.5)
            eventActive = true
        }

        // Update event timer
        if eventActive {
            eventTimer -= safeDt
            if eventTimer <= 0 {
                eventActive = false
                eventValue = 0
            }
        }

        // Compose total variation from all components
        // Since components are independent, they add linearly
        let totalVariation = xMicro + xMacro + (eventActive ? eventValue : 0)

        // Apply safety clamps to prevent unrealistic values
        // Clamps are power-dependent to maintain realism
        let minFrac = -min(0.20, 60.0 / max(120.0, targetPower))
        let maxFrac = min(0.20, 80.0 / max(120.0, targetPower))

        return max(minFrac, min(maxFrac, totalVariation))
    }

    /// Reset the variance manager to initial state
    /// Useful for testing or when starting a new session
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        xMicro = 0
        xMacro = 0
        eventActive = false
        eventTimer = 0
        eventValue = 0
    }

    /// Get current state for debugging/monitoring
    /// - Returns: Current internal state
    public func getState() -> (micro: Double, macro: Double, event: Double, eventActive: Bool, eventTimer: Double) {
        lock.lock()
        defer { lock.unlock() }

        return (
            micro: xMicro,
            macro: xMacro,
            event: eventActive ? eventValue : 0,
            eventActive: eventActive,
            eventTimer: eventTimer
        )
    }

    // MARK: - Private Methods

    /// Sample from truncated normal distribution
    /// - Parameters:
    ///   - mean: Mean of the distribution
    ///   - sd: Standard deviation
    ///   - min: Minimum allowed value
    ///   - max: Maximum allowed value
    /// - Returns: Clamped sample
    private func clampNormal(mean: Double, sd: Double, min: Double, max: Double) -> Double {
        let value = mean + sd * RandomUtility.randn()
        return Swift.max(min, Swift.min(max, value))
    }
}

// MARK: - Integration with Simulation

extension OrnsteinUhlenbeckVariance {
    /// Apply variance to a base power value
    /// - Parameters:
    ///   - basePower: The target power in watts
    ///   - randomness: Randomness setting (0-100)
    ///   - dt: Time step in seconds
    /// - Returns: Power with realistic variations applied
    public func applyVariance(to basePower: Double, randomness: Double, dt: Double) -> Double {
        let variation = update(randomness: randomness, targetPower: basePower, dt: dt)
        let variedPower = basePower * (1.0 + variation)

        // Final safety bounds
        return max(0, min(2000, variedPower))
    }
}