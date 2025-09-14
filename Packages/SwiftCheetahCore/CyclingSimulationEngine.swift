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
    private let validator: ValueValidator

    // Track last update time for delta calculation
    private var lastUpdateTime: TimeInterval

    public init(
        physicsParams: PhysicsCalculator.Parameters = PhysicsCalculator.Parameters()
    ) {
        self.powerManager = PowerManager()
        self.varianceManager = OrnsteinUhlenbeckVariance()
        self.cadenceManager = CadenceManager()
        self.physicsParams = physicsParams
        self.validator = ValueValidator(category: .enthusiast)
        self.lastUpdateTime = Date().timeIntervalSince1970
    }

    /// Update simulation and return current state
    public func update(with input: SimulationInput) -> SimulationState {
        let now = Date().timeIntervalSince1970
        let dt = max(0.001, now - lastUpdateTime)
        lastUpdateTime = now

        // Validate input parameters and clamp critical values to safe limits
        let safePower = validator.clampToSafeLimits(Double(input.targetPower), parameter: "power")
        let safeGrade = validator.clampToSafeLimits(input.gradePercent, parameter: "gradient")
        let safeRandomness = validator.clampToSafeLimits(Double(input.randomness), parameter: "randomness")

        var safeCadence: Double?
        if let manualCadence = input.manualCadence {
            safeCadence = validator.clampToSafeLimits(Double(manualCadence), parameter: "cadence")
        }

        // Log any validation warnings for debugging
        let powerValidation = validator.validatePower(safePower)
        let gradeValidation = validator.validateGradient(safeGrade)
        let randomnessValidation = validator.validateRandomness(Int(safeRandomness))

        if let cadence = safeCadence {
            let cadenceValidation = validator.validateCadence(cadence, power: safePower)
            if !cadenceValidation.isValid {
                ErrorHandler.shared.logValidation(
                    "Cadence validation - \(cadenceValidation.message)",
                    context: [
                        "component": "CyclingSimulationEngine",
                        "originalCadence": "\(input.manualCadence ?? 0)",
                        "validatedCadence": "\(cadence)",
                        "power": "\(safePower)"
                    ]
                )
            }
        }

        if !powerValidation.isValid {
            ErrorHandler.shared.logValidation(
                "Power validation - \(powerValidation.message)",
                context: [
                    "component": "CyclingSimulationEngine",
                    "originalPower": "\(input.targetPower)",
                    "safePower": "\(safePower)"
                ]
            )
        }
        if !gradeValidation.isValid {
            ErrorHandler.shared.logValidation(
                "Grade validation - \(gradeValidation.message)",
                context: [
                    "component": "CyclingSimulationEngine",
                    "originalGrade": "\(input.gradePercent)",
                    "safeGrade": "\(safeGrade)"
                ]
            )
        }
        if !randomnessValidation.isValid {
            ErrorHandler.shared.logValidation(
                "Randomness validation - \(randomnessValidation.message)",
                context: [
                    "component": "CyclingSimulationEngine",
                    "originalRandomness": "\(input.randomness)",
                    "safeRandomness": "\(safeRandomness)"
                ]
            )
        }

        // Calculate power variance using validated values
        let variation = varianceManager.update(
            randomness: safeRandomness,
            targetPower: safePower,
            dt: dt
        )

        // Apply power management (smoothing and variation)
        let realisticWatts = powerManager.update(
            targetPower: Int(safePower),
            cadenceRPM: safeCadence.map { Int($0) } ?? 90,
            variation: variation,
            isResting: input.isResting
        )

        // Calculate speed from power and grade using validated values
        let speedMps = PhysicsCalculator.calculateSpeed(
            powerWatts: Double(realisticWatts),
            gradePercent: safeGrade,
            params: physicsParams
        )

        // Calculate cadence (auto or manual) using validated values
        let cadenceRpm: Int
        if let safeCadence = safeCadence {
            cadenceRpm = Int(safeCadence)
            // Update cadence manager state even in manual mode for gear tracking
            _ = cadenceManager.update(
                power: Double(realisticWatts),
                grade: safeGrade,
                speedMps: speedMps,
                dt: dt
            )
        } else {
            let autoValue = cadenceManager.update(
                power: Double(realisticWatts),
                grade: safeGrade,
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
