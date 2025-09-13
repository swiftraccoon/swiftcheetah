import Foundation

/// Aggregated live metrics decoded from BLE fitness services.
public struct SensorMetrics: Sendable {
    public var timestamp: Date
    public var speedMps: Double?
    public var cadenceRpm: Double?
    public var powerWatts: Int?
    public var inclineGrade: Double?

    public init(timestamp: Date = Date(), speedMps: Double? = nil, cadenceRpm: Double? = nil, powerWatts: Int? = nil, inclineGrade: Double? = nil) {
        self.timestamp = timestamp
        self.speedMps = speedMps
        self.cadenceRpm = cadenceRpm
        self.powerWatts = powerWatts
        self.inclineGrade = inclineGrade
    }
}

/// Keeps CPS crank state to compute cadence across notifications.
struct CPSState {
    var lastCrankRevs: UInt16?
    var lastCrankEventTime: UInt16? // 1/1024s
}
