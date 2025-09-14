import Foundation

/// BLENotificationScheduler - Manages periodic BLE notification timers
///
/// This class encapsulates the timer management logic for FTMS, CPS, and RSC
/// notifications that were previously embedded in PeripheralManager.
/// It handles different notification frequencies per BLE specification.
public final class BLENotificationScheduler: @unchecked Sendable {

    /// Notification frequencies per BLE spec
    public struct NotificationConfig {
        public static let ftmsInterval: TimeInterval = 0.25  // 4 Hz
        public static let rscInterval: TimeInterval = 0.5    // 2 Hz
        public static let cpsMaxInterval: TimeInterval = 0.25 // Max 4 Hz
    }

    /// Delegate for notification callbacks
    public protocol Delegate: AnyObject {
        func schedulerShouldSendFTMSNotification()
        func schedulerShouldSendCPSNotification()
        func schedulerShouldSendRSCNotification()
        func schedulerNeedsCadenceForCPSInterval() -> Int
    }

    public weak var delegate: Delegate?

    private var ftmsTimer: Timer?
    private var cpsTimer: Timer?
    private var rscTimer: Timer?
    private var isActive: Bool = false

    public init() {}

    /// Start all notification timers
    public func startNotifications() {
        guard !isActive else { return }
        isActive = true

        stopNotifications()  // Clear any existing timers

        // FTMS at 4 Hz
        ftmsTimer = Timer.scheduledTimer(withTimeInterval: NotificationConfig.ftmsInterval, repeats: true) { [weak self] _ in
            self?.delegate?.schedulerShouldSendFTMSNotification()
        }

        // CPS with dynamic interval based on cadence
        scheduleNextCPSTick()

        // RSC at 2 Hz
        rscTimer = Timer.scheduledTimer(withTimeInterval: NotificationConfig.rscInterval, repeats: true) { [weak self] _ in
            self?.delegate?.schedulerShouldSendRSCNotification()
        }
    }

    /// Stop all notification timers
    public func stopNotifications() {
        isActive = false
        ftmsTimer?.invalidate()
        cpsTimer?.invalidate()
        rscTimer?.invalidate()
        ftmsTimer = nil
        cpsTimer = nil
        rscTimer = nil
    }

    /// CPS uses dynamic interval based on cadence to match crank events
    private func scheduleNextCPSTick() {
        guard isActive else { return }

        cpsTimer?.invalidate()

        // Get current cadence from delegate
        let cadence = delegate?.schedulerNeedsCadenceForCPSInterval() ?? 0

        // Calculate timer interval based on cadence
        let interval: TimeInterval
        if cadence > 0 {
            // Match crank event timing
            let cadenceBasedInterval = 60.0 / Double(cadence)
            // Cap at max frequency (4Hz)
            interval = min(NotificationConfig.cpsMaxInterval, cadenceBasedInterval)
        } else {
            // Default interval when no cadence
            interval = NotificationConfig.cpsMaxInterval
        }

        cpsTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.delegate?.schedulerShouldSendCPSNotification()
            self?.scheduleNextCPSTick()  // Reschedule for next tick
        }
    }

    /// Check if notifications are currently active
    public var isNotifying: Bool {
        return isActive
    }

    deinit {
        stopNotifications()
    }
}