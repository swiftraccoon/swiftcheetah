import Foundation

/// Standardized error handling and logging system for SwiftCheetah
public final class ErrorHandler: @unchecked Sendable {

    /// Error severity levels for categorization and filtering
    public enum Severity: String, CaseIterable, Sendable {
        case critical = "CRITICAL"  // System-breaking errors
        case error = "ERROR"        // Operations failed but system continues
        case warning = "WARNING"    // Invalid inputs that were corrected
        case info = "INFO"          // Normal operational events
    }

    /// Error categories for better organization
    public enum Category: String, CaseIterable, Sendable {
        case ble = "BLE"                    // Bluetooth communication
        case simulation = "SIMULATION"     // Physics/cadence calculations
        case validation = "VALIDATION"     // Input parameter validation
        case system = "SYSTEM"             // Initialization, configuration
    }

    /// Standard error entry with context
    public struct ErrorEntry: Sendable {
        public let timestamp: Date
        public let severity: Severity
        public let category: Category
        public let message: String
        public let context: [String: String]

        public var formattedMessage: String {
            let timeStr = ISO8601DateFormatter().string(from: timestamp)
            let contextStr = context.isEmpty ? "" : " | \(context.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"
            return "[\(timeStr)] \(severity.rawValue) [\(category.rawValue)] \(message)\(contextStr)"
        }
    }

    /// Shared instance for consistent logging across components
    public static let shared = ErrorHandler()

    private var entries: [ErrorEntry] = []
    private let queue = DispatchQueue(label: "com.swiftcheetah.errorhandling", qos: .utility)

    private init() {}

    /// Log an error with severity and category
    public func log(
        _ message: String,
        severity: Severity,
        category: Category,
        context: [String: String] = [:]
    ) {
        let entry = ErrorEntry(
            timestamp: Date(),
            severity: severity,
            category: category,
            message: message,
            context: context
        )

        queue.async {
            self.entries.append(entry)
            // Print to console for immediate visibility during development
            print(entry.formattedMessage)
        }
    }

    /// Get all logged entries (thread-safe)
    public func getEntries() -> [ErrorEntry] {
        return queue.sync { entries }
    }

    /// Get entries filtered by severity and/or category
    public func getEntries(
        severity: Severity? = nil,
        category: Category? = nil
    ) -> [ErrorEntry] {
        return queue.sync {
            entries.filter { entry in
                if let severity = severity, entry.severity != severity { return false }
                if let category = category, entry.category != category { return false }
                return true
            }
        }
    }

    /// Clear all entries (useful for testing)
    public func clearEntries() {
        queue.async {
            self.entries.removeAll()
        }
    }

    /// Get summary statistics
    public func getSummary() -> [Severity: Int] {
        return queue.sync {
            var summary: [Severity: Int] = [:]
            for severity in Severity.allCases {
                summary[severity] = entries.filter { $0.severity == severity }.count
            }
            return summary
        }
    }
}

/// Convenience extensions for common error patterns
public extension ErrorHandler {

    /// Log BLE communication errors
    func logBLE(
        _ message: String,
        severity: Severity = .error,
        context: [String: String] = [:]
    ) {
        log(message, severity: severity, category: .ble, context: context)
    }

    /// Log simulation calculation errors
    func logSimulation(
        _ message: String,
        severity: Severity = .warning,
        context: [String: String] = [:]
    ) {
        log(message, severity: severity, category: .simulation, context: context)
    }

    /// Log validation warnings (most common case)
    func logValidation(
        _ message: String,
        context: [String: String] = [:]
    ) {
        log(message, severity: .warning, category: .validation, context: context)
    }

    /// Log system-level errors
    func logSystem(
        _ message: String,
        severity: Severity = .error,
        context: [String: String] = [:]
    ) {
        log(message, severity: severity, category: .system, context: context)
    }
}