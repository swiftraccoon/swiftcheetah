import Foundation

/// Little-endian byte reader helpers for BLE payload decoding.
enum ByteReader {
    static func u8(_ data: Data, _ idx: inout Int) -> UInt8? {
        guard idx + 1 <= data.count else { return nil }
        defer { idx += 1 }
        return data[idx]
    }
    static func u16(_ data: Data, _ idx: inout Int) -> UInt16? {
        guard idx + 2 <= data.count else { return nil }
        let v = UInt16(data[idx]) | (UInt16(data[idx+1]) << 8)
        idx += 2
        return v
    }
    static func s16(_ data: Data, _ idx: inout Int) -> Int16? {
        guard let u = u16(data, &idx) else { return nil }
        return Int16(bitPattern: u)
    }
    static func u24(_ data: Data, _ idx: inout Int) -> UInt32? {
        guard idx + 3 <= data.count else { return nil }
        let b0 = UInt32(data[idx])
        let b1 = UInt32(data[idx+1])
        let b2 = UInt32(data[idx+2])
        idx += 3
        return b0 | (b1 << 8) | (b2 << 16)
    }
    static func u32(_ data: Data, _ idx: inout Int) -> UInt32? {
        guard idx + 4 <= data.count else { return nil }
        let b0 = UInt32(data[idx])
        let b1 = UInt32(data[idx+1])
        let b2 = UInt32(data[idx+2])
        let b3 = UInt32(data[idx+3])
        idx += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}

/// Subset of Cycling Power Measurement fields we use (power, cadence).
struct CPSMeasurement {
    let instantaneousPower: Int16 // Watts
    let cadenceRpm: Double?

    /// Parses CPS Measurement, computing cadence from crank deltas when available.
    static func parse(_ data: Data, state: inout CPSState) -> CPSMeasurement? {
        var i = 0
        guard let flags = ByteReader.u16(data, &i), let power = ByteReader.s16(data, &i) else { return nil }
        let pedalCrankDataPresent = (flags & 0x0020) != 0 // Bit 5 per spec
        var cadence: Double?
        // Optional fields prior to Crank may include Wheel Revolution Data; skip if present
        let wheelRevolutionDataPresent = (flags & 0x0001) != 0
        if wheelRevolutionDataPresent {
            // Cumulative Wheel Revolutions (u32) + Last Wheel Event Time (u16)
            _ = ByteReader.u32(data, &i)
            _ = ByteReader.u16(data, &i)
        }
        if pedalCrankDataPresent {
            if let crankRevs = ByteReader.u16(data, &i), let lastCrankTime = ByteReader.u16(data, &i) {
                if let prevRevs = state.lastCrankRevs, let prevTime = state.lastCrankEventTime {
                    let revDelta = Int((crankRevs &- prevRevs))
                    let timeDeltaTicks = Int((lastCrankTime &- prevTime)) // 1/1024 s
                    if timeDeltaTicks > 0 {
                        let timeSec = Double(timeDeltaTicks) / 1024.0
                        cadence = (Double(revDelta) / timeSec) * 60.0
                    }
                }
                state.lastCrankRevs = crankRevs
                state.lastCrankEventTime = lastCrankTime
            }
        }
        return CPSMeasurement(instantaneousPower: power, cadenceRpm: cadence)
    }
}

/// Subset of FTMS Indoor Bike Data fields (speed, cadence, power).
struct FTMSIndoorBikeData {
    let speedMps: Double?
    let cadenceRpm: Double?
    let instantaneousPowerWatts: Int16?

    // Per FTMS: Instantaneous Speed unit 0.01 m/s, Instantaneous Cadence unit 0.5 rpm
    /// Parses FTMS Indoor Bike Data characteristics.
    static func parse(_ data: Data) -> FTMSIndoorBikeData? {
        var i = 0
        guard let flags = ByteReader.u16(data, &i) else { return nil }
        var speed: Double?
        var cadence: Double?
        var power: Int16?

        // Field presence bits from Bluetooth FTMS spec (subset)
        let moreData = (flags & 0x0001) != 0
        _ = moreData // unused here
        let avgSpeedPresent = (flags & 0x0002) != 0
        let instCadencePresent = (flags & 0x0004) != 0
        let avgCadencePresent = (flags & 0x0008) != 0
        let totalDistancePresent = (flags & 0x0010) != 0
        let resistanceLevelPresent = (flags & 0x0020) != 0
        let instPowerPresent = (flags & 0x0040) != 0
        // Parsing order per spec
        if let rawSpeed = ByteReader.u16(data, &i) {
            speed = Double(rawSpeed) / 100.0 // 0.01 m/s
        }
        if avgSpeedPresent { _ = ByteReader.u16(data, &i) }
        if instCadencePresent, let rawCad = ByteReader.u16(data, &i) {
            cadence = Double(rawCad) * 0.5 // 0.5 rpm units
        }
        if avgCadencePresent { _ = ByteReader.u16(data, &i) }
        if totalDistancePresent { _ = ByteReader.u24(data, &i) }
        if resistanceLevelPresent { _ = ByteReader.s16(data, &i) }
        if instPowerPresent, let p = ByteReader.s16(data, &i) { power = p }
        return FTMSIndoorBikeData(speedMps: speed, cadenceRpm: cadence, instantaneousPowerWatts: power)
    }
}

/// Subset of RSC Measurement fields (speed, cadence).
struct RSCMeasurement {
    let speedMps: Double?
    let cadenceRpm: Double?

    // RSC: instantaneous speed in m/s with resolution of 1/256, cadence in steps/min
    /// Parses Running Speed and Cadence data.
    static func parse(_ data: Data) -> RSCMeasurement? {
        var i = 0
        guard let flags = ByteReader.u8(data, &i) else { return nil }
        let instStrideLenPresent = (flags & 0x01) != 0
        let totalDistancePresent = (flags & 0x02) != 0
        _ = instStrideLenPresent
        if let speedRaw = ByteReader.u16(data, &i), let cadenceRaw = ByteReader.u8(data, &i) {
            let speed = Double(speedRaw) / 256.0
            let cadence = Double(cadenceRaw)
            if instStrideLenPresent { _ = ByteReader.u16(data, &i) }
            if totalDistancePresent { _ = ByteReader.u32Compat(data, &i) }
            return RSCMeasurement(speedMps: speed, cadenceRpm: cadence)
        }
        return nil
    }
}

private extension ByteReader {
    static func u32Compat(_ data: Data, _ idx: inout Int) -> UInt32? {
        return u32(data, &idx)
    }
}
