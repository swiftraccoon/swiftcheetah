import Foundation

/// Parser for Zwift's .ZWO workout file format (XML-based).
///
/// ZWO files define structured workouts with intervals, warmups, cooldowns,
/// and free ride segments. Power targets are specified as percentages of FTP.
public enum ZWOParser {

    /// A single interval in a workout.
    public struct Interval: Sendable {
        public enum IntervalType: String, Sendable {
            case warmup = "Warmup"
            case cooldown = "Cooldown"
            case steadyState = "SteadyState"
            case intervals = "IntervalsT"
            case freeRide = "FreeRide"
            case ramp = "Ramp"
        }

        public let type: IntervalType
        /// Duration in seconds.
        public let duration: TimeInterval
        /// Power target as fraction of FTP (e.g., 0.75 = 75% FTP).
        public let powerLow: Double
        /// End power for ramps/warmups/cooldowns (same as powerLow for steady state).
        public let powerHigh: Double
        /// Cadence target (nil if not specified).
        public let cadence: Int?
        /// For IntervalsT: number of on/off repeats.
        public let repeat_count: Int
        /// For IntervalsT: off-interval duration.
        public let offDuration: TimeInterval
        /// For IntervalsT: off-interval power as fraction of FTP.
        public let offPower: Double

        public init(type: IntervalType, duration: TimeInterval, powerLow: Double,
                    powerHigh: Double? = nil, cadence: Int? = nil,
                    repeat_count: Int = 1, offDuration: TimeInterval = 0, offPower: Double = 0.5) {
            self.type = type; self.duration = duration; self.powerLow = powerLow
            self.powerHigh = powerHigh ?? powerLow; self.cadence = cadence
            self.repeat_count = repeat_count; self.offDuration = offDuration; self.offPower = offPower
        }
    }

    /// A parsed ZWO workout.
    public struct Workout: Sendable {
        public let name: String
        public let author: String
        public let description: String
        public let intervals: [Interval]
        /// FTP override from the workout file (nil = use rider's FTP).
        public let ftpOverride: Int?

        /// Total workout duration in seconds.
        public var totalDuration: TimeInterval {
            intervals.reduce(0) { total, interval in
                if interval.type == .intervals {
                    return total + Double(interval.repeat_count) * (interval.duration + interval.offDuration)
                }
                return total + interval.duration
            }
        }
    }

    /// Parse a ZWO XML string into a Workout.
    /// - Parameter xml: ZWO file contents as a string
    /// - Returns: parsed Workout, or nil if parsing fails
    public static func parse(_ xml: String) -> Workout? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let delegate = ZWOXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.buildWorkout()
    }

    /// Parse a ZWO file from a URL.
    public static func parse(contentsOf url: URL) -> Workout? {
        guard let xml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(xml)
    }
}

// MARK: - Workout Execution

/// Drives a simulation through a parsed ZWO workout, advancing power targets over time.
public final class WorkoutExecutor: @unchecked Sendable {

    public enum ExecutorState: Sendable {
        case idle
        case running
        case paused
        case completed
    }

    public struct Status: Sendable {
        public let state: ExecutorState
        public let currentInterval: Int
        public let intervalName: String
        public let targetPowerFTP: Double
        public let targetCadence: Int?
        public let elapsedInInterval: TimeInterval
        public let intervalDuration: TimeInterval
        public let totalElapsed: TimeInterval
        public let totalDuration: TimeInterval
    }

    private let workout: ZWOParser.Workout
    private let ftp: Int
    private var elapsed: TimeInterval = 0
    private var state: ExecutorState = .idle

    /// Flattened timeline: each entry is (startTime, duration, powerFraction, cadence, label)
    private let timeline: [(start: TimeInterval, duration: TimeInterval, power: Double, cadence: Int?, label: String)]

    public init(workout: ZWOParser.Workout, ftp: Int) {
        self.workout = workout
        self.ftp = workout.ftpOverride ?? ftp

        // Build flattened timeline from intervals
        var entries: [(start: TimeInterval, duration: TimeInterval, power: Double, cadence: Int?, label: String)] = []
        var t: TimeInterval = 0

        for interval in workout.intervals {
            switch interval.type {
            case .intervals:
                for rep in 0..<interval.repeat_count {
                    entries.append((t, interval.duration, interval.powerLow, interval.cadence,
                                    "\(interval.type.rawValue) \(rep+1)/\(interval.repeat_count) ON"))
                    t += interval.duration
                    entries.append((t, interval.offDuration, interval.offPower, nil,
                                    "\(interval.type.rawValue) \(rep+1)/\(interval.repeat_count) OFF"))
                    t += interval.offDuration
                }
            default:
                entries.append((t, interval.duration, interval.powerLow, interval.cadence, interval.type.rawValue))
                t += interval.duration
            }
        }
        self.timeline = entries
    }

