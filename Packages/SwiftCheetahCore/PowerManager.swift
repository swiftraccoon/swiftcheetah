import Foundation

public final class PowerManager: @unchecked Sendable {
    public struct Options: Sendable {
        public var powerImbalance: Double
        public var torqueVariation: Double
        public var trainerTau: Double
        public var maxImbalance: Double
        public var displayWindowMs: Int
        public init(powerImbalance: Double = 0.02, torqueVariation: Double = 0.20, trainerTau: Double = 3.0, maxImbalance: Double = 0.10, displayWindowMs: Int = 3000) {
            self.powerImbalance = powerImbalance
            self.torqueVariation = torqueVariation
            self.trainerTau = trainerTau
            self.maxImbalance = maxImbalance
            self.displayWindowMs = displayWindowMs
        }
    }

    private var pedalAngle: Double = 0
    private var powerImbalance: Double
    private var controlPower: Double = 0
    private var lastUpdate: TimeInterval = Date().timeIntervalSince1970
    private var displayBuffer: [(t: TimeInterval, v: Double)] = []
    private var smoothedPower: Double = 0
    private let opt: Options

    public init(options: Options = Options()) {
        self.opt = options
        self.powerImbalance = min(max(-options.maxImbalance, options.powerImbalance), options.maxImbalance)
    }

    public func update(targetPower: Int, cadenceRPM: Int, variation: Double, isResting: Bool) -> Int {
        if isResting { smoothedPower = 0; controlPower = 0; displayBuffer.removeAll(); return 0 }
        let now = Date().timeIntervalSince1970
        let dt = min(1.0, max(0.0, now - lastUpdate))
        lastUpdate = now

        let safePower = max(0.0, min(2500.0, Double(targetPower)))
        let safeCad = max(0.0, min(200.0, Double(cadenceRPM)))

        if safeCad > 0 {
            pedalAngle.formTruncatingRemainder(dividingBy: 360.0)
            pedalAngle += (safeCad * 360.0 * dt / 60.0)
            if pedalAngle >= 360.0 { pedalAngle -= 360.0 }
        }

        let torqueMult = 1.0 + opt.torqueVariation * sin(pedalAngle * .pi / 180.0)
        let imbalanceMult = pedalAngle < 180.0 ? (1.0 + powerImbalance) : (1.0 - powerImbalance)

        var inst = safePower * torqueMult * imbalanceMult
        inst *= (1.0 + variation)

        let alpha = 1.0 - exp(-dt / opt.trainerTau)
        controlPower = alpha * inst + (1.0 - alpha) * controlPower

        displayBuffer.append((now, controlPower))
        let cutoff = now - Double(opt.displayWindowMs) / 1000.0
        displayBuffer.removeAll { $0.t < cutoff }
        if displayBuffer.isEmpty {
            smoothedPower = controlPower
        } else {
            smoothedPower = displayBuffer.reduce(0) { $0 + $1.v } / Double(displayBuffer.count)
        }

        return max(0, Int(controlPower.rounded()))
    }

    public func getSmoothedPower() -> Int { Int(smoothedPower.rounded()) }
}
