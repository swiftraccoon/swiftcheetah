import Foundation
import CoreBluetooth
#if SWIFT_PACKAGE
import SwiftCheetahCore
#endif
// Pure encoders for GATT payloads
// (Keep separate from CoreBluetooth to allow unit testing.)
// BLEEncoding is internal to this module; no import needed beyond same target.

/// BLE Peripheral role: advertises FTMS/CPS/RSC and notifies measurement data.
/// PeripheralManager - Refactored as a facade coordinating specialized components:
/// - CyclingSimulationEngine: Handles all physics/cadence/power simulation
/// - FTMSControlPointHandler: Processes FTMS control commands
/// - BLENotificationScheduler: Manages notification timers
/// - SimulationStateManager: Centralized state management
///
/// This class now acts as a thin coordinator, delegating responsibilities to
/// specialized components following SOLID principles.
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

    // Extracted components
    private var controlPointHandler: FTMSControlPointHandler!
    private var simulationEngine = CyclingSimulationEngine()
    private var notificationScheduler = BLENotificationScheduler()

    private var manager: CBPeripheralManager!
    private var options = Options()
    private var lastPowerUpdate: TimeInterval = Date().timeIntervalSince1970

    // Services/Characteristics
    private var ftmsIndoorBikeData: CBMutableCharacteristic?
    private var ftmsFeature: CBMutableCharacteristic?
    private var ftmsStatus: CBMutableCharacteristic?
    private var ftmsControlPoint: CBMutableCharacteristic?
    private var ftmsSupportedPowerRange: CBMutableCharacteristic?

    private var cpsMeasurement: CBMutableCharacteristic?
    private var cpsFeature: CBMutableCharacteristic?
    private var cpsSensorLocation: CBMutableCharacteristic?

    private var rscMeasurement: CBMutableCharacteristic?
    private var rscFeature: CBMutableCharacteristic?
    private var rscSensorLocation: CBMutableCharacteristic?

    // Backpressure queue for indications/notifications
    private var pendingUpdates: [(CBMutableCharacteristic, Data)] = []
    // Track service registration and delay advertising until all are added
    private var servicesPendingAdd: Int = 0
    private var pendingAdvertData: [String: Any] = [:]
    // Store broadcast request when Bluetooth isn't ready yet
    private var pendingBroadcastRequest: (localName: String?, options: Options)?
    // Live stats for UI
    public struct LiveStats: Sendable {
        public var speedKmh: Double
        public var powerW: Int
        public var cadenceRpm: Int
        public var mode: String
        public var gear: String
        public var targetCadence: Int
        public var fatigue: Double
        public var noise: Double
        public var gradePercent: Double
    }

    @Published public private(set) var stats = LiveStats(
        speedKmh: 25.0,
        powerW: 250,
        cadenceRpm: 90,
        mode: "AUTO",
        gear: "2x5",
        targetCadence: 90,
        fatigue: 0,
        noise: 0,
        gradePercent: 0
    )

    // Rolling counters for CPS
    private var revCount: UInt16 = 0
    private var cadTimeTicks: UInt16 = 0 // 1/1024s units
    private var wheelCount: UInt32 = 0
    private var wheelTimeTicks: UInt16 = 0

    public override init() {
        super.init()

        // Initialize control point handler with current watts value
        let initialState = FTMSControlPointHandler.ControlState(
            hasControl: true,
            isStarted: true,
            targetPower: watts,
            simWindSpeedMps: 0,
            simCrr: 0.004,
            simCw: 0.51,
            gradePercent: 0
        )
        self.controlPointHandler = FTMSControlPointHandler(initialState: initialState)

        self.manager = CBPeripheralManager(delegate: self, queue: .main)

        // Start a simulation timer for UI updates even when not broadcasting
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSimulation()
        }
    }

    private func updateSimulation() {
        // Update stats for UI even when not broadcasting
        if !isAdvertising {
            let input = CyclingSimulationEngine.SimulationInput(
                targetPower: watts,
                manualCadence: cadenceMode == .manual ? cadenceRpm : nil,
                gradePercent: gradePercent,
                randomness: randomness,
                isResting: false
            )
            let state = simulationEngine.update(with: input)
            updateLiveStats(speedMps: state.speedMps, watts: state.powerWatts, cadence: state.cadenceRpm)
        }
    }

    @Published public var localName: String = "Trainer"

    /// Begin advertising after all enabled services are added.
    public func startBroadcast(localName: String? = nil, options: Options? = nil) {
        eventLog.append("startBroadcast called - BT state: \(manager.state.rawValue)")
        guard manager.state == .poweredOn else {
            // Set state to indicate we're waiting for Bluetooth to be ready
            state = .starting
            lastError = "Waiting for Bluetooth to be ready (state: \(manager.state.rawValue))"
            eventLog.append("Bluetooth not ready (state: \(manager.state.rawValue)), waiting...")

            // Store the broadcast request for when Bluetooth becomes available
            let effective = options ?? Options(advertiseFTMS: advertiseFTMS, advertiseCPS: advertiseCPS, advertiseRSC: advertiseRSC)
            self.options = effective
            pendingBroadcastRequest = (localName, effective)
            return
        }
        eventLog.append("Bluetooth ready, setting up services...")
        let effective = options ?? Options(advertiseFTMS: advertiseFTMS, advertiseCPS: advertiseCPS, advertiseRSC: advertiseRSC)
        self.options = effective
        state = .advertising
        isAdvertising = true  // Set immediately to update UI
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
        startTicking()  // Start simulation immediately
    }

    public func stopBroadcast() {
        manager.stopAdvertising()
        isAdvertising = false
        state = .stopped
        notificationScheduler.stopNotifications()
        pendingBroadcastRequest = nil
    }

    /// Create and add services/characteristics with spec‑correct properties and descriptors.
    private func setupServices() {
        eventLog.append("Setting up services - FTMS:\(options.advertiseFTMS) CPS:\(options.advertiseCPS) RSC:\(options.advertiseRSC)")
        servicesPendingAdd = 0
        // FTMS
        if options.advertiseFTMS {
            eventLog.append("Creating FTMS service...")
            ftmsIndoorBikeData = CBMutableCharacteristic(type: GATT.ftmsIndoorBikeData, properties: [.notify], value: nil, permissions: [])
            ftmsIndoorBikeData?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Indoor Bike Data")]
            ftmsFeature = CBMutableCharacteristic(type: GATT.ftmsFitnessMachineFeature, properties: [.read], value: nil, permissions: [.readable])
            ftmsFeature?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Fitness Machine Feature")]
            ftmsStatus = CBMutableCharacteristic(type: GATT.ftmsFitnessMachineStatus, properties: [.notify], value: nil, permissions: [])
            ftmsStatus?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Fitness Machine Status")]
            ftmsControlPoint = CBMutableCharacteristic(type: GATT.ftmsControlPoint, properties: [.write, .indicate], value: nil, permissions: [.writeable])
            ftmsControlPoint?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Fitness Machine Control Point")]
            ftmsSupportedPowerRange = CBMutableCharacteristic(type: GATT.ftmsSupportedPowerRange, properties: [.read], value: nil, permissions: [.readable])
            ftmsSupportedPowerRange?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Supported Power Range")]
            let s = CBMutableService(type: GATT.fitnessMachine, primary: true)
            s.characteristics = [ftmsFeature!, ftmsIndoorBikeData!, ftmsStatus!, ftmsControlPoint!, ftmsSupportedPowerRange!]
            servicesPendingAdd += 1
            manager.add(s)
        }

        // CPS
        if options.advertiseCPS {
            cpsMeasurement = CBMutableCharacteristic(type: GATT.cpsMeasurement, properties: [.notify], value: nil, permissions: [])
            cpsMeasurement?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Cycling Power Measurement")]
            cpsFeature = CBMutableCharacteristic(type: CBUUID(string: "2A65"), properties: [.read], value: nil, permissions: [.readable])
            cpsFeature?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Cycling Power Feature")]
            cpsSensorLocation = CBMutableCharacteristic(type: CBUUID(string: "2A5D"), properties: [.read], value: nil, permissions: [.readable])
            cpsSensorLocation?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Sensor Location")]
            let s = CBMutableService(type: GATT.cyclingPower, primary: true)
            s.characteristics = [cpsMeasurement!, cpsFeature!, cpsSensorLocation!]
            servicesPendingAdd += 1
            manager.add(s)
        }

        // RSC
        if options.advertiseRSC {
            rscMeasurement = CBMutableCharacteristic(type: GATT.rscMeasurement, properties: [.notify], value: nil, permissions: [])
            rscMeasurement?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Running Speed and Cadence Measurement")]
            rscFeature = CBMutableCharacteristic(type: CBUUID(string: "2A54"), properties: [.read], value: nil, permissions: [.readable])
            rscFeature?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "RSC Feature")]
            rscSensorLocation = CBMutableCharacteristic(type: CBUUID(string: "2A5D"), properties: [.read], value: nil, permissions: [.readable])
            rscSensorLocation?.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2901"), value: "Sensor Location")]
            let s = CBMutableService(type: GATT.runningSpeedCadence, primary: true)
            s.characteristics = [rscMeasurement!, rscFeature!, rscSensorLocation!]
            servicesPendingAdd += 1
            manager.add(s)
        }
    }

    /// Start periodic notifications per service (FTMS 4Hz, CPS ≤4Hz, RSC 2Hz).
    private func startTicking() {
        notificationScheduler.delegate = self
        notificationScheduler.startNotifications()
    }


    /// FTMS periodic updates: compute realistic watts (variance + trainer tau),
    /// speed from power/grade, cadence via simulation engine, then notify Indoor Bike Data.
    private func tickFTMS() {
        let now = Date().timeIntervalSince1970
        let dt = max(0.001, now - lastPowerUpdate)
        lastPowerUpdate = now

        let input = CyclingSimulationEngine.SimulationInput(
            targetPower: watts,
            manualCadence: cadenceMode == .manual ? cadenceRpm : nil,
            gradePercent: gradePercent,
            randomness: randomness,
            isResting: false
        )
        let state = simulationEngine.update(with: input)
        speedMps = state.speedMps
        let realisticWatts = state.powerWatts
        let cad = state.cadenceRpm

        // Notify FTMS with appropriate values based on include flags
        if options.advertiseFTMS {
            let wattsToSend = ftmsIncludePower ? realisticWatts : 0
            let cadenceToSend = ftmsIncludeCadence ? cad : 0
            notifyFTMS(watts: wattsToSend, cadence: cadenceToSend)
        }
        advanceCounters(dt: dt, cadence: cad)
        updateLiveStats(speedMps: state.speedMps, watts: realisticWatts, cadence: cad)
    }

    /// CPS periodic updates: same physics + cadence pipeline, then notify CPS Measurement.
    private func tickCPS() {
        let now = Date().timeIntervalSince1970
        let dt = max(0.001, now - lastPowerUpdate)
        lastPowerUpdate = now

        let input = CyclingSimulationEngine.SimulationInput(
            targetPower: watts,
            manualCadence: cadenceMode == .manual ? cadenceRpm : nil,
            gradePercent: gradePercent,
            randomness: randomness,
            isResting: false
        )
        let state = simulationEngine.update(with: input)
        speedMps = state.speedMps
        let realisticWatts = state.powerWatts
        let cad = state.cadenceRpm

        // Notify CPS with appropriate values based on include flags
        if options.advertiseCPS {
            let wattsToSend = cpsIncludePower ? realisticWatts : 0
            let cadenceToSend = cpsIncludeCadence ? cad : 0
            notifyCPS(watts: wattsToSend, cadence: cadenceToSend, includeWheel: cpsIncludeSpeed)
        }
        advanceCounters(dt: dt, cadence: cad)
        updateLiveStats(speedMps: state.speedMps, watts: realisticWatts, cadence: cad)
    }

    /// RSC periodic updates: expose running-like speed/cadence if enabled (simple cadence reuse).
    private func tickRSC() {
        // Calculate cadence based on mode
        let input = CyclingSimulationEngine.SimulationInput(
            targetPower: watts,
            manualCadence: cadenceMode == .manual ? cadenceRpm : nil,
            gradePercent: gradePercent,
            randomness: randomness,
            isResting: false
        )
        let state = simulationEngine.update(with: input)
        let cad = state.cadenceRpm

        if options.advertiseRSC {
            notifyRSC(speedMps: speedMps, cadence: cad)
        }
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
        // Get latest simulation state for detailed info
        let input = CyclingSimulationEngine.SimulationInput(
            targetPower: self.watts,
            manualCadence: cadenceMode == .manual ? cadenceRpm : nil,
            gradePercent: gradePercent,
            randomness: randomness,
            isResting: false
        )
        let simState = simulationEngine.update(with: input)

        stats = LiveStats(
            speedKmh: v * 3.6,
            powerW: watts,
            cadenceRpm: cadence,
            mode: cadenceMode == .auto ? "AUTO" : "MANUAL",
            gear: "\(simState.gear.front)x\(simState.gear.rear)",
            targetCadence: Int(simState.targetCadence.rounded()),
            fatigue: simState.fatigue,
            noise: simState.noise,
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
            ErrorHandler.shared.logBLE(
                "FTMS Indoor Bike Data transmission failed, queued for retry",
                severity: .warning,
                context: ["characteristic": "ftmsIndoorBikeData", "queueSize": "\(pendingUpdates.count)"]
            )
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
            ErrorHandler.shared.logBLE(
                "CPS Measurement transmission failed, queued for retry",
                severity: .warning,
                context: ["characteristic": "cpsMeasurement", "queueSize": "\(pendingUpdates.count)"]
            )
        }
    }

    public func notifyRSC(speedMps: Double, cadence: Int) {
        guard let ch = rscMeasurement else { return }
        let payload = BLEEncoding.rscMeasurement(speedMps: speedMps, cadence: cadence)
        if manager.updateValue(payload, for: ch, onSubscribedCentrals: nil) == false {
            pendingUpdates.append((ch, payload))
            ErrorHandler.shared.logBLE(
                "RSC Measurement transmission failed, queued for retry",
                severity: .warning,
                context: ["characteristic": "rscMeasurement", "queueSize": "\(pendingUpdates.count)"]
            )
        }
    }
}

