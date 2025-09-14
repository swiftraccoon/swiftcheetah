import Foundation

/// PhysicsCalculator - Calculate cycling speed from power, grade, and environmental factors
///
/// Uses standard cycling physics equations with Newton-Raphson solver for accurate speed calculation.
/// This provides realistic simulation of cycling dynamics including special handling for descents
/// and terminal velocity calculations.
///
/// References:
/// - Martin et al. (1998): "Validation of a Mathematical Model for Road Cycling Power"
/// - Foss, Ø., & Hallén, J. (2004): "The most economical cadence increases with increasing workload"
/// - https://www.gribble.org/cycling/power_v_speed.html
public struct PhysicsCalculator {

    // MARK: - Physical Constants
    private static let gravity: Double = 9.81  // m/s²

    // MARK: - Parameters

    /// Physical parameters for cycling simulation
    public struct Parameters: Sendable {
        /// Total mass in kilograms (rider + bike + gear)
        public var massKg: Double
        /// Coefficient of rolling resistance (typical: 0.004 for road, 0.008 for gravel)
        public var crr: Double
        /// Effective frontal area × drag coefficient (typical: 0.28-0.35 m²)
        public var cda: Double
        /// Air density in kg/m³ (typical: 1.225 at sea level)
        public var airDensity: Double
        /// Drivetrain efficiency (typical: 0.95-0.98)
        public var efficiency: Double

        public init(
            massKg: Double = 75.0,
            crr: Double = 0.004,
            cda: Double = 0.32,
            airDensity: Double = 1.225,
            efficiency: Double = 0.97
        ) {
            self.massKg = massKg
            self.crr = crr
            self.cda = cda
            self.airDensity = airDensity
            self.efficiency = efficiency
        }
    }

    // MARK: - Speed Calculation (Newton-Raphson)

    /// Calculate speed from power using Newton-Raphson iterative solver
    /// - Parameters:
    ///   - powerWatts: Power output in watts
    ///   - gradePercent: Grade in percent (positive = uphill, negative = downhill)
    ///   - params: Physical parameters
    /// - Returns: Speed in meters per second
    public static func calculateSpeed(
        powerWatts: Double,
        gradePercent: Double,
        params: Parameters = Parameters()
    ) -> Double {
        // Validate and clamp inputs
        let safePower = max(0, min(2000, powerWatts.isFinite ? powerWatts : 0))
        let safeGrade = max(-30, min(30, gradePercent.isFinite ? gradePercent : 0))

        // Convert grade from percent to decimal
        let gradeDecimal = safeGrade / 100.0

        // Effective power after drivetrain losses
        let effectivePower = safePower * params.efficiency

        // Special handling for steep descents - calculate terminal velocity
        if safeGrade < -2 {
            return calculateDescentSpeed(
                effectivePower: effectivePower,
                gradeDecimal: gradeDecimal,
                params: params
            )
        }

        // For climbs and moderate grades, use Newton-Raphson solver
        return newtonRaphsonSolver(
            effectivePower: effectivePower,
            gradeDecimal: gradeDecimal,
            params: params
        )
    }

    /// Newton-Raphson iterative solver for speed calculation
    private static func newtonRaphsonSolver(
        effectivePower: Double,
        gradeDecimal: Double,
        params: Parameters
    ) -> Double {
        // Better initial guess based on power (assuming flat ground)
        var v = effectivePower > 0 ? sqrt(effectivePower / (params.cda * params.airDensity * 0.5)) : 1.0
        v = max(1.0, min(10.0, v))  // Reasonable starting point (3.6-36 km/h)

        // Newton-Raphson iterations
        for _ in 0..<15 {
            // Use proper angle for grade (not small angle approximation)
            let theta = atan(gradeDecimal)

            // Forces at current speed
            let F_gravity = params.massKg * gravity * sin(theta)  // Uphill component
            let F_rolling = params.massKg * gravity * params.crr * cos(theta)
            let F_air = 0.5 * params.cda * params.airDensity * v * v

            // Total resistive force
            let F_total = F_gravity + F_rolling + F_air

            // Power required at this speed
            let P_required = F_total * v

            // Error between available and required power
            let error = effectivePower - P_required

            // Jacobian (derivative of power with respect to speed)
            let dP_dv = F_gravity + F_rolling + 1.5 * params.cda * params.airDensity * v * v

            // Avoid division by zero
            if abs(dP_dv) < 0.001 { break }

            // Update speed estimate
            let delta = error / dP_dv
            v += delta

            // Keep speed positive
            v = max(0.1, v)

            // Convergence check
            if abs(delta) < 0.001 { break }
        }

        // Apply realistic bounds based on conditions
        return applySpeedBounds(speed: v, grade: gradeDecimal * 100, power: effectivePower)
    }

