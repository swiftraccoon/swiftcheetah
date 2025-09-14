import Foundation
import CoreBluetooth
#if SWIFT_PACKAGE
import SwiftCheetahCore
#endif
// Pure encoders for GATT payloads
// (Keep separate from CoreBluetooth to allow unit testing.)
// BLEEncoding is internal to this module; no import needed beyond same target.

/// BLE Peripheral role: advertises FTMS/CPS/RSC and notifies measurement data.
/// PeripheralManager
/// - Advertises FTMS/CPS/RSC services with spec‑correct characteristics and descriptors; FTMS Indoor Bike Data
///   instantaneous speed is set to 0 to match common trainer implementations.
/// - Handles FTMS Control Point (Request Control, Reset, Set Target Power, Start/Stop, Set Indoor Bike Simulation)
///   and emits Fitness Machine Status notifications.
/// - Notifies measurement data at realistic rates (FTMS 4 Hz, RSC 2 Hz, CPS ≤4 Hz driven by cadence).
/// - AUTO mode uses research‑based cadence modeling (logistic power→cadence, grade effects, gear constraints) and
///   power→speed physics; see module docs for details.
public final class PeripheralManager: NSObject, ObservableObject, @unchecked Sendable {
    public enum State: String, Sendable { case idle, starting, advertising, stopped, failed }
    public struct Options: Sendable {
        public var advertiseFTMS: Bool
        public var advertiseCPS: Bool
        public var advertiseRSC: Bool
        public init(advertiseFTMS: Bool = true, advertiseCPS: Bool = true, advertiseRSC: Bool = true) {
            self.advertiseFTMS = advertiseFTMS; self.advertiseCPS = advertiseCPS; self.advertiseRSC = advertiseRSC
        }
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var isAdvertising: Bool = false
    @Published public private(set) var subscriberCount: Int = 0
    @Published public private(set) var lastError: String?
    @Published public private(set) var eventLog: [String] = []

    // Simulation inputs
    @Published public var watts: Int = 250
    @Published public var cadenceRpm: Int = 90
    @Published public var speedMps: Double = 8.33 // internal use; not user-controlled
    @Published public var gradePercent: Double = 0.0 // set via FTMS Control Point
    @Published public var randomness: Int = 0 // 0-100
    @Published public var increment: Int = 25 // power step for steppers (was powerStep)
    public enum CadenceMode: String, Sendable { case auto, manual }
    @Published public var cadenceMode: CadenceMode = .auto

    // Service toggles
    @Published public var advertiseFTMS: Bool = true
    @Published public var advertiseCPS: Bool = false
    @Published public var advertiseRSC: Bool = false
    // Field toggles for CPS and FTMS
    @Published public var cpsIncludePower: Bool = true
    @Published public var cpsIncludeCadence: Bool = true
    @Published public var cpsIncludeSpeed: Bool = true // wheel
    @Published public var ftmsIncludePower: Bool = true
    @Published public var ftmsIncludeCadence: Bool = true

    // FTMS CP state
    private var hasControl = true
    private var isStarted = true
    private var targetPower: Int = 250
    private var simWindSpeedMps: Double = 0
    private var simCrr: Double = 0.004
    private var simCw: Double = 0.51

    private var manager: CBPeripheralManager!
    private var options = Options()
    private var ftmsTimer: Timer?
    private var cpsTimer: Timer?
    private var rscTimer: Timer?
    private var lastPowerUpdate: TimeInterval = Date().timeIntervalSince1970
    private var powerMgr = PowerManager()
    private var varMgr = OrnsteinUhlenbeckVariance()
    private var cadenceMgr = CadenceManager()
    private var physicsParams = PhysicsCalculator.Parameters()

    // Services/Characteristics
    private var ftmsService: CBMutableService?
    private var ftmsIndoorBikeData: CBMutableCharacteristic?
    private var ftmsFeature: CBMutableCharacteristic?
    private var ftmsStatus: CBMutableCharacteristic?
    private var ftmsControlPoint: CBMutableCharacteristic?
    private var ftmsSupportedPowerRange: CBMutableCharacteristic?

    private var cpsService: CBMutableService?
    private var cpsMeasurement: CBMutableCharacteristic?
    private var cpsFeature: CBMutableCharacteristic?
    private var cpsSensorLocation: CBMutableCharacteristic?

    private var rscService: CBMutableService?
    private var rscMeasurement: CBMutableCharacteristic?
    private var rscFeature: CBMutableCharacteristic?
    private var rscSensorLocation: CBMutableCharacteristic?

    // Backpressure queue for indications/notifications
    private var pendingUpdates: [(CBMutableCharacteristic, Data)] = []
    // Track service registration and delay advertising until all are added
    private var servicesPendingAdd: Int = 0
    private var pendingAdvertData: [String: Any] = [:]
    // Live stats for UI
    public struct LiveStats: Sendable { public var speedKmh: Double; public var powerW: Int; public var cadenceRpm: Int; public var mode: String; public var gear: String; public var targetCadence: Int; public var fatigue: Double; public var noise: Double; public var gradePercent: Double }
    @Published public private(set) var stats: LiveStats = LiveStats(speedKmh: 25.0, powerW: 250, cadenceRpm: 90, mode: "AUTO", gear: "2x5", targetCadence: 90, fatigue: 0, noise: 0, gradePercent: 0)

