// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
        .iOS("18.4"), .watchOS(.v11), .macOS(.v15), .tvOS("18.4")
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
