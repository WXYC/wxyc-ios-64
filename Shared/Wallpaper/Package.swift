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
        .package(url: "https://github.com/fatbobman/ObservableDefaults", from: "1.7.0"),
        .package(name: "WXUI", path: "../WXUI"),
    ],
    targets: [
        .target(
            name: "Wallpaper",
            dependencies: [
                "ObservableDefaults",
                "WXUI",
            ],
            resources: [
                .process("Resources/Wallpapers"),
                .process("Resources/Shaders")
            ]
        ),
    ]
)
