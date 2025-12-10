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
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
    ],
    targets: [
        .target(
            name: "AVAudioStreamer",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]),
        .testTarget(
            name: "AVAudioStreamerTests",
            dependencies: ["AVAudioStreamer"]),
    ]
)
