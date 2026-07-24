// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WXYCIntents",
    platforms: [
        .iOS("18.4"), .watchOS(.v11), .macOS(.v15)
    ],
    products: [
        .library(name: "WXYCIntents", targets: ["WXYCIntents"]),
    ],
    dependencies: [
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Core", path: "../Core"),
        .package(name: "Logger", path: "../Logger"),
        .package(name: "Playback", path: "../Playback"),
        .package(name: "Playlist", path: "../Playlist"),
    ],
    targets: [
        .target(
            name: "WXYCIntents",
            dependencies: [
                "Analytics",
                "Core",
                "Logger",
                "Playback",
                "Playlist",
                .product(name: "PlaybackCore", package: "Playback"),
            ],
            path: "Sources/Intents"
        ),
        .testTarget(
            name: "WXYCIntentsTests",
            dependencies: [
                "WXYCIntents",
                "Core",
                "Playlist",
                .product(name: "PlaylistTesting", package: "Playlist"),
                // Only needed to build an isolated in-memory `PlaycutHistoryStore`
                // (`CacheCoordinator(cache: InMemoryCache())`) for the F3
                // `@Dependency`-binding tests — production WXYCIntents code never
                // imports Caching directly.
                "Caching",
            ],
            path: "Tests/WXYCIntentsTests"
        ),
    ]
)