    // Rolling counters for CPS
    private var revCount: UInt16 = 0
    private var cadTimeTicks: UInt16 = 0 // 1/1024s units
    private var wheelCount: UInt32 = 0
    private var wheelTimeTicks: UInt16 = 0

    public override init() {
        super.init()
        self.manager = CBPeripheralManager(delegate: self, queue: .main)

        // Start a simulation timer for UI updates even when not broadcasting
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSimulation()
        }
    }

    private func updateSimulation() {
        // Update stats for UI even when not broadcasting
        if !isAdvertising {
            let dt = 1.0
            let variation = varMgr.update(randomness: Double(randomness), targetPower: Double(watts), dt: dt)
            let realisticWatts = powerMgr.update(targetPower: watts, cadenceRPM: cadenceRpm, variation: variation, isResting: false)
            let v = PhysicsCalculator.calculateSpeed(powerWatts: Double(realisticWatts), gradePercent: gradePercent, params: physicsParams)

            let cad: Int
            if cadenceMode == .auto {
                let cadenceValue = cadenceMgr.update(power: Double(realisticWatts), grade: gradePercent, speedMps: v, dt: dt)
                cad = Int(cadenceValue.rounded())
            } else {
                cad = cadenceRpm
            }

            updateLiveStats(speedMps: v, watts: realisticWatts, cadence: cad)
        }
    }

    @Published public var localName: String = "Trainer"

    /// Begin advertising after all enabled services are added.
    public func startBroadcast(localName: String? = nil, options: Options? = nil) {
        guard manager.state == .poweredOn else { return }
        let effective = options ?? Options(advertiseFTMS: advertiseFTMS, advertiseCPS: advertiseCPS, advertiseRSC: advertiseRSC)
        self.options = effective
        state = .starting
        // Prepare advert data but start only after services added
        var serviceUUIDs: [CBUUID] = []
        if effective.advertiseFTMS { serviceUUIDs.append(GATT.fitnessMachine) }
        if effective.advertiseCPS { serviceUUIDs.append(GATT.cyclingPower) }
        if effective.advertiseRSC { serviceUUIDs.append(GATT.runningSpeedCadence) }
        pendingAdvertData = [
            CBAdvertisementDataLocalNameKey: (localName ?? self.localName),
            CBAdvertisementDataServiceUUIDsKey: serviceUUIDs
        ]
        setupServices()
    }

    public func stopBroadcast() {
        manager.stopAdvertising()
        isAdvertising = false
        state = .stopped
        ftmsTimer?.invalidate(); cpsTimer?.invalidate(); rscTimer?.invalidate()
        ftmsTimer = nil; cpsTimer = nil; rscTimer = nil
    }

    /// Create and add services/characteristics with spec‑correct properties and descriptors.
    private func setupServices() {
        servicesPendingAdd = 0
        // FTMS
        if options.advertiseFTMS {
            ftmsIndoorBikeData = CBMutableCharacteristic(type: GATT.ftmsIndoorBikeData, properties: [.notify], value: nil, permissions: [])
            ftmsIndoorBikeData?.descriptors = [
                CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Indoor Bike Data"),
                CBMutableDescriptor(type: CBUUID(string: "2902"), value: Data([0x00, 0x00])),  // Client Characteristic Configuration
                CBMutableDescriptor(type: CBUUID(string: "2904"), value: Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))  // Presentation Format
            ]
            ftmsFeature = CBMutableCharacteristic(type: GATT.ftmsFitnessMachineFeature, properties: [.read], value: nil, permissions: [.readable])
            ftmsFeature?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Fitness Machine Feature")]
            ftmsStatus = CBMutableCharacteristic(type: GATT.ftmsFitnessMachineStatus, properties: [.notify], value: nil, permissions: [])
            ftmsStatus?.descriptors = [
                CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Fitness Machine Status"),
                CBMutableDescriptor(type: CBUUID(string: "2902"), value: Data([0x00, 0x00]))  // Client Characteristic Configuration
            ]
            ftmsControlPoint = CBMutableCharacteristic(type: GATT.ftmsControlPoint, properties: [.write, .indicate], value: nil, permissions: [.writeable])
            ftmsControlPoint?.descriptors = [
                CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Fitness Machine Control Point"),
                CBMutableDescriptor(type: CBUUID(string: "2902"), value: Data([0x00, 0x00]))  // Client Characteristic Configuration for indications
            ]
            ftmsSupportedPowerRange = CBMutableCharacteristic(type: GATT.ftmsSupportedPowerRange, properties: [.read], value: nil, permissions: [.readable])
            ftmsSupportedPowerRange?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Supported Power Range")]
            let s = CBMutableService(type: GATT.fitnessMachine, primary: true)
            s.characteristics = [ftmsFeature!, ftmsIndoorBikeData!, ftmsStatus!, ftmsControlPoint!, ftmsSupportedPowerRange!]
            ftmsService = s
            servicesPendingAdd += 1
            manager.add(s)
        } else { ftmsService = nil }

