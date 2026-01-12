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
            name: "MP3StreamerModule",
            dependencies: [
                "PlaybackCore",
                "Core",
            ],
            path: "Sources/MP3Streamer"
        ),

        // MARK: - Public-Facing Targets

        // iOS/macOS/tvOS playback (includes both players)
        .target(
            name: "Playback",
            dependencies: [
                "PlaybackCore",
                "RadioPlayerModule",
                "MP3StreamerModule",
            ]
        ),

        // watchOS playback (RadioPlayer only, no MP3Streamer)
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
            dependencies: ["Playback", "RadioPlayerModule", "MP3StreamerModule"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RadioPlayerTests",
            dependencies: ["RadioPlayerModule", "PlaybackCore", "Analytics", "Core"]
        ),
        .testTarget(
            name: "MP3StreamerTests",
            dependencies: ["MP3StreamerModule", "PlaybackCore", "Core"],
            resources: [.process("Resources")]
        ),
    ]
)
