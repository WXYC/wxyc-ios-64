// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AVAudioStreamer",
    platforms: [
        .iOS("18.4"),
        .macOS(.v15),
        .tvOS(.v18),
        // watchOS excluded - AudioToolbox not available
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "AVAudioStreamer",
            targets: ["AVAudioStreamer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(name: "Core", path: "../../Core"),
    ],
    targets: [
        .target(
            name: "AVAudioStreamer",
            dependencies: [
                .product(name: "DequeModule", package: "swift-collections"),
                "Core",
            ]),
        .testTarget(
            name: "AVAudioStreamerTests",
            dependencies: ["AVAudioStreamer"]),
    ]
)
