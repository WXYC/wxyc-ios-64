// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Wallpaper",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Wallpaper",
            targets: ["Wallpaper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/fatbobman/ObservableDefaults", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "Wallpaper",
            dependencies: [
                "ObservableDefaults",
            ],
            resources: [
                .process("Resources/Wallpapers"),
                .process("Resources/Shaders")
            ]
        ),
    ]
)
