import Foundation

public final class PowerVarianceManager: @unchecked Sendable {
    private var xMicro: Double = 0
    private var xMacro: Double = 0
    private var eventActive: Bool = false
    private var eventTimer: Double = 0
    private var eventValue: Double = 0

    private let tauMicro: Double = 0.167
    private let tauMacro: Double = 3.33

    public init() {}

    public func update(randomness: Int, targetPower: Int, dt rawDt: Double) -> Double {
        var dt = rawDt
        if !(dt > 0 && dt <= 10) { dt = 0.25 }

        let cvTotal = Double(randomness) / 1000.0
        let cvMicro = cvTotal * sqrt(0.50)
        let cvMacro = cvTotal * sqrt(0.35)
        let cvEvent = cvTotal * sqrt(0.15)

        let aMicro = exp(-dt / tauMicro)
        xMicro = xMicro * aMicro + cvMicro * sqrt(1 - aMicro * aMicro) * randn()

        let aMacro = exp(-dt / tauMacro)
        xMacro = xMacro * aMacro + cvMacro * sqrt(1 - aMacro * aMacro) * randn()

        let eventsPerMinute = 0.2 + 1.8 * (Double(randomness) / 100.0)
        let lambda = eventsPerMinute / 60.0
        let pEvent = 1.0 - exp(-lambda * dt)
        if !eventActive && Double.random(in: 0...1) < pEvent {
            let fracCap = min(0.10, 25.0 / max(100.0, Double(targetPower)))
            eventValue = clamp(mean: 0, sd: cvEvent * 2, min: -fracCap, max: fracCap)
            eventTimer = 0.5 + Double.random(in: 0...1.5)
            eventActive = true
        }
        if eventActive {
            eventTimer -= dt
            if eventTimer <= 0 { eventActive = false; eventValue = 0 }
        }

        let total = xMicro + xMacro + (eventActive ? eventValue : 0)
        let minFrac = -min(0.20, 60.0 / max(120.0, Double(targetPower)))
        let maxFrac = min(0.20, 80.0 / max(120.0, Double(targetPower)))
        return max(minFrac, min(maxFrac, total))
    }

    private func randn() -> Double {
        let u1 = max(1e-10, Double.random(in: 0...1))
        let u2 = Double.random(in: 0...1)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }

    private func clamp(mean: Double, sd: Double, min: Double, max: Double) -> Double {
        let v = mean + sd * randn()
        return Swift.max(min, Swift.min(max, v))
    }
}

