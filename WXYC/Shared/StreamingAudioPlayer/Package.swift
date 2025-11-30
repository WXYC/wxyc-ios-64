// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StreamingAudioPlayer",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .watchOS(.v26),
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "StreamingAudioPlayer",
            targets: ["StreamingAudioPlayer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/dimitris-c/AudioStreaming.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "StreamingAudioPlayer",
            dependencies: ["AudioStreaming"]
        ),
        .testTarget(
            name: "StreamingAudioPlayerTests",
            dependencies: ["StreamingAudioPlayer"]
        ),
    ]
)

