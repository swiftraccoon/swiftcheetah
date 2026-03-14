import Foundation

/// Tracks cumulative W/kg over time using a sliding window to detect
/// when power output would trigger Zwift's CPC anti-cheat system.
///
/// The window maintains a rolling average of W/kg at multiple time scales
/// (matching CPC reference curve durations) and compares against thresholds.
public final class CPCSlidingWindow: @unchecked Sendable {

    /// Status of the current power output relative to CPC thresholds.
    public enum CPCStatus: Sendable {
        /// Well below threshold (< 70% of limit)
        case safe
        /// Approaching threshold (70-90% of limit)
        case warning
        /// Near threshold (90-100% of limit)
        case danger
        /// Exceeding threshold — would trigger CPC detection
        case flagged
    }

    /// Snapshot of CPC analysis at a point in time.
    public struct CPCSnapshot: Sendable {
        /// Overall status (worst across all durations).
        public let status: CPCStatus
        /// Ratio of current W/kg to threshold at the most critical duration.
        /// Values > 1.0 mean CPC would trigger.
        public let worstRatio: Double
        /// Duration (seconds) at which the rider is closest to the threshold.
        public let criticalDuration: TimeInterval
        /// Current average W/kg at the critical duration.
        public let currentWkg: Double
        /// CPC threshold W/kg at the critical duration.
        public let thresholdWkg: Double
    }

    private struct Sample {
        let timestamp: TimeInterval
        let wkg: Double
    }

    private var samples: [Sample] = []
    private let weightKg: Double
    private let hasPowerMeter: Bool
    private var elapsedTime: TimeInterval = 0

    /// Durations to check against the CPC reference curve (seconds).
    private static let checkDurations: [TimeInterval] = [5, 30, 60, 120, 300, 600, 1200, 3600]

    public init(weightKg: Double = 75.0, hasPowerMeter: Bool = true) {
        self.weightKg = max(30, weightKg)
        self.hasPowerMeter = hasPowerMeter
    }

    /// Record a power sample and advance the window.
    /// - Parameters:
    ///   - powerWatts: instantaneous power in watts
    ///   - dt: time step in seconds
    /// - Returns: current CPC analysis snapshot
    @discardableResult
    public func record(powerWatts: Double, dt: Double) -> CPCSnapshot {
        let dt = max(0.001, dt)
        elapsedTime += dt
        let wkg = max(0, powerWatts) / weightKg

        samples.append(Sample(timestamp: elapsedTime, wkg: wkg))

        // Prune samples older than the longest check duration + buffer
        let maxWindow = Self.checkDurations.last! + 10
        let cutoff = elapsedTime - maxWindow
        if let firstValid = samples.firstIndex(where: { $0.timestamp > cutoff }) {
            if firstValid > 0 {
                samples.removeFirst(firstValid)
            }
        }

        return analyze()
    }

    /// Analyze current window against all CPC durations.
    public func analyze() -> CPCSnapshot {
        var worstRatio: Double = 0
        var criticalDuration: TimeInterval = 0
        var currentWkg: Double = 0
        var thresholdWkg: Double = 0

        for duration in Self.checkDurations {
            // Only check durations we have data for
            guard elapsedTime >= duration else { continue }

            let avgWkg = averageWkg(over: duration)
            let threshold = CPCReferenceCurves.detectionThreshold(at: duration, hasPowerMeter: hasPowerMeter)
            let ratio = threshold > 0 ? avgWkg / threshold : 0

            if ratio > worstRatio {
                worstRatio = ratio
                criticalDuration = duration
                currentWkg = avgWkg
                thresholdWkg = threshold
            }
        }

        let status: CPCStatus
        if worstRatio > 1.0 {
            status = .flagged
        } else if worstRatio > 0.9 {
            status = .danger
        } else if worstRatio > 0.7 {
            status = .warning
        } else {
            status = .safe
        }

        return CPCSnapshot(
            status: status,
            worstRatio: worstRatio,
            criticalDuration: criticalDuration,
            currentWkg: currentWkg,
            thresholdWkg: thresholdWkg
        )
    }

    /// Calculate average W/kg over the last N seconds.
    private func averageWkg(over duration: TimeInterval) -> Double {
        let windowStart = elapsedTime - duration
        let relevantSamples = samples.filter { $0.timestamp > windowStart }
        guard !relevantSamples.isEmpty else { return 0 }
        let sum = relevantSamples.reduce(0.0) { $0 + $1.wkg }
        return sum / Double(relevantSamples.count)
    }

    /// Reset the sliding window (e.g., on new ride).
    public func reset() {
        samples.removeAll()
        elapsedTime = 0
    }

    /// Current elapsed time tracked by the window.
    public var currentElapsedTime: TimeInterval { elapsedTime }
}
