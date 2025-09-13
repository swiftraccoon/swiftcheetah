import Foundation

/// CadenceManager
/// Research-backed cadence simulation.
///
/// Behavior overview:
/// - Target cadence follows a logistic (S-curve) relationship with power
///   (Foss & Hallén 2004) transitioning from lowCadence to highCadence
///   around p50 with slope kP.
/// - Grade reduces cadence via a saturating drop (Sassi et al. 2008) with
///   maximum effect maxUphillDrop and scale gScale. Downhill gets a small bump
///   capped by maxDownBump.
/// - Actual cadence is constrained by gear physics: cadenceFromGear maps
///   speed and gear ratio to achievable RPM. Gear selection steps one cog at a time
///   with separate rear/front cooldowns to avoid unrealistic rapid shifts.
/// - High-speed behavior: spin-out and coasting thresholds applied (55/45/35 km/h cases).
/// - Dynamics: first‑order response toward gear cadence; OU‑like jitter for natural variation;
///   slow fatigue accumulation above FTP and recovery below.
public final class CadenceManager: @unchecked Sendable {
    /// Realistic gear set definition (compact 50/34; 11–32 cassette by default).
    public struct Gearset: Sendable {
        public var chainrings: [Int]
        public var cassette: [Int]
        public init(chainrings: [Int] = [50, 34], cassette: [Int] = [11, 12, 13, 14, 16, 18, 20, 22, 25, 28, 32]) {
            self.chainrings = chainrings
            self.cassette = cassette
        }
    }

    /// Rider and model preferences; defaults align with common research-backed values
    /// for economical cadence and gradient effects.
    public struct RiderPrefs: Sendable {
        public var lowCadence: Double
        public var highCadence: Double
        public var p50: Double
        public var kP: Double
        public var maxUphillDrop: Double
        public var gScale: Double
        public var maxDownBump: Double
        public var ftp: Double
        public var wheelCircum: Double
        public init(lowCadence: Double = 75, highCadence: Double = 95, p50: Double = 250, kP: Double = 75,
                    maxUphillDrop: Double = 14, gScale: Double = 6, maxDownBump: Double = 6,
                    ftp: Double = 250, wheelCircum: Double = 2.112) {
            self.lowCadence = lowCadence; self.highCadence = highCadence; self.p50 = p50; self.kP = kP
            self.maxUphillDrop = maxUphillDrop; self.gScale = gScale; self.maxDownBump = maxDownBump
            self.ftp = ftp; self.wheelCircum = wheelCircum
        }
    }

    private let gearset: Gearset
    private let prefs: RiderPrefs

    /// Current cadence (RPM), continuous.
    private(set) public var cadence: Double = 85
    /// Current gear selection (front/rear teeth).
    private(set) public var currentGear: (front: Int, rear: Int)
    private var fatigue: Double = 0
    private var lastRearShift: TimeInterval = 0
    private var lastFrontShift: TimeInterval = 0
    private var noise: Double = 0
    private var lastTarget: Double = 85

    public init(gearset: Gearset = Gearset(), prefs: RiderPrefs = RiderPrefs()) {
        self.gearset = gearset
        self.prefs = prefs
        self.currentGear = (gearset.chainrings.first ?? 50, gearset.cassette[4])
    }

    /// Update cadence state.
    /// - Parameters:
    ///   - power: instantaneous power in watts
    ///   - grade: road gradient in percent (positive uphill)
    ///   - speedMps: current speed in meters/second
    ///   - dt: time step in seconds (0.01–2s recommended)
    /// - Returns: current cadence (RPM)
    public func update(power: Double, grade: Double, speedMps: Double, dt rawDt: Double) -> Double {
        let now = Date().timeIntervalSince1970
        let dt = max(0.01, min(2.0, rawDt))
        // 1) Target cadence from physiology (logistic) + grade adjustments
        let cTarget = targetCadence(power: power, grade: grade)
        lastTarget = cTarget

        // 2) Consider shifting toward gear that meets target
        checkGearShift(cTarget: cTarget, grade: grade, speedMps: speedMps, now: now)

        // 3) Cadence from gear and speed
        var cGear = cadenceFromGear(speedMps: speedMps, front: currentGear.front, rear: currentGear.rear)

        // High-speed handling (spin-out/coast) consistent with observed cycling behavior
        let speedKmh = speedMps * 3.6
        if speedKmh > 55 {
            if power < 150 { cGear = 0 } else { cGear = min(110, cGear) }
        } else if speedKmh > 45 {
            if grade < -5 { cGear = min(100, cGear * 0.6) } else { cGear = min(120, cGear) }
        } else if speedKmh > 35 && grade < -8 {
            cGear = min(90, cGear * 0.7)
        }
        if speedMps < 1.5 { cGear = min(50, cGear) }

        // 4) First-order response to gear cadence
        let tau = 0.8
        let alpha = 1 - exp(-dt / tau)
        cadence = cadence + alpha * (cGear - cadence)

        // 5) Natural jitter (bounded OU-like)
        updateNoise(dt: dt)
        cadence += noise

        // 6) Fatigue slow update
        updateFatigue(power: power, dt: dt)

        cadence = max(0, min(180, cadence))
        if !cadence.isFinite { cadence = 85 }
        return cadence
    }

