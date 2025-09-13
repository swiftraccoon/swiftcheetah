import Foundation

/// Estimates cycling power from basic resistive forces (rolling, gravity, aerodynamic).
///
/// Values are intended for live UI display and rough guidance, not scientific analysis.
public struct PhysicsCalculator {
    /// Input parameters for the power estimate.
    public struct Inputs: Sendable {
        /// Rider + bike system speed in meters per second.
        public var speedMetersPerSecond: Double
        /// Road grade as a ratio (e.g. 0.05 for 5%).
        public var slopeGrade: Double
        /// Total mass in kilograms (rider + bike + gear).
        public var massKg: Double
        /// Coefficient of rolling resistance.
        public var crr: Double
        /// Effective frontal area × drag coefficient.
        public var cda: Double
        /// Air density in kg/m^3.
        public var airDensity: Double
        /// Head/tail wind relative to rider in m/s (positive is headwind).
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

    /// Returns the estimated instantaneous power in watts.
    public static func estimatePowerWatts(_ i: Inputs) -> Double {
        let g = 9.80665
        let v = max(0.0, i.speedMetersPerSecond)
        let m = max(0.0, i.massKg)
        let grade = i.slopeGrade
        let normalForce = m * g * cos(atan(grade))
        let rolling = normalForce * i.crr * v
        let climbing = m * g * sin(atan(grade)) * v
        let relWind = v + i.windMetersPerSecond
        let aero = 0.5 * i.airDensity * i.cda * relWind * relWind * v
        let total = rolling + climbing + aero
        return max(0.0, total)
    }
}
