import XCTest
@testable import SwiftCheetahBLE

final class BLENotificationSchedulerTests: XCTestCase {

    var scheduler: BLENotificationScheduler!
    private var mockDelegate: MockSchedulerDelegate!

    override func setUp() {
        super.setUp()
        scheduler = BLENotificationScheduler()
        mockDelegate = MockSchedulerDelegate()
        scheduler.delegate = mockDelegate
    }

    override func tearDown() {
        scheduler.stopNotifications()
        scheduler = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        let newScheduler = BLENotificationScheduler()
        XCTAssertFalse(newScheduler.isNotifying)
        XCTAssertNil(newScheduler.delegate)
    }

    func testNotificationConfig() {
        XCTAssertEqual(BLENotificationScheduler.NotificationConfig.ftmsInterval, 0.25)
        XCTAssertEqual(BLENotificationScheduler.NotificationConfig.rscInterval, 0.5)
        XCTAssertEqual(BLENotificationScheduler.NotificationConfig.cpsMaxInterval, 0.25)
    }

    // MARK: - Start/Stop Lifecycle Tests

    func testStartNotifications() {
        XCTAssertFalse(scheduler.isNotifying)

        scheduler.startNotifications()

        XCTAssertTrue(scheduler.isNotifying)
    }

    func testStopNotifications() {
        scheduler.startNotifications()
        XCTAssertTrue(scheduler.isNotifying)

        scheduler.stopNotifications()

        XCTAssertFalse(scheduler.isNotifying)
    }

    func testStartNotificationsMultipleTimes() {
        // Starting multiple times should not create multiple timers
        scheduler.startNotifications()
        XCTAssertTrue(scheduler.isNotifying)

        scheduler.startNotifications()
        XCTAssertTrue(scheduler.isNotifying)

        // Should still work normally
        scheduler.stopNotifications()
        XCTAssertFalse(scheduler.isNotifying)
    }

    func testStartAfterStop() {
        scheduler.startNotifications()
        scheduler.stopNotifications()

        XCTAssertFalse(scheduler.isNotifying)

        scheduler.startNotifications()
        XCTAssertTrue(scheduler.isNotifying)
    }

    // MARK: - FTMS Timer Tests

    func DISABLED_testFTMSTimerCallback() {
        let expectation = XCTestExpectation(description: "FTMS callback")
        expectation.expectedFulfillmentCount = 2

        mockDelegate.onFTMSNotification = {
            expectation.fulfill()
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 1.0)
    }

    func DISABLED_testFTMSTimerFrequency() {
        let expectation = XCTestExpectation(description: "FTMS frequency test")
        expectation.expectedFulfillmentCount = 4

        var callTimes: [Date] = []
        mockDelegate.onFTMSNotification = {
            callTimes.append(Date())
            expectation.fulfill()
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 1.5)

        // Verify intervals are approximately 0.25 seconds
        for i in 1..<callTimes.count {
            let interval = callTimes[i].timeIntervalSince(callTimes[i-1])
            XCTAssertEqual(interval, 0.25, accuracy: 0.1, "FTMS interval should be ~0.25s")
        }
    }

    // MARK: - RSC Timer Tests

    func DISABLED_testRSCTimerCallback() {
        let expectation = XCTestExpectation(description: "RSC callback")
        expectation.expectedFulfillmentCount = 2

        mockDelegate.onRSCNotification = {
            expectation.fulfill()
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 1.5)
    }

    func DISABLED_testRSCTimerFrequency() {
        let expectation = XCTestExpectation(description: "RSC frequency test")
        expectation.expectedFulfillmentCount = 3

        var callTimes: [Date] = []
        mockDelegate.onRSCNotification = {
            callTimes.append(Date())
            expectation.fulfill()
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 2.0)

        // Verify intervals are approximately 0.5 seconds
        for i in 1..<callTimes.count {
            let interval = callTimes[i].timeIntervalSince(callTimes[i-1])
            XCTAssertEqual(interval, 0.5, accuracy: 0.1, "RSC interval should be ~0.5s")
        }
    }

    // MARK: - CPS Dynamic Timer Tests

    func DISABLED_testCPSTimerCallback() {
        let expectation = XCTestExpectation(description: "CPS callback")
        expectation.expectedFulfillmentCount = 2

        mockDelegate.cadence = 90
        mockDelegate.onCPSNotification = {
            expectation.fulfill()
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 2.0)
    }

