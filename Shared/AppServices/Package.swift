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
        .package(name: "WXYCIntents", path: "../Intents"),
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
                // WXYCIntents pulls in Playback (iOS/macOS/tvOS). Watch has no
                // CoreSpotlight and no SpotlightDonationService — dropping the
                // dep on watchOS keeps Playback out of the watch build graph.
                .product(name: "WXYCIntents", package: "WXYCIntents", condition: .when(platforms: [.iOS, .macOS, .tvOS])),
            ]
        ),
        .testTarget(
            name: "AppServicesTests",
            dependencies: [
                "AppServices",
                "Caching",
                "Playlist",
                .product(name: "PlaylistTesting", package: "Playlist"),
                "Artwork",
                .product(name: "PlaybackCore", package: "Playback"),
                .product(name: "WXYCIntents", package: "WXYCIntents", condition: .when(platforms: [.iOS, .macOS, .tvOS])),
            ]
        )
    ]
)

