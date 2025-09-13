import Foundation

/// Lightweight numeric utilities for input sanitization and clamping.
public enum ValueValidator {
    /// Returns `value` clamped into the closed interval [min, max].
    public static func clamped(_ value: Double, min: Double, max: Double) -> Double {
        return Swift.max(min, Swift.min(max, value))
    }

    /// True if the value is finite and not NaN.
    public static func isFinite(_ value: Double) -> Bool {
        return value.isFinite && !value.isNaN
    }

    /// Returns the value if finite; otherwise `nil`.
    public static func optionalFinite(_ value: Double?) -> Double? {
        guard let v = value, isFinite(v) else { return nil }
        return v
    }
}
