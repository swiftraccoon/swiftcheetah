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
}

