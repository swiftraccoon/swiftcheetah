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
        // FTMS simulation parameters from Zwift (nil = use defaults)
        public let simCrr: Double?
        public let simCw: Double?
        public let simWindSpeedMps: Double?
        // Power profile mode for CPC-aware power capping
        public let powerProfileMode: PowerProfileMode

        public init(
            targetPower: Int,
            manualCadence: Int? = nil,
            gradePercent: Double = 0,
            randomness: Int = 0,
            isResting: Bool = false,
            simCrr: Double? = nil,
            simCw: Double? = nil,
            simWindSpeedMps: Double? = nil,
            powerProfileMode: PowerProfileMode = .uncapped
        ) {
            self.targetPower = targetPower
            self.manualCadence = manualCadence
            self.gradePercent = gradePercent
            self.randomness = randomness
            self.isResting = isResting
            self.simCrr = simCrr
            self.simCw = simCw
            self.simWindSpeedMps = simWindSpeedMps
            self.powerProfileMode = powerProfileMode
        }
    }

    // Internal simulation components
    private let powerManager: PowerManager
    private let varianceManager: OrnsteinUhlenbeckVariance
    private let cadenceManager: CadenceManager
    private let physicsParams: PhysicsCalculator.Parameters
    private let validator: ValueValidator

    // CPC anti-cheat tracking
    private let cpcWindow: CPCSlidingWindow

    // Track last update time for delta calculation
    private var lastUpdateTime: TimeInterval
    // Cached last simulation state for read-only access
    private var lastState: SimulationState?
    // Latest CPC analysis snapshot
    private var lastCPCSnapshot: CPCSlidingWindow.CPCSnapshot?

    public init(
        physicsParams: PhysicsCalculator.Parameters = PhysicsCalculator.Parameters(),
        riderWeightKg: Double = 75.0,
        hasPowerMeter: Bool = true
    ) {
        self.powerManager = PowerManager()
        self.varianceManager = OrnsteinUhlenbeckVariance()
        self.cadenceManager = CadenceManager()
        self.physicsParams = physicsParams
        self.validator = ValueValidator(category: .enthusiast)
        self.cpcWindow = CPCSlidingWindow(weightKg: riderWeightKg, hasPowerMeter: hasPowerMeter)
        self.lastUpdateTime = Date().timeIntervalSince1970
    }

    /// Read-only accessor for the latest CPC analysis snapshot.
    public var cpcStatus: CPCSlidingWindow.CPCSnapshot? { lastCPCSnapshot }

    /// Read-only accessor for the most recent simulation state (avoids mutating update)
    public var currentState: SimulationState {
        return lastState ?? SimulationState(
            powerWatts: 0, speedMps: 0, cadenceRpm: 0,
            fatigue: 0, noise: 0, gear: (front: 50, rear: 16), targetCadence: 85
        )
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
        var realisticWatts = powerManager.update(
            targetPower: Int(safePower),
            cadenceRPM: safeCadence.map { Int($0) } ?? 90,
            variation: variation,
            isResting: input.isResting
        )

        // Apply CPC power profile capping
        if input.powerProfileMode != .uncapped {
            realisticWatts = PowerProfileCapper.apply(
                targetPower: realisticWatts,
                mode: input.powerProfileMode,
                window: cpcWindow,
                weightKg: physicsParams.massKg,
                hasPowerMeter: true
            )
        }

        // Record power in CPC sliding window
        lastCPCSnapshot = cpcWindow.record(powerWatts: Double(realisticWatts), dt: dt)

        // Override physics params with FTMS sim values when present
        var activeParams = physicsParams
        if let crr = input.simCrr, crr > 0 { activeParams.crr = crr }
        if let cw = input.simCw, cw > 0 { activeParams.cda = cw }

        // Calculate speed from power and grade using validated values
        let speedMps = PhysicsCalculator.calculateSpeed(
            powerWatts: Double(realisticWatts),
            gradePercent: safeGrade,
            windSpeedMps: input.simWindSpeedMps ?? 0,
            params: activeParams
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

        let state = SimulationState(
            powerWatts: realisticWatts,
            speedMps: speedMps,
            cadenceRpm: cadenceRpm,
            fatigue: cadenceState.fatigue,
            noise: cadenceState.noise,
            gear: (front: cadenceState.gear.front, rear: cadenceState.gear.rear),
            targetCadence: cadenceState.target
        )
        lastState = state
        return state
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
