// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Wallpaper",
    platforms: [
        .iOS("18.4"),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Wallpaper",
            targets: ["Wallpaper"]),
    ],
    dependencies: [
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Core", path: "../Core"),
        .package(name: "WXUI", path: "../WXUI"),
    ],
    targets: [
        .target(
            name: "Wallpaper",
            dependencies: [
                "Analytics",
                "Core",
                "WXUI",
            ],
            exclude: [
                "Resources/Wallpapers/Opal"
            ],
            resources: [
                .process("Resources/Wallpapers"),
                .process("Resources/Shaders")
            ]
        ),
        .testTarget(
            name: "WallpaperTests",
            dependencies: ["Wallpaper"]
        ),
    ]
)
