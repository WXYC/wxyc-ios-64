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
    ],
    targets: [
        .target(
            name: "Playlist",
            dependencies: ["Analytics", "Core", "Caching", "Logger"],
            resources: [.process("Playlist Detail Assets.xcassets")]
        ),
        .target(
            name: "PlaylistTesting",
            dependencies: ["Playlist"]
        ),
        .testTarget(
            name: "PlaylistTests",
            dependencies: [
                "Playlist",
                "PlaylistTesting",
                "Caching",
                .product(name: "AnalyticsTesting", package: "Analytics"),
                .product(name: "LoggerTesting", package: "Logger"),
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)
