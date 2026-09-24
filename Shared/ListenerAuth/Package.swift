// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ListenerAuth",
    platforms: [
        .iOS("18.4"),
        .watchOS(.v11),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ListenerAuth",
            targets: ["ListenerAuth"]),
    ],
    dependencies: [
        .package(path: "../Logger"),
        .package(path: "../Core"),
        .package(path: "../Analytics"),
        .package(path: "../Caching"),
    ],
    targets: [
        .target(
            name: "ListenerAuth",
            dependencies: ["Logger", "Core", "Analytics", "Caching"]),
        .testTarget(
            name: "ListenerAuthTests",
            dependencies: [
                "ListenerAuth",
                .product(name: "AnalyticsTesting", package: "Analytics"),
                .product(name: "Caching", package: "Caching"),
                .product(name: "CoreTesting", package: "Core"),
            ]),
    ]
)
