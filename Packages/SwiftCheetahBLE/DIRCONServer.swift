import Foundation
import Network
#if SWIFT_PACKAGE
import SwiftCheetahCore
#endif

/// DIRCON TCP server that mirrors PeripheralManager's published interface.
/// Uses Network.framework instead of CoreBluetooth for Wahoo DIRCON protocol.
/// Clients (e.g., Zwift) connect via TCP and interact using DIRCON framing
/// on top of standard BLE GATT semantics.
public final class DIRCONServer: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published state (matches PeripheralManager)

    @Published public private(set) var isAdvertising: Bool = false
    @Published public private(set) var subscriberCount: Int = 0
    @Published public private(set) var eventLog: [String] = []

    // Simulation inputs
    @Published public var watts: Int = 250
    @Published public var cadenceRpm: Int = 90
    @Published public var speedMps: Double = 8.33
    @Published public var gradePercent: Double = 0.0
    @Published public var simCrr: Double = 0
    @Published public var simCw: Double = 0
    @Published public var simWindSpeedMps: Double = 0
    @Published public var randomness: Int = 0
    @Published public var increment: Int = 25
    public enum CadenceMode: String, Sendable { case auto, manual }
    @Published public var cadenceMode: CadenceMode = .auto

    // Service toggles
    @Published public var advertiseFTMS: Bool = true
    @Published public var advertiseCPS: Bool = false
    @Published public var advertiseRSC: Bool = false
    @Published public var advertiseHRS: Bool = false
    @Published public var advertiseDIS: Bool = false
    @Published public var trainerIdentity: PeripheralManager.TrainerIdentity = PeripheralManager.TrainerIdentity()
    @Published public var powerProfileMode: PowerProfileMode = .uncapped
    @Published public var eventPreset: EventPreset = .freeRide

    // Field toggles (mirrors PeripheralManager for UI compatibility)
    @Published public var ftmsIncludePower: Bool = true
    @Published public var ftmsIncludeCadence: Bool = true
    @Published public var cpsIncludePower: Bool = true
    @Published public var cpsIncludeCadence: Bool = true
    @Published public var cpsIncludeSpeed: Bool = true

    @Published public var localName: String = "Trainer"

    // Live stats for UI
    public struct LiveStats: Sendable {
        public var speedKmh: Double
        public var powerW: Int
        public var cadenceRpm: Int
        public var heartRateBpm: Int
        public var mode: String
        public var gear: String
        public var targetCadence: Int
        public var fatigue: Double
        public var noise: Double
        public var gradePercent: Double

        public init(speedKmh: Double = 25.0, powerW: Int = 250, cadenceRpm: Int = 90,
                    heartRateBpm: Int = 60, mode: String = "AUTO", gear: String = "2x5",
                    targetCadence: Int = 90, fatigue: Double = 0, noise: Double = 0,
                    gradePercent: Double = 0) {
            self.speedKmh = speedKmh; self.powerW = powerW; self.cadenceRpm = cadenceRpm
            self.heartRateBpm = heartRateBpm; self.mode = mode; self.gear = gear
            self.targetCadence = targetCadence; self.fatigue = fatigue; self.noise = noise
            self.gradePercent = gradePercent
        }
    }

    @Published public private(set) var stats = LiveStats()

    // MARK: - Internal components

    private var controlPointHandler: FTMSControlPointHandler!
    private var simulationEngine = CyclingSimulationEngine()
    private var notificationScheduler = BLENotificationScheduler()
    private var heartRateSimulator = HeartRateSimulator()
    private let serviceTable = DIRCONServiceTable()

    // MARK: - Network state

    private var listener: NWListener?
    private let clientLock = NSLock()
    /// Per-client state: connection -> set of subscribed characteristic short UUIDs
    private var clients: [ObjectIdentifier: ClientState] = [:]

    private struct ClientState {
        let connection: NWConnection
        var subscribedCharacteristics: Set<UInt16> = []
    }

    // MARK: - Simulation state

    private var lastPowerUpdate: TimeInterval = Date().timeIntervalSince1970
    private var lastSimulationState: CyclingSimulationEngine.SimulationState?
    private var simulationDirty: Bool = true

    // Rolling counters for CPS
    private var revCount: UInt16 = 0
    private var cadTimeTicks: UInt16 = 0
    private var wheelCount: UInt32 = 0
    private var wheelTimeTicks: UInt16 = 0
    private var accumulatedCrankRevs: Double = 0
    private var accumulatedWheelRevs: Double = 0
    private var lastHeartRateBpm: Int = 60

    // MARK: - Port (for testing)

    /// The TCP port the server is listening on (available after startBroadcast)
    public private(set) var listeningPort: UInt16 = 0

    // MARK: - Init

    public override init() {
        super.init()

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

        // Background simulation timer for UI updates
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSimulation()
        }
    }

    // MARK: - Broadcast control

    /// Start listening on the DIRCON port with Bonjour advertisement.
    public func startBroadcast(localName: String? = nil, port: UInt16 = DIRCONProtocol.defaultPort) {
        if let name = localName { self.localName = name }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            appendLog("Failed to create listener: \(error)")
            return
        }

        // Bonjour service advertisement
        let serviceUUIDs = buildServiceUUIDString()
        let txtItems: [(String, String)] = [
            ("serial-number", "SC-DIRCON-001"),
            ("mac-address", "00:00:00:00:00:00"),
            ("ble-service-uuids", serviceUUIDs)
        ]
        var txtRecord = NWTXTRecord()
        for (key, value) in txtItems {
            txtRecord[key] = value
        }
        listener?.service = NWListener.Service(
            name: self.localName,
            type: "_wahoo-fitness-tnp._tcp",
            txtRecord: txtRecord
        )

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                let actualPort = self.listener?.port?.rawValue ?? port
                self.listeningPort = actualPort
                Task { @MainActor in
                    self.isAdvertising = true
                    self.appendLog("DIRCON server listening on port \(actualPort)")
                }
                self.startTicking()
            case .failed(let error):
                Task { @MainActor in
                    self.isAdvertising = false
                    self.appendLog("Listener failed: \(error)")
                }
            case .cancelled:
                Task { @MainActor in
                    self.isAdvertising = false
                    self.appendLog("Listener cancelled")
                }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: .main)
    }

    /// Stop listening and disconnect all clients.
    public func stopBroadcast() {
        notificationScheduler.stopNotifications()
        listener?.cancel()
        listener = nil

        clientLock.lock()
        let allClients = clients
        clients.removeAll()
        clientLock.unlock()

        for state in allClients.values {
            state.connection.cancel()
        }

        Task { @MainActor in
            self.isAdvertising = false
            self.subscriberCount = 0
            self.appendLog("DIRCON server stopped")
        }
    }

    // MARK: - Service UUID string for TXT record

    private func buildServiceUUIDString() -> String {
        var uuids: [String] = []
        if advertiseFTMS { uuids.append("1826") }
        if advertiseCPS { uuids.append("1818") }
        if advertiseHRS { uuids.append("180D") }
        if advertiseRSC { uuids.append("1814") }
        return uuids.joined(separator: ",")
    }

    // MARK: - Connection handling

    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                // NWListener dispatches on .main, so client dict mutation is safe here
                self.clientLock.lock()
                self.clients[id] = ClientState(connection: connection)
                let count = self.clients.count
                self.clientLock.unlock()
                Task { @MainActor in
                    self.appendLog("Client connected: \(connection.endpoint)")
                    self.subscriberCount = count
                }
                self.receiveLoop(connection: connection)
            case .failed(let error):
                self.removeClient(id)
                Task { @MainActor in
                    self.appendLog("Client failed: \(error)")
                }
            case .cancelled:
                self.removeClient(id)
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    private func removeClient(_ id: ObjectIdentifier) {
        clientLock.lock()
        let removed = clients.removeValue(forKey: id)
        let count = clients.count
        clientLock.unlock()

        guard removed != nil else { return }

        if count == 0 {
            // Reset counters like PeripheralManager does when last subscriber leaves
            revCount = 0
            cadTimeTicks = 0
            wheelCount = 0
            wheelTimeTicks = 0
            accumulatedCrankRevs = 0
            accumulatedWheelRevs = 0
        }

        Task { @MainActor in
            self.subscriberCount = count
            self.appendLog("Client disconnected. Remaining: \(count)")
        }
    }

    // MARK: - Receive loop (two-phase: header then payload)

    private func receiveLoop(connection: NWConnection) {
        // Phase 1: read 6-byte header
        connection.receive(minimumIncompleteLength: DIRCONMessage.headerSize,
                           maximumLength: DIRCONMessage.headerSize) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            guard let headerData = data, headerData.count == DIRCONMessage.headerSize else {
                connection.cancel()
                return
            }

            let bytes = [UInt8](headerData)
            let dataLength = Int(UInt16(bytes[4]) << 8 | UInt16(bytes[5]))

            if dataLength == 0 {
                // No payload — handle message directly
                if let msg = DIRCONMessage.deserialize(from: headerData) {
                    self.dispatch(message: msg, on: connection)
                }
                self.receiveLoop(connection: connection)
                return
            }

            // Phase 2: read payload
            connection.receive(minimumIncompleteLength: dataLength,
                               maximumLength: dataLength) { [weak self] payloadData, _, isComplete2, error2 in
                guard let self = self else { return }

                if isComplete2 && payloadData == nil || error2 != nil {
                    connection.cancel()
                    return
                }

                guard let payload = payloadData, payload.count == dataLength else {
                    connection.cancel()
                    return
                }

                var fullMessage = headerData
                fullMessage.append(payload)

                if let msg = DIRCONMessage.deserialize(from: fullMessage) {
                    self.dispatch(message: msg, on: connection)
                }

                self.receiveLoop(connection: connection)
            }
        }
    }

    // MARK: - Message dispatch

    private func dispatch(message: DIRCONMessage, on connection: NWConnection) {
        switch message.opcode {
        case .discoverServices:
            handleDiscoverServices(message: message, on: connection)
        case .discoverCharacteristics:
            handleDiscoverCharacteristics(message: message, on: connection)
        case .readCharacteristic:
            handleReadCharacteristic(message: message, on: connection)
        case .writeCharacteristic:
            handleWriteCharacteristic(message: message, on: connection)
        case .enableNotifications:
            handleEnableNotifications(message: message, on: connection)
        case .notification:
            // Clients don't send notifications to the server
            break
        }
    }

    // MARK: - Opcode handlers

    private func handleDiscoverServices(message: DIRCONMessage, on connection: NWConnection) {
        let payload = serviceTable.discoverServicesPayload()
        sendResponse(opcode: .discoverServices, seq: message.sequenceNumber,
                     responseCode: .success, payload: payload, on: connection)
    }

    private func handleDiscoverCharacteristics(message: DIRCONMessage, on connection: NWConnection) {
        guard message.payload.count >= 16 else {
            sendError(opcode: .discoverCharacteristics, seq: message.sequenceNumber,
                      responseCode: .serviceNotFound, on: connection)
            return
        }

        let shortUUID = DIRCONProtocol.shortUUID(from: message.payload)
        guard let payload = serviceTable.discoverCharacteristicsPayload(forServiceShortUUID: shortUUID) else {
            sendError(opcode: .discoverCharacteristics, seq: message.sequenceNumber,
                      responseCode: .serviceNotFound, on: connection)
            return
        }

        sendResponse(opcode: .discoverCharacteristics, seq: message.sequenceNumber,
                     responseCode: .success, payload: payload, on: connection)
    }

    private func handleReadCharacteristic(message: DIRCONMessage, on connection: NWConnection) {
        guard message.payload.count >= 16 else {
            sendError(opcode: .readCharacteristic, seq: message.sequenceNumber,
                      responseCode: .characteristicNotFound, on: connection)
            return
        }

        let shortUUID = DIRCONProtocol.shortUUID(from: message.payload)
        guard let value = serviceTable.readCharacteristicValue(shortUUID: shortUUID) else {
            sendError(opcode: .readCharacteristic, seq: message.sequenceNumber,
                      responseCode: .characteristicNotFound, on: connection)
            return
        }

        var payload = Data(DIRCONProtocol.wireUUID(from: shortUUID))
        payload.append(value)
        sendResponse(opcode: .readCharacteristic, seq: message.sequenceNumber,
                     responseCode: .success, payload: payload, on: connection)
    }

    private func handleWriteCharacteristic(message: DIRCONMessage, on connection: NWConnection) {
        guard message.payload.count >= 16 else {
            sendError(opcode: .writeCharacteristic, seq: message.sequenceNumber,
                      responseCode: .characteristicNotFound, on: connection)
            return
        }

        let shortUUID = DIRCONProtocol.shortUUID(from: message.payload)
        let writeData = message.payload.suffix(from: message.payload.startIndex + 16)

        // Send write acknowledgment with the characteristic UUID
        let ackPayload = Data(DIRCONProtocol.wireUUID(from: shortUUID))
        sendResponse(opcode: .writeCharacteristic, seq: message.sequenceNumber,
                     responseCode: .success, payload: ackPayload, on: connection)

        // FTMS Control Point (0x2AD9)
        if shortUUID == 0x2AD9 {
            let result = controlPointHandler.handleCommand(Data(writeData))
            appendLog(result.logMessage)

            // Send indication response on 0x2AD9
            if let response = result.response {
                sendNotification(charShortUUID: 0x2AD9, payload: response)
            }

            // Apply state update
            if let update = result.stateUpdate {
                var state = controlPointHandler.getState()
                update(&state)
                controlPointHandler.setState(state)

                // Sync state to published properties
                // Only sync watts for SetTargetPower — other commands must not
                // overwrite the user's manual power setting with the default.
                let isSetTargetPower = result.command == .setTargetPower
                let syncGrade = state.gradePercent
                let syncCrr = state.simCrr
                let syncCw = state.simCw
                let syncWind = state.simWindSpeedMps
                let syncPower = state.targetPower
                Task { @MainActor in
                    if isSetTargetPower {
                        self.watts = syncPower
                    }
                    self.gradePercent = syncGrade
                    self.simCrr = syncCrr
                    self.simCw = syncCw
                    self.simWindSpeedMps = syncWind
                }
            }

            // Send status notification on 0x2ADA after optional delay
            if let status = result.status {
                if result.statusDelay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + result.statusDelay) { [weak self] in
                        self?.sendNotification(charShortUUID: 0x2ADA, payload: status)
                    }
                } else {
                    sendNotification(charShortUUID: 0x2ADA, payload: status)
                }
            }
        }
    }

    private func handleEnableNotifications(message: DIRCONMessage, on connection: NWConnection) {
        guard message.payload.count >= 16 else {
            sendError(opcode: .enableNotifications, seq: message.sequenceNumber,
                      responseCode: .characteristicNotFound, on: connection)
            return
        }

        let shortUUID = DIRCONProtocol.shortUUID(from: message.payload)
        let id = ObjectIdentifier(connection)

        clientLock.lock()
        clients[id]?.subscribedCharacteristics.insert(shortUUID)
        clientLock.unlock()

        let responsePayload = Data(DIRCONProtocol.wireUUID(from: shortUUID))
        sendResponse(opcode: .enableNotifications, seq: message.sequenceNumber,
                     responseCode: .success, payload: responsePayload, on: connection)

        appendLog("Client subscribed to char 0x\(String(shortUUID, radix: 16, uppercase: true))")
    }

    // MARK: - Send helpers

    private func sendResponse(opcode: DIRCONOpcode, seq: UInt8, responseCode: DIRCONResponseCode,
                               payload: Data, on connection: NWConnection) {
        let msg = DIRCONMessage(opcode: opcode, sequenceNumber: seq,
                                responseCode: responseCode.rawValue, payload: payload)
        connection.send(content: msg.serialize(), completion: .contentProcessed({ _ in }))
    }

    private func sendError(opcode: DIRCONOpcode, seq: UInt8, responseCode: DIRCONResponseCode,
                            on connection: NWConnection) {
        let msg = DIRCONMessage(opcode: opcode, sequenceNumber: seq,
                                responseCode: responseCode.rawValue, payload: Data())
        connection.send(content: msg.serialize(), completion: .contentProcessed({ _ in }))
    }

    /// Send a notification frame (opcode 0x06) to all clients subscribed to the given characteristic.
    private func sendNotification(charShortUUID: UInt16, payload: Data) {
        var notifPayload = Data(DIRCONProtocol.wireUUID(from: charShortUUID))
        notifPayload.append(payload)

        let msg = DIRCONMessage(opcode: .notification, sequenceNumber: 0,
                                responseCode: DIRCONResponseCode.success.rawValue,
                                payload: notifPayload)
        let wireData = msg.serialize()

        clientLock.lock()
        let snapshot = clients.values.filter { $0.subscribedCharacteristics.contains(charShortUUID) }
        clientLock.unlock()

        for client in snapshot {
            client.connection.send(content: wireData, completion: .contentProcessed({ _ in }))
        }
    }

    // MARK: - Simulation (reuses PeripheralManager patterns)

    private func updateSimulation() {
        if !isAdvertising {
            let input = CyclingSimulationEngine.SimulationInput(
                targetPower: watts,
                manualCadence: cadenceMode == .manual ? cadenceRpm : nil,
                gradePercent: gradePercent,
                randomness: randomness,
                isResting: false,
                simCrr: simCrr > 0 ? simCrr : nil,
                simCw: simCw > 0 ? simCw : nil,
                simWindSpeedMps: simWindSpeedMps != 0 ? simWindSpeedMps : nil,
                powerProfileMode: powerProfileMode
            )
            let state = simulationEngine.update(with: input)
            lastHeartRateBpm = heartRateSimulator.update(power: Double(state.powerWatts), dt: 1.0)
            updateLiveStats(simState: state)
        }
    }

    private func runSimulationIfNeeded() {
        guard simulationDirty else { return }
        let now = Date().timeIntervalSince1970
        let dt = max(0.001, now - lastPowerUpdate)
        lastPowerUpdate = now

        let input = CyclingSimulationEngine.SimulationInput(
            targetPower: watts,
            manualCadence: cadenceMode == .manual ? cadenceRpm : nil,
            gradePercent: gradePercent,
            randomness: randomness,
            isResting: false,
            simCrr: simCrr > 0 ? simCrr : nil,
            simCw: simCw > 0 ? simCw : nil,
            simWindSpeedMps: simWindSpeedMps != 0 ? simWindSpeedMps : nil,
            powerProfileMode: powerProfileMode
        )
        let state = simulationEngine.update(with: input)
        lastSimulationState = state
        speedMps = state.speedMps
        lastHeartRateBpm = heartRateSimulator.update(power: Double(state.powerWatts), dt: dt)
        advanceCounters(dt: dt, cadence: state.cadenceRpm)
        updateLiveStats(simState: state)
        simulationDirty = false
    }

    private func advanceCounters(dt: Double, cadence: Int) {
        accumulatedCrankRevs += dt * Double(cadence) / 60.0
        let wholeCrankRevs = Int(accumulatedCrankRevs)
        if wholeCrankRevs >= 1 {
            revCount &+= UInt16(wholeCrankRevs)
            accumulatedCrankRevs -= Double(wholeCrankRevs)
        }
        cadTimeTicks = UInt16((Date().timeIntervalSince1970 * 1024).truncatingRemainder(dividingBy: 65536))

        let circumference = 2.096
        let wheelRevsDelta = dt * (cpsIncludeSpeed ? (speedMps / circumference) : 0)
        accumulatedWheelRevs += wheelRevsDelta
        let wholeWheelRevs = Int(accumulatedWheelRevs)
        if wholeWheelRevs >= 1 {
            wheelCount &+= UInt32(wholeWheelRevs)
            accumulatedWheelRevs -= Double(wholeWheelRevs)
        }
        wheelTimeTicks = UInt16((Date().timeIntervalSince1970 * 2048).truncatingRemainder(dividingBy: 65536))
    }

    private func updateLiveStats(simState: CyclingSimulationEngine.SimulationState) {
        stats = LiveStats(
            speedKmh: simState.speedMps * 3.6,
            powerW: simState.powerWatts,
            cadenceRpm: simState.cadenceRpm,
            heartRateBpm: lastHeartRateBpm,
            mode: cadenceMode == .auto ? "AUTO" : "MANUAL",
            gear: "\(simState.gear.front)x\(simState.gear.rear)",
            targetCadence: Int(simState.targetCadence.rounded()),
            fatigue: simState.fatigue,
            noise: simState.noise,
            gradePercent: gradePercent
        )
    }

    // MARK: - Notification tick handlers (scheduler callbacks)

    private func tickFTMS() {
        simulationDirty = true
        runSimulationIfNeeded()
        guard let state = lastSimulationState else { return }

        if advertiseFTMS {
            let wattsToSend = ftmsIncludePower ? state.powerWatts : 0
            let cadenceToSend = ftmsIncludeCadence ? state.cadenceRpm : 0
            let payload = BLEEncoding.ftmsIndoorBikeData(
                speedKmh: state.speedMps * 3.6,
                cadenceRpm: (ftmsIncludeCadence && cadenceToSend > 0) ? cadenceToSend : nil,
                powerW: (ftmsIncludePower && wattsToSend != 0) ? wattsToSend : nil
            )
            sendNotification(charShortUUID: 0x2AD2, payload: payload)
        }
    }

    private func tickCPS() {
        runSimulationIfNeeded()
        guard let state = lastSimulationState else { return }

        if advertiseCPS {
            let wattsToSend = cpsIncludePower ? state.powerWatts : 0
            let cadenceToSend = cpsIncludeCadence ? state.cadenceRpm : 0
            let payload = BLEEncoding.cpsMeasurement(
                powerW: wattsToSend,
                wheelCount: cpsIncludeSpeed ? wheelCount : nil,
                wheelTime2048: cpsIncludeSpeed ? wheelTimeTicks : nil,
                crankRevs: cadenceToSend > 0 ? revCount : nil,
                crankTime1024: cadenceToSend > 0 ? cadTimeTicks : nil
            )
            sendNotification(charShortUUID: 0x2A63, payload: payload)
        }
    }

    private func tickRSC() {
        runSimulationIfNeeded()
        guard let state = lastSimulationState else { return }

        if advertiseRSC {
            let payload = BLEEncoding.rscMeasurement(speedMps: state.speedMps, cadence: state.cadenceRpm)
            sendNotification(charShortUUID: 0x2A53, payload: payload)
        }
    }

    private func tickHRS() {
        runSimulationIfNeeded()

        if advertiseHRS {
            let payload = BLEEncoding.heartRateMeasurement(bpm: lastHeartRateBpm)
            sendNotification(charShortUUID: 0x2A37, payload: payload)
        }
    }

    private func startTicking() {
        notificationScheduler.delegate = self
        notificationScheduler.startNotifications()
    }

    // MARK: - Logging

    private func appendLog(_ message: String) {
        eventLog.append(message)
    }
}

// MARK: - BLENotificationScheduler.Delegate

extension DIRCONServer: BLENotificationScheduler.Delegate {
    public func schedulerShouldSendFTMSNotification() {
        tickFTMS()
    }

    public func schedulerShouldSendCPSNotification() {
        tickCPS()
    }

    public func schedulerShouldSendRSCNotification() {
        tickRSC()
    }

    public func schedulerShouldSendHRSNotification() {
        tickHRS()
    }

    public func schedulerNeedsCadenceForCPSInterval() -> Int {
        return simulationEngine.currentState.cadenceRpm
    }
}
