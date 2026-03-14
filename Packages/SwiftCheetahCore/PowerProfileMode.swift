import Foundation

/// Power profile modes that control how generated power interacts with
/// Zwift's CPC anti-cheat system.
public enum PowerProfileMode: String, Sendable, CaseIterable {
    /// No power limiting. Current behavior.
    case uncapped

    /// Automatically caps power to stay below CPC detection thresholds
    /// at all tracked durations. Uses CPCSlidingWindow to monitor.
    case cpcSafe

    /// Generates power at 95% of CPC threshold — for mapping
    /// exactly where detection triggers.
    case cpcEdge
}

/// Event simulation presets that configure BLE services and anti-cheat parameters.
public struct EventPreset: Sendable {
    public let name: String
    public let tag: String
    /// Which BLE services should be active.
    public let requiresFTMS: Bool
    public let requiresCPS: Bool
    public let requiresHRS: Bool
    /// CPC threshold multiplier override (nil = use default based on PM presence).
    public let cpcMultiplierOverride: Double?
    /// Whether sandbagger detection is active.
    public let sandbaggerActive: Bool

    public init(name: String, tag: String, requiresFTMS: Bool = true,
                requiresCPS: Bool = false, requiresHRS: Bool = false,
                cpcMultiplierOverride: Double? = nil, sandbaggerActive: Bool = false) {
        self.name = name; self.tag = tag
        self.requiresFTMS = requiresFTMS; self.requiresCPS = requiresCPS
        self.requiresHRS = requiresHRS
        self.cpcMultiplierOverride = cpcMultiplierOverride
        self.sandbaggerActive = sandbaggerActive
    }
}

extension EventPreset {
    /// Free ride — no restrictions, no detection.
    public static let freeRide = EventPreset(
        name: "Free Ride", tag: ""
    )

    /// No flagging — all detection disabled.
    public static let noFlagging = EventPreset(
        name: "No Flagging", tag: "#no_flagging",
        cpcMultiplierOverride: 999.0  // effectively disabled
    )

    /// Anti-sandbagging — sandbagger penalties active.
    public static let antiSandbagging = EventPreset(
        name: "Anti-Sandbagging", tag: "#antisandbagging",
        sandbaggerActive: true
    )

    /// HRM required — activates HRS.
    public static let hrmRequired = EventPreset(
        name: "HRM Required", tag: "#hrm_required",
        requiresHRS: true
    )

    /// PM required — ensures CPS active, stricter CPC threshold.
    public static let pmRequired = EventPreset(
        name: "PM Required", tag: "#pm_required",
        requiresCPS: true,
        cpcMultiplierOverride: ZwiftThresholds.cpcThresholdWithPM
    )

    /// All presets in display order.
    public static let allPresets: [EventPreset] = [
        .freeRide, .noFlagging, .antiSandbagging, .hrmRequired, .pmRequired
    ]
}

/// Applies power profile capping logic to a target power value.
public enum PowerProfileCapper {
    /// Apply the active power profile mode to cap power if needed.
    /// - Parameters:
    ///   - targetPower: desired power in watts
    ///   - mode: active power profile mode
    ///   - window: CPC sliding window tracking current ride
    ///   - weightKg: rider weight in kg
    ///   - hasPowerMeter: whether the rider has a power meter
    /// - Returns: possibly capped power in watts
    public static func apply(
        targetPower: Int,
        mode: PowerProfileMode,
        window: CPCSlidingWindow,
        weightKg: Double,
        hasPowerMeter: Bool
    ) -> Int {
        switch mode {
        case .uncapped:
            return targetPower

        case .cpcSafe:
            // Cap to safe ceiling at current ride duration
            let ceiling = CPCReferenceCurves.safePowerCeiling(
                weightKg: weightKg,
                at: max(1, window.currentElapsedTime),
                hasPowerMeter: hasPowerMeter
            )
            return min(targetPower, Int(ceiling))

        case .cpcEdge:
            // Target 95% of the detection threshold
            let threshold = CPCReferenceCurves.detectionThreshold(
                at: max(1, window.currentElapsedTime),
                hasPowerMeter: hasPowerMeter
            )
            let edgePower = Int(threshold * weightKg * 0.95)
            return edgePower
        }
    }
}