// MARK: - BLENotificationScheduler Delegate

extension PeripheralManager: BLENotificationScheduler.Delegate {
    public func schedulerShouldSendFTMSNotification() {
        tickFTMS()
    }

    public func schedulerShouldSendCPSNotification() {
        tickCPS()
    }

    public func schedulerShouldSendRSCNotification() {
        tickRSC()
    }

    public func schedulerNeedsCadenceForCPSInterval() -> Int {
        let input = CyclingSimulationEngine.SimulationInput(
            targetPower: watts,
            manualCadence: cadenceMode == .manual ? cadenceRpm : nil,
            gradePercent: gradePercent,
            randomness: randomness,
            isResting: false
        )
        let state = simulationEngine.update(with: input)
        return state.cadenceRpm
    }
}

// MARK: - CoreBluetooth Delegate

nonisolated(unsafe) extension PeripheralManager: CBPeripheralManagerDelegate {
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        let hasError = error?.localizedDescription
        let serviceUUID = service.uuid.uuidString
        Task { @MainActor in
            if let e = hasError {
                self.lastError = e
                self.eventLog.append("❌ Error adding service \(serviceUUID): \(e)")
                self.state = .failed
                self.isAdvertising = false
            } else {
                self.eventLog.append("✅ Service added: \(serviceUUID)")
            }
            if self.servicesPendingAdd > 0 { self.servicesPendingAdd -= 1 }
            self.eventLog.append("Services pending: \(self.servicesPendingAdd)")
            if self.servicesPendingAdd == 0 {
                if !self.pendingAdvertData.isEmpty {
                    self.eventLog.append("📡 All services added, starting advertising with data: \(self.pendingAdvertData)")
                    self.manager.startAdvertising(self.pendingAdvertData)
                } else {
                    self.eventLog.append("⚠️ No advertisement data to broadcast!")
                    self.state = .failed
                    self.isAdvertising = false
                }
            }
        }
    }
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let s = peripheral.state
        Task { @MainActor in
            self.eventLog.append("Bluetooth state changed to: \(s.rawValue)")
            switch s {
            case .poweredOn:
                self.eventLog.append("Bluetooth is now powered on")
                self.lastError = nil
                // If there was a pending broadcast request, execute it now
                if let pending = self.pendingBroadcastRequest {
                    self.eventLog.append("Executing pending broadcast request")
                    self.pendingBroadcastRequest = nil
                    self.startBroadcast(localName: pending.localName, options: pending.options)
                }
            case .poweredOff:
                self.eventLog.append("Bluetooth powered off")
                self.stopBroadcast()
            case .unauthorized, .unsupported, .resetting:
                self.eventLog.append("Bluetooth error: \(s.rawValue)")
                self.lastError = "Bluetooth unavailable: \(s.rawValue)"
                self.state = .failed
                self.pendingBroadcastRequest = nil
            case .unknown:
                self.eventLog.append("Bluetooth state unknown")
            @unknown default:
                self.eventLog.append("Bluetooth unknown state: \(s.rawValue)")
            }
        }
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        let err = error?.localizedDescription
        Task { @MainActor in
            if let err = err {
                self.eventLog.append("Failed to start advertising: \(err)")
                self.state = .failed
                self.lastError = err
                self.isAdvertising = false
            } else {
                self.eventLog.append("✅ Successfully started advertising!")
                // isAdvertising already set to true in startBroadcast
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor in
            self.subscriberCount += 1
            self.eventLog.append("Subscriber connected! Total: \(self.subscriberCount)")
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            self.subscriberCount = max(0, self.subscriberCount - 1)
            if self.subscriberCount == 0 {
                self.notificationScheduler.stopNotifications()
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        // Provide static values for features and ranges
        if request.characteristic.uuid == GATT.ftmsFitnessMachineFeature {
            // FTMS Feature characteristic requires 8 bytes in little-endian format
            // Split into two 32-bit words: lower (measurement features) and upper (target/control features)
            var buf = Data(count: 8)

            // Lower 32 bits: Measurement features
            var lower: UInt32 = 0
            lower |= 1 << 1   // Bit 1: Cadence measurement supported
            lower |= 1 << 14  // Bit 14: Power measurement supported

            // Upper 32 bits: Target setting and control features
            var upper: UInt32 = 0
            upper |= 1 << 3   // Bit 3: Power target setting supported
            upper |= 1 << 13  // Bit 13: Indoor bike simulation parameters supported

            // Convert to little-endian byte array
            // Lower 32-bit word (bytes 0-3)
            buf[0] = UInt8(lower & 0xFF)
            buf[1] = UInt8((lower >> 8) & 0xFF)
            buf[2] = UInt8((lower >> 16) & 0xFF)
            buf[3] = UInt8((lower >> 24) & 0xFF)

            // Upper 32-bit word (bytes 4-7)
            buf[4] = UInt8(upper & 0xFF)
            buf[5] = UInt8((upper >> 8) & 0xFF)
            buf[6] = UInt8((upper >> 16) & 0xFF)
            buf[7] = UInt8((upper >> 24) & 0xFF)

            request.value = buf
            manager.respond(to: request, withResult: .success)
            return
        }
        if request.characteristic.uuid == GATT.ftmsSupportedPowerRange {
            // FTMS Supported Power Range: min, max, and increment values
            var buf = Data()

            // Helper functions to append little-endian 16-bit values
            func appendSigned16(_ value: Int16) {
                let unsigned = UInt16(bitPattern: value)
                buf.append(UInt8(unsigned & 0xFF))        // Low byte
                buf.append(UInt8(unsigned >> 8))          // High byte
            }

            func appendUnsigned16(_ value: UInt16) {
                buf.append(UInt8(value & 0xFF))           // Low byte
                buf.append(UInt8(value >> 8))             // High byte
            }

            appendSigned16(0)     // Minimum power: 0 watts
            appendSigned16(1000)  // Maximum power: 1000 watts
            appendUnsigned16(1)   // Increment: 1 watt resolution

            request.value = buf
            manager.respond(to: request, withResult: .success)
            return
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

        // Process command through handler
        let result = controlPointHandler.handleCommand(data)

        // Send indication response if provided
        if let response = result.response {
            if manager.updateValue(response, for: cp, onSubscribedCentrals: nil) == false {
                pendingUpdates.append((cp, response))
            }
        }

        // Send status notification if provided
        if let statusData = result.status {
            if result.statusDelay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + result.statusDelay) { [weak self] in
                    guard let self = self, let status = self.ftmsStatus else { return }
                    if self.manager.updateValue(statusData, for: status, onSubscribedCentrals: nil) == false {
                        self.pendingUpdates.append((status, statusData))
                    }
                }
            } else {
                if manager.updateValue(statusData, for: status, onSubscribedCentrals: nil) == false {
                    pendingUpdates.append((status, statusData))
                }
            }
        }

        // Apply state updates
        if let update = result.stateUpdate {
            var state = controlPointHandler.getState()
            update(&state)
            controlPointHandler.setState(state)

            // Update local properties that depend on control state
            let controlState = controlPointHandler.getState()
            self.gradePercent = controlState.gradePercent

            // Only sync watts for SetTargetPower command
            if result.command == .setTargetPower {
                self.watts = controlState.targetPower
            }
        }

        // Log the result
        Task { @MainActor in self.log(result.logMessage) }
    }

    @MainActor private func log(_ line: String) {
        // Maintain backward compatibility with eventLog
        eventLog.append(line)
        if eventLog.count > 200 { eventLog.removeFirst(eventLog.count - 200) }

        // Also log to standardized error handler with BLE category
        ErrorHandler.shared.logBLE(line, severity: .info, context: ["component": "PeripheralManager"])
    }
}
