import XCTest
import CoreBluetooth
@testable import SwiftCheetahBLE

final class IntegrationCentralTests: XCTestCase {
    // Set BLE_INTEGRATION=1 in the environment to enable this test locally.
    func testFTMSCentralReceivesIndoorBikeData() throws {
        guard ProcessInfo.processInfo.environment["BLE_INTEGRATION"] == "1" else {
            throw XCTSkip("Integration BLE test disabled. Set BLE_INTEGRATION=1 to run.")
        }

        let periph = PeripheralManager()
        periph.advertiseFTMS = true
        periph.advertiseCPS = false
        periph.advertiseRSC = false
        periph.ftmsIncludeCadence = true
        periph.ftmsIncludePower = true
        periph.cadenceMode = .manual
        periph.cadenceRpm = 90
        periph.watts = 250

        let name = "TrainerTest-\(Int.random(in: 1000...9999))"
        periph.startBroadcast(localName: name)

        let didDiscover = expectation(description: "Discovered peripheral")
        let didConnect = expectation(description: "Connected")
        let didNotify = expectation(description: "Received FTMS Indoor Bike Data notify")

        class Central: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
            let name: String
            let didDiscover: XCTestExpectation
            let didConnect: XCTestExpectation
            let didNotify: XCTestExpectation
            var manager: CBCentralManager!
            var peripheral: CBPeripheral?
            init(name: String, didDiscover: XCTestExpectation, didConnect: XCTestExpectation, didNotify: XCTestExpectation) {
                self.name = name; self.didDiscover = didDiscover; self.didConnect = didConnect; self.didNotify = didNotify
                super.init()
                self.manager = CBCentralManager(delegate: self, queue: .main)
            }
            func centralManagerDidUpdateState(_ central: CBCentralManager) {
                if central.state == .poweredOn {
                    manager.scanForPeripherals(withServices: [CBUUID(string: "1826")], options: nil)
                }
            }
            func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
                let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
                if advName == name {
                    didDiscover.fulfill()
                    peripheral = p
                    manager.stopScan()
                    manager.connect(p, options: nil)
                }
            }
            func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
                didConnect.fulfill()
                p.delegate = self
                p.discoverServices([CBUUID(string: "1826")])
            }
            func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
                guard let s = peripheral.services?.first(where: { $0.uuid == CBUUID(string: "1826") }) else { return }
                peripheral.discoverCharacteristics([CBUUID(string: "2AD2")], for: s)
            }
            func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
                guard let c = service.characteristics?.first(where: { $0.uuid == CBUUID(string: "2AD2") }) else { return }
                peripheral.setNotifyValue(true, for: c)
            }
            func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
                guard characteristic.uuid == CBUUID(string: "2AD2"), let data = characteristic.value else { return }
                let bytes = [UInt8](data)
                // flags (2), speed(2)=0
                if bytes.count >= 4 {
                    let speedLE = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
                    if speedLE == 0 { didNotify.fulfill() }
                }
            }
        }

        let central = Central(name: name, didDiscover: didDiscover, didConnect: didConnect, didNotify: didNotify)
        _ = central // keep alive

        wait(for: [didDiscover, didConnect, didNotify], timeout: 15.0)

        periph.stopBroadcast()
    }

    // MARK: - FTMS Control Point Integration Tests

    func testFTMSControlPointOperations() throws {
        guard ProcessInfo.processInfo.environment["BLE_INTEGRATION"] == "1" else {
            throw XCTSkip("Integration BLE test disabled. Set BLE_INTEGRATION=1 to run.")
        }

        let periph = PeripheralManager()
        periph.advertiseFTMS = true
        periph.ftmsIncludePower = true
        periph.ftmsIncludeCadence = true
        periph.watts = 200
        periph.cadenceRpm = 85

        let name = "ControlTest-\(Int.random(in: 1000...9999))"
        periph.startBroadcast(localName: name)

        let didConnect = expectation(description: "Connected")
        let didWriteControl = expectation(description: "Wrote control point")
        let didReceiveStatus = expectation(description: "Received status notification")

        class ControlTestCentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
            let name: String
            let didConnect: XCTestExpectation
            let didWriteControl: XCTestExpectation
            let didReceiveStatus: XCTestExpectation
            var manager: CBCentralManager!
            var peripheral: CBPeripheral?
            var controlPoint: CBCharacteristic?
            var statusChar: CBCharacteristic?

            init(name: String, connect: XCTestExpectation, write: XCTestExpectation, status: XCTestExpectation) {
                self.name = name
                self.didConnect = connect
                self.didWriteControl = write
                self.didReceiveStatus = status
                super.init()
                self.manager = CBCentralManager(delegate: self, queue: .main)
            }

            func centralManagerDidUpdateState(_ central: CBCentralManager) {
                if central.state == .poweredOn {
                    manager.scanForPeripherals(withServices: [CBUUID(string: "1826")], options: nil)
                }
            }

            func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
                let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
                if advName == name {
                    peripheral = p
                    manager.stopScan()
                    manager.connect(p, options: nil)
                }
            }

            func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
                didConnect.fulfill()
                p.delegate = self
                p.discoverServices([CBUUID(string: "1826")])
            }

            func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
                guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: "1826") }) else { return }
                // Discover Control Point (2AD9) and Machine Status (2ADA)
                peripheral.discoverCharacteristics([CBUUID(string: "2AD9"), CBUUID(string: "2ADA")], for: service)
            }

            func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
                for char in service.characteristics ?? [] {
                    if char.uuid == CBUUID(string: "2AD9") {
                        controlPoint = char
                        // Write SetTargetPower command
                        let powerData = Data([0x05, 0xFA, 0x00]) // Opcode 0x05, Power 250W
                        peripheral.writeValue(powerData, for: char, type: .withResponse)
                    } else if char.uuid == CBUUID(string: "2ADA") {
                        statusChar = char
                        peripheral.setNotifyValue(true, for: char)
                    }
                }
            }

            func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
                if characteristic.uuid == CBUUID(string: "2AD9") {
                    didWriteControl.fulfill()
                }
            }

            func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
                if characteristic.uuid == CBUUID(string: "2ADA"), let data = characteristic.value {
                    // Check for status response (0x80 opcode)
                    if data.count >= 3 && data[0] == 0x80 {
                        didReceiveStatus.fulfill()
                    }
                }
            }
        }

        let central = ControlTestCentral(name: name, connect: didConnect, write: didWriteControl, status: didReceiveStatus)
        _ = central // keep alive

        wait(for: [didConnect, didWriteControl, didReceiveStatus], timeout: 15.0)

        periph.stopBroadcast()
    }

    func testMultiServiceAdvertising() throws {
        guard ProcessInfo.processInfo.environment["BLE_INTEGRATION"] == "1" else {
            throw XCTSkip("Integration BLE test disabled. Set BLE_INTEGRATION=1 to run.")
        }

        let periph = PeripheralManager()
        periph.advertiseFTMS = true
        periph.advertiseCPS = true
        periph.advertiseRSC = true
        periph.watts = 250
        periph.cadenceRpm = 90

        let name = "MultiTest-\(Int.random(in: 1000...9999))"
        periph.startBroadcast(localName: name)

        let didDiscoverFTMS = expectation(description: "Discovered FTMS service")
        let didDiscoverCPS = expectation(description: "Discovered CPS service")
        let didDiscoverRSC = expectation(description: "Discovered RSC service")

        class MultiServiceCentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
            let name: String
            let ftmsExp: XCTestExpectation
            let cpsExp: XCTestExpectation
            let rscExp: XCTestExpectation
            var manager: CBCentralManager!
            var peripheral: CBPeripheral?

            init(name: String, ftms: XCTestExpectation, cps: XCTestExpectation, rsc: XCTestExpectation) {
                self.name = name
                self.ftmsExp = ftms
                self.cpsExp = cps
                self.rscExp = rsc
                super.init()
                self.manager = CBCentralManager(delegate: self, queue: .main)
            }

            func centralManagerDidUpdateState(_ central: CBCentralManager) {
                if central.state == .poweredOn {
                    manager.scanForPeripherals(withServices: nil, options: nil)
                }
            }

            func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
                let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
                if advName == name {
                    peripheral = p
                    manager.stopScan()
                    manager.connect(p, options: nil)
                }
            }

            func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
                p.delegate = self
                p.discoverServices(nil)
            }

            func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
                for service in peripheral.services ?? [] {
                    switch service.uuid {
                    case CBUUID(string: "1826"): // FTMS
                        ftmsExp.fulfill()
                    case CBUUID(string: "1818"): // CPS
                        cpsExp.fulfill()
                    case CBUUID(string: "1814"): // RSC
                        rscExp.fulfill()
                    default:
                        break
                    }
                }
            }
        }

        let central = MultiServiceCentral(name: name, ftms: didDiscoverFTMS, cps: didDiscoverCPS, rsc: didDiscoverRSC)
        _ = central // keep alive

        wait(for: [didDiscoverFTMS, didDiscoverCPS, didDiscoverRSC], timeout: 15.0)

        periph.stopBroadcast()
    }
}

