// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LikedSongs",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "LikedSongs", targets: ["LikedSongs"]),
    ],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "Playlist", path: "../Playlist"),
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "LikedSongs",
            dependencies: ["Core", "Playlist", "Logger"]
        ),
        .testTarget(
            name: "LikedSongsTests",
            dependencies: [
                "LikedSongs",
                .product(name: "CoreTesting", package: "Core"),
                .product(name: "PlaylistTesting", package: "Playlist"),
            ]
        )
    ]
)