    /// Calculate speed on descents with terminal velocity consideration
    private static func calculateDescentSpeed(
        effectivePower: Double,
        gradeDecimal: Double,
        params: Parameters
    ) -> Double {
        // Use proper trigonometry for forces on descent
        let theta = atan(gradeDecimal)

        // Component of gravity along the slope (negative = downhill)
        let F_gravity_parallel = -params.massKg * gravity * sin(theta)

        // Rolling resistance (always opposes motion)
        let F_rolling = params.massKg * gravity * params.crr * cos(theta)

        // Net driving force without pedaling
        let F_net = F_gravity_parallel - F_rolling

        guard F_net > 0 else {
            // Not steep enough for terminal velocity, use standard solver
            return newtonRaphsonSolver(
                effectivePower: effectivePower,
                gradeDecimal: gradeDecimal,
                params: params
            )
        }

        // Calculate terminal velocity where air drag balances net force
        let v_terminal = sqrt(2 * F_net / (params.cda * params.airDensity))

        // Pure coasting (very low power)
        if effectivePower <= 10 {
            return min(30, v_terminal)  // Cap at 108 km/h
        }

        // With power on descent, iterate from terminal velocity
        var v = v_terminal

        for _ in 0..<10 {
            let F_air = 0.5 * params.cda * params.airDensity * v * v
            let F_required = F_air - F_gravity_parallel + F_rolling
            let P_required = F_required * v

            let error = effectivePower - P_required

            // Damped adjustment to prevent oscillation
            let adjustment = error / (params.massKg * v + params.cda * params.airDensity * v * v)
            v += adjustment * 0.5

            if abs(error) < 5 { break }
        }

        // Reasonable bounds for descent
        return min(35, max(v_terminal * 0.8, v))  // 80% of terminal to 126 km/h
    }

    /// Apply realistic speed bounds based on conditions
    private static func applySpeedBounds(speed: Double, grade: Double, power: Double) -> Double {
        var minSpeed = 0.5   // 1.8 km/h - trackstand speed
        var maxSpeed = 25.0  // 90 km/h - high but safe max

        // Adjust bounds based on grade and power
        if grade > 10 && power < 100 {
            maxSpeed = 5  // Very slow on steep climbs with low power
        } else if grade < -10 {
            minSpeed = 5   // Minimum 18 km/h on steep descents
            maxSpeed = 35  // Up to 126 km/h on very steep descents
        }

        let finalSpeed = max(minSpeed, min(maxSpeed, speed))

        // Final safety check
        if !finalSpeed.isFinite {
            return 5.0  // Default to moderate speed if calculation fails
        }

        return finalSpeed
    }

    // MARK: - Power Calculation (Inverse)

    /// Calculate the power required to maintain a given speed
    /// - Parameters:
    ///   - speedMps: Target speed in meters per second
    ///   - gradePercent: Grade in percent
    ///   - params: Physical parameters
    /// - Returns: Required power in watts
    public static func calculatePowerRequired(
        speedMps: Double,
        gradePercent: Double,
        params: Parameters = Parameters()
    ) -> Double {
        let gradeDecimal = gradePercent / 100.0
        let theta = atan(gradeDecimal)

        // Calculate forces using proper trigonometry
        let F_gravity = params.massKg * gravity * sin(theta)
        let F_rolling = params.massKg * gravity * params.crr * cos(theta)
        let F_air = 0.5 * params.cda * params.airDensity * speedMps * speedMps

        // Total power required
        let powerRequired = (F_gravity + F_rolling + F_air) * speedMps

        // Account for drivetrain efficiency
        return max(0, powerRequired / params.efficiency)
    }

    // MARK: - Legacy Interface (for backward compatibility)

    /// Input parameters for the power estimate (legacy interface)
    public struct Inputs: Sendable {
        public var speedMetersPerSecond: Double
        public var slopeGrade: Double
        public var massKg: Double
        public var crr: Double
        public var cda: Double
        public var airDensity: Double
        public var windMetersPerSecond: Double

        public init(
            speedMetersPerSecond: Double,
            slopeGrade: Double,
            massKg: Double,
            crr: Double = 0.005,
            cda: Double = 0.3,
            airDensity: Double = 1.225,
            windMetersPerSecond: Double = 0.0
        ) {
            self.speedMetersPerSecond = speedMetersPerSecond
            self.slopeGrade = slopeGrade
            self.massKg = massKg
            self.crr = crr
            self.cda = cda
            self.airDensity = airDensity
            self.windMetersPerSecond = windMetersPerSecond
        }
    }

    /// Returns the estimated instantaneous power in watts (legacy interface)
    public static func estimatePowerWatts(_ i: Inputs) -> Double {
        let params = Parameters(
            massKg: i.massKg,
            crr: i.crr,
            cda: i.cda,
            airDensity: i.airDensity
        )

        // Convert slope grade to percent (if it's a ratio, multiply by 100)
        let gradePercent = i.slopeGrade * 100

        // Account for wind in effective speed
        let effectiveSpeed = i.speedMetersPerSecond + i.windMetersPerSecond

        return calculatePowerRequired(
            speedMps: effectiveSpeed,
            gradePercent: gradePercent,
            params: params
        )
    }

    // MARK: - Unit Conversions

    public struct SpeedConversions {
        public static func mpsToKmh(_ mps: Double) -> Double { mps * 3.6 }
        public static func kmhToMps(_ kmh: Double) -> Double { kmh / 3.6 }
        public static func mpsToMph(_ mps: Double) -> Double { mps * 2.237 }
        public static func mphToMps(_ mph: Double) -> Double { mph / 2.237 }
    }
}
