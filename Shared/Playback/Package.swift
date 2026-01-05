// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Playback",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15), .tvOS("18.4")],
    products: [
        // Public-facing libraries
        .library(name: "Playback", targets: ["Playback"]),
        .library(name: "PlaybackWatchOS", targets: ["PlaybackWatchOS"]),
        // Internal libraries (exposed for testing)
        .library(name: "PlaybackCore", targets: ["PlaybackCore"]),
    ],
    dependencies: [
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Core", path: "../Core"),
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Logger", path: "../Logger"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.35.0")),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ],
    targets: [
        // MARK: - Internal Targets

        // Shared protocols and types
        .target(
            name: "PlaybackCore",
            dependencies: [
                "Caching",
                "Core",
                "Analytics",
                "Logger",
                .product(name: "PostHog", package: "posthog-ios"),
            ]
        ),

        // AVPlayer-based player (watchOS-compatible)
        .target(
            name: "RadioPlayerModule",
            dependencies: [
                "PlaybackCore",
            ],
            path: "Sources/RadioPlayer"
        ),

        // AudioToolbox-based player (iOS/macOS/tvOS only, not watchOS)
        .target(
            name: "AVAudioStreamerModule",
            dependencies: [
                "PlaybackCore",
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            path: "Sources/AVAudioStreamer"
        ),

        // MARK: - Public-Facing Targets

        // iOS/macOS/tvOS playback (includes both players)
        .target(
            name: "Playback",
            dependencies: [
                "PlaybackCore",
                "RadioPlayerModule",
                "AVAudioStreamerModule",
            ]
        ),

        // watchOS playback (RadioPlayer only, no AVAudioStreamer)
        .target(
            name: "PlaybackWatchOS",
            dependencies: [
                "PlaybackCore",
                "RadioPlayerModule",
            ]
        ),

        // MARK: - Tests

        .testTarget(
            name: "PlaybackTests",
            dependencies: ["Playback", "RadioPlayerModule", "AVAudioStreamerModule"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RadioPlayerTests",
            dependencies: ["RadioPlayerModule", "PlaybackCore", "Analytics", "Core"]
        ),
        .testTarget(
            name: "AVAudioStreamerTests",
            dependencies: ["AVAudioStreamerModule", "PlaybackCore", "Core"],
            resources: [.process("Resources")]
        ),
    ]
)
