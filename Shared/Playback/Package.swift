// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Playback",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15), .tvOS(.v18)],
    products: [.library(name: "Playback", targets: ["Playback"])],
    dependencies: [
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Core", path: "../Core"),
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Logger", path: "../Logger"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.35.0")),
        .package(name: "AVAudioStreamer", path: "AVAudioStreamer"),
        .package(name: "MiniMP3Streamer", path: "MiniMP3Streamer"),
    ],
    targets: [
        .target(
            name: "Playback",
            dependencies: [
                "Caching",
                "Core",
                "Analytics",
                "Logger",
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "AVAudioStreamer", package: "AVAudioStreamer", condition: .when(platforms: [.iOS, .macOS, .tvOS, .visionOS])),
                .product(name: "MiniMP3Streamer", package: "MiniMP3Streamer"),
            ]
        ),
        .testTarget(
            name: "PlaybackTests",
            dependencies: ["Playback"]
        )
    ]
)
