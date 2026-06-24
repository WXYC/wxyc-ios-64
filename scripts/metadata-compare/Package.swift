// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "metadata-compare",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "metadata-compare", targets: ["MetadataCompare"]),
    ],
    dependencies: [
        .package(name: "Core", path: "../../Shared/Core"),
        .package(name: "Playlist", path: "../../Shared/Playlist"),
        .package(name: "Metadata", path: "../../Shared/Metadata"),
    ],
    targets: [
        .executableTarget(
            name: "MetadataCompare",
            dependencies: ["Core", "Playlist", "Metadata"]
        ),
    ]
)
