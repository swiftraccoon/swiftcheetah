SwiftCheetah (macOS)
====================

![SwiftCheetah App](swiftcheetah.png)

Overview
--------

SwiftCheetah is a macOS app (Swift/SwiftUI) that acts as a Bluetooth LE peripheral for fitness software. It broadcasts FTMS, CPS and RSC services and generates realistic indoor‑bike metrics using research‑backed physics and cadence models. The codebase is split into a pure core (engine) and the BLE/app layers.

Status (WIP)
------------

- Completed
  - BLE peripheral for FTMS (0x1826), CPS (0x1818), RSC (0x1814)
  - FTMS Control Point handling (Request Control, Reset, Set Target Power, Start/Stop, Set Indoor Bike Simulation) with Fitness Machine Status notifications
  - FTMS Indoor Bike Data notifications (speed encoded as 0, cadence, power)
  - Research‑based engine for speed (power→speed physics) and cadence (logistic power→cadence, grade effects, gear constraints)
  - Unit tests for engine and GATT payload encoders; GitHub Actions CI with build + test + lint
- In progress / TODO
  - Add more end‑to‑end integration tests (central harness) for CPS and RSC payloads
  - Settings panel for engine parameters (mass, Crr, CdA, FTP), export/import configuration
  - Packaging and release instructions

System Requirements
-------------------

- macOS 26 (Tahoe) runtime
- Xcode 26+ and Swift 6+ for building

Repository Layout
-----------------

- `Package.swift` — Swift package manifest (core + BLE)
- `Sources/SwiftCheetahCore/` — engine modules (physics, cadence, variance, utilities)
- `Sources/SwiftCheetahBLE/` — BLE layer (CBPeripheralManager, GATT encoders)
- `App/SwiftCheetahDemoApp/` — minimal SwiftUI app target
- `Tests/` — unit tests for core and BLE (encoding), optional integration test harness

Build and Run
-------------

- Xcode (recommended)
  1. Open `SwiftCheetahApp/SwiftCheetahApp.xcodeproj`
  2. Select the `SwiftCheetahApp` scheme
  3. Set Signing (Automatic); build and run on “My Mac”

- SwiftPM (engine only)
  - `swift build`
  - `swift test` (engine + BLE encoding tests)

CI
--

- GitHub Actions workflow builds the app target, runs unit tests and SwiftLint on push/PR.
- BLE integration tests are opt‑in; they require a central to run on the same machine and are skipped in CI by default.

Design Notes (Engine)
---------------------

- Cadence (AUTO): logistic power→cadence model with saturating uphill penalty, small downhill bump, gear constraints (one‑cog shifts, cooldowns), high‑speed coasting/spin‑out handling, first‑order response, OU‑style jitter, fatigue accumulation/recovery.
- Speed: oriented gravity/rolling/aero with drivetrain efficiency, descent terminal velocity and steady‑state solver.
- The engine is deterministic and designed to avoid invalid or unrealistic values.

Known Limitations (WIP)
-----------------------

- GUI is in an early state (layout, spacing, and controls need refinement).
- Only a subset of FTMS optional fields are encoded; speed in Indoor Bike Data is fixed to 0 by design.
- BLE integration tests are present but opt‑in; more scenarios will be added (CPS/RSC payload assertions).

Integration Test Harness (Optional)
-----------------------------------

- To run the central‑side integration test locally:
  - In Xcode: Edit Scheme → Test → Environment Variables → set `BLE_INTEGRATION=1`
  - Or via CLI: `BLE_INTEGRATION=1 xcodebuild -project SwiftCheetahApp/SwiftCheetahApp.xcodeproj -scheme SwiftCheetahApp -destination 'platform=macOS' test`
  - The test scans, connects, subscribes to FTMS Indoor Bike Data, and asserts a notification payload.
