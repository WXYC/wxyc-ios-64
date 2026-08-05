// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ColorPalette",
    platforms: [.iOS("18.4"), .macOS(.v15)],
    products: [.library(name: "ColorPalette", targets: ["ColorPalette"])],
    dependencies: [
        .package(name: "Core", path: "../Core"),
    ],
    targets: [
        .target(
            name: "ColorPalette",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "ColorPaletteTests",
            dependencies: ["ColorPalette"]
        )
    ]
)
