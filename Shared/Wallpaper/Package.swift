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
        .package(name: "Caching", path: "../Caching"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "Core", path: "../Core"),
        .package(url: "https://github.com/jakebromberg/Lerpable.git", branch: "main"),
        .package(name: "Logger", path: "../Logger"),
        .package(name: "WXUI", path: "../WXUI"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Wallpaper",
            dependencies: [
                "Analytics",
                "Caching",
                "ColorPalette",
                "Core",
                "Lerpable",
                "Logger",
                "WXUI",
            ],
            resources: [
                .process("Resources/Wallpapers"),
                .process("Resources/Shaders")
            ]
        ),
        .testTarget(
            name: "WallpaperTests",
            dependencies: [
                "Wallpaper",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "AnalyticsTesting", package: "Analytics"),
            ]
        ),
    ]
)
