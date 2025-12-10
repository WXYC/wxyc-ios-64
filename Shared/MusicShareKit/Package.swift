// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicShareKit",
    platforms: [
        .iOS("18.4"),
        .watchOS(.v11),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MusicShareKit",
            targets: ["MusicShareKit"]),
    ],
    dependencies: [
        .package(path: "../Secrets"),
        .package(path: "../WXUI"),
        .package(path: "../Analytics"),
        .package(path: "../Logger"),
    ],
    targets: [
        .target(
            name: "MusicShareKit",
            dependencies: ["Secrets", "WXUI", "Analytics", "Logger"],
            resources: [
                .process("Resources/Assets.xcassets")
            ],
        ),
        .testTarget(
            name: "MusicShareKitTests",
            dependencies: ["MusicShareKit"]),
    ]
)