    func DISABLED_testCPSTimerWithZeroCadence() {
        let expectation = XCTestExpectation(description: "CPS zero cadence")
        expectation.expectedFulfillmentCount = 3

        mockDelegate.cadence = 0
        mockDelegate.onCPSNotification = {
            expectation.fulfill()
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 1.0)
    }

    func DISABLED_testCPSTimerDynamicInterval() {
        let expectation = XCTestExpectation(description: "CPS dynamic interval")

        var intervals: [TimeInterval] = []
        var lastCallTime = Date()
        var callCount = 0

        mockDelegate.cadence = 60  // Should give 1.0 second intervals
        mockDelegate.onCPSNotification = {
            if callCount > 0 {
                let interval = Date().timeIntervalSince(lastCallTime)
                intervals.append(interval)
            }
            lastCallTime = Date()
            callCount += 1

            if callCount >= 3 {
                expectation.fulfill()
            }
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 3.5)

        // Verify intervals match expected cadence-based timing (60 RPM = 1 second)
        for interval in intervals {
            XCTAssertEqual(interval, 1.0, accuracy: 0.1, "CPS interval should match cadence timing")
        }
    }

    func DISABLED_testCPSTimerHighCadenceCapping() {
        let expectation = XCTestExpectation(description: "CPS high cadence capping")

        var intervals: [TimeInterval] = []
        var lastCallTime = Date()
        var callCount = 0

        mockDelegate.cadence = 300  // Very high cadence should be capped at max frequency
        mockDelegate.onCPSNotification = {
            if callCount > 0 {
                let interval = Date().timeIntervalSince(lastCallTime)
                intervals.append(interval)
            }
            lastCallTime = Date()
            callCount += 1

            if callCount >= 4 {
                expectation.fulfill()
            }
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 1.5)

        // Verify intervals are capped at max frequency (0.25s)
        for interval in intervals {
            XCTAssertGreaterThanOrEqual(interval, 0.25, "CPS interval should not exceed max frequency")
            XCTAssertEqual(interval, 0.25, accuracy: 0.1, "High cadence should be capped at 0.25s")
        }
    }

    func DISABLED_testCPSTimerCadenceChange() {
        let expectation = XCTestExpectation(description: "CPS cadence change")

        var callCount = 0
        mockDelegate.cadence = 90  // Start with 90 RPM

        mockDelegate.onCPSNotification = {
            callCount += 1
            if callCount == 2 {
                // Change cadence after second call
                self.mockDelegate.cadence = 45  // Half the cadence
            }
            if callCount >= 4 {
                expectation.fulfill()
            }
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 3.0)

        // Test passed if no crashes and expectation fulfilled
        XCTAssertGreaterThanOrEqual(callCount, 4)
    }

    // MARK: - Delegate Tests

    func testNilDelegate() {
        scheduler.delegate = nil

        // Should not crash when starting with nil delegate
        scheduler.startNotifications()
        XCTAssertTrue(scheduler.isNotifying)

        // Wait briefly to ensure no crashes
        Thread.sleep(forTimeInterval: 0.3)

        scheduler.stopNotifications()
        XCTAssertFalse(scheduler.isNotifying)
    }

    // This test requires run loop which doesn't work reliably in test environment
    func DISABLED_testDelegateCallbackVerification() {
        var ftmsCallCount = 0
        var cpsCallCount = 0
        var rscCallCount = 0
        var cadenceQueryCount = 0

        mockDelegate.onFTMSNotification = { ftmsCallCount += 1 }
        mockDelegate.onCPSNotification = { cpsCallCount += 1 }
        mockDelegate.onRSCNotification = { rscCallCount += 1 }
        mockDelegate.onCadenceQuery = { cadenceQueryCount += 1 }
        mockDelegate.cadence = 90

        scheduler.startNotifications()

        // Wait for multiple timer cycles
        Thread.sleep(forTimeInterval: 0.8)

        scheduler.stopNotifications()

        XCTAssertGreaterThan(ftmsCallCount, 0, "FTMS should be called")
        XCTAssertGreaterThan(cpsCallCount, 0, "CPS should be called")
        XCTAssertGreaterThan(rscCallCount, 0, "RSC should be called")
        XCTAssertGreaterThan(cadenceQueryCount, 0, "Cadence should be queried")
    }

