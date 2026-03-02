// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
        .iOS("18.4"), .watchOS(.v9), .macOS(.v15)
    ],
    products: [
        .library(name: "Logger", targets: ["Logger"]),
        .library(name: "LoggerTesting", targets: ["LoggerTesting"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(
            name: "Logger",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "LoggerTesting",
            dependencies: ["Logger"]
        ),
        .testTarget(
            name: "LoggerTests",
            dependencies: ["Logger", "LoggerTesting"]
        ),
    ]
)
