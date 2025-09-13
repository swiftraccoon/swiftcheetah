import Foundation

/// SpeedFromPower
/// Cycling speed model from power and grade using standard road-cycling physics:
/// oriented gravity component, rolling resistance, aerodynamic drag, and drivetrain efficiency.
/// Includes terminal velocity on descents and an iterative solver for steady-state speed.
public enum SpeedFromPower {
    public struct Params: Sendable {
        public var mass: Double // kg
        public var Crr: Double
        public var CdA: Double
        public var rho: Double
        public var efficiency: Double
        public init(mass: Double = 75, Crr: Double = 0.004, CdA: Double = 0.32, rho: Double = 1.225, efficiency: Double = 0.97) {
            self.mass = mass; self.Crr = Crr; self.CdA = CdA; self.rho = rho; self.efficiency = efficiency
        }
    }

    /// Compute speed from power and grade.
    /// - Parameters:
    ///   - power: rider power in watts (≥ 0)
    ///   - gradePercent: road gradient in percent (−30..+30 typical)
    ///   - params: physical constants (mass, Crr, CdA, rho, drivetrain efficiency)
    /// - Returns: speed in meters per second
    public static func calculateSpeed(power: Double, gradePercent: Double, params: Params = Params()) -> Double {
        let p = max(0, power)
        let g = 9.81
        let safeGrade = max(-30.0, min(30.0, gradePercent))
        let theta = atan(safeGrade / 100.0)
        let effPower = p * params.efficiency

        if safeGrade < -2 {
            let FgPar = -params.mass * g * sin(theta)
            let Froll = params.mass * g * params.Crr * cos(theta)
            let Fnet = FgPar - Froll
            if Fnet > 0 {
                let vTerminal = sqrt(2 * Fnet / (params.CdA * params.rho))
                if effPower <= 10 { return min(30, vTerminal) }
                var v = vTerminal
                for _ in 0..<10 {
                    let Fair = 0.5 * params.CdA * params.rho * v * v
                    let Freq = Fair - FgPar + Froll
                    let Preq = Freq * v
                    let err = effPower - Preq
                    let denom = params.mass * v + params.CdA * params.rho * v * v
                    if denom <= 0 { break }
                    v += (err / denom) * 0.5
                    if abs(err) < 5 { break }
                }
                return min(35, max(vTerminal * 0.8, v))
            }
        }

        var v = effPower > 0 ? sqrt(effPower / (params.CdA * params.rho * 0.5)) : 1
        v = max(1, min(10, v))
        for _ in 0..<15 {
            let Fg = params.mass * g * sin(theta)
            let Froll = params.mass * g * params.Crr * cos(theta)
            let Fair = 0.5 * params.CdA * params.rho * v * v
            let Ftotal = Fg + Froll + Fair
            let Preq = Ftotal * v
            let err = effPower - Preq
            let dPdv = Fg + Froll + 1.5 * params.CdA * params.rho * v * v
            if abs(dPdv) < 0.001 { break }
            let delta = err / dPdv
            v = max(0.1, v + delta)
            if abs(delta) < 0.001 { break }
        }

        var minSpeed = 0.5
        var maxSpeed = 25.0
        if safeGrade > 10 && effPower < 100 { maxSpeed = 5 }
        else if safeGrade < -10 { minSpeed = 5; maxSpeed = 35 }
        let finalV = max(minSpeed, min(maxSpeed, v))
        return finalV.isFinite ? finalV : 5
    }
}
