import Foundation
import CoreBluetooth

/// FTMSControlPointHandler - Handles FTMS Control Point commands
///
/// This class encapsulates the logic for processing FTMS Control Point commands
/// that were previously embedded in PeripheralManager. It follows the Strategy
/// pattern to handle 20+ different control commands.
public final class FTMSControlPointHandler {

    /// Control state
    public struct ControlState {
        public var hasControl: Bool = true
        public var isStarted: Bool = true
        public var targetPower: Int = 250
        public var simWindSpeedMps: Double = 0
        public var simCrr: Double = 0.004
        public var simCw: Double = 0.51
        public var gradePercent: Double = 0

        public init(
            hasControl: Bool = true,
            isStarted: Bool = true,
            targetPower: Int = 250,
            simWindSpeedMps: Double = 0,
            simCrr: Double = 0.004,
            simCw: Double = 0.51,
            gradePercent: Double = 0
        ) {
            self.hasControl = hasControl
            self.isStarted = isStarted
            self.targetPower = targetPower
            self.simWindSpeedMps = simWindSpeedMps
            self.simCrr = simCrr
            self.simCw = simCw
            self.gradePercent = gradePercent
        }
    }

    /// Command result
    public struct CommandResult {
        public let command: Opcode?
        public let response: Data?
        public let status: Data?
        public let statusDelay: TimeInterval
        public let logMessage: String
        public let stateUpdate: ((inout ControlState) -> Void)?
    }

    // FTMS Control Point Opcodes (per FTMS specification)
    public enum Opcode: UInt8 {
        case requestControl = 0x00
        case reset = 0x01
        case setTargetSpeed = 0x02
        case setTargetInclination = 0x03
        case setTargetResistanceLevel = 0x04
        case setTargetPower = 0x05
        case setTargetHeartRate = 0x06
        case startOrResume = 0x07
        case stopOrPause = 0x08
        case setTargetedExpendedEnergy = 0x09
        case setTargetedNumberOfSteps = 0x0A
        case setTargetedNumberOfStrides = 0x0B
        case setTargetedDistance = 0x0C
        case setTargetedTrainingTime = 0x0D
        case setTargetedTimeInTwoHeartRateZones = 0x0E
        case setTargetedTimeInThreeHeartRateZones = 0x0F
        case setTargetedTimeInFiveHeartRateZones = 0x10
        case setIndoorBikeSimulation = 0x11
        case setWheelCircumference = 0x12
        case spinDownControl = 0x13
        case setTargetedCadence = 0x14
    }

    // Response Codes
    private let responseCode: UInt8 = 0x80
    private let success: UInt8 = 0x01
    private let opCodeNotSupported: UInt8 = 0x02
    private let invalidParameter: UInt8 = 0x03
    private let controlNotPermitted: UInt8 = 0x05

    // Status notification codes (per FTMS specification)
    private enum StatusCode: UInt8 {
        case reset = 0x01
        case stoppedOrPaused = 0x02
        case startedOrResumed = 0x04
        case targetPowerChanged = 0x08
        case targetSpeedChanged = 0x10
        case targetInclineChanged = 0x11
        case indoorBikeSimulationParametersChanged = 0x12
        case wheelCircumferenceChanged = 0x13
        case spinDownStarted = 0x14
        case spinDownIgnored = 0x15
        case targetCadenceChanged = 0x16
    }

    private var state: ControlState

    public init(initialState: ControlState = ControlState()) {
        self.state = initialState
    }

    /// Get current control state
    public func getState() -> ControlState {
        return state
    }

    /// Update control state
    public func setState(_ newState: ControlState) {
        self.state = newState
    }

    /// Process FTMS Control Point command
    public func handleCommand(_ data: Data) -> CommandResult {
        guard data.count >= 1 else {
            return CommandResult(
                command: nil,
                response: nil,
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: Invalid command data",
                stateUpdate: nil
            )
        }

        let opcodeValue = data[0]
        guard let opcode = Opcode(rawValue: opcodeValue) else {
            return handleUnknownOpcode(opcodeValue)
        }

        switch opcode {
        case .requestControl:
            return handleRequestControl()

        case .reset:
            return handleReset()

        case .setTargetPower:
            return handleSetTargetPower(data)

        case .startOrResume:
            return handleStartOrResume()

        case .stopOrPause:
            return handleStopOrPause()

        case .setIndoorBikeSimulation:
            return handleSetIndoorBikeSimulation(data)

        case .spinDownControl:
            return handleSpinDownControl(data)

        case .setTargetSpeed:
            return handleSetTargetSpeed(data)

        case .setTargetInclination:
            return handleSetTargetInclination(data)

        case .setWheelCircumference:
            return handleSetWheelCircumference(data)

        case .setTargetedCadence:
            return handleSetTargetedCadence(data)

        case .setTargetResistanceLevel:
            return handleSetTargetResistanceLevel(data)

        default:
            return handleUnsupportedOpcode(opcodeValue)
        }
    }

