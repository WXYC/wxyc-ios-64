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
        .package(path: "../WXUI"),
        .package(path: "../Logger"),
        .package(path: "../Core"),
        .package(path: "../Analytics"),
        .package(path: "../Caching"),
    ],
    targets: [
        .target(
            name: "MusicShareKit",
            dependencies: ["WXUI", "Logger", "Core", "Analytics", "Caching"],
            resources: [
                .process("Resources/Assets.xcassets")
            ],
        ),
        .testTarget(
            name: "MusicShareKitTests",
            dependencies: [
                "MusicShareKit",
                .product(name: "AnalyticsTesting", package: "Analytics"),
                .product(name: "Caching", package: "Caching"),
            ]),
    ]
)

