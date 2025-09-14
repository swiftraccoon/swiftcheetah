import Foundation

/// Simple bit flag helpers for 32-bit masks.
public enum Flags {
    /// Returns true if the bit at `bit` is set.
    public static func isSet(_ value: UInt32, bit: Int) -> Bool {
        guard bit >= 0 && bit < 32 else { return false }
        return (value & (1 << bit)) != 0
    }

    /// Sets the bit at `bit` and returns the updated mask.
    public static func set(_ value: UInt32, bit: Int) -> UInt32 {
        guard bit >= 0 && bit < 32 else { return value }
        return value | (1 << bit)
    }

    /// Clears the bit at `bit` and returns the updated mask.
    public static func clear(_ value: UInt32, bit: Int) -> UInt32 {
        guard bit >= 0 && bit < 32 else { return value }
        return value & ~(1 << bit)
    }
}
