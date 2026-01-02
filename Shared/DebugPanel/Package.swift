// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DebugPanel",
    platforms: [
        .iOS("18.4"),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS("18.4")
    ],
    products: [
        .library(
            name: "DebugPanel",
            targets: ["DebugPanel"]
        ),
    ],
    dependencies: [
        .package(name: "AppServices", path: "../AppServices"),
        .package(name: "Playback", path: "../Playback"),
        .package(name: "Playlist", path: "../Playlist"),
        .package(name: "Wallpaper", path: "../Wallpaper"),
        .package(name: "PlayerHeaderView", path: "../PlayerHeaderView"),
        .package(name: "WXUI", path: "../WXUI"),
    ],
    targets: [
        .target(
            name: "DebugPanel",
            dependencies: [
                "AppServices",
                "Playback",
                "Playlist",
                "Wallpaper",
                "PlayerHeaderView",
                "WXUI",
            ]
        ),
    ]
)
