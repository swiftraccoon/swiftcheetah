import XCTest
@testable import SwiftCheetahBLE

final class FTMSControlPointHandlerTests: XCTestCase {

    var handler: FTMSControlPointHandler!

    override func setUp() {
        super.setUp()
        handler = FTMSControlPointHandler()
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    // MARK: - Basic Interface Tests

    func testInitialization() {
        let state = handler.getState()
        XCTAssertTrue(state.hasControl)
        XCTAssertTrue(state.isStarted)
        XCTAssertEqual(state.targetPower, 250)
        XCTAssertEqual(state.gradePercent, 0)
    }

    func testCustomInitialization() {
        let customState = FTMSControlPointHandler.ControlState(
            hasControl: false,
            isStarted: false,
            targetPower: 100,
            gradePercent: 5.0
        )
        let customHandler = FTMSControlPointHandler(initialState: customState)
        let state = customHandler.getState()

        XCTAssertFalse(state.hasControl)
        XCTAssertFalse(state.isStarted)
        XCTAssertEqual(state.targetPower, 100)
        XCTAssertEqual(state.gradePercent, 5.0)
    }

    func testSetState() {
        var newState = handler.getState()
        newState.targetPower = 300
        newState.gradePercent = 10.0

        handler.setState(newState)
        let retrievedState = handler.getState()

        XCTAssertEqual(retrievedState.targetPower, 300)
        XCTAssertEqual(retrievedState.gradePercent, 10.0)
    }

    // MARK: - Error Handling Tests

    func testEmptyCommandData() {
        let result = handler.handleCommand(Data())

        XCTAssertNil(result.command)
        XCTAssertNil(result.response)
        XCTAssertNil(result.status)
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertEqual(result.logMessage, "FTMS: Invalid command data")
        XCTAssertNil(result.stateUpdate)
    }

    func testUnknownOpcode() {
        let unknownOpcode: UInt8 = 0xFF
        let data = Data([unknownOpcode])
        let result = handler.handleCommand(data)

        XCTAssertNil(result.command)
        XCTAssertNotNil(result.response)
        XCTAssertNil(result.status)
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertTrue(result.logMessage.contains("Unknown opcode"))
        XCTAssertNil(result.stateUpdate)

        // Verify error response format
        if let response = result.response {
            XCTAssertEqual(response.count, 3)
            XCTAssertEqual(response[0], 0x80) // Response code
            XCTAssertEqual(response[1], unknownOpcode) // Original opcode
            XCTAssertEqual(response[2], 0x02) // Op code not supported
        }
    }

    // MARK: - Request Control Tests

    func testRequestControl() {
        let data = Data([0x00]) // Request Control opcode
        let result = handler.handleCommand(data)

        XCTAssertEqual(result.command, .requestControl)
        XCTAssertNotNil(result.response)
        XCTAssertNil(result.status)
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertTrue(result.logMessage.contains("RequestControl"))
        XCTAssertNotNil(result.stateUpdate)

        // Verify response format
        if let response = result.response {
            XCTAssertEqual(response.count, 3)
            XCTAssertEqual(response[0], 0x80) // Response code
            XCTAssertEqual(response[1], 0x00) // Request Control opcode
            XCTAssertEqual(response[2], 0x01) // Success
        }

        // Apply state update and verify
        if let stateUpdate = result.stateUpdate {
            var state = handler.getState()
            stateUpdate(&state)
            XCTAssertTrue(state.hasControl)
        }
    }

    // MARK: - Reset Tests

    func testReset() {
        let data = Data([0x01]) // Reset opcode
        let result = handler.handleCommand(data)

        XCTAssertEqual(result.command, .reset)
        XCTAssertNotNil(result.response)
        XCTAssertNotNil(result.status)
        XCTAssertEqual(result.statusDelay, 0.5)
        XCTAssertTrue(result.logMessage.contains("Reset"))
        XCTAssertNotNil(result.stateUpdate)

        // Verify response format
        if let response = result.response {
            XCTAssertEqual(response.count, 3)
            XCTAssertEqual(response[0], 0x80) // Response code
            XCTAssertEqual(response[1], 0x01) // Reset opcode
            XCTAssertEqual(response[2], 0x01) // Success
        }

        // Verify status format
        if let status = result.status {
            XCTAssertEqual(status.count, 1)
            XCTAssertEqual(status[0], 0x01) // Reset status
        }

        // Apply state update and verify reset behavior
        if let stateUpdate = result.stateUpdate {
            var state = handler.getState()
            stateUpdate(&state)
            XCTAssertFalse(state.hasControl)
            XCTAssertFalse(state.isStarted)
        }
    }

    // MARK: - Set Target Power Tests

    func testSetTargetPowerValid() {
        let targetPower: UInt16 = 200
        let powerBytes = withUnsafeBytes(of: targetPower.littleEndian) { Array($0) }
        let data = Data([0x05] + powerBytes) // Set Target Power opcode + power value

        let result = handler.handleCommand(data)

        XCTAssertEqual(result.command, .setTargetPower)
        XCTAssertNotNil(result.response)
        XCTAssertNotNil(result.status)
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertTrue(result.logMessage.contains("SetTargetPower"))
        XCTAssertNotNil(result.stateUpdate)

        // Verify response format
        if let response = result.response {
            XCTAssertEqual(response.count, 3)
            XCTAssertEqual(response[0], 0x80) // Response code
            XCTAssertEqual(response[1], 0x05) // Set Target Power opcode
            XCTAssertEqual(response[2], 0x01) // Success
        }

        // Apply state update and verify power change
        if let stateUpdate = result.stateUpdate {
            var state = handler.getState()
            stateUpdate(&state)
            XCTAssertEqual(state.targetPower, Int(targetPower))
        }
    }

    func testSetTargetPowerInvalidLength() {
        let data = Data([0x05]) // Set Target Power opcode without power value
        let result = handler.handleCommand(data)

        XCTAssertEqual(result.command, .setTargetPower)
        XCTAssertNotNil(result.response)
        XCTAssertNil(result.status)
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertTrue(result.logMessage.contains("invalid data length"))
        XCTAssertNil(result.stateUpdate)

        // Verify error response
        if let response = result.response {
            XCTAssertEqual(response.count, 3)
            XCTAssertEqual(response[0], 0x80) // Response code
            XCTAssertEqual(response[1], 0x05) // Set Target Power opcode
            XCTAssertEqual(response[2], 0x03) // Invalid parameter
        }
    }

    // MARK: - Start/Resume Tests

    func testStartOrResume() {
        let data = Data([0x07]) // Start or Resume opcode
        let result = handler.handleCommand(data)

        XCTAssertEqual(result.command, .startOrResume)
        XCTAssertNotNil(result.response)
        XCTAssertNil(result.status) // No status since already started by default
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertTrue(result.logMessage.contains("already started"))
        XCTAssertNotNil(result.stateUpdate)

        // Apply state update and verify started state
        if let stateUpdate = result.stateUpdate {
            var state = handler.getState()
            state.isStarted = false // Set to false first
            stateUpdate(&state)
            XCTAssertTrue(state.isStarted)
        }
    }

    // MARK: - Stop/Pause Tests

    func testStopOrPause() {
        let data = Data([0x08]) // Stop or Pause opcode
        let result = handler.handleCommand(data)

        XCTAssertEqual(result.command, .stopOrPause)
        XCTAssertNotNil(result.response)
        XCTAssertNotNil(result.status) // Status since currently started by default
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertTrue(result.logMessage.contains("StopOrPause"))
        XCTAssertNotNil(result.stateUpdate)

        // Apply state update and verify stopped state
        if let stateUpdate = result.stateUpdate {
            var state = handler.getState()
            state.isStarted = true // Set to true first
            stateUpdate(&state)
            XCTAssertFalse(state.isStarted)
        }
    }

    // MARK: - Set Indoor Bike Simulation Tests

    func testSetIndoorBikeSimulationValid() {
        // Create proper FTMS Indoor Bike Simulation data
        let windSpeed: Int16 = 500 // 0.5 m/s (in 0.001 m/s units)
        let grade: Int16 = 500 // 5.0% (in 0.01% units)
        let crr: UInt8 = 40 // 0.004 (in 0.0001 units)
        let cw: UInt8 = 51 // 0.51 kg/m (in 0.01 kg/m units)

        let windBytes = withUnsafeBytes(of: windSpeed.littleEndian) { Array($0) }
        let gradeBytes = withUnsafeBytes(of: grade.littleEndian) { Array($0) }

        let data = Data([0x11] + windBytes + gradeBytes + [crr, cw])

        let result = handler.handleCommand(data)

        XCTAssertEqual(result.command, .setIndoorBikeSimulation)
        XCTAssertNotNil(result.response)
        XCTAssertNotNil(result.status)
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertTrue(result.logMessage.contains("BikeSim"))
        XCTAssertNotNil(result.stateUpdate)

        // Apply state update and verify simulation parameters
        if let stateUpdate = result.stateUpdate {
            var state = handler.getState()
            stateUpdate(&state)
            XCTAssertEqual(state.simWindSpeedMps, 0.5, accuracy: 0.001)
            XCTAssertEqual(state.gradePercent, 5.0, accuracy: 0.001)
            XCTAssertEqual(state.simCrr, 0.004, accuracy: 0.0001)
            XCTAssertEqual(state.simCw, 0.51, accuracy: 0.001)
        }
    }

    func testSetIndoorBikeSimulationInvalidLength() {
        let data = Data([0x11, 0x00]) // Indoor Bike Simulation with insufficient data
        let result = handler.handleCommand(data)

        XCTAssertEqual(result.command, .setIndoorBikeSimulation)
        XCTAssertNotNil(result.response)
        XCTAssertNil(result.status)
        XCTAssertEqual(result.statusDelay, 0)
        XCTAssertTrue(result.logMessage.contains("invalid data length"))
        XCTAssertNil(result.stateUpdate)

        // Verify error response
        if let response = result.response {
            XCTAssertEqual(response[2], 0x03) // Invalid parameter
        }
    }

    // MARK: - Comprehensive Opcode Coverage Tests

    func testAllSupportedOpcodes() {
        let supportedOpcodes: [UInt8] = [
            0x00, // requestControl
            0x01, // reset
            0x05, // setTargetPower (with data)
            0x07, // startOrResume
            0x08, // stopOrPause
            0x11  // setIndoorBikeSimulation (with data)
        ]

        for opcode in supportedOpcodes {
            var data = Data([opcode])

            // Add required data for opcodes that need it
            if opcode == 0x05 { // setTargetPower
                let powerBytes = withUnsafeBytes(of: UInt16(200).littleEndian) { Array($0) }
                data.append(contentsOf: powerBytes)
            } else if opcode == 0x11 { // setIndoorBikeSimulation
                data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x40, 0x51])
            }

            let result = handler.handleCommand(data)

            // All supported opcodes should return valid responses
            XCTAssertNotNil(result.response, "Opcode 0x\(String(opcode, radix: 16)) should have response")
            XCTAssertNotNil(result.command, "Opcode 0x\(String(opcode, radix: 16)) should have command")

            // Verify response format for all supported commands
            if let response = result.response {
                XCTAssertEqual(response[0], 0x80, "Response code should be 0x80")
                XCTAssertEqual(response[1], opcode, "Response should echo opcode")
                XCTAssertEqual(response[2], 0x01, "All valid commands should return success")
            }
        }
    }

    // MARK: - State Persistence Tests

    func testStatePersistenceThroughCommands() {
        // Set initial custom state
        var initialState = handler.getState()
        initialState.targetPower = 150
        initialState.gradePercent = 3.0
        handler.setState(initialState)

        // Execute a command that doesn't change these values
        let controlData = Data([0x00]) // Request Control
        let controlResult = handler.handleCommand(controlData)

        if let stateUpdate = controlResult.stateUpdate {
            var state = handler.getState()
            stateUpdate(&state)
            handler.setState(state)
        }

        // Verify original values are preserved
        let finalState = handler.getState()
        XCTAssertEqual(finalState.targetPower, 150)
        XCTAssertEqual(finalState.gradePercent, 3.0)
        XCTAssertTrue(finalState.hasControl) // This should be updated by the command
    }

    // MARK: - Performance Tests

    func testCommandProcessingPerformance() {
        let data = Data([0x05, 0xC8, 0x00]) // Set Target Power to 200W

        measure {
            for _ in 0..<1000 {
                _ = handler.handleCommand(data)
            }
        }
    }

    // MARK: - Protocol Compliance Tests

    func testResponseCodeCompliance() {
        let data = Data([0x00]) // Request Control
        let result = handler.handleCommand(data)

        // All responses should follow FTMS specification format
        if let response = result.response {
            XCTAssertGreaterThanOrEqual(response.count, 3, "FTMS responses must be at least 3 bytes")
            XCTAssertEqual(response[0], 0x80, "First byte must be response code 0x80")
            XCTAssertEqual(response[1], 0x00, "Second byte must be original opcode")
            // Third byte is result code (0x01 = success, 0x02 = not supported, etc.)
        }
    }

    func testStatusNotificationCompliance() {
        let data = Data([0x01]) // Reset command
        let result = handler.handleCommand(data)

        // Commands that trigger status notifications should have proper format
        if let status = result.status {
            XCTAssertEqual(status.count, 1, "Status notifications should be 1 byte")
            XCTAssertEqual(status[0], 0x01, "Reset status should be 0x01")
        }

        // Status delay should be 0.5 seconds for reset
        XCTAssertEqual(result.statusDelay, 0.5)
    }

    // MARK: - Edge Cases and Robustness Tests

    func testLargeDataPayload() {
        // Test with data much larger than expected
        let largeData = Data(repeating: 0x05, count: 1000)
        let result = handler.handleCommand(largeData)

        // Should still process the first byte as opcode
        XCTAssertEqual(result.command, .setTargetPower)
        XCTAssertNotNil(result.response)
    }

    func testConcurrentCommandHandling() {
        let expectation = XCTestExpectation(description: "Concurrent command handling")
        let commandCount = 100
        var completedCommands = 0

        let queue = DispatchQueue.global(qos: .default)

        for i in 0..<commandCount {
            queue.async {
                let power = UInt16(100 + i)
                let powerBytes = withUnsafeBytes(of: power.littleEndian) { Array($0) }
                let data = Data([0x05] + powerBytes)

                let result = self.handler.handleCommand(data)

                XCTAssertNotNil(result.response)
                XCTAssertEqual(result.command, .setTargetPower)

                DispatchQueue.main.async {
                    completedCommands += 1
                    if completedCommands == commandCount {
                        expectation.fulfill()
                    }
                }
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
