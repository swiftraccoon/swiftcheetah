import Foundation
import Combine
#if SWIFT_PACKAGE
import SwiftCheetahCore
#endif

/// SimulationStateManager - Centralized state management for cycling simulation
///
/// This class consolidates all the @Published properties and configuration state
/// that were previously scattered throughout PeripheralManager.
public final class SimulationStateManager: ObservableObject {

    // MARK: - Broadcast State
    @Published public var state: BroadcastState = .idle
    @Published public var isAdvertising: Bool = false
    @Published public var subscriberCount: Int = 0
    @Published public var lastError: String?
    @Published public var eventLog: [String] = []

    // MARK: - Simulation Parameters
    @Published public var watts: Int = 250
    @Published public var cadenceRpm: Int = 90
    @Published public var speedMps: Double = 8.33
    @Published public var gradePercent: Double = 0.0
    @Published public var randomness: Int = 0  // 0-100
    @Published public var increment: Int = 25  // power step for UI controls

    // MARK: - Mode Configuration
    @Published public var cadenceMode: CadenceMode = .auto
    @Published public var localName: String = "Trainer"

    // MARK: - Service Configuration
    @Published public var advertiseFTMS: Bool = true
    @Published public var advertiseCPS: Bool = false
    @Published public var advertiseRSC: Bool = false

    // MARK: - Field Toggles
    @Published public var cpsIncludePower: Bool = true
    @Published public var cpsIncludeCadence: Bool = true
    @Published public var cpsIncludeSpeed: Bool = true  // wheel speed
    @Published public var ftmsIncludePower: Bool = true
    @Published public var ftmsIncludeCadence: Bool = true

    // MARK: - Live Statistics
    @Published public var liveStats: LiveStats

    // MARK: - Validation
    private let validator: ValueValidator

    // MARK: - Types

    public enum BroadcastState: String, Sendable {
        case idle
        case starting
        case advertising
        case stopped
        case failed
    }

    public enum CadenceMode: String, Sendable {
        case auto
        case manual
    }

    public struct LiveStats: Sendable {
        public var speedKmh: Double
        public var powerW: Int
        public var cadenceRpm: Int
        public var mode: String
        public var gear: String
        public var targetCadence: Int
        public var fatigue: Double
        public var noise: Double
        public var gradePercent: Double

        public init(
            speedKmh: Double = 25.0,
            powerW: Int = 250,
            cadenceRpm: Int = 90,
            mode: String = "AUTO",
            gear: String = "2x5",
            targetCadence: Int = 90,
            fatigue: Double = 0,
            noise: Double = 0,
            gradePercent: Double = 0
        ) {
            self.speedKmh = speedKmh
            self.powerW = powerW
            self.cadenceRpm = cadenceRpm
            self.mode = mode
            self.gear = gear
            self.targetCadence = targetCadence
            self.fatigue = fatigue
            self.noise = noise
            self.gradePercent = gradePercent
        }
    }

    public struct ServiceOptions: Sendable {
        public var advertiseFTMS: Bool
        public var advertiseCPS: Bool
        public var advertiseRSC: Bool

        public init(
            advertiseFTMS: Bool = true,
            advertiseCPS: Bool = true,
            advertiseRSC: Bool = true
        ) {
            self.advertiseFTMS = advertiseFTMS
            self.advertiseCPS = advertiseCPS
            self.advertiseRSC = advertiseRSC
        }
    }

    // MARK: - Initialization

    public init() {
        self.liveStats = LiveStats()
        self.validator = ValueValidator(category: .enthusiast)
    }

    // MARK: - Event Logging

    public func log(_ message: String) {
        // Maintain backward compatibility with eventLog
        eventLog.append(message)
        if eventLog.count > 200 {
            eventLog.removeFirst(eventLog.count - 200)
        }

        // Also log to standardized error handler for debugging
        ErrorHandler.shared.logValidation(message, context: ["component": "SimulationStateManager"])
    }

    public func clearEventLog() {
        eventLog.removeAll()
    }

    // MARK: - State Updates

    public func updateLiveStats(from simulationState: CyclingSimulationEngine.SimulationState) {
        liveStats = LiveStats(
            speedKmh: simulationState.speedMps * 3.6,
            powerW: simulationState.powerWatts,
            cadenceRpm: simulationState.cadenceRpm,
            mode: cadenceMode == .auto ? "AUTO" : "MANUAL",
            gear: "\(simulationState.gear.front)x\(simulationState.gear.rear)",
            targetCadence: Int(simulationState.targetCadence.rounded()),
            fatigue: simulationState.fatigue,
            noise: simulationState.noise,
            gradePercent: gradePercent
        )
    }

    public func setError(_ error: String?) {
        lastError = error
    }

    public func getServiceOptions() -> ServiceOptions {
        return ServiceOptions(
            advertiseFTMS: advertiseFTMS,
            advertiseCPS: advertiseCPS,
            advertiseRSC: advertiseRSC
        )
    }

    public func updateFromControlState(_ controlState: FTMSControlPointHandler.ControlState) {
        // Validate and set values using validator
        setValidatedGradePercent(controlState.gradePercent)
        setValidatedWatts(controlState.targetPower)
    }

    // MARK: - Validation Methods

    /// Validate and set watts value with logging
    public func setValidatedWatts(_ newWatts: Int) {
        let validation = validator.validatePower(Double(newWatts))
        if !validation.isValid {
            log("Power validation: \(validation.message)")
        }

        // Clamp to safe limits to prevent system instability
        let safeWatts = Int(validator.clampToSafeLimits(Double(newWatts), parameter: "power"))
        watts = safeWatts

        if safeWatts != newWatts {
            log("Power clamped from \(newWatts)W to \(safeWatts)W")
        }
    }

    /// Validate and set cadence with logging
    public func setValidatedCadenceRpm(_ newCadence: Int) {
        let validation = validator.validateCadence(Double(newCadence), power: Double(watts))
        if !validation.isValid {
            log("Cadence validation: \(validation.message)")
        }

        let safeCadence = Int(validator.clampToSafeLimits(Double(newCadence), parameter: "cadence"))
        cadenceRpm = safeCadence

        if safeCadence != newCadence {
            log("Cadence clamped from \(newCadence) RPM to \(safeCadence) RPM")
        }
    }

    /// Validate and set grade percent with logging
    public func setValidatedGradePercent(_ newGrade: Double) {
        let validation = validator.validateGradient(newGrade)
        if !validation.isValid {
            log("Grade validation: \(validation.message)")
        }

        let safeGrade = validator.clampToSafeLimits(newGrade, parameter: "gradient")
        gradePercent = safeGrade

        if abs(safeGrade - newGrade) > 0.001 {
            log("Grade clamped from \(newGrade)% to \(safeGrade)%")
        }
    }

    /// Validate and set randomness with logging
    public func setValidatedRandomness(_ newRandomness: Int) {
        let validation = validator.validateRandomness(newRandomness)
        if !validation.isValid {
            log("Randomness validation: \(validation.message)")
        }

        let safeRandomness = Int(validator.clampToSafeLimits(Double(newRandomness), parameter: "randomness"))
        randomness = safeRandomness

        if safeRandomness != newRandomness {
            log("Randomness clamped from \(newRandomness) to \(safeRandomness)")
        }
    }

    /// Validate complete simulation state
    public func validateCurrentState() -> [ValueValidator.ValidationResult] {
        return validator.validateSimulationState(
            power: Double(watts),
            speed: speedMps,
            cadence: Double(cadenceRpm),
            grade: gradePercent,
            randomness: randomness
        )
    }
}
