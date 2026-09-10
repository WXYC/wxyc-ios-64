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
        .package(name: "Caching", path: "../Caching"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "Playback", path: "../Playback"),
        // Load-bearing — do not remove as "unused" just because OnAirDebugState and
        // OnAirBannerDebugView no longer need it (WXYC/wxyc-ios-64#767 moved their
        // typography/color types to WXUI/ColorPalette). VisualizerDebugView still
        // needs Playlist for `PlaylistService` (the fetch-error readout), so this
        // edge stays — note the API-version picker it also served went with the v1
        // path in #262.
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
                "Caching",
                "ColorPalette",
                "Playback",
                "Playlist",
                "Wallpaper",
                "PlayerHeaderView",
                "WXUI",
            ],
        ),
        .testTarget(
            name: "DebugPanelTests",
            dependencies: ["DebugPanel"]
        ),
    ]
)