        // CPS
        if options.advertiseCPS {
            cpsMeasurement = CBMutableCharacteristic(type: GATT.cpsMeasurement, properties: [.notify], value: nil, permissions: [])
            cpsMeasurement?.descriptors = [
                CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Cycling Power Measurement"),
                CBMutableDescriptor(type: CBUUID(string: "2902"), value: Data([0x00, 0x00])),  // Client Characteristic Configuration
                CBMutableDescriptor(type: CBUUID(string: "2904"), value: Data([0x0B, 0x27, 0xAD, 0x01, 0x00, 0x00, 0x00]))  // Presentation Format: sint16, watts
            ]
            cpsFeature = CBMutableCharacteristic(type: CBUUID(string: "2A65"), properties: [.read], value: nil, permissions: [.readable])
            cpsFeature?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Cycling Power Feature")]
            cpsSensorLocation = CBMutableCharacteristic(type: CBUUID(string: "2A5D"), properties: [.read], value: nil, permissions: [.readable])
            cpsSensorLocation?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Sensor Location")]
            let s = CBMutableService(type: GATT.cyclingPower, primary: true)
            s.characteristics = [cpsMeasurement!, cpsFeature!, cpsSensorLocation!]
            cpsService = s
            servicesPendingAdd += 1
            manager.add(s)
        } else { cpsService = nil }