    // MARK: - Command Handlers

    private func handleRequestControl() -> CommandResult {
        let response = createResponse(.requestControl, success)
        let message = state.hasControl ?
            "FTMS: RequestControl -> success (already had control)" :
            "FTMS: RequestControl -> success"

        return CommandResult(
            command: .requestControl,
            response: response,
            status: nil,
            statusDelay: 0,
            logMessage: message,
            stateUpdate: { $0.hasControl = true }
        )
    }

    private func handleReset() -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .reset,
                response: createResponse(.reset, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: Reset -> control not permitted",
                stateUpdate: nil
            )
        }

        return CommandResult(
            command: .reset,
            response: createResponse(.reset, success),
            status: Data([StatusCode.reset.rawValue]),
            statusDelay: 0.5,
            logMessage: "FTMS: Reset -> success",
            stateUpdate: { state in
                state.hasControl = false
                state.isStarted = false
                // Removed: state.targetPower = 0 to prevent overwriting user's watts
            }
        )
    }

    private func handleSetTargetPower(_ data: Data) -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .setTargetPower,
                response: createResponse(.setTargetPower, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetPower -> control not permitted",
                stateUpdate: nil
            )
        }

        guard data.count >= 3 else {
            return CommandResult(
                command: .setTargetPower,
                response: createResponse(.setTargetPower, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetPower -> invalid data length",
                stateUpdate: nil
            )
        }

        let targetPower = Int(Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8)))

        guard targetPower >= 0 && targetPower <= 4000 else {
            return CommandResult(
                command: .setTargetPower,
                response: createResponse(.setTargetPower, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetPower -> invalid parameter (\(targetPower)W)",
                stateUpdate: nil
            )
        }

        // Create status notification with new target power
        var statusData = Data([StatusCode.targetPowerChanged.rawValue])
        let powerUInt = UInt16(bitPattern: Int16(clamping: targetPower))
        statusData.append(UInt8(truncatingIfNeeded: powerUInt & 0xFF))
        statusData.append(UInt8(truncatingIfNeeded: powerUInt >> 8))

        return CommandResult(
            command: .setTargetPower,
            response: createResponse(.setTargetPower, success),
            status: statusData,
            statusDelay: 0,
            logMessage: "FTMS: SetTargetPower -> \(targetPower)W",
            stateUpdate: { $0.targetPower = targetPower }
        )
    }

    private func handleStartOrResume() -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .startOrResume,
                response: createResponse(.startOrResume, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: StartOrResume -> control not permitted",
                stateUpdate: nil
            )
        }

        let message = state.isStarted ?
            "FTMS: StartOrResume -> already started" :
            "FTMS: StartOrResume -> success"

        return CommandResult(
            command: .startOrResume,
            response: createResponse(.startOrResume, success),
            status: state.isStarted ? nil : Data([StatusCode.startedOrResumed.rawValue]),
            statusDelay: 0,
            logMessage: message,
            stateUpdate: { $0.isStarted = true }
        )
    }

    private func handleStopOrPause() -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .stopOrPause,
                response: createResponse(.stopOrPause, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: StopOrPause -> control not permitted",
                stateUpdate: nil
            )
        }

        let message = state.isStarted ?
            "FTMS: StopOrPause -> success" :
            "FTMS: StopOrPause -> already stopped"

        return CommandResult(
            command: .stopOrPause,
            response: createResponse(.stopOrPause, success),
            status: state.isStarted ? Data([StatusCode.stoppedOrPaused.rawValue]) : nil,
            statusDelay: 0,
            logMessage: message,
            stateUpdate: { $0.isStarted = false }
        )
    }

    private func handleSetIndoorBikeSimulation(_ data: Data) -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .setIndoorBikeSimulation,
                response: createResponse(.setIndoorBikeSimulation, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetIndoorBikeSimulation -> control not permitted",
                stateUpdate: nil
            )
        }

        guard data.count >= 7 else {
            return CommandResult(
                command: .setIndoorBikeSimulation,
                response: createResponse(.setIndoorBikeSimulation, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetIndoorBikeSimulation -> invalid data length",
                stateUpdate: nil
            )
        }

        let wind = Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8))
        let grade = Int16(bitPattern: UInt16(data[3]) | (UInt16(data[4]) << 8))
        let crr = data[5]
        let cw = data[6]

        guard abs(wind) <= 32767 && abs(grade) <= 4000 && crr <= 255 && cw <= 255 else {
            return CommandResult(
                command: .setIndoorBikeSimulation,
                response: createResponse(.setIndoorBikeSimulation, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetIndoorBikeSimulation -> invalid parameters",
                stateUpdate: nil
            )
        }

        let windSpeed = Double(wind) * 0.001
        let gradePercent = Double(grade) * 0.01
        let crrValue = Double(crr) * 0.0001
        let cwValue = Double(cw) * 0.01

        // Create status notification
        var statusData = Data(count: 7)
        statusData[0] = StatusCode.indoorBikeSimulationParametersChanged.rawValue
        statusData[1] = UInt8(truncatingIfNeeded: UInt16(bitPattern: wind) & 0xFF)
        statusData[2] = UInt8(truncatingIfNeeded: UInt16(bitPattern: wind) >> 8)
        statusData[3] = UInt8(truncatingIfNeeded: UInt16(bitPattern: grade) & 0xFF)
        statusData[4] = UInt8(truncatingIfNeeded: UInt16(bitPattern: grade) >> 8)
        statusData[5] = crr
        statusData[6] = cw

        let message = String(format: "FTMS: BikeSim wind=%.3f m/s grade=%.2f%% crr=%.4f cw=%.2f",
                           windSpeed, gradePercent, crrValue, cwValue)

        return CommandResult(
            command: .setIndoorBikeSimulation,
            response: createResponse(.setIndoorBikeSimulation, success),
            status: statusData,
            statusDelay: 0,
            logMessage: message,
            stateUpdate: { state in
                state.simWindSpeedMps = windSpeed
                state.gradePercent = gradePercent
                state.simCrr = crrValue
                state.simCw = cwValue
            }
        )
    }

    private func handleSpinDownControl(_ data: Data) -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .spinDownControl,
                response: createResponse(.spinDownControl, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SpinDownControl -> control not permitted",
                stateUpdate: nil
            )
        }

        guard data.count >= 2 else {
            return CommandResult(
                command: .spinDownControl,
                response: createResponse(.spinDownControl, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SpinDownControl -> invalid data length",
                stateUpdate: nil
            )
        }

        let spinDownCommand = data[1]

        if spinDownCommand == 0x01 {  // Start spin down
            return CommandResult(
                command: .spinDownControl,
                response: createResponse(.spinDownControl, success),
                status: Data([StatusCode.spinDownStarted.rawValue]),
                statusDelay: 2.5,  // Simulate completion after delay
                logMessage: "FTMS: SpinDownControl -> start",
                stateUpdate: nil
            )
        } else if spinDownCommand == 0x02 {  // Ignore spin down
            return CommandResult(
                command: .spinDownControl,
                response: createResponse(.spinDownControl, success),
                status: Data([StatusCode.spinDownIgnored.rawValue]),
                statusDelay: 0,
                logMessage: "FTMS: SpinDownControl -> ignore",
                stateUpdate: nil
            )
        } else {
            return CommandResult(
                command: .spinDownControl,
                response: createResponse(.spinDownControl, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SpinDownControl -> invalid parameter",
                stateUpdate: nil
            )
        }
    }

    private func handleSetTargetSpeed(_ data: Data) -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .setTargetSpeed,
                response: createResponse(.setTargetSpeed, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetSpeed -> control not permitted",
                stateUpdate: nil
            )
        }

        guard data.count >= 3 else {
            return CommandResult(
                command: .setTargetSpeed,
                response: createResponse(.setTargetSpeed, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetSpeed -> invalid data length",
                stateUpdate: nil
            )
        }

        let speedCms = UInt16(data[1]) | (UInt16(data[2]) << 8)
        let speedMs = Double(speedCms) / 100.0

        var statusData = Data([StatusCode.targetSpeedChanged.rawValue])
        statusData.append(contentsOf: withUnsafeBytes(of: speedCms.littleEndian) { Data($0) })

        return CommandResult(
            command: .setTargetSpeed,
            response: createResponse(.setTargetSpeed, success),
            status: statusData,
            statusDelay: 0,
            logMessage: "FTMS: SetTargetSpeed \(speedMs) m/s",
            stateUpdate: nil
        )
    }

    private func handleSetTargetInclination(_ data: Data) -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .setTargetInclination,
                response: createResponse(.setTargetInclination, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetInclination -> control not permitted",
                stateUpdate: nil
            )
        }

        guard data.count >= 3 else {
            return CommandResult(
                command: .setTargetInclination,
                response: createResponse(.setTargetInclination, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetInclination -> invalid data length",
                stateUpdate: nil
            )
        }

        let inclineRaw = Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8))
        let inclinePercent = Double(inclineRaw) / 10.0

        var statusData = Data([StatusCode.targetInclineChanged.rawValue])
        statusData.append(contentsOf: withUnsafeBytes(of: inclineRaw.littleEndian) { Data($0) })

        return CommandResult(
            command: .setTargetInclination,
            response: createResponse(.setTargetInclination, success),
            status: statusData,
            statusDelay: 0,
            logMessage: "FTMS: SetTargetInclination \(inclinePercent)%",
            stateUpdate: { $0.gradePercent = inclinePercent }
        )
    }

    private func handleSetWheelCircumference(_ data: Data) -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .setWheelCircumference,
                response: createResponse(.setWheelCircumference, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetWheelCircumference -> control not permitted",
                stateUpdate: nil
            )
        }

        guard data.count >= 3 else {
            return CommandResult(
                command: .setWheelCircumference,
                response: createResponse(.setWheelCircumference, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetWheelCircumference -> invalid data length",
                stateUpdate: nil
            )
        }

        let circumferenceMm = UInt16(data[1]) | (UInt16(data[2]) << 8)

        var statusData = Data([StatusCode.wheelCircumferenceChanged.rawValue])
        statusData.append(contentsOf: withUnsafeBytes(of: circumferenceMm.littleEndian) { Data($0) })

        return CommandResult(
            command: .setWheelCircumference,
            response: createResponse(.setWheelCircumference, success),
            status: statusData,
            statusDelay: 0,
            logMessage: "FTMS: SetWheelCircumference \(circumferenceMm)mm",
            stateUpdate: nil
        )
    }

    private func handleSetTargetedCadence(_ data: Data) -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .setTargetedCadence,
                response: createResponse(.setTargetedCadence, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetedCadence -> control not permitted",
                stateUpdate: nil
            )
        }

        guard data.count >= 3 else {
            return CommandResult(
                command: .setTargetedCadence,
                response: createResponse(.setTargetedCadence, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetedCadence -> invalid data length",
                stateUpdate: nil
            )
        }

        let targetCadence = UInt16(data[1]) | (UInt16(data[2]) << 8)
        let targetRpm = Double(targetCadence) / 2.0

        var statusData = Data([StatusCode.targetCadenceChanged.rawValue])
        statusData.append(contentsOf: withUnsafeBytes(of: targetCadence.littleEndian) { Data($0) })

        return CommandResult(
            command: .setTargetedCadence,
            response: createResponse(.setTargetedCadence, success),
            status: statusData,
            statusDelay: 0,
            logMessage: "FTMS: SetTargetedCadence \(targetRpm) RPM",
            stateUpdate: nil
        )
    }

    private func handleSetTargetResistanceLevel(_ data: Data) -> CommandResult {
        if !state.hasControl {
            return CommandResult(
                command: .setTargetResistanceLevel,
                response: createResponse(.setTargetResistanceLevel, controlNotPermitted),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetResistanceLevel -> control not permitted",
                stateUpdate: nil
            )
        }

        guard data.count >= 3 else {
            return CommandResult(
                command: .setTargetResistanceLevel,
                response: createResponse(.setTargetResistanceLevel, invalidParameter),
                status: nil,
                statusDelay: 0,
                logMessage: "FTMS: SetTargetResistanceLevel -> invalid data length",
                stateUpdate: nil
            )
        }

        let resistance = Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8))
        let message = "FTMS: SetTargetResistanceLevel -> not supported (resistance: \(Double(resistance) * 0.1))"

        return CommandResult(
            command: .setTargetResistanceLevel,
            response: createResponse(.setTargetResistanceLevel, opCodeNotSupported),
            status: nil,
            statusDelay: 0,
            logMessage: message,
            stateUpdate: nil
        )
    }

    private func handleUnsupportedOpcode(_ opcode: UInt8) -> CommandResult {
        let message = "FTMS: Opcode \(String(format: "0x%02X", opcode)) -> not supported"
        return CommandResult(
            command: nil,
            response: Data([responseCode, opcode, opCodeNotSupported]),
            status: nil,
            statusDelay: 0,
            logMessage: message,
            stateUpdate: nil
        )
    }

    private func handleUnknownOpcode(_ opcode: UInt8) -> CommandResult {
        let message = "FTMS: Unknown opcode \(String(format: "0x%02X", opcode)) -> not supported"
        return CommandResult(
            command: nil,
            response: Data([responseCode, opcode, opCodeNotSupported]),
            status: nil,
            statusDelay: 0,
            logMessage: message,
            stateUpdate: nil
        )
    }

    // MARK: - Helper Methods

    private func createResponse(_ opcode: Opcode, _ result: UInt8) -> Data {
        return Data([responseCode, opcode.rawValue, result])
    }
}