    /// Logistic power→cadence target + saturating grade effects; bounded 40–120 RPM.
    private func targetCadence(power: Double, grade: Double) -> Double {
        let safeP = max(0, min(2000, power))
        let safeG = max(-30, min(30, grade))
        let cPower = prefs.lowCadence + (prefs.highCadence - prefs.lowCadence) / (1 + exp(-(safeP - prefs.p50)/prefs.kP))
        let dropUp = safeG > 0 ? prefs.maxUphillDrop * (1 - exp(-safeG / prefs.gScale)) : 0
        let bumpDn: Double = (safeG < -3) ? prefs.maxDownBump * (1 - exp(-(abs(safeG) - 3)/3)) : 0
        let fatigueDrop = min(5, fatigue * 5)
        return max(40, min(120, cPower - dropUp + bumpDn - fatigueDrop))
    }

    /// Expose internal state for diagnostics and UI.
    public func getState() -> (cadence: Double, target: Double, gear: (front: Int, rear: Int), fatigue: Double, noise: Double) {
        return (cadence, lastTarget, currentGear, fatigue, noise)
    }

    /// Gear physics: RPM = 60 * speed / circumference * (rear/front).
    /// Clamped to [0, 180]. Returns 0 below ~0.5 m/s.
    private func cadenceFromGear(speedMps: Double, front: Int, rear: Int) -> Double {
        guard speedMps > 0.5, prefs.wheelCircum > 0, front > 0, rear > 0 else { return 0 }
        let raw = (60.0 * speedMps / prefs.wheelCircum) * (Double(rear) / Double(front))
        return max(0, min(180, raw))
    }

    /// Exhaustive search of gearset to find the gear whose cadence matches target best.
    private func selectGear(for cTarget: Double, speedMps: Double) -> (Int, Int)? {
        guard speedMps >= 0.5 else { return nil }
        var best: (front: Int, rear: Int)?
        var bestErr = Double.greatestFiniteMagnitude
        for f in gearset.chainrings {
            for r in gearset.cassette {
                let c = cadenceFromGear(speedMps: speedMps, front: f, rear: r)
                let err = abs(c - cTarget)
                if err < bestErr { bestErr = err; best = (f, r) }
            }
        }
        return best
    }

    /// Step one gear toward the desired target; prefer rear shifts; respect cooldowns.
    private func stepOneGearToward(current: (Int, Int), desired: (Int, Int), now: TimeInterval) -> (Int, Int) {
        let rearIdx = gearset.cassette.firstIndex(of: current.1) ?? 0
        let targetRearIdx = gearset.cassette.firstIndex(of: desired.1) ?? rearIdx
        if abs(targetRearIdx - rearIdx) >= 1 {
            if now - lastRearShift >= 2.0 {
                let step = targetRearIdx > rearIdx ? 1 : -1
                let newIdx = max(0, min(gearset.cassette.count - 1, rearIdx + step))
                lastRearShift = now
                return (current.0, gearset.cassette[newIdx])
            }
            return current
        }
        if desired.0 != current.0 {
            if now - lastFrontShift >= 4.0 {
                lastFrontShift = now
                cadence -= 8 // transient drop
                return (desired.0, current.1)
            }
        }
        return current
    }

    /// Probabilistic shift decision (Poisson-like), influenced by cadence error and grade.
    private func checkGearShift(cTarget: Double, grade: Double, speedMps: Double, now: TimeInterval) {
        let cGear = cadenceFromGear(speedMps: speedMps, front: currentGear.front, rear: currentGear.rear)
        if cGear == 0 || speedMps < 0.5 { return }
        let timeSinceRear = now - lastRearShift
        let timeSinceFront = now - lastFrontShift
        let canRear = timeSinceRear >= 2.0
        let canFront = timeSinceFront >= 4.0
        let cadenceError = abs(cTarget - cGear)
        let baseRate = 1.0 / 60.0
        let errorRate = (cadenceError / 20.0) * (2.0 / 60.0)
        let gradeRate = abs(grade) > 5 ? 1.0 / 60.0 : 0
        let totalRate = baseRate + errorRate + gradeRate
        let pShift = 1 - exp(-totalRate * 0.25) // assume ~4 Hz control internally
        if Double.random(in: 0...1) < pShift {
            if let target = selectGear(for: cTarget, speedMps: speedMps) {
                let next = stepOneGearToward(current: currentGear, desired: target, now: now)
                let isFront = next.0 != currentGear.0
                if (isFront && canFront) || (!isFront && canRear) {
                    currentGear = next
                }
            }
        }
    }

    /// Update OU-like jitter; bounded to ±2 RPM to avoid runaway.
    private func updateNoise(dt: Double) {
        let k = 2.0, sigma = 0.6
        let alpha = exp(-k * dt)
        noise = noise * alpha + sigma * sqrt(1 - alpha * alpha) * randn()
        noise = max(-2, min(2, noise))
    }

    /// Fatigue accumulates above FTP (10 min @110% ≈ +0.1) and recovers with 5 s tau below.
    private func updateFatigue(power: Double, dt: Double) {
        let frac = power / max(1.0, prefs.ftp)
        if frac > 1.0 {
            fatigue += (frac - 1.0) * dt / 600.0
        } else {
            fatigue *= exp(-dt / 300.0)
        }
        fatigue = min(1.0, max(0.0, fatigue))
    }

    private func randn() -> Double {
        let u1 = max(1e-10, Double.random(in: 0...1))
        let u2 = Double.random(in: 0...1)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
