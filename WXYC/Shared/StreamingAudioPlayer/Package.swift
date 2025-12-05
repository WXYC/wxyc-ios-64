// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StreamingAudioPlayer",
    platforms: [
        .iOS("18.4"),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "StreamingAudioPlayer",
            targets: ["StreamingAudioPlayer"]
        ),
    ],
    dependencies: [
        .package(name: "Analytics", path: "../Analytics"),
    ],
    targets: [
        .target(
            name: "StreamingAudioPlayer",
            dependencies: [
                "Analytics",
            ]
        ),
        .testTarget(
            name: "StreamingAudioPlayerTests",
            dependencies: ["StreamingAudioPlayer"]
        ),
    ]
)
