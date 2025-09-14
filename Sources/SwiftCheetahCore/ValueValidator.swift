import Foundation

/// ValueValidator - Comprehensive validation for cycling simulation values
///
/// This module validates simulation parameters against real-world constraints
/// to ensure realistic behavior and prevent impossible value combinations.
///
/// Based on research and empirical cycling data:
/// - Power limits based on rider category (recreational to pro)
/// - Speed constraints based on gradient and power
/// - Cadence physiological limits
/// - Heart rate zones and maximum values
public final class ValueValidator {

    /// Warning levels for validation issues
    public enum ValidationLevel: String {
        case valid = "Valid"
        case warning = "Warning"
        case error = "Error"
        case critical = "Critical"
    }

    /// Validation result with level and message
    public struct ValidationResult {
        public let level: ValidationLevel
        public let message: String
        public let parameter: String

        public var isValid: Bool {
            level == .valid
        }
    }

    /// Rider categories for context-aware limits
    public enum RiderCategory {
        case recreational  // < 200W FTP
        case enthusiast    // 200-250W FTP
        case competitive   // 250-350W FTP
        case elite        // 350-450W FTP
        case professional // > 450W FTP

        var maxSustainedPower: Double {
            switch self {
            case .recreational: return 250
            case .enthusiast: return 350
            case .competitive: return 450
            case .elite: return 550
            case .professional: return 650
            }
        }

        var maxSprintPower: Double {
            switch self {
            case .recreational: return 600
            case .enthusiast: return 900
            case .competitive: return 1200
            case .elite: return 1500
            case .professional: return 2000
            }
        }
    }

    private let category: RiderCategory

    public init(category: RiderCategory = .enthusiast) {
        self.category = category
    }

    /// Validate power value in context
    public func validatePower(_ power: Double, duration: TimeInterval = 0) -> ValidationResult {
        // Negative power is invalid
        if power < 0 {
            return ValidationResult(level: .error, message: "Power cannot be negative", parameter: "power")
        }

        // Check against absolute maximum (world record ~2600W sprint)
        if power > 2600 {
            return ValidationResult(level: .critical, message: "Power exceeds world record levels", parameter: "power")
        }

        // Check against category limits
        if duration < 10 {
            // Sprint effort
            if power > category.maxSprintPower {
                return ValidationResult(level: .warning,
                    message: "Sprint power exceeds typical for category", parameter: "power")
            }
        } else if duration > 60 {
            // Sustained effort
            if power > category.maxSustainedPower {
                return ValidationResult(level: .warning,
                    message: "Sustained power exceeds typical for category", parameter: "power")
            }
        }

        return ValidationResult(level: .valid, message: "Power within normal range", parameter: "power")
    }

    /// Validate speed given power and gradient
    public func validateSpeed(_ speedMps: Double, power: Double, grade: Double) -> ValidationResult {
        let speedKmh = speedMps * 3.6

        // Negative speed is invalid
        if speedMps < 0 {
            return ValidationResult(level: .error, message: "Speed cannot be negative", parameter: "speed")
        }

        // Check absolute maximum (world record ~133 km/h)
        if speedKmh > 140 {
            return ValidationResult(level: .critical, message: "Speed exceeds world record", parameter: "speed")
        }

        // Context-aware checks
        if grade > 10 {
            // Steep climb
            if speedKmh > 25 {
                return ValidationResult(level: .warning,
                    message: "Speed too high for steep gradient", parameter: "speed")
            }
            if power < 150 && speedKmh > 10 {
                return ValidationResult(level: .warning,
                    message: "Speed inconsistent with low power on climb", parameter: "speed")
            }
        } else if grade < -10 {
            // Steep descent
            if speedKmh < 30 && power < 50 {
                return ValidationResult(level: .warning,
                    message: "Speed too low for steep descent", parameter: "speed")
            }
            if speedKmh > 100 {
                return ValidationResult(level: .warning,
                    message: "Dangerous descent speed", parameter: "speed")
            }
        } else {
            // Flat or moderate gradient
            if power > 300 && speedKmh < 25 {
                return ValidationResult(level: .warning,
                    message: "Speed too low for power output", parameter: "speed")
            }
            if power < 100 && speedKmh > 40 {
                return ValidationResult(level: .warning,
                    message: "Speed too high for power output", parameter: "speed")
            }
        }

        return ValidationResult(level: .valid, message: "Speed reasonable for conditions", parameter: "speed")
    }

