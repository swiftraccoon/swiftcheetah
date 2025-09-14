import Foundation

/// Pure encoders for GATT characteristics to allow unit testing without CoreBluetooth.
enum BLEEncoding {
    /// Encode FTMS Indoor Bike Data (0x2AD2).
    /// - Parameters:
    ///   - cadenceRpm: optional cadence in rpm; encoded at 0.5 rpm units if present.
    ///   - powerW: optional instantaneous power in watts; encoded as Int16 if present.
    /// - Returns: Data payload: [flags,u16] [speed u16=0] [cadence u16?] [power s16?]
    static func ftmsIndoorBikeData(cadenceRpm: Int?, powerW: Int?) -> Data {
        var flags: UInt16 = 0
        if let c = cadenceRpm, c > 0 { flags |= 1 << 2 }
        if let p = powerW, p != 0 { flags |= 1 << 6 }
        var data = Data(count: 8)
        var i = 0
        func putU16(_ v: UInt16) { data[i] = UInt8(truncatingIfNeeded: v & 0xFF); data[i+1] = UInt8(truncatingIfNeeded: v >> 8); i += 2 }
        func putS16(_ v: Int16) { putU16(UInt16(bitPattern: v)) }
        putU16(flags)
        // Instantaneous speed: set to 0.00 m/s (two bytes LE)
        putU16(0)
        if (flags & (1 << 2)) != 0 {
            let raw = UInt16(max(0, min(65535, (cadenceRpm ?? 0) * 2)))
            putU16(raw)
        }
        if (flags & (1 << 6)) != 0 {
            putS16(Int16(clamping: powerW ?? 0))
        }
        return data.prefix(i)
    }

    /// Encode CPS Measurement (0x2A63).
    /// - Returns: Data beginning with flags, followed by present fields in order.
    static func cpsMeasurement(powerW: Int?, wheelCount: UInt32?, wheelTime2048: UInt16?, crankRevs: UInt16?, crankTime1024: UInt16?) -> Data {
        var flags: UInt16 = 0
        if wheelCount != nil && wheelTime2048 != nil { flags |= 0x10 }
        if crankRevs != nil && crankTime1024 != nil { flags |= 0x20 }
        var d = Data()
        func putU16(_ v: UInt16) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
        func putS16(_ v: Int16) { putU16(UInt16(bitPattern: v)) }
        func putU32(_ v: UInt32) {
            d.append(UInt8(truncatingIfNeeded: v & 0xFF))
            d.append(UInt8(truncatingIfNeeded: (v >> 8) & 0xFF))
            d.append(UInt8(truncatingIfNeeded: (v >> 16) & 0xFF))
            d.append(UInt8(truncatingIfNeeded: (v >> 24) & 0xFF))
        }
        putU16(flags)
        putS16(Int16(clamping: powerW ?? 0))
        if (flags & 0x10) != 0 { putU32(wheelCount!); putU16(wheelTime2048!) }
        if (flags & 0x20) != 0 { putU16(crankRevs!); putU16(crankTime1024!) }
        return d
    }

    /// Encode RSC Measurement (0x2A53) with no optional fields.
    static func rscMeasurement(speedMps: Double, cadence: Int) -> Data {
        var d = Data()
        d.append(0x00) // flags
        let speedRaw = UInt16(max(0, min(65535, Int(speedMps * 256))))
        d.append(UInt8(truncatingIfNeeded: speedRaw & 0xFF))
        d.append(UInt8(truncatingIfNeeded: speedRaw >> 8))
        d.append(UInt8(truncatingIfNeeded: max(0, min(255, cadence))))
        return d
    }
}
