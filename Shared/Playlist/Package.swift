// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Playlist",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "Playlist", targets: ["Playlist"]),
        .library(name: "PlaylistTesting", targets: ["PlaylistTesting"]),
    ],
    dependencies: [
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Core", path: "../Core"),
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Logger", path: "../Logger"),
        // Load-bearing — do not remove as "unused". The WXYC app target imports
        // Concerts directly but has no explicit product dependency on it; it
        // resolves transitively because Playlist (which the app does depend on)
        // pulls Concerts into the build graph. The playcut-CTA work also adds
        // Concerts usage inside this package (`upcoming_show: Concert?`). Dropping
        // this edge breaks the app's `import Concerts`.
        .package(name: "Concerts", path: "../Concerts"),
    ],
    targets: [
        .target(
            name: "Playlist",
            dependencies: ["Analytics", "Core", "Caching", "Logger", "Concerts"],
            resources: [.process("Playlist Detail Assets.xcassets")]
        ),
        .target(
            name: "PlaylistTesting",
            dependencies: ["Playlist", "Concerts"]
        ),
        .testTarget(
            name: "PlaylistTests",
            dependencies: [
                "Playlist",
                "PlaylistTesting",
                "Caching",
                "Concerts",
                .product(name: "CachingTesting", package: "Caching"),
                .product(name: "AnalyticsTesting", package: "Analytics"),
                .product(name: "LoggerTesting", package: "Logger"),
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)
