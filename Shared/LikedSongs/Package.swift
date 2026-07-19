// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LikedSongs",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "LikedSongs", targets: ["LikedSongs"]),
        .library(name: "LikedSongsTesting", targets: ["LikedSongsTesting"]),
    ],
    dependencies: [
        .package(name: "Playlist", path: "../Playlist"),
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "LikedSongs",
            dependencies: ["Playlist", "Logger"]
        ),
        .target(
            name: "LikedSongsTesting",
            dependencies: ["LikedSongs"]
        ),
        .testTarget(
            name: "LikedSongsTests",
            dependencies: [
                "LikedSongs",
                "LikedSongsTesting",
            ]
        )
    ]
)
