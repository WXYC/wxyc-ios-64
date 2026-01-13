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
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Playback", path: "../Playback"),
        .package(name: "Wallpaper", path: "../Wallpaper"),
        .package(name: "WXUI", path: "../WXUI"),
    ],
    targets: [
        .target(
            name: "PlayerHeaderView",
            dependencies: [
                "Caching",
                "Playback",
                "Wallpaper",
                "WXUI",
            ]
        ),
        .testTarget(
            name: "PlayerHeaderViewTests",
            dependencies: ["PlayerHeaderView", "Playback"]
        ),
    ]
)
