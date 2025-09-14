import CoreBluetooth

/// GATT service and characteristic UUIDs used by SwiftCheetah.
///
/// Defined as computed properties to avoid global stored state of non-Sendable types under Swift 6.
enum GATT {
    // Services
    static var fitnessMachine: CBUUID { CBUUID(string: "1826") }
    static var cyclingPower: CBUUID { CBUUID(string: "1818") }
    static var runningSpeedCadence: CBUUID { CBUUID(string: "1814") }
    static var deviceInformation: CBUUID { CBUUID(string: "180A") }

    // FTMS Characteristics
    static var ftmsIndoorBikeData: CBUUID { CBUUID(string: "2AD2") }
    static var ftmsFitnessMachineFeature: CBUUID { CBUUID(string: "2ACC") }
    static var ftmsFitnessMachineStatus: CBUUID { CBUUID(string: "2ADA") }
    static var ftmsControlPoint: CBUUID { CBUUID(string: "2AD9") }
    static var ftmsSupportedPowerRange: CBUUID { CBUUID(string: "2AD8") }

    // CPS Characteristics
    static var cpsMeasurement: CBUUID { CBUUID(string: "2A63") }

    // RSC Characteristics
    static var rscMeasurement: CBUUID { CBUUID(string: "2A53") }
}