    /// Advance the workout by dt seconds and return target power in watts.
    public func advance(dt: Double) -> (powerWatts: Int, cadence: Int?, status: Status) {
        guard state == .running || state == .idle else {
            return (0, nil, currentStatus())
        }
        if state == .idle { state = .running }

        elapsed += dt

        if elapsed >= workout.totalDuration {
            state = .completed
            return (0, nil, currentStatus())
        }

        // Find current timeline entry
        guard let entry = timeline.last(where: { $0.start <= elapsed }) else {
            return (ftp, nil, currentStatus())
        }

        let progressInEntry = elapsed - entry.start
        let entryIdx = timeline.firstIndex(where: { $0.start == entry.start }) ?? 0

        // For ramps/warmups/cooldowns, interpolate power
        let interval = workout.intervals.isEmpty ? nil : findInterval(at: elapsed)
        let powerFraction: Double
        if let interval = interval, (interval.type == .warmup || interval.type == .cooldown || interval.type == .ramp) {
            let progress = min(1.0, progressInEntry / max(1, entry.duration))
            powerFraction = interval.powerLow + (interval.powerHigh - interval.powerLow) * progress
        } else {
            powerFraction = entry.power
        }

        let targetWatts = Int(powerFraction * Double(ftp))

        let status = Status(
            state: state,
            currentInterval: entryIdx,
            intervalName: entry.label,
            targetPowerFTP: powerFraction,
            targetCadence: entry.cadence,
            elapsedInInterval: progressInEntry,
            intervalDuration: entry.duration,
            totalElapsed: elapsed,
            totalDuration: workout.totalDuration
        )

        return (targetWatts, entry.cadence, status)
    }

    public func pause() { if state == .running { state = .paused } }
    public func resume() { if state == .paused { state = .running } }
    public func reset() { elapsed = 0; state = .idle }

    private func currentStatus() -> Status {
        Status(state: state, currentInterval: 0, intervalName: state == .completed ? "Complete" : "Idle",
               targetPowerFTP: 0, targetCadence: nil, elapsedInInterval: 0,
               intervalDuration: 0, totalElapsed: elapsed, totalDuration: workout.totalDuration)
    }

    private func findInterval(at time: TimeInterval) -> ZWOParser.Interval? {
        var t: TimeInterval = 0
        for interval in workout.intervals {
            let dur = interval.type == .intervals
                ? Double(interval.repeat_count) * (interval.duration + interval.offDuration)
                : interval.duration
            if time < t + dur { return interval }
            t += dur
        }
        return nil
    }
}

// MARK: - XML Parsing

private class ZWOXMLDelegate: NSObject, XMLParserDelegate {
    private var name = ""
    private var author = ""
    private var workoutDescription = ""
    private var intervals: [ZWOParser.Interval] = []
    private var ftpOverride: Int?
    private var currentElement = ""
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "workout_file":
            break
        case "name", "author", "description":
            break
        case "Warmup":
            intervals.append(parseRampInterval(.warmup, attrs: attributeDict))
        case "Cooldown":
            intervals.append(parseRampInterval(.cooldown, attrs: attributeDict))
        case "SteadyState":
            intervals.append(parseSteadyState(attrs: attributeDict))
        case "IntervalsT":
            intervals.append(parseIntervalsT(attrs: attributeDict))
        case "FreeRide":
            intervals.append(parseFreeRide(attrs: attributeDict))
        case "Ramp":
            intervals.append(parseRampInterval(.ramp, attrs: attributeDict))
        default:
            break
        }

        if let ftp = attributeDict["ftpOverride"] ?? attributeDict["ftpFemaleOverride"] ?? attributeDict["ftpMaleOverride"] {
            ftpOverride = Int(ftp)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "name": name = text
        case "author": author = text
        case "description": workoutDescription = text
        default: break
        }
    }

    func buildWorkout() -> ZWOParser.Workout {
        ZWOParser.Workout(name: name, author: author, description: workoutDescription,
                          intervals: intervals, ftpOverride: ftpOverride)
    }

    private func parseRampInterval(_ type: ZWOParser.Interval.IntervalType,
                                    attrs: [String: String]) -> ZWOParser.Interval {
        ZWOParser.Interval(
            type: type,
            duration: TimeInterval(attrs["Duration"] ?? "0") ?? 0,
            powerLow: Double(attrs["PowerLow"] ?? attrs["Power"] ?? "0.5") ?? 0.5,
            powerHigh: Double(attrs["PowerHigh"] ?? attrs["Power"] ?? "0.5") ?? 0.5,
            cadence: attrs["Cadence"].flatMap { Int($0) }
        )
    }

    private func parseSteadyState(attrs: [String: String]) -> ZWOParser.Interval {
        ZWOParser.Interval(
            type: .steadyState,
            duration: TimeInterval(attrs["Duration"] ?? "0") ?? 0,
            powerLow: Double(attrs["Power"] ?? "0.5") ?? 0.5,
            cadence: attrs["Cadence"].flatMap { Int($0) }
        )
    }

    private func parseIntervalsT(attrs: [String: String]) -> ZWOParser.Interval {
        ZWOParser.Interval(
            type: .intervals,
            duration: TimeInterval(attrs["OnDuration"] ?? "0") ?? 0,
            powerLow: Double(attrs["OnPower"] ?? attrs["PowerOnZone"] ?? "1.0") ?? 1.0,
            cadence: attrs["Cadence"] .flatMap { Int($0) },
            repeat_count: Int(attrs["Repeat"] ?? "1") ?? 1,
            offDuration: TimeInterval(attrs["OffDuration"] ?? "0") ?? 0,
            offPower: Double(attrs["OffPower"] ?? attrs["PowerOffZone"] ?? "0.5") ?? 0.5
        )
    }

    private func parseFreeRide(attrs: [String: String]) -> ZWOParser.Interval {
        ZWOParser.Interval(
            type: .freeRide,
            duration: TimeInterval(attrs["Duration"] ?? "0") ?? 0,
            powerLow: 0,
            cadence: attrs["Cadence"].flatMap { Int($0) }
        )
    }
}
