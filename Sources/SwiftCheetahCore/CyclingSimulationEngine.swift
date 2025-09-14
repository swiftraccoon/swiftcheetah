import Foundation

/// CyclingSimulationEngine - Encapsulates all cycling physics and simulation logic
///
/// This class consolidates power management, variance, cadence, and physics calculations
/// that were previously scattered throughout PeripheralManager. It provides a clean
/// interface for cycling simulation without any BLE dependencies.
public final class CyclingSimulationEngine: @unchecked Sendable {

    /// Simulation output data
    public struct SimulationState: Sendable {
        public let powerWatts: Int
        public let speedMps: Double
        public let cadenceRpm: Int
        public let fatigue: Double
        public let noise: Double
        public let gear: (front: Int, rear: Int)
        public let targetCadence: Double
    }

    /// Simulation input parameters
    public struct SimulationInput: Sendable {
        public let targetPower: Int
        public let manualCadence: Int?  // nil for auto mode
        public let gradePercent: Double
        public let randomness: Int  // 0-100
        public let isResting: Bool

        public init(
            targetPower: Int,
            manualCadence: Int? = nil,
            gradePercent: Double = 0,
            randomness: Int = 0,
            isResting: Bool = false
        ) {
            self.targetPower = targetPower
            self.manualCadence = manualCadence
            self.gradePercent = gradePercent
            self.randomness = randomness
            self.isResting = isResting
        }
    }

    // Internal simulation components
    private let powerManager: PowerManager
    private let varianceManager: OrnsteinUhlenbeckVariance
    private let cadenceManager: CadenceManager
    private let physicsParams: PhysicsCalculator.Parameters

    // Track last update time for delta calculation
    private var lastUpdateTime: TimeInterval

    public init(
        physicsParams: PhysicsCalculator.Parameters = PhysicsCalculator.Parameters()
    ) {
        self.powerManager = PowerManager()
        self.varianceManager = OrnsteinUhlenbeckVariance()
        self.cadenceManager = CadenceManager()
        self.physicsParams = physicsParams
        self.lastUpdateTime = Date().timeIntervalSince1970
    }

    /// Update simulation and return current state
    public func update(with input: SimulationInput) -> SimulationState {
        let now = Date().timeIntervalSince1970
        let dt = max(0.001, now - lastUpdateTime)
        lastUpdateTime = now

        // Calculate power variance
        let variation = varianceManager.update(
            randomness: Double(input.randomness),
            targetPower: Double(input.targetPower),
            dt: dt
        )

        // Apply power management (smoothing and variation)
        let realisticWatts = powerManager.update(
            targetPower: input.targetPower,
            cadenceRPM: input.manualCadence ?? 90,
            variation: variation,
            isResting: input.isResting
        )

        // Calculate speed from power and grade
        let speedMps = PhysicsCalculator.calculateSpeed(
            powerWatts: Double(realisticWatts),
            gradePercent: input.gradePercent,
            params: physicsParams
        )

        // Calculate cadence (auto or manual)
        let cadenceRpm: Int
        if let manual = input.manualCadence {
            cadenceRpm = manual
            // Update cadence manager state even in manual mode for gear tracking
            _ = cadenceManager.update(
                power: Double(realisticWatts),
                grade: input.gradePercent,
                speedMps: speedMps,
                dt: dt
            )
        } else {
            let autoValue = cadenceManager.update(
                power: Double(realisticWatts),
                grade: input.gradePercent,
                speedMps: speedMps,
                dt: dt
            )
            cadenceRpm = Int(autoValue.rounded())
        }

        // Get current cadence manager state
        let cadenceState = cadenceManager.getState()

        return SimulationState(
            powerWatts: realisticWatts,
            speedMps: speedMps,
            cadenceRpm: cadenceRpm,
            fatigue: cadenceState.fatigue,
            noise: cadenceState.noise,
            gear: (front: cadenceState.gear.front, rear: cadenceState.gear.rear),
            targetCadence: cadenceState.target
        )
    }

    /// Reset simulation to initial state
    public func reset() {
        lastUpdateTime = Date().timeIntervalSince1970
        // Components maintain their own state and will reset naturally
    }

    /// Get current simulation parameters for inspection
    public func getPhysicsParameters() -> PhysicsCalculator.Parameters {
        return physicsParams
    }
}