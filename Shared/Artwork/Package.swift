// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Artwork",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "Artwork", targets: ["Artwork"])],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Playlist", path: "../Playlist"),
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "Artwork",
            dependencies: ["Core", "Caching", "Playlist", "Logger"]
        ),
        .testTarget(
            name: "ArtworkTests",
            dependencies: [
                "Artwork",
                "Caching",
                "Playlist",
                .product(name: "PlaylistTesting", package: "Playlist"),
            ]
        )
    ]
)