        // RSC
        if options.advertiseRSC {
            rscMeasurement = CBMutableCharacteristic(type: GATT.rscMeasurement, properties: [.notify], value: nil, permissions: [])
            rscMeasurement?.descriptors = [
                CBMutableDescriptor(type: CBUUID(string: "2901"), value: "RSC Measurement"),
                CBMutableDescriptor(type: CBUUID(string: "2902"), value: Data([0x00, 0x00]))  // Client Characteristic Configuration
            ]
            rscFeature = CBMutableCharacteristic(type: CBUUID(string: "2A54"), properties: [.read], value: nil, permissions: [.readable])
            rscFeature?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "RSC Feature")]
            rscSensorLocation = CBMutableCharacteristic(type: CBUUID(string: "2A5D"), properties: [.read], value: nil, permissions: [.readable])
            rscSensorLocation?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Sensor Location")]
            let s = CBMutableService(type: GATT.runningSpeedCadence, primary: true)
            s.characteristics = [rscMeasurement!, rscFeature!, rscSensorLocation!]
            rscService = s
            servicesPendingAdd += 1
            manager.add(s)
        } else { rscService = nil }
    }

    /// Start periodic notifications per service (FTMS 4Hz, CPS ≤4Hz, RSC 2Hz).
    private func startTicking() {
        ftmsTimer?.invalidate(); cpsTimer?.invalidate(); rscTimer?.invalidate()
        // FTMS at 4 Hz
        ftmsTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tickFTMS() }
        // CPS dynamic interval (<=4Hz) based on cadence
        scheduleNextCPSTick()
        // RSC at 2 Hz
        rscTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tickRSC() }
    }

    /// CPS tick rate adapts to cadence (≤4Hz) to match crank event timing.
    private func scheduleNextCPSTick() {
        cpsTimer?.invalidate()
        let cad = max(0, cadenceMode == .auto ? Int(cadenceMgr.update(power: Double(watts), grade: gradePercent, speedMps: speedMps, dt: 0.25).rounded()) : cadenceRpm)
        let interval = cad > 0 ? min(0.25, 60.0 / Double(cad)) : 0.25
        cpsTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in self?.tickCPS() }
    }

    /// FTMS periodic updates: compute realistic watts (variance + trainer tau),
    /// speed from power/grade, cadence via CadenceManager (AUTO), then notify Indoor Bike Data.
    private func tickFTMS() {
        let now = Date().timeIntervalSince1970
        let dt = max(0.001, now - lastPowerUpdate)
        lastPowerUpdate = now
        // Compute speed from power + grade; then AUTO cadence via CadenceManager
        let variation = varMgr.update(randomness: Double(randomness), targetPower: Double(watts), dt: dt)
        let realisticWatts = powerMgr.update(targetPower: watts, cadenceRPM: cadenceRpm, variation: variation, isResting: false)
        let v = PhysicsCalculator.calculateSpeed(powerWatts: Double(realisticWatts), gradePercent: gradePercent, params: physicsParams)
        speedMps = v
        let cadAuto = Int(cadenceMgr.update(power: Double(realisticWatts), grade: gradePercent, speedMps: v, dt: dt).rounded())
        let cad = cadenceMode == .auto ? cadAuto : cadenceRpm
        if options.advertiseFTMS { notifyFTMS(watts: ftmsIncludePower ? realisticWatts : 0, cadence: ftmsIncludeCadence ? cad : 0) }
        advanceCounters(dt: dt, cadence: cad)
        updateLiveStats(speedMps: v, watts: realisticWatts, cadence: cad)
    }

    /// CPS periodic updates: same physics + cadence pipeline, then notify CPS Measurement.
    private func tickCPS() {
        let now = Date().timeIntervalSince1970
        let dt = max(0.001, now - lastPowerUpdate)
        lastPowerUpdate = now
        let variation = varMgr.update(randomness: Double(randomness), targetPower: Double(watts), dt: dt)
        let realisticWatts = powerMgr.update(targetPower: watts, cadenceRPM: cadenceRpm, variation: variation, isResting: false)
        let v = PhysicsCalculator.calculateSpeed(powerWatts: Double(realisticWatts), gradePercent: gradePercent, params: physicsParams)
        speedMps = v
        let cadAuto = Int(cadenceMgr.update(power: Double(realisticWatts), grade: gradePercent, speedMps: v, dt: dt).rounded())
        let cad = cadenceMode == .auto ? cadAuto : cadenceRpm
        if options.advertiseCPS { notifyCPS(watts: cpsIncludePower ? realisticWatts : 0, cadence: cpsIncludeCadence ? cad : 0, includeWheel: cpsIncludeSpeed) }
        advanceCounters(dt: dt, cadence: cad)
        scheduleNextCPSTick()
        updateLiveStats(speedMps: v, watts: realisticWatts, cadence: cad)
    }

    /// RSC periodic updates: expose running-like speed/cadence if enabled (simple cadence reuse).
    private func tickRSC() {
        let cad = cadenceMode == .auto ? Int(cadenceMgr.update(power: Double(watts), grade: gradePercent, speedMps: speedMps, dt: 0.5).rounded()) : cadenceRpm
        if options.advertiseRSC { notifyRSC(speedMps: speedMps, cadence: cad) }
    }

    /// Update crank/wheel counters and event times per spec units:
    /// - CPS cadence time in 1/1024s
    /// - CPS wheel time in 1/2048s
    private func advanceCounters(dt: Double, cadence: Int) {
        // crank
        let expectedRevs = dt * Double(cadence) / 60.0
        if expectedRevs >= 1.0 { revCount &+= UInt16(expectedRevs.rounded(.toNearestOrAwayFromZero)) }
        // cadence event time in 1/1024s (matching CPS cadence units)
        cadTimeTicks = UInt16((Date().timeIntervalSince1970 * 1024).truncatingRemainder(dividingBy: 65536))
        // wheel: use circumference 2.096m and 1/2048s tick unit
        let circumference = 2.096
        // Use a conservative fixed wheel speed for CPS to avoid exposing UI speed controls
        let cpsWheelSpeedMps = 5.0 // ~18 km/h
        let wheelRevs = dt * (cpsIncludeSpeed ? (cpsWheelSpeedMps / circumference) : 0)
        if wheelRevs >= 1.0 { wheelCount &+= UInt32(wheelRevs.rounded(.toNearestOrAwayFromZero)) }
        wheelTimeTicks = UInt16((Date().timeIntervalSince1970 * 2048).truncatingRemainder(dividingBy: 65536))
    }

    private func updateLiveStats(speedMps v: Double, watts: Int, cadence: Int) {
        let s = cadenceMgr.getState()
        stats = LiveStats(
            speedKmh: v * 3.6,
            powerW: watts,
            cadenceRpm: cadence,
            mode: cadenceMode == .auto ? "AUTO" : "MANUAL",
            gear: "\(s.gear.front)x\(s.gear.rear)",
            targetCadence: Int(s.target.rounded()),
            fatigue: s.fatigue,
            noise: s.noise,
            gradePercent: gradePercent
        )
    }

    // computeAutoCadence replaced by CadenceManager

    // MARK: - Notify Encoders
    public func notifyFTMS(watts: Int, cadence: Int) {
        guard let ch = ftmsIndoorBikeData else { return }
        let payload = BLEEncoding.ftmsIndoorBikeData(cadenceRpm: (ftmsIncludeCadence && cadence > 0) ? cadence : nil,
                                                     powerW: (ftmsIncludePower && watts != 0) ? watts : nil)
        if manager.updateValue(payload, for: ch, onSubscribedCentrals: nil) == false {
            pendingUpdates.append((ch, payload))
        }
    }

    public func notifyCPS(watts: Int, cadence: Int, includeWheel: Bool) {
        guard let ch = cpsMeasurement else { return }
        let payload = BLEEncoding.cpsMeasurement(powerW: cpsIncludePower ? watts : 0,
                                                 wheelCount: includeWheel ? wheelCount : nil,
                                                 wheelTime2048: includeWheel ? wheelTimeTicks : nil,
                                                 crankRevs: cadence > 0 ? revCount : nil,
                                                 crankTime1024: cadence > 0 ? cadTimeTicks : nil)
        if manager.updateValue(payload, for: ch, onSubscribedCentrals: nil) == false {
            pendingUpdates.append((ch, payload))
        }
    }

    public func notifyRSC(speedMps: Double, cadence: Int) {
        guard let ch = rscMeasurement else { return }
        let payload = BLEEncoding.rscMeasurement(speedMps: speedMps, cadence: cadence)
        if manager.updateValue(payload, for: ch, onSubscribedCentrals: nil) == false {
            pendingUpdates.append((ch, payload))
        }
    }
}

