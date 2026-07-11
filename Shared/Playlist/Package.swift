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
                .product(name: "ConcertsTesting", package: "Concerts"),
                .product(name: "CachingTesting", package: "Caching"),
                .product(name: "AnalyticsTesting", package: "Analytics"),
                .product(name: "LoggerTesting", package: "Logger"),
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)
