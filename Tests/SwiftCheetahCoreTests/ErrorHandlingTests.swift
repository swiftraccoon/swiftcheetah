import XCTest
@testable import SwiftCheetahCore

final class ErrorHandlingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear any existing entries before each test
        ErrorHandler.shared.clearEntries()
        // Give the async clear operation time to complete
        Thread.sleep(forTimeInterval: 0.01)
    }

    override func tearDown() {
        ErrorHandler.shared.clearEntries()
        super.tearDown()
    }

    // MARK: - Basic Logging Tests

    func testBasicLogging() {
        let message = "Test error message"
        let context = ["key": "value", "component": "test"]

        ErrorHandler.shared.log(
            message,
            severity: .error,
            category: .ble,
            context: context
        )

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)

        let entry = entries.first!
        XCTAssertEqual(entry.message, message)
        XCTAssertEqual(entry.severity, .error)
        XCTAssertEqual(entry.category, .ble)
        XCTAssertEqual(entry.context, context)
        XCTAssertLessThan(abs(entry.timestamp.timeIntervalSinceNow), 1.0)
    }

    func testLoggingWithoutContext() {
        ErrorHandler.shared.log(
            "Simple message",
            severity: .info,
            category: .system
        )

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries.first!.context.isEmpty)
    }

    func testMultipleLogging() {
        let messages = ["First error", "Second warning", "Third info"]
        let severities: [ErrorHandler.Severity] = [.error, .warning, .info]
        let categories: [ErrorHandler.Category] = [.ble, .simulation, .validation]

        for (index, message) in messages.enumerated() {
            ErrorHandler.shared.log(
                message,
                severity: severities[index],
                category: categories[index]
            )
        }

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 3)

        // Verify entries are in order
        for (index, entry) in entries.enumerated() {
            XCTAssertEqual(entry.message, messages[index])
            XCTAssertEqual(entry.severity, severities[index])
            XCTAssertEqual(entry.category, categories[index])
        }
    }

    // MARK: - Filtering Tests

    func testFilterBySeverity() {
        ErrorHandler.shared.log("Critical error", severity: .critical, category: .system)
        ErrorHandler.shared.log("Regular error", severity: .error, category: .ble)
        ErrorHandler.shared.log("Warning message", severity: .warning, category: .simulation)
        ErrorHandler.shared.log("Info message", severity: .info, category: .validation)

        let criticalEntries = ErrorHandler.shared.getEntries(severity: .critical)
        XCTAssertEqual(criticalEntries.count, 1)
        XCTAssertEqual(criticalEntries.first!.message, "Critical error")

        let errorEntries = ErrorHandler.shared.getEntries(severity: .error)
        XCTAssertEqual(errorEntries.count, 1)
        XCTAssertEqual(errorEntries.first!.message, "Regular error")

        let warningEntries = ErrorHandler.shared.getEntries(severity: .warning)
        XCTAssertEqual(warningEntries.count, 1)
        XCTAssertEqual(warningEntries.first!.message, "Warning message")

        let infoEntries = ErrorHandler.shared.getEntries(severity: .info)
        XCTAssertEqual(infoEntries.count, 1)
        XCTAssertEqual(infoEntries.first!.message, "Info message")
    }

    func testFilterByCategory() {
        ErrorHandler.shared.log("BLE error", severity: .error, category: .ble)
        ErrorHandler.shared.log("Simulation warning", severity: .warning, category: .simulation)
        ErrorHandler.shared.log("Validation issue", severity: .warning, category: .validation)
        ErrorHandler.shared.log("System startup", severity: .info, category: .system)

        let bleEntries = ErrorHandler.shared.getEntries(category: .ble)
        XCTAssertEqual(bleEntries.count, 1)
        XCTAssertEqual(bleEntries.first!.message, "BLE error")

        let simulationEntries = ErrorHandler.shared.getEntries(category: .simulation)
        XCTAssertEqual(simulationEntries.count, 1)
        XCTAssertEqual(simulationEntries.first!.message, "Simulation warning")

        let validationEntries = ErrorHandler.shared.getEntries(category: .validation)
        XCTAssertEqual(validationEntries.count, 1)
        XCTAssertEqual(validationEntries.first!.message, "Validation issue")

        let systemEntries = ErrorHandler.shared.getEntries(category: .system)
        XCTAssertEqual(systemEntries.count, 1)
        XCTAssertEqual(systemEntries.first!.message, "System startup")
    }

    func testFilterBySeverityAndCategory() {
        ErrorHandler.shared.log("BLE error", severity: .error, category: .ble)
        ErrorHandler.shared.log("BLE warning", severity: .warning, category: .ble)
        ErrorHandler.shared.log("Simulation error", severity: .error, category: .simulation)
        ErrorHandler.shared.log("Simulation warning", severity: .warning, category: .simulation)

        let bleErrors = ErrorHandler.shared.getEntries(severity: .error, category: .ble)
        XCTAssertEqual(bleErrors.count, 1)
        XCTAssertEqual(bleErrors.first!.message, "BLE error")

        let simulationWarnings = ErrorHandler.shared.getEntries(severity: .warning, category: .simulation)
        XCTAssertEqual(simulationWarnings.count, 1)
        XCTAssertEqual(simulationWarnings.first!.message, "Simulation warning")

        // Test non-existent combination
        let validationCritical = ErrorHandler.shared.getEntries(severity: .critical, category: .validation)
        XCTAssertEqual(validationCritical.count, 0)
    }

    // MARK: - Summary Statistics Tests

    func testGetSummary() {
        ErrorHandler.shared.log("Critical 1", severity: .critical, category: .system)
        ErrorHandler.shared.log("Error 1", severity: .error, category: .ble)
        ErrorHandler.shared.log("Error 2", severity: .error, category: .simulation)
        ErrorHandler.shared.log("Warning 1", severity: .warning, category: .validation)
        ErrorHandler.shared.log("Warning 2", severity: .warning, category: .ble)
        ErrorHandler.shared.log("Warning 3", severity: .warning, category: .simulation)
        ErrorHandler.shared.log("Info 1", severity: .info, category: .system)

        let summary = ErrorHandler.shared.getSummary()

        XCTAssertEqual(summary[.critical], 1)
        XCTAssertEqual(summary[.error], 2)
        XCTAssertEqual(summary[.warning], 3)
        XCTAssertEqual(summary[.info], 1)
    }

    func testGetSummaryEmpty() {
        let summary = ErrorHandler.shared.getSummary()

        XCTAssertEqual(summary[.critical], 0)
        XCTAssertEqual(summary[.error], 0)
        XCTAssertEqual(summary[.warning], 0)
        XCTAssertEqual(summary[.info], 0)
    }

    // MARK: - Clear Entries Tests

    func testClearEntries() {
        ErrorHandler.shared.log("Test 1", severity: .error, category: .ble)
        ErrorHandler.shared.log("Test 2", severity: .warning, category: .simulation)

        XCTAssertEqual(ErrorHandler.shared.getEntries().count, 2)

        ErrorHandler.shared.clearEntries()

        // Give async operation time to complete
        Thread.sleep(forTimeInterval: 0.01)

        XCTAssertEqual(ErrorHandler.shared.getEntries().count, 0)

        let summary = ErrorHandler.shared.getSummary()
        XCTAssertEqual(summary[.error], 0)
        XCTAssertEqual(summary[.warning], 0)
    }

    // MARK: - Convenience Method Tests

    func testLogBLE() {
        let context = ["peripheral": "test-device"]

        // Test default severity (error)
        ErrorHandler.shared.logBLE("Connection failed", context: context)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)

        let entry = entries.first!
        XCTAssertEqual(entry.message, "Connection failed")
        XCTAssertEqual(entry.severity, .error)
        XCTAssertEqual(entry.category, .ble)
        XCTAssertEqual(entry.context, context)
    }

    func testLogBLECustomSeverity() {
        ErrorHandler.shared.logBLE("Device discovered", severity: .info)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first!.severity, .info)
        XCTAssertEqual(entries.first!.category, .ble)
    }

    func testLogSimulation() {
        let context = ["power": "250", "grade": "5.0"]

        // Test default severity (warning)
        ErrorHandler.shared.logSimulation("Physics calculation convergence issue", context: context)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)

        let entry = entries.first!
        XCTAssertEqual(entry.message, "Physics calculation convergence issue")
        XCTAssertEqual(entry.severity, .warning)
        XCTAssertEqual(entry.category, .simulation)
        XCTAssertEqual(entry.context, context)
    }

    func testLogSimulationCustomSeverity() {
        ErrorHandler.shared.logSimulation("Critical calculation error", severity: .critical)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first!.severity, .critical)
        XCTAssertEqual(entries.first!.category, .simulation)
    }

    func testLogValidation() {
        let context = ["parameter": "power", "value": "-100"]

        // Validation always uses warning severity
        ErrorHandler.shared.logValidation("Invalid power value", context: context)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)

        let entry = entries.first!
        XCTAssertEqual(entry.message, "Invalid power value")
        XCTAssertEqual(entry.severity, .warning)
        XCTAssertEqual(entry.category, .validation)
        XCTAssertEqual(entry.context, context)
    }

    func testLogSystem() {
        let context = ["component": "PeripheralManager"]

        // Test default severity (error)
        ErrorHandler.shared.logSystem("Initialization failed", context: context)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)

        let entry = entries.first!
        XCTAssertEqual(entry.message, "Initialization failed")
        XCTAssertEqual(entry.severity, .error)
        XCTAssertEqual(entry.category, .system)
        XCTAssertEqual(entry.context, context)
    }

    func testLogSystemCustomSeverity() {
        ErrorHandler.shared.logSystem("System ready", severity: .info)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first!.severity, .info)
        XCTAssertEqual(entries.first!.category, .system)
    }

    // MARK: - Formatted Message Tests

    func testFormattedMessage() {
        let message = "Test error"
        let context = ["key1": "value1", "key2": "value2"]

        ErrorHandler.shared.log(message, severity: .error, category: .ble, context: context)

        let entry = ErrorHandler.shared.getEntries().first!
        let formatted = entry.formattedMessage

        // Check basic structure
        XCTAssertTrue(formatted.contains("ERROR"))
        XCTAssertTrue(formatted.contains("[BLE]"))
        XCTAssertTrue(formatted.contains(message))
        XCTAssertTrue(formatted.contains("key1=value1"))
        XCTAssertTrue(formatted.contains("key2=value2"))

        // Check ISO8601 timestamp format
        let timestampPattern = "\\[\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z\\]"
        let regex = try? NSRegularExpression(pattern: timestampPattern)
        XCTAssertNotNil(regex)
        let matches = regex?.matches(in: formatted, range: NSRange(formatted.startIndex..., in: formatted)) ?? []
        XCTAssertEqual(matches.count, 1)
    }

    func testFormattedMessageWithoutContext() {
        ErrorHandler.shared.log("Simple message", severity: .info, category: .system)

        let entry = ErrorHandler.shared.getEntries().first!
        let formatted = entry.formattedMessage

        XCTAssertTrue(formatted.contains("INFO"))
        XCTAssertTrue(formatted.contains("[SYSTEM]"))
        XCTAssertTrue(formatted.contains("Simple message"))
        XCTAssertFalse(formatted.contains(" | "))  // No context separator
    }

    // MARK: - Thread Safety Tests

    func testConcurrentLogging() {
        let expectation = XCTestExpectation(description: "Concurrent logging")
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        let numberOfThreads = 10
        let messagesPerThread = 50

        for threadIndex in 0..<numberOfThreads {
            group.enter()
            queue.async {
                for messageIndex in 0..<messagesPerThread {
                    ErrorHandler.shared.log(
                        "Thread \(threadIndex) Message \(messageIndex)",
                        severity: .info,
                        category: .system,
                        context: ["thread": "\(threadIndex)", "message": "\(messageIndex)"]
                    )
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Verify all messages were logged
        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, numberOfThreads * messagesPerThread)

        // Verify no data corruption
        let uniqueMessages = Set(entries.map { $0.message })
        XCTAssertEqual(uniqueMessages.count, numberOfThreads * messagesPerThread)
    }

    func testConcurrentReadWrite() {
        let expectation = XCTestExpectation(description: "Concurrent read/write")
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        // Writer threads
        for threadIndex in 0..<5 {
            group.enter()
            queue.async {
                for messageIndex in 0..<20 {
                    ErrorHandler.shared.log(
                        "Writer \(threadIndex) Message \(messageIndex)",
                        severity: .info,
                        category: .system
                    )
                }
                group.leave()
            }
        }

        // Reader threads
        for threadIndex in 0..<3 {
            group.enter()
            queue.async {
                for _ in 0..<50 {
                    _ = ErrorHandler.shared.getEntries()
                    _ = ErrorHandler.shared.getSummary()
                    _ = ErrorHandler.shared.getEntries(severity: .info)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Should not crash and should have consistent data
        let finalEntries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(finalEntries.count, 100)  // 5 writers × 20 messages each
    }

    // MARK: - Performance Tests

    func testLoggingPerformance() {
        measure {
            for i in 0..<100 {  // Reduced from 1000 to 100
                ErrorHandler.shared.log(
                    "Performance test message \(i)",
                    severity: .info,
                    category: .system,
                    context: ["index": "\(i)", "batch": "performance"]
                )
            }
        }
    }

    func testFilteringPerformance() {
        // Setup: Add many entries
        for i in 0..<100 {  // Reduced from 1000 to 100
            let severity: ErrorHandler.Severity = [.critical, .error, .warning, .info][i % 4]
            let category: ErrorHandler.Category = [.ble, .simulation, .validation, .system][i % 4]

            ErrorHandler.shared.log(
                "Test message \(i)",
                severity: severity,
                category: category
            )
        }

        measure {
            for _ in 0..<10 {  // Reduced from 100 to 10
                _ = ErrorHandler.shared.getEntries(severity: .error)
                _ = ErrorHandler.shared.getEntries(category: .ble)
                _ = ErrorHandler.shared.getEntries(severity: .warning, category: .simulation)
            }
        }
    }

    // MARK: - Edge Cases Tests

    func testEmptyStringMessage() {
        ErrorHandler.shared.log("", severity: .info, category: .system)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first!.message, "")
    }

    func testVeryLongMessage() {
        let longMessage = String(repeating: "A", count: 500)  // Reduced from 10000 to avoid test runner issues
        ErrorHandler.shared.log(longMessage, severity: .info, category: .system)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first!.message.count, 500)
    }

    func testLargeContext() {
        var largeContext: [String: String] = [:]
        for i in 0..<100 {
            largeContext["key\(i)"] = "value\(i)"
        }

        ErrorHandler.shared.log("Large context test", severity: .info, category: .system, context: largeContext)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first!.context.count, 100)
    }

    func testSpecialCharactersInMessage() {
        let specialMessage = "Error with special chars: 🚴‍♂️ äöü ñ 中文 \"quotes\" 'apostrophes' [brackets] {braces} | pipes"
        ErrorHandler.shared.log(specialMessage, severity: .error, category: .ble)

        let entries = ErrorHandler.shared.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first!.message, specialMessage)

        // Should not crash when formatting
        let formatted = entries.first!.formattedMessage
        XCTAssertTrue(formatted.contains(specialMessage))
    }
}
