import Foundation

/// CPC (Critical Power Curve) reference data for Zwift's anti-cheat system.
///
/// Zwift compares a rider's W/kg output at various durations against these reference
/// curves. If output exceeds the threshold (0.88x with PM, 1.1x without PM), the
/// rider is flagged.
///
/// The reference values below are derived from published research on elite human
/// power output limits (Pinot & Grappe 2011, Coggan power profiling) and calibrated
/// against observed Zwift CPC behavior. Exact Zwift values from DAT_1022b0c20 may
/// differ slightly.
public enum CPCReferenceCurves {

    /// A single point on the reference power curve.
    public struct CurvePoint: Sendable {
        /// Duration in seconds.
        public let duration: TimeInterval
        /// Maximum credible W/kg at this duration (male elite reference).
        public let maxWkg: Double

        public init(duration: TimeInterval, maxWkg: Double) {
            self.duration = duration
            self.maxWkg = maxWkg
        }
    }

    /// Reference curve points representing the upper boundary of credible human performance.
    /// Based on male elite limits. Zwift applies these with threshold multipliers.
    ///
    /// Sources:
    /// - Pinot & Grappe (2011): Record power profile for professional cyclists
    /// - Coggan Power Profiling: functional threshold zones
    /// - Observed Zwift CPC trigger behavior from community reports
    public static let referenceCurve: [CurvePoint] = [
        CurvePoint(duration: 1,     maxWkg: 25.0),   // 1s sprint peak
        CurvePoint(duration: 5,     maxWkg: 24.0),   // 5s neuromuscular
        CurvePoint(duration: 10,    maxWkg: 20.0),   // 10s anaerobic
        CurvePoint(duration: 30,    maxWkg: 14.0),   // 30s anaerobic capacity
        CurvePoint(duration: 60,    maxWkg: 11.5),   // 1min VO2max burst
        CurvePoint(duration: 120,   maxWkg: 9.5),    // 2min
        CurvePoint(duration: 300,   maxWkg: 7.5),    // 5min VO2max
        CurvePoint(duration: 600,   maxWkg: 7.0),    // 10min
        CurvePoint(duration: 1200,  maxWkg: 6.4),    // 20min threshold
        CurvePoint(duration: 3600,  maxWkg: 6.1),    // 1hr FTP
        CurvePoint(duration: 7200,  maxWkg: 5.5),    // 2hr endurance
        CurvePoint(duration: 14400, maxWkg: 4.8),    // 4hr endurance
    ]

    /// Interpolate the maximum credible W/kg at a given duration.
    /// Uses log-linear interpolation between reference points.
    /// - Parameter duration: ride duration in seconds (clamped to curve range)
    /// - Returns: maximum credible W/kg for this duration
    public static func maxWkg(at duration: TimeInterval) -> Double {
        let d = max(1, min(14400, duration))

        // Find bounding points
        guard let upper = referenceCurve.first(where: { $0.duration >= d }) else {
            return referenceCurve.last!.maxWkg
        }
        guard let lowerIdx = referenceCurve.lastIndex(where: { $0.duration <= d }) else {
            return referenceCurve.first!.maxWkg
        }

        let lower = referenceCurve[lowerIdx]

        // Exact match
        if lower.duration == upper.duration { return lower.maxWkg }

        // Log-linear interpolation (power curves are approximately linear in log-duration)
        let logRatio = log(d / lower.duration) / log(upper.duration / lower.duration)
        return lower.maxWkg + (upper.maxWkg - lower.maxWkg) * logRatio
    }

    /// Get the CPC detection threshold W/kg at a given duration.
    /// - Parameters:
    ///   - duration: ride duration in seconds
    ///   - hasPowerMeter: whether the rider has a power meter (stricter threshold)
    /// - Returns: W/kg above which CPC detection triggers
    public static func detectionThreshold(at duration: TimeInterval, hasPowerMeter: Bool) -> Double {
        let base = maxWkg(at: duration)
        let multiplier = hasPowerMeter
            ? ZwiftThresholds.cpcThresholdWithPM
            : ZwiftThresholds.cpcThresholdWithoutPM
        return base * multiplier
    }

    /// Check if a given W/kg would trigger CPC detection at the specified duration.
    /// - Parameters:
    ///   - wkg: rider's watts per kilogram
    ///   - duration: elapsed ride duration in seconds
    ///   - hasPowerMeter: whether the rider has a power meter
    /// - Returns: true if output exceeds the CPC threshold
    public static func wouldTriggerCPC(wkg: Double, at duration: TimeInterval, hasPowerMeter: Bool) -> Bool {
        return wkg > detectionThreshold(at: duration, hasPowerMeter: hasPowerMeter)
    }

    /// Calculate the safe maximum power in watts for a given weight and duration.
    /// Returns power at 95% of CPC threshold for safety margin.
    /// - Parameters:
    ///   - weightKg: rider weight in kg
    ///   - duration: ride duration in seconds
    ///   - hasPowerMeter: whether the rider has a power meter
    /// - Returns: safe maximum power in watts
    public static func safePowerCeiling(weightKg: Double, at duration: TimeInterval, hasPowerMeter: Bool) -> Double {
        let threshold = detectionThreshold(at: duration, hasPowerMeter: hasPowerMeter)
        return threshold * weightKg * 0.95
    }
}
