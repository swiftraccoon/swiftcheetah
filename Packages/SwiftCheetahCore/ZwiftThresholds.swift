import Foundation

/// Constants extracted from Zwift binary reverse engineering.
///
/// All values derived from static analysis of the macOS Zwift binary via Ghidra.
/// Pre-ASLR addresses reference the `__common` and `__data` segments.
public enum ZwiftThresholds {

    // MARK: - CPC Detection

    /// CPC threshold multiplier when rider has a power meter connected.
    /// Power exceeding `referenceCurve * 0.88` at any duration triggers detection.
    public static let cpcThresholdWithPM: Double = 0.88

    /// CPC threshold multiplier when rider has no power meter.
    /// Relaxed to 1.1x (10% above reference curve) since virtual power is less accurate.
    public static let cpcThresholdWithoutPM: Double = 1.1

    // MARK: - Physics Validation (FUN_1014a1e08)

    /// Acceptable range for air density parameter (kg/m³).
    /// Values outside this range trigger auto-reset and tamper flag.
    public static let airDensityRange: ClosedRange<Double> = 0.1226...12.26

    /// Acceptable range for rolling resistance coefficient.
    public static let crrRange: ClosedRange<Double> = 0.0004...0.04

    /// Acceptable range for CdA scale factor.
    public static let cdaScaleRange: ClosedRange<Double> = 0.1...10.0

    // MARK: - Sandbagger Detection

    /// Default sandbagger penalty multiplier applied to power.
    /// At `game_state + 0x10` in the physics parameter block at `0x102646b44`.
    public static let sandbaggerPenalty: Double = 0.7

    /// Default sandbagger scale factor.
    public static let sandbaggerScale: Double = 1.0

    // MARK: - Anti-Cheat Flags (game_state offsets)

    public enum GameStateOffset: UInt32 {
        /// Primary cheat flag — set by CPC analysis and power architecture detection.
        case primaryCheatFlag = 0x3970
        /// Secondary cheat flag — set by challenge manager.
        case secondaryCheatFlag = 0x3971
        /// CPC suppress flag — setting to 1 disables CPC analysis.
        case cpcSuppressFlag = 0x3973
        /// Flagged performance — set by power/timing validation.
        case flaggedPerformance = 0x4290
        /// Lurking flag — player is not actively riding.
        case lurkingFlag = 0x4292
    }

    // MARK: - Event Tags (parsed in FUN_1017032a8)

    /// Bitfield values for Zwift event tags.
    public enum EventTag: UInt64 {
        /// Disable all cheating detection.
        case noFlagging        = 0x8000000       // #no_flagging
        /// Relax detection thresholds.
        case reducedFlagging   = 0x200000000     // #reducedflagging
        /// Enable sandbagger detection.
        case antiSandbagging   = 0x2000000000    // #antisandbagging
        /// Require heart rate monitor.
        case hrmRequired       = 0x10000000      // #hrm_required
        /// Require power meter.
        case pmRequired        = 0x20000000      // #pm_required
        /// Allow e-bikes.
        case ebike             = 0x80000000      // #ebike
        /// Red light jump detection.
        case rlj               = 0x80000         // #rlj
    }

    // MARK: - Player Immunity

    /// Player types immune to anti-cheat detection.
    /// Derived from `(1 << player_type) & 0x70C` check in FUN_1015ba584.
    public enum PlayerType: Int {
        case normal    = 0x0
        case spectator = 0x2
        case pacer     = 0x3
        case bot       = 0x8
        case ghost     = 0x9
        case selfView  = 0x10
    }

    /// Immunity bitmask: bits 2, 3, 8, 9, 10 are immune player types.
    public static let immunityMask: UInt32 = 0x70C

    /// Check if a player type is immune to anti-cheat.
    public static func isImmune(playerType: Int) -> Bool {
        return ((1 << playerType) & immunityMask) != 0
    }

    // MARK: - Integrity Verification

    /// XOR key used for checksum verification of drops and XP values.
    public static let integrityXORKey: UInt32 = 0xCE44FFE3

    /// Bit shift applied after XOR in checksum computation.
    public static let integrityShift: Int = 19

    /// Maximum bike progress delta per tick (when cap is enabled).
    public static let maxProgressDeltaPerTick: Double = 3.28

    // MARK: - Memory Addresses (pre-ASLR, macOS arm64)

    public enum MemoryAddress {
        /// Physics parameter block: [air_density, crr, cda_scale, fa_anim, sandbagger_penalty, sandbagger_scale]
        public static let physicsParams: UInt64 = 0x102646b44
        /// Segment cheat timescale (f32, writable)
        public static let segmentCheatTimescale: UInt64 = 0x102646c04
        /// CPC cheat timescale (f32, writable)
        public static let cpcCheatTimescale: UInt64 = 0x102646c08
        /// Game state chain base pointer
        public static let gameStateChain: UInt64 = 0x1028b2c88
        /// Physics tamper flag (u8)
        public static let physicsTamperFlag: UInt64 = 0x1028b28aa
    }
}
