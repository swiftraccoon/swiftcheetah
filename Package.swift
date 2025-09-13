// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftCheetah",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SwiftCheetahCore", targets: ["SwiftCheetahCore"]),
        .library(name: "SwiftCheetahBLE", targets: ["SwiftCheetahBLE"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftCheetahCore",
            path: "Sources/SwiftCheetahCore"
        ),
        .target(
            name: "SwiftCheetahBLE",
            dependencies: ["SwiftCheetahCore"],
            path: "Sources/SwiftCheetahBLE"
        ),
        .testTarget(
            name: "SwiftCheetahCoreTests",
            dependencies: ["SwiftCheetahCore"],
            path: "Tests/SwiftCheetahCoreTests"
        ),
        .testTarget(
            name: "SwiftCheetahBLETests",
            dependencies: ["SwiftCheetahBLE"],
            path: "Tests/SwiftCheetahBLETests"
        )
    ]
)
