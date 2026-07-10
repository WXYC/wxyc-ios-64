// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AppServices",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15), .tvOS("18.4")],
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
                // WXYCIntents' PlaycutEntity conforms to `IndexedEntity` and
                // uses `CSSearchableItemAttributeSet` (both @available(tvOS,
                // unavailable), CoreSpotlight is CS_TVOS_UNAVAILABLE). Watch
                // has no CoreSpotlight either, so the dep is gated to iOS +
                // macOS to keep both the tvOS and watchOS build graphs clean.
                .product(name: "WXYCIntents", package: "WXYCIntents", condition: .when(platforms: [.iOS, .macOS])),
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
                .product(name: "WXYCIntents", package: "WXYCIntents", condition: .when(platforms: [.iOS, .macOS])),
            ]
        )
    ]
)

