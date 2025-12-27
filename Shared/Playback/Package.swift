// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Playback",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15), .tvOS(.v18)],
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
            name: "RadioPlayer",
            dependencies: [
                "PlaybackCore",
            ]
        ),

        // AudioToolbox-based player (iOS/macOS/tvOS only, not watchOS)
        .target(
            name: "AVAudioStreamer",
            dependencies: [
                "PlaybackCore",
            ]
        ),

        // MARK: - Public-Facing Targets

        // iOS/macOS/tvOS playback (includes both players)
        .target(
            name: "Playback",
            dependencies: [
                "PlaybackCore",
                "RadioPlayer",
                "AVAudioStreamer",
                .product(name: "DequeModule", package: "swift-collections", condition: .when(platforms: [.iOS, .macOS, .tvOS, .visionOS])),
            ]
        ),

        // watchOS playback (RadioPlayer only, no AVAudioStreamer)
        .target(
            name: "PlaybackWatchOS",
            dependencies: [
                "PlaybackCore",
                "RadioPlayer",
            ]
        ),

        // MARK: - Tests

        .testTarget(
            name: "PlaybackTests",
            dependencies: ["Playback"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RadioPlayerTests",
            dependencies: ["RadioPlayer", "PlaybackCore", "Analytics", "Core"]
        ),
        .testTarget(
            name: "AVAudioStreamerTests",
            dependencies: ["AVAudioStreamer", "PlaybackCore", "Core"],
            resources: [.process("Resources")]
        ),
    ]
)