    /// Validate cadence value
    public func validateCadence(_ cadence: Double, power: Double = 0) -> ValidationResult {
        // Negative cadence is invalid
        if cadence < 0 {
            return ValidationResult(level: .error, message: "Cadence cannot be negative", parameter: "cadence")
        }

        // Physiological limits
        if cadence > 200 {
            return ValidationResult(level: .critical, message: "Cadence exceeds human limits", parameter: "cadence")
        }

        if cadence > 140 {
            return ValidationResult(level: .warning, message: "Very high cadence", parameter: "cadence")
        }

        if cadence < 30 && cadence > 0 {
            return ValidationResult(level: .warning, message: "Very low cadence", parameter: "cadence")
        }

        // Context check with power
        if power > 300 && cadence < 60 {
            return ValidationResult(level: .warning,
                message: "Low cadence for high power", parameter: "cadence")
        }

        if power < 100 && cadence > 110 {
            return ValidationResult(level: .warning,
                message: "High cadence for low power", parameter: "cadence")
        }

        return ValidationResult(level: .valid, message: "Cadence within normal range", parameter: "cadence")
    }

    /// Validate gradient
    public func validateGradient(_ grade: Double) -> ValidationResult {
        // Check absolute limits (steepest roads ~35%)
        if abs(grade) > 40 {
            return ValidationResult(level: .critical, message: "Gradient exceeds road limits", parameter: "gradient")
        }

        if abs(grade) > 30 {
            return ValidationResult(level: .warning, message: "Extreme gradient", parameter: "gradient")
        }

        if grade > 20 {
            return ValidationResult(level: .warning, message: "Very steep climb", parameter: "gradient")
        }

        if grade < -20 {
            return ValidationResult(level: .warning, message: "Very steep descent", parameter: "gradient")
        }

        return ValidationResult(level: .valid, message: "Gradient within normal range", parameter: "gradient")
    }

    /// Validate heart rate
    public func validateHeartRate(_ hr: Int, age: Int = 30) -> ValidationResult {
        // Calculate max HR (rough estimate: 220 - age)
        let maxHR = 220 - age

        if hr < 30 {
            return ValidationResult(level: .critical, message: "Heart rate dangerously low", parameter: "heartRate")
        }

        if hr < 40 {
            return ValidationResult(level: .warning, message: "Very low heart rate", parameter: "heartRate")
        }

        if hr > maxHR + 10 {
            return ValidationResult(level: .critical, message: "Heart rate exceeds maximum", parameter: "heartRate")
        }

        if hr > maxHR {
            return ValidationResult(level: .warning, message: "Heart rate at maximum", parameter: "heartRate")
        }

        if hr > 200 {
            return ValidationResult(level: .warning, message: "Very high heart rate", parameter: "heartRate")
        }

        return ValidationResult(level: .valid, message: "Heart rate within normal range", parameter: "heartRate")
    }

    /// Validate complete simulation state
    public func validateSimulationState(
        power: Double,
        speed: Double,
        cadence: Double,
        grade: Double,
        heartRate: Int? = nil,
        duration: TimeInterval = 0
    ) -> [ValidationResult] {
        var results: [ValidationResult] = []

        // Individual validations
        results.append(validatePower(power, duration: duration))
        results.append(validateSpeed(speed, power: power, grade: grade))
        results.append(validateCadence(cadence, power: power))
        results.append(validateGradient(grade))

        if let hr = heartRate {
            results.append(validateHeartRate(hr))
        }

        // Cross-parameter validations

        // Power-speed consistency check
        if power > 200 && speed < 2.0 && abs(grade) < 5 {
            results.append(ValidationResult(level: .warning,
                message: "High power but low speed on moderate gradient", parameter: "power-speed"))
        }

        // Cadence-speed consistency
        if cadence > 100 && speed < 3.0 && power > 100 {
            results.append(ValidationResult(level: .warning,
                message: "High cadence but low speed", parameter: "cadence-speed"))
        }

        // Effort level consistency
        if let hr = heartRate {
            let hrPercent = Double(hr) / Double(220 - 30) // Assume age 30 for now
            let powerPercent = power / 250.0 // Assume 250W FTP

            if abs(hrPercent - powerPercent) > 0.3 {
                results.append(ValidationResult(level: .warning,
                    message: "Heart rate and power effort levels inconsistent", parameter: "hr-power"))
            }
        }

        return results.filter { $0.level != .valid }  // Only return non-valid results
    }

    /// Get safety limits for a parameter
    public func getSafetyLimits(for parameter: String) -> (min: Double, max: Double, recommended: ClosedRange<Double>)? {
        switch parameter.lowercased() {
        case "power":
            return (min: 0, max: 2000, recommended: 50...400)
        case "speed":
            return (min: 0, max: 30, recommended: 5...15)  // m/s
        case "cadence":
            return (min: 0, max: 180, recommended: 70...100)
        case "gradient", "grade":
            return (min: -30, max: 30, recommended: -10...10)
        case "heartrate", "hr":
            return (min: 40, max: 200, recommended: 100...170)
        default:
            return nil
        }
    }

    /// Clamp a value to safe limits
    public func clampToSafeLimits(_ value: Double, parameter: String) -> Double {
        guard let limits = getSafetyLimits(for: parameter) else { return value }
        return max(limits.min, min(limits.max, value))
    }
}