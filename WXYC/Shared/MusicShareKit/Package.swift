// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicShareKit",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MusicShareKit",
            targets: ["MusicShareKit"]),
    ],
    dependencies: [
        .package(path: "../RequestService"),
        .package(path: "../Secrets"),
        .package(path: "../WXUI"),
    ],
    targets: [
        .target(
            name: "MusicShareKit",
            dependencies: ["RequestService", "Secrets", "WXUI"],
            resources: [
                .process("Resources/Assets.xcassets")
            ],
        ),
        .testTarget(
            name: "MusicShareKitTests",
            dependencies: ["MusicShareKit"]),
    ]
)

