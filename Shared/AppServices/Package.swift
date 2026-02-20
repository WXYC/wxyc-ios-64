// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AppServices",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "AppServices", targets: ["AppServices"])],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "Playback", path: "../Playback"),
        .package(name: "Playlist", path: "../Playlist"),
        .package(name: "Artwork", path: "../Artwork"),
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Logger", path: "../Logger"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.35.0")),
    ],
    targets: [
        .target(
            name: "AppServices",
            dependencies: [
                "Core",
                .product(name: "PlaybackCore", package: "Playback"),
                "Playlist",
                "Artwork",
                "Caching",
                "Analytics",
                "Logger",
                .product(name: "PostHog", package: "posthog-ios")
            ]
        ),
        .testTarget(
            name: "AppServicesTests",
            dependencies: [
                "AppServices",
                "Caching",
                "Playlist",
                "Artwork",
                .product(name: "PlaybackCore", package: "Playback"),
            ]
        )
    ]
)

