// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StreamingAudioPlayer",
    platforms: [
        .iOS(.v18),
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
        .package(url: "https://github.com/dimitris-c/AudioStreaming.git", from: "1.0.0"),
        .package(name: "Analytics", path: "../Analytics"),
    ],
    targets: [
        .target(
            name: "StreamingAudioPlayer",
            dependencies: [
                "AudioStreaming",
                "Analytics",
            ]
        ),
        .testTarget(
            name: "StreamingAudioPlayerTests",
            dependencies: ["StreamingAudioPlayer"]
        ),
    ]
)

