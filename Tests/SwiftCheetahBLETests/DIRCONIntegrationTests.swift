import XCTest
import Network
@testable import SwiftCheetahBLE

/// End-to-end integration test: start DIRCON server, connect as TCP client,
/// discover services, discover FTMS characteristics, enable Indoor Bike Data
/// notifications, verify notification payloads arrive with valid FTMS encoding.
///
/// Gated by `DIRCON_INTEGRATION=1` environment variable (skipped otherwise).
@MainActor
final class DIRCONIntegrationTests: XCTestCase {

    /// Thread-safe single-resume guard for continuations used in NWConnection callbacks.
    private final class ResumeGuard: @unchecked Sendable {
        private var _resumed = false
        private let lock = NSLock()
        var resumed: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _resumed }
            set { lock.lock(); defer { lock.unlock() }; _resumed = newValue }
        }
    }

    /// Waits for a condition to become true with a timeout.
    private func waitFor(timeout: TimeInterval = 3.0, condition: @escaping @Sendable () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Opens a persistent TCP connection and returns it once ready.
    private func openConnection(port: UInt16) async throws -> NWConnection {
        let guard_ = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            let conn = NWConnection(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !guard_.resumed else { return }
                    guard_.resumed = true
                    continuation.resume(returning: conn)
                case .failed(let error):
                    guard !guard_.resumed else { return }
                    guard_.resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            conn.start(queue: .main)
        }
    }

    /// Sends a DIRCON message and reads the response on an existing connection.
    private func sendAndReceive(conn: NWConnection, message: DIRCONMessage) async throws -> DIRCONMessage? {
        let guard_ = ResumeGuard()
        let wireData = message.serialize()
        return try await withCheckedThrowingContinuation { continuation in
            conn.send(content: wireData, completion: .contentProcessed { error in
                if let error = error {
                    guard !guard_.resumed else { return }
                    guard_.resumed = true
                    continuation.resume(throwing: error)
                    return
                }

                conn.receive(minimumIncompleteLength: DIRCONMessage.headerSize,
                             maximumLength: 4096) { data, _, _, recvError in
                    guard !guard_.resumed else { return }
                    guard_.resumed = true

                    if let recvError = recvError {
                        continuation.resume(throwing: recvError)
                        return
                    }

                    guard let data = data else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let msg = DIRCONMessage.deserialize(from: data)
                    continuation.resume(returning: msg)
                }
            })
        }
    }

    /// Reads the next message from a connection (for unsolicited notifications).
    private func receiveNext(conn: NWConnection) async throws -> DIRCONMessage? {
        let guard_ = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            conn.receive(minimumIncompleteLength: DIRCONMessage.headerSize,
                         maximumLength: 4096) { data, _, _, recvError in
                guard !guard_.resumed else { return }
                guard_.resumed = true

                if let recvError = recvError {
                    continuation.resume(throwing: recvError)
                    return
                }

                guard let data = data else {
                    continuation.resume(returning: nil)
                    return
                }

                let msg = DIRCONMessage.deserialize(from: data)
                continuation.resume(returning: msg)
            }
        }
    }

    func testFullDiscoveryAndNotificationFlow() async throws {
        guard ProcessInfo.processInfo.environment["DIRCON_INTEGRATION"] == "1" else {
            throw XCTSkip("Set DIRCON_INTEGRATION=1 to run")
        }

        let server = DIRCONServer()
        server.watts = 200
        server.cadenceRpm = 85

        // Use a random high port to avoid conflicts
        let testPort: UInt16 = 40_000 &+ UInt16(arc4random_uniform(5000))
        server.startBroadcast(port: testPort)

        // Wait for the server to start listening
        await waitFor { server.isAdvertising }
        XCTAssertTrue(server.isAdvertising, "Server should be advertising")

        let port = server.listeningPort != 0 ? server.listeningPort : DIRCONProtocol.defaultPort

        // Open a persistent TCP connection
        let conn = try await openConnection(port: port)

        // 1. Discover services
        let discoverServicesReq = DIRCONMessage(
            opcode: .discoverServices, sequenceNumber: 1, responseCode: 0, payload: Data()
        )
        let servicesResp = try await sendAndReceive(conn: conn, message: discoverServicesReq)
        XCTAssertNotNil(servicesResp)
        XCTAssertEqual(servicesResp?.opcode, .discoverServices)
        XCTAssertEqual(servicesResp?.responseCode, 0)
        // Should contain at least FTMS (0x1826) in the service list
        XCTAssertGreaterThanOrEqual(servicesResp?.payload.count ?? 0, 16)

        // 2. Discover FTMS characteristics
        let discoverCharsReq = DIRCONMessage(
            opcode: .discoverCharacteristics, sequenceNumber: 2, responseCode: 0,
            payload: Data(DIRCONProtocol.wireUUID(from: 0x1826))
        )
        let charsResp = try await sendAndReceive(conn: conn, message: discoverCharsReq)
        XCTAssertNotNil(charsResp)
        XCTAssertEqual(charsResp?.opcode, .discoverCharacteristics)
        XCTAssertEqual(charsResp?.responseCode, 0)
        // FTMS has 5 characteristics: 16 (service UUID) + 5 * 17 (each char UUID + properties) = 101
        XCTAssertGreaterThanOrEqual(charsResp?.payload.count ?? 0, 101)

        // 3. Enable Indoor Bike Data (0x2AD2) notifications
        var enablePayload = Data(DIRCONProtocol.wireUUID(from: 0x2AD2))
        enablePayload.append(0x01) // enable flag
        let enableReq = DIRCONMessage(
            opcode: .enableNotifications, sequenceNumber: 3, responseCode: 0,
            payload: enablePayload
        )
        let enableResp = try await sendAndReceive(conn: conn, message: enableReq)
        XCTAssertNotNil(enableResp)
        XCTAssertEqual(enableResp?.opcode, .enableNotifications)
        XCTAssertEqual(enableResp?.responseCode, 0)

        // 4. Wait for unsolicited FTMS Indoor Bike Data notification
        // The notification scheduler sends FTMS data periodically once a client subscribes.
        // We may need to wait a few seconds for the first tick.
        let notification = try await receiveNext(conn: conn)
        XCTAssertNotNil(notification, "Should receive an FTMS notification")
        XCTAssertEqual(notification?.opcode, .notification)
        XCTAssertEqual(notification?.sequenceNumber, 0, "Notifications use sequence number 0")

        let charUUID = DIRCONProtocol.shortUUID(from: notification!.payload)
        XCTAssertEqual(charUUID, 0x2AD2, "Notification should be for Indoor Bike Data (0x2AD2)")
        // Payload = 16-byte UUID + FTMS encoded data (at least a few bytes for flags + fields)
        XCTAssertTrue(notification!.payload.count > 16,
                       "Notification payload should contain UUID (16 bytes) + FTMS data")

        conn.cancel()
        server.stopBroadcast()

        // Give the server time to clean up
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}
