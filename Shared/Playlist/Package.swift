// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Playlist",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "Playlist", targets: ["Playlist"])],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Logger", path: "../Logger"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.35.0")),
    ],
    targets: [
        .target(
            name: "Playlist",
            dependencies: ["Core", "Caching", "Logger", .product(name: "PostHog", package: "posthog-ios")],
            resources: [.process("Playlist Detail Assets.xcassets")]
        ),
        .testTarget(
            name: "PlaylistTests",
            dependencies: ["Playlist", "Caching"]
        )
    ]
)

