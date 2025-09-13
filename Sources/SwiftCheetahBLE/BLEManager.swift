import Foundation
import CoreBluetooth
import Combine

/// Discovered BLE device summary used in the UI.
public struct BLEDevice: Identifiable, Hashable, Sendable {
    public var id: UUID { peripheralIdentifier }
    public let name: String
    public let peripheralIdentifier: UUID
}

/// BLE services we care about for fitness sensors.
public enum SensorService: CaseIterable, Sendable {
    case fitnessMachine
    case cyclingPower
    case runningSpeedCadence
    case deviceInformation

    /// The CBUUID for the service.
    public var cbUUID: CBUUID {
        switch self {
        case .fitnessMachine: return GATT.fitnessMachine
        case .cyclingPower: return GATT.cyclingPower
        case .runningSpeedCadence: return GATT.runningSpeedCadence
        case .deviceInformation: return GATT.deviceInformation
        }
    }
}

/// CoreBluetooth facade that scans, connects and publishes decoded sensor metrics.
public final class BLEManager: NSObject, ObservableObject, @unchecked Sendable {
    /// List of discovered devices during an active scan.
    @Published public private(set) var devices: [BLEDevice] = []
    /// Latest decoded metrics aggregated across relevant characteristics.
    @Published public private(set) var metrics: SensorMetrics = SensorMetrics()
    public private(set) var connectedPeripheral: CBPeripheral?

    private var central: CBCentralManager!
    private var discovered: [UUID: CBPeripheral] = [:]
    private var cpsState = CPSState()

    /// Creates a manager and initializes the central on the main queue.
    public override init() {
        super.init()
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Starts scanning for the given services.
    public func startScan(for services: [SensorService] = SensorService.allCases) {
        guard central.state == .poweredOn else { return }
        let uuids = services.map { $0.cbUUID }
        central.scanForPeripherals(withServices: uuids, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    /// Stops scanning.
    public func stopScan() {
        central.stopScan()
    }

    /// Initiates a connection to the selected device.
    public func connect(to device: BLEDevice) {
        guard let p = discovered[device.peripheralIdentifier] else { return }
        central.connect(p, options: nil)
    }

    /// Cancels the active connection, if any.
    public func disconnect() {
        if let p = connectedPeripheral {
            central.cancelPeripheralConnection(p)
        }
    }
}

nonisolated(unsafe) extension BLEManager: CBCentralManagerDelegate {
    /// Start scanning as soon as Bluetooth is powered on.
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        }
    }

    /// Track discovered peripherals and expose simplified device descriptors.
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discovered[peripheral.identifier] = peripheral
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        let device = BLEDevice(name: name, peripheralIdentifier: peripheral.identifier)
        if !devices.contains(device) {
            devices.append(device)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices(SensorService.allCases.map { $0.cbUUID })
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
        }
    }
}

nonisolated(unsafe) extension BLEManager: CBPeripheralDelegate {
    /// Discover all characteristics for the services we're interested in.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// Subscribe to notify and read initial values when available.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        guard let chars = service.characteristics else { return }
        for ch in chars {
            if ch.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: ch)
            }
            if ch.properties.contains(.read) {
                peripheral.readValue(for: ch)
            }
        }
    }

    /// Decode incoming characteristic updates into `SensorMetrics`.
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let now = Date()
        var updated = metrics

        switch characteristic.uuid {
        case GATT.cpsMeasurement:
            if var state = Optional.some(cpsState), let m = CPSMeasurement.parse(data, state: &state) {
                cpsState = state
                updated.powerWatts = Int(m.instantaneousPower)
                if let cadence = m.cadenceRpm, cadence.isFinite {
                    updated.cadenceRpm = cadence
                }
            }
        case GATT.ftmsIndoorBikeData:
            if let m = FTMSIndoorBikeData.parse(data) {
                if let s = m.speedMps, s.isFinite { updated.speedMps = s }
                if let c = m.cadenceRpm, c.isFinite { updated.cadenceRpm = c }
                if let p = m.instantaneousPowerWatts { updated.powerWatts = Int(p) }
            }
        case GATT.rscMeasurement:
            if let m = RSCMeasurement.parse(data) {
                if let s = m.speedMps, s.isFinite { updated.speedMps = s }
                if let c = m.cadenceRpm, c.isFinite { updated.cadenceRpm = c }
            }
        default:
            break
        }

        updated.timestamp = now
        metrics = updated
    }
}
