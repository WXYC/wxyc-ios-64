// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Metadata",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "Metadata", targets: ["Metadata"])],
    dependencies: [
        .package(name: "Artwork", path: "../Artwork"),
        .package(name: "Core", path: "../Core"),
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Playlist", path: "../Playlist"),
        .package(name: "Secrets", path: "../Secrets"),
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "Metadata",
            dependencies: ["Artwork", "Core", "Caching", "Playlist", "Secrets", "Logger"]
        ),
        .testTarget(
            name: "MetadataTests",
            dependencies: ["Metadata", "Caching", "Playlist"]
        )
    ]
)

