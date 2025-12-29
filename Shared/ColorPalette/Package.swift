// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ColorPalette",
    platforms: [.iOS("18.4"), .macOS(.v15)],
    products: [.library(name: "ColorPalette", targets: ["ColorPalette"])],
    dependencies: [
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Core", path: "../Core"),
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "ColorPalette",
            dependencies: ["Caching", "Core", "Logger"]
        ),
        .testTarget(
            name: "ColorPaletteTests",
            dependencies: ["ColorPalette"]
        )
    ]
)
