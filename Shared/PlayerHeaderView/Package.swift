// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlayerHeaderView",
    platforms: [
        .iOS("18.4"),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS("18.4")
    ],
    products: [
        .library(
            name: "PlayerHeaderView",
            targets: ["PlayerHeaderView"]
        ),
    ],
    dependencies: [
        .package(name: "Playback", path: "../Playback"),
        .package(name: "Wallpaper", path: "../Wallpaper"),
        .package(url: "https://github.com/fatbobman/ObservableDefaults", from: "1.7.0")
    ],
    targets: [
        .target(
            name: "PlayerHeaderView",
            dependencies: [
                "Playback",
                "Wallpaper",
                .product(name: "ObservableDefaults", package: "ObservableDefaults")
            ]
        ),
        .testTarget(
            name: "PlayerHeaderViewTests",
            dependencies: ["PlayerHeaderView", "Playback"]
        ),
    ]
)