    func testWeakDelegateReference() {
        var delegate: MockSchedulerDelegate? = MockSchedulerDelegate()
        delegate?.cadence = 90

        scheduler.delegate = delegate
        scheduler.startNotifications()

        // Verify delegate is set
        XCTAssertNotNil(scheduler.delegate)

        // Release delegate
        delegate = nil

        // Scheduler should handle nil delegate gracefully
        Thread.sleep(forTimeInterval: 0.3)

        // Should not crash and delegate should be nil
        XCTAssertNil(scheduler.delegate)
    }

    // MARK: - State Management Tests

    func testIsNotifyingState() {
        XCTAssertFalse(scheduler.isNotifying)

        scheduler.startNotifications()
        XCTAssertTrue(scheduler.isNotifying)

        scheduler.stopNotifications()
        XCTAssertFalse(scheduler.isNotifying)
    }

    func testStopWithoutStart() {
        // Should not crash when stopping without starting
        XCTAssertFalse(scheduler.isNotifying)

        scheduler.stopNotifications()
        XCTAssertFalse(scheduler.isNotifying)
    }

    // MARK: - Edge Cases and Error Handling

    func DISABLED_testNegativeCadence() {
        let expectation = XCTestExpectation(description: "Negative cadence handling")
        expectation.expectedFulfillmentCount = 2

        mockDelegate.cadence = -50  // Invalid negative cadence
        mockDelegate.onCPSNotification = {
            expectation.fulfill()
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 1.0)

        // Should handle negative cadence gracefully (treat as zero)
    }

    func DISABLED_testVeryHighCadence() {
        let expectation = XCTestExpectation(description: "Very high cadence")

        mockDelegate.cadence = 1000  // Unrealistic high cadence
        mockDelegate.onCPSNotification = {
            expectation.fulfill()
        }

        scheduler.startNotifications()

        wait(for: [expectation], timeout: 0.5)

        // Should be capped at max frequency without issues
    }

    func testRapidStartStop() {
        // Rapid start/stop cycles should not cause issues
        for _ in 0..<10 {
            scheduler.startNotifications()
            XCTAssertTrue(scheduler.isNotifying)

            scheduler.stopNotifications()
            XCTAssertFalse(scheduler.isNotifying)
        }
    }

    // MARK: - Performance Tests

    func testTimerPerformance() {
        measure {
            scheduler.startNotifications()
            Thread.sleep(forTimeInterval: 0.1)
            scheduler.stopNotifications()
        }
    }

    func DISABLED_testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access")
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        // Multiple threads starting/stopping
        for _ in 0..<5 {
            group.enter()
            queue.async {
                for _ in 0..<20 {
                    self.scheduler.startNotifications()
                    Thread.sleep(forTimeInterval: 0.001)
                    self.scheduler.stopNotifications()
                }
                group.leave()
            }
        }

        // Threads checking state
        for _ in 0..<3 {
            group.enter()
            queue.async {
                for _ in 0..<100 {
                    _ = self.scheduler.isNotifying
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Should not crash and end in a consistent state
        scheduler.stopNotifications()
        XCTAssertFalse(scheduler.isNotifying)
    }

    // MARK: - Memory Management Tests

    func testDeinitStopsTimers() {
        var localScheduler: BLENotificationScheduler? = BLENotificationScheduler()
        localScheduler?.delegate = mockDelegate
        localScheduler?.startNotifications()

        XCTAssertTrue(localScheduler!.isNotifying)

        // Releasing scheduler should stop timers
        localScheduler = nil

        // Verify no crashes after deallocation
        Thread.sleep(forTimeInterval: 0.3)
    }
}

// MARK: - Mock Delegate

private class MockSchedulerDelegate: BLENotificationScheduler.Delegate {
    var cadence: Int = 90

    var onFTMSNotification: (() -> Void)?
    var onCPSNotification: (() -> Void)?
    var onRSCNotification: (() -> Void)?
    var onCadenceQuery: (() -> Void)?

    func schedulerShouldSendFTMSNotification() {
        onFTMSNotification?()
    }

    func schedulerShouldSendCPSNotification() {
        onCPSNotification?()
    }

    func schedulerShouldSendRSCNotification() {
        onRSCNotification?()
    }

    func schedulerNeedsCadenceForCPSInterval() -> Int {
        onCadenceQuery?()
        return max(0, cadence)  // Ensure non-negative cadence
    }
}
