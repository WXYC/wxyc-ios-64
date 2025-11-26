// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicShareKit",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "MusicShareKit",
            targets: ["MusicShareKit"]),
    ],
    dependencies: [
        .package(path: "../RequestService"),
        .package(path: "../Secrets"),
    ],
    targets: [
        .target(
            name: "MusicShareKit",
            dependencies: ["RequestService", "Secrets"],
            resources: [
                .process("Resources/Assets.xcassets")
            ],
        ),
        .testTarget(
            name: "MusicShareKitTests",
            dependencies: ["MusicShareKit"]),
    ]
)