nonisolated(unsafe) extension PeripheralManager: CBPeripheralManagerDelegate {
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        let hasError = error?.localizedDescription
        Task { @MainActor in
            if let e = hasError { self.lastError = e }
            if self.servicesPendingAdd > 0 { self.servicesPendingAdd -= 1 }
            if self.servicesPendingAdd == 0 && !self.pendingAdvertData.isEmpty {
                self.manager.startAdvertising(self.pendingAdvertData)
            }
        }
    }
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let s = peripheral.state
        Task { @MainActor in
            switch s {
            case .poweredOn:
                self.lastError = nil
                case .poweredOff: self.stopBroadcast()
            case .unauthorized, .unsupported, .resetting: self.lastError = "Bluetooth unavailable: \(s.rawValue)"
            case .unknown: break
            @unknown default: break
            }
        }
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        let err = error?.localizedDescription
        Task { @MainActor in
            if let err = err { self.state = .failed; self.lastError = err; self.isAdvertising = false }
            else { self.state = .advertising; self.isAdvertising = true }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor in self.subscriberCount += 1; self.startTicking() }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            self.subscriberCount = max(0, self.subscriberCount - 1)
            if self.subscriberCount == 0 {
                self.ftmsTimer?.invalidate(); self.cpsTimer?.invalidate(); self.rscTimer?.invalidate()
                self.ftmsTimer = nil; self.cpsTimer = nil; self.rscTimer = nil
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        // Provide static values for features and ranges
        if request.characteristic.uuid == GATT.ftmsFitnessMachineFeature {
            // 8 bytes LE: lower dword includes cadence+power measurement; upper dword includes simulation params + power target
            var buf = Data(count: 8)
            // lower
            var lower: UInt32 = 0
            lower |= 1 << 1 // cadence supported
            lower |= 1 << 14 // power measurement supported
            // upper
            var upper: UInt32 = 0
            upper |= 1 << 3  // power target setting supported
            upper |= 1 << 13 // indoor bike simulation supported
            buf[0] = UInt8(lower & 0xFF); buf[1] = UInt8((lower >> 8) & 0xFF); buf[2] = UInt8((lower >> 16) & 0xFF); buf[3] = UInt8((lower >> 24) & 0xFF)
            buf[4] = UInt8(upper & 0xFF); buf[5] = UInt8((upper >> 8) & 0xFF); buf[6] = UInt8((upper >> 16) & 0xFF); buf[7] = UInt8((upper >> 24) & 0xFF)
            request.value = buf
            manager.respond(to: request, withResult: .success); return
        }
        if request.characteristic.uuid == GATT.ftmsSupportedPowerRange {
            var buf = Data()
            func putS16(_ v: Int16) { let u = UInt16(bitPattern: v); buf.append(UInt8(u & 0xFF)); buf.append(UInt8(u >> 8)) }
            func putU16(_ v: UInt16) { buf.append(UInt8(v & 0xFF)); buf.append(UInt8(v >> 8)) }
            putS16(0) // min
            putS16(1000) // max
            putU16(1) // increment
            request.value = buf
            manager.respond(to: request, withResult: .success); return
        }
        if request.characteristic.uuid == CBUUID(string: "2A65") { // CPS Feature
            var buf = Data(count: 4)
            // 0x08 crank revolutions
            buf[0] = 0x08; buf[1] = 0x00; buf[2] = 0x00; buf[3] = 0x00
            request.value = buf; manager.respond(to: request, withResult: .success); return
        }
        if request.characteristic.uuid == CBUUID(string: "2A5D") { // Sensor Location
            var buf = Data(count: 1)
            if let ch = request.characteristic as? CBMutableCharacteristic, ch == cpsSensorLocation {
                buf[0] = 13 // CPS: rear hub
            } else {
                buf[0] = 0 // RSC: other
            }
            request.value = buf; manager.respond(to: request, withResult: .success); return
        }
        if request.characteristic.uuid == CBUUID(string: "2A54") { // RSC Feature -> none
            var buf = Data(count: 2); buf[0] = 0x00; buf[1] = 0x00
            request.value = buf; manager.respond(to: request, withResult: .success); return
        }
        manager.respond(to: request, withResult: .attributeNotFound)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if req.characteristic.uuid == GATT.ftmsControlPoint, let data = req.value, data.count >= 1 {
                handleFTMSControlPoint(data: data)
            }
            manager.respond(to: req, withResult: .success)
        }
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Drain pending updates
        while !pendingUpdates.isEmpty {
            let (ch, data) = pendingUpdates.removeFirst()
            if manager.updateValue(data, for: ch, onSubscribedCentrals: nil) == false {
                // Still not ready, put back and exit to avoid spin
                pendingUpdates.insert((ch, data), at: 0)
                break
            }
        }
    }

    private func handleFTMSControlPoint(data: Data) {
        guard let cp = ftmsControlPoint, let status = ftmsStatus else { return }
        let opcode = data[0]

        // FTMS Control Point Opcodes (per FTMS specification)
        let RequestControl: UInt8 = 0x00
        let Reset: UInt8 = 0x01
        let SetTargetSpeed: UInt8 = 0x02
        let SetTargetInclination: UInt8 = 0x03
        let SetTargetResistanceLevel: UInt8 = 0x04
        let SetTargetPower: UInt8 = 0x05
        let SetTargetHeartRate: UInt8 = 0x06
        let StartOrResume: UInt8 = 0x07
        let StopOrPause: UInt8 = 0x08
        let SetTargetedExpendedEnergy: UInt8 = 0x09
        let SetTargetedNumberOfSteps: UInt8 = 0x0A
        let SetTargetedNumberOfStrides: UInt8 = 0x0B
        let SetTargetedDistance: UInt8 = 0x0C
        let SetTargetedTrainingTime: UInt8 = 0x0D
        let SetTargetedTimeInTwoHeartRateZones: UInt8 = 0x0E
        let SetTargetedTimeInThreeHeartRateZones: UInt8 = 0x0F
        let SetTargetedTimeInFiveHeartRateZones: UInt8 = 0x10
        let SetIndoorBikeSimulation: UInt8 = 0x11
        let SetWheelCircumference: UInt8 = 0x12
        let SpinDownControl: UInt8 = 0x13
        let SetTargetedCadence: UInt8 = 0x14

        // Response Codes
        let ResponseCode: UInt8 = 0x80
        let Success: UInt8 = 0x01
        let OpCodeNotSupported: UInt8 = 0x02
        let InvalidParameter: UInt8 = 0x03
        // let OperationFailed: UInt8 = 0x04  // Not currently used
        let ControlNotPermitted: UInt8 = 0x05

        // Status notification codes (per FTMS specification)
        let StatusReset: UInt8 = 0x01
        let StatusStoppedOrPaused: UInt8 = 0x02
        let StatusStartedOrResumed: UInt8 = 0x04
        let StatusTargetPowerChanged: UInt8 = 0x08
        let StatusTargetSpeedChanged: UInt8 = 0x10
        let StatusTargetInclineChanged: UInt8 = 0x11
        let StatusIndoorBikeSimulationParametersChanged: UInt8 = 0x12
        let StatusWheelCircumferenceChanged: UInt8 = 0x13
        let StatusSpinDownStarted: UInt8 = 0x14
        let StatusSpinDownIgnored: UInt8 = 0x15
        let StatusTargetCadenceChanged: UInt8 = 0x16

        // Helper function to send indication response (per FTMS spec: must respond within 3 seconds)
        func indicate(_ opcode: UInt8, _ result: UInt8) {
            let resp = Data([ResponseCode, opcode, result])
            if manager.updateValue(resp, for: cp, onSubscribedCentrals: nil) == false {
                pendingUpdates.append((cp, resp))
            }
        }

        // Helper function to send status notifications with timing compliance
        func notifyStatus(_ payload: Data, delay: TimeInterval = 0) {
            // Per FTMS spec, status notifications should be sent within 3 seconds
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, let ftmsStatus = self.ftmsStatus else { return }
                    if self.manager.updateValue(payload, for: ftmsStatus, onSubscribedCentrals: nil) == false {
                        self.pendingUpdates.append((ftmsStatus, payload))
                    }
                }
            } else {
                if manager.updateValue(payload, for: status, onSubscribedCentrals: nil) == false {
                    pendingUpdates.append((status, payload))
                }
            }
        }

        // Process control point commands
        switch opcode {
        case RequestControl:
            // Client requesting control of the fitness machine
            if hasControl {
                // Already have control - could deny or allow transfer
                // For compatibility, we'll allow it (like zwack does)
                indicate(opcode, Success)
                Task { @MainActor in self.log("FTMS: RequestControl -> success (already had control)") }
            } else {
                hasControl = true
                indicate(opcode, Success)
                Task { @MainActor in self.log("FTMS: RequestControl -> success") }
            }

        case Reset:
            // Reset the fitness machine
            if hasControl {
                hasControl = false
                isStarted = false
                targetPower = 0
                indicate(opcode, Success)
                notifyStatus(Data([StatusReset])) // Reset status notification
                // Send additional status update after short delay
                notifyStatus(Data([StatusReset]), delay: 0.5)
                Task { @MainActor in self.log("FTMS: Reset -> success") }
            } else {
                indicate(opcode, ControlNotPermitted)
                Task { @MainActor in self.log("FTMS: Reset -> control not permitted") }
            }

        case SetTargetPower:
            // Set target power in watts
            if hasControl {
                if data.count >= 3 {
                    let tp = Int(Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8)))
                    if tp >= 0 && tp <= 4000 {  // Validate reasonable power range
                        targetPower = tp
                        indicate(opcode, Success)
                        // Send status notification with new target power
                        var buf = Data([StatusTargetPowerChanged])
                        let u = UInt16(bitPattern: Int16(clamping: tp))
                        buf.append(UInt8(truncatingIfNeeded: u & 0xFF))
                        buf.append(UInt8(truncatingIfNeeded: u >> 8))
                        notifyStatus(buf)
                        Task { @MainActor in self.log("FTMS: SetTargetPower -> \(tp)W") }
                    } else {
                        indicate(opcode, InvalidParameter)
                        Task { @MainActor in self.log("FTMS: SetTargetPower -> invalid parameter (\(tp)W)") }
                    }
                } else {
                    indicate(opcode, InvalidParameter)
                    Task { @MainActor in self.log("FTMS: SetTargetPower -> invalid data length") }
                }
            } else {
                indicate(opcode, ControlNotPermitted)
                Task { @MainActor in self.log("FTMS: SetTargetPower -> control not permitted") }
            }

        case StartOrResume:
            // Start or resume the fitness machine
            if hasControl {
                if !isStarted {
                    isStarted = true
                    indicate(opcode, Success)
                    notifyStatus(Data([StatusStartedOrResumed]))  // FitnessMachineStartedOrResumedByUser
                    Task { @MainActor in self.log("FTMS: StartOrResume -> success") }
                } else {
                    // Already started - per spec, this should succeed
                    indicate(opcode, Success)
                    Task { @MainActor in self.log("FTMS: StartOrResume -> already started") }
                }
            } else {
                indicate(opcode, ControlNotPermitted)
                Task { @MainActor in self.log("FTMS: StartOrResume -> control not permitted") }
            }

        case StopOrPause:
            // Stop or pause the fitness machine
            if hasControl {
                if isStarted {
                    isStarted = false
                    indicate(opcode, Success)
                    notifyStatus(Data([StatusStoppedOrPaused]))  // FitnessMachineStoppedOrPausedByUser
                    Task { @MainActor in self.log("FTMS: StopOrPause -> success") }
                } else {
                    // Already stopped - per spec, this should succeed
                    indicate(opcode, Success)
                    Task { @MainActor in self.log("FTMS: StopOrPause -> already stopped") }
                }
            } else {
                indicate(opcode, ControlNotPermitted)
                Task { @MainActor in self.log("FTMS: StopOrPause -> control not permitted") }
            }

        case SetIndoorBikeSimulation:
            // Set indoor bike simulation parameters
            if hasControl {
                if data.count >= 7 {
                    let wind = Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8))
                    let grade = Int16(bitPattern: UInt16(data[3]) | (UInt16(data[4]) << 8))
                    let crr = data[5]
                    let cw = data[6]

                    // Validate parameters
                    if abs(wind) <= 32767 && abs(grade) <= 4000 && crr <= 255 && cw <= 255 {
                        simWindSpeedMps = Double(wind) * 0.001
                        gradePercent = Double(grade) * 0.01
                        simCrr = Double(crr) * 0.0001
                        simCw = Double(cw) * 0.01
                        indicate(opcode, Success)

                        // Send status notification with simulation parameters
                        var buf = Data(count: 7)
                        buf[0] = StatusIndoorBikeSimulationParametersChanged
                        let w = Int16(simWindSpeedMps / 0.001)
                        buf[1] = UInt8(truncatingIfNeeded: UInt16(bitPattern: w) & 0xFF)
                        buf[2] = UInt8(truncatingIfNeeded: UInt16(bitPattern: w) >> 8)
                        let g = Int16(gradePercent / 0.01)
                        buf[3] = UInt8(truncatingIfNeeded: UInt16(bitPattern: g) & 0xFF)
                        buf[4] = UInt8(truncatingIfNeeded: UInt16(bitPattern: g) >> 8)
                        buf[5] = UInt8(truncatingIfNeeded: Int(simCrr / 0.0001))
                        buf[6] = UInt8(truncatingIfNeeded: Int(simCw / 0.01))
                        notifyStatus(buf)

                        Task { @MainActor in
                            self.log(String(format: "FTMS: BikeSim wind=%.3f m/s grade=%.2f%% crr=%.4f cw=%.2f",
                                          self.simWindSpeedMps, self.gradePercent, self.simCrr, self.simCw))
                        }
                    } else {
                        indicate(opcode, InvalidParameter)
                        Task { @MainActor in self.log("FTMS: SetIndoorBikeSimulation -> invalid parameters") }
                    }
                } else {
                    indicate(opcode, InvalidParameter)
                    Task { @MainActor in self.log("FTMS: SetIndoorBikeSimulation -> invalid data length") }
                }
            } else {
                indicate(opcode, ControlNotPermitted)
                Task { @MainActor in self.log("FTMS: SetIndoorBikeSimulation -> control not permitted") }
            }

        case SpinDownControl:
            // Spin down control (for calibration)
            if hasControl && data.count >= 2 {
                let spinDownCommand = data[1]
                if spinDownCommand == 0x01 {  // Start spin down
                    indicate(opcode, Success)
                    notifyStatus(Data([StatusSpinDownStarted]))  // SpinDownStarted
                    // Simulate spindown completion after delay (normally would monitor actual spindown)
                    notifyStatus(Data([StatusSpinDownIgnored]), delay: 2.5)  // Send completion status
                    Task { @MainActor in self.log("FTMS: SpinDownControl -> start") }
                } else if spinDownCommand == 0x02 {  // Ignore spin down
                    indicate(opcode, Success)
                    notifyStatus(Data([StatusSpinDownIgnored]))  // SpinDownIgnored
                    Task { @MainActor in self.log("FTMS: SpinDownControl -> ignore") }
                } else {
                    indicate(opcode, InvalidParameter)
                }
            } else {
                indicate(opcode, hasControl ? InvalidParameter : ControlNotPermitted)
            }

        case SetTargetResistanceLevel:
            // Set target resistance level (0.1 unitless increments)
            if hasControl && data.count >= 3 {
                let resistance = Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8))
                // For now, we don't implement resistance mode, but acknowledge it
                indicate(opcode, OpCodeNotSupported)
                Task { @MainActor in self.log("FTMS: SetTargetResistanceLevel -> not supported (resistance: \(Double(resistance) * 0.1))") }
            } else {
                indicate(opcode, hasControl ? InvalidParameter : ControlNotPermitted)
            }

        case SetTargetHeartRate, SetTargetedExpendedEnergy, SetTargetedNumberOfSteps,
             SetTargetedNumberOfStrides, SetTargetedDistance, SetTargetedTrainingTime,
             SetTargetedTimeInTwoHeartRateZones, SetTargetedTimeInThreeHeartRateZones,
             SetTargetedTimeInFiveHeartRateZones:
            // These opcodes are not currently supported
            indicate(opcode, OpCodeNotSupported)
            Task { @MainActor in self.log("FTMS: Opcode \(String(format: "0x%02X", opcode)) -> not supported") }

        case SetTargetSpeed:
            // Set target speed (m/s × 100)
            if hasControl {
                if data.count >= 3 {
                    let speedCms = UInt16(data[1]) | (UInt16(data[2]) << 8)
                    let speedMs = Double(speedCms) / 100.0
                    // Store target speed for simulation (you could use this for speed control mode)
                    indicate(opcode, Success)
                    // Notify target speed changed
                    var statusData = Data([StatusTargetSpeedChanged])
                    statusData.append(contentsOf: withUnsafeBytes(of: speedCms.littleEndian) { Data($0) })
                    notifyStatus(statusData)
                    Task { @MainActor in self.log("FTMS: SetTargetSpeed \(speedMs) m/s") }
                } else {
                    indicate(opcode, InvalidParameter)
                }
            } else {
                indicate(opcode, ControlNotPermitted)
            }

        case SetTargetInclination:
            // Set target incline (% × 10, signed)
            if hasControl {
                if data.count >= 3 {
                    let inclineRaw = Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8))
                    let inclinePercent = Double(inclineRaw) / 10.0
                    gradePercent = inclinePercent
                    indicate(opcode, Success)
                    // Notify target incline changed
                    var statusData = Data([StatusTargetInclineChanged])
                    statusData.append(contentsOf: withUnsafeBytes(of: inclineRaw.littleEndian) { Data($0) })
                    notifyStatus(statusData)
                    Task { @MainActor in self.log("FTMS: SetTargetInclination \(inclinePercent)%") }
                } else {
                    indicate(opcode, InvalidParameter)
                }
            } else {
                indicate(opcode, ControlNotPermitted)
            }

        case SetWheelCircumference:
            // Set wheel circumference (mm)
            if hasControl {
                if data.count >= 3 {
                    let circumferenceMm = UInt16(data[1]) | (UInt16(data[2]) << 8)
                    // Store wheel circumference (useful for speed calculations)
                    indicate(opcode, Success)
                    // Send wheel circumference changed status
                    var statusData = Data([StatusWheelCircumferenceChanged])
                    statusData.append(contentsOf: withUnsafeBytes(of: circumferenceMm.littleEndian) { Data($0) })
                    notifyStatus(statusData)
                    Task { @MainActor in self.log("FTMS: SetWheelCircumference \(circumferenceMm)mm") }
                } else {
                    indicate(opcode, InvalidParameter)
                }
            } else {
                indicate(opcode, ControlNotPermitted)
            }

        case SetTargetedCadence:
            // Set target cadence (RPM × 2)
            if hasControl {
                if data.count >= 3 {
                    let targetCadence = UInt16(data[1]) | (UInt16(data[2]) << 8)
                    let targetRpm = Double(targetCadence) / 2.0
                    // Store target cadence for simulation
                    indicate(opcode, Success)
                    // Send target cadence changed status
                    var statusData = Data([StatusTargetCadenceChanged])
                    statusData.append(contentsOf: withUnsafeBytes(of: targetCadence.littleEndian) { Data($0) })
                    notifyStatus(statusData)
                    Task { @MainActor in self.log("FTMS: SetTargetedCadence \(targetRpm) RPM") }
                } else {
                    indicate(opcode, InvalidParameter)
                }
            } else {
                indicate(opcode, ControlNotPermitted)
            }

        default:
            // Unknown opcode
            indicate(opcode, OpCodeNotSupported)
            Task { @MainActor in self.log("FTMS: Unknown opcode \(String(format: "0x%02X", opcode)) -> not supported") }
        }
    }

    @MainActor private func log(_ line: String) {
        eventLog.append(line)
        if eventLog.count > 200 { eventLog.removeFirst(eventLog.count - 200) }
    }
}
