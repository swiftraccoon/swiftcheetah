import SwiftUI
#if canImport(SwiftCheetahBLE)
// BLE sources are part of the same target
#endif

/// Main SwiftCheetah app entry point for macOS BLE cycling trainer.
@main
struct SwiftCheetahApp: App {
    @StateObject private var ble = BLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
        }
        .defaultSize(width: 900, height: 560)
        .windowResizability(.contentSize)
    }
}