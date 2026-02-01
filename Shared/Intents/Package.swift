// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WXYCIntents",
    platforms: [
        .iOS("18.4"), .watchOS(.v11), .macOS(.v15)
    ],
    products: [
        .library(name: "WXYCIntents", targets: ["WXYCIntents"]),
    ],
    dependencies: [
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Logger", path: "../Logger"),
        .package(name: "Playback", path: "../Playback"),
    ],
    targets: [
        .target(
            name: "WXYCIntents",
            dependencies: [
                "Analytics",
                "Logger",
                "Playback",
                .product(name: "PlaybackCore", package: "Playback"),
            ],
            path: "Sources/Intents"
        ),
    ]
)
