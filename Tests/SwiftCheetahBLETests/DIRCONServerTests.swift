import XCTest
import Network
@testable import SwiftCheetahBLE

@MainActor
final class DIRCONServerTests: XCTestCase {

    private var server: DIRCONServer!
    private var testPort: UInt16 = 0

    override func setUp() async throws {
        try await super.setUp()
        server = DIRCONServer()
        testPort = 40_000 &+ UInt16(arc4random_uniform(5000))
    }

    override func tearDown() async throws {
        server.stopBroadcast()
        try await Task.sleep(nanoseconds: 100_000_000)
        server = nil
        try await super.tearDown()
    }

    // MARK: - Helper

    /// Thread-safe single-resume guard for continuations used in NWConnection callbacks.
    private final class ResumeGuard: @unchecked Sendable {
        private var _resumed = false
        private let lock = NSLock()
        var resumed: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _resumed }
            set { lock.lock(); defer { lock.unlock() }; _resumed = newValue }
        }
    }

    /// Opens a TCP connection, sends a DIRCON request, returns the response.
    private func sendAndReceive(port: UInt16, message: DIRCONMessage) async throws -> DIRCONMessage? {
        let guard_ = ResumeGuard()
        let wireData = message.serialize()
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: wireData, completion: .contentProcessed({ error in
                        if let error = error {
                            guard !guard_.resumed else { return }
                            guard_.resumed = true
                            continuation.resume(throwing: error)
                            return
                        }

                        connection.receive(minimumIncompleteLength: DIRCONMessage.headerSize,
                                           maximumLength: 1024) { data, _, _, recvError in
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
                            connection.cancel()
                            continuation.resume(returning: msg)
                        }
                    }))
                case .failed(let error):
                    guard !guard_.resumed else { return }
                    guard_.resumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard !guard_.resumed else { return }
                    guard_.resumed = true
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }

            connection.start(queue: .main)
        }
    }

    /// Waits for a condition to become true with a timeout.
    private func waitFor(timeout: TimeInterval = 3.0, condition: @escaping @Sendable () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Starts the server and waits until it's advertising.
    private func startServerAndWait(localName: String? = nil) async {
        if let name = localName {
            server.startBroadcast(localName: name, port: testPort)
        } else {
            server.startBroadcast(port: testPort)
        }
        // Wait for the listener to become ready
        await waitFor { [server] in
            guard let s = server else { return false }
            return s.isAdvertising
        }
    }

    // MARK: - Tests

    func testServerStartsListening() async throws {
        await startServerAndWait(localName: "TestTrainer")

        XCTAssertTrue(server.isAdvertising, "Server should be advertising after startBroadcast")
        XCTAssertGreaterThan(server.listeningPort, 0, "Listening port should be set")
    }

    func testServerAcceptsTCPConnection() async throws {
        await startServerAndWait()
        let port = server.listeningPort

        let guard_ = ResumeGuard()
        let connected = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let connection = NWConnection(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            connection.stateUpdateHandler = { state in
                guard !guard_.resumed else { return }
                switch state {
                case .ready:
                    guard_.resumed = true
                    continuation.resume(returning: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        connection.cancel()
                    }
                case .failed(let error):
                    guard_.resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .main)
        }

        XCTAssertTrue(connected)

        await waitFor { [server] in
            guard let s = server else { return false }
            return s.subscriberCount > 0
        }

        XCTAssertEqual(server.subscriberCount, 1)
    }

    func testDiscoverServicesResponse() async throws {
        await startServerAndWait()

        let request = DIRCONMessage(
            opcode: .discoverServices, sequenceNumber: 1, responseCode: 0, payload: Data()
        )

        let response = try await sendAndReceive(port: server.listeningPort, message: request)

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.opcode, .discoverServices)
        XCTAssertEqual(response?.sequenceNumber, 1)
        XCTAssertEqual(response?.responseCode, DIRCONResponseCode.success.rawValue)
        // 4 services x 16 bytes = 64 bytes
        XCTAssertGreaterThanOrEqual(response?.payload.count ?? 0, 64,
                                    "Should contain at least 4 service UUIDs (64 bytes)")
    }

    func testDiscoverCharacteristicsResponse() async throws {
        await startServerAndWait()

        let request = DIRCONMessage(
            opcode: .discoverCharacteristics, sequenceNumber: 2, responseCode: 0,
            payload: Data(DIRCONProtocol.wireUUID(from: 0x1826))
        )

        let response = try await sendAndReceive(port: server.listeningPort, message: request)

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.opcode, .discoverCharacteristics)
        XCTAssertEqual(response?.sequenceNumber, 2)
        XCTAssertEqual(response?.responseCode, DIRCONResponseCode.success.rawValue)
        let payloadCount = response?.payload.count ?? 0
        XCTAssertEqual(payloadCount, 101,
                       "FTMS discover chars should be 16 + 5*17 = 101 bytes, got \(payloadCount)")
    }

    func testReadCharacteristicResponse() async throws {
        await startServerAndWait()

        let request = DIRCONMessage(
            opcode: .readCharacteristic, sequenceNumber: 3, responseCode: 0,
            payload: Data(DIRCONProtocol.wireUUID(from: 0x2ACC))
        )

        let response = try await sendAndReceive(port: server.listeningPort, message: request)

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.opcode, .readCharacteristic)
        XCTAssertEqual(response?.sequenceNumber, 3)
        XCTAssertEqual(response?.responseCode, DIRCONResponseCode.success.rawValue)
        XCTAssertEqual(response?.payload.count, 24,
                       "FTMS Feature read should return 24 bytes (16 UUID + 8 value)")
    }

    func testEnableNotificationsResponse() async throws {
        await startServerAndWait()

        let request = DIRCONMessage(
            opcode: .enableNotifications, sequenceNumber: 4, responseCode: 0,
            payload: Data(DIRCONProtocol.wireUUID(from: 0x2AD2))
        )

        let response = try await sendAndReceive(port: server.listeningPort, message: request)

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.opcode, .enableNotifications)
        XCTAssertEqual(response?.sequenceNumber, 4)
        XCTAssertEqual(response?.responseCode, DIRCONResponseCode.success.rawValue)
        XCTAssertEqual(response?.payload.count, 16,
                       "Enable notifications response should echo 16-byte UUID")
    }

    func testWriteCharacteristicResponse() async throws {
        await startServerAndWait()

        var writePayload = Data(DIRCONProtocol.wireUUID(from: 0x2AD9))
        writePayload.append(Data([0x00]))

        let request = DIRCONMessage(
            opcode: .writeCharacteristic, sequenceNumber: 5, responseCode: 0,
            payload: writePayload
        )

        let response = try await sendAndReceive(port: server.listeningPort, message: request)

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.opcode, .writeCharacteristic)
        XCTAssertEqual(response?.sequenceNumber, 5)
        XCTAssertEqual(response?.responseCode, DIRCONResponseCode.success.rawValue)
        XCTAssertEqual(response?.payload.count, 16,
                       "Write response should echo 16-byte UUID for FTMS Control Point")
    }
}
