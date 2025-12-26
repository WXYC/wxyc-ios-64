// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Playback",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15), .tvOS(.v18)],
    products: [
        .library(name: "Playback", targets: ["Playback"]),
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
        .target(
            name: "Playback",
            dependencies: [
                "PlaybackCore",
                .product(name: "DequeModule", package: "swift-collections", condition: .when(platforms: [.iOS, .macOS, .tvOS, .visionOS])),
            ]
        ),
        .testTarget(
            name: "PlaybackTests",
            dependencies: ["Playback"],
            resources: [.process("Resources")]
        ),
    ]
)
