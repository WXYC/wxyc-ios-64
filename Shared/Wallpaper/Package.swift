// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

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
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.0.0"..<"603.0.0"),
    ],
    targets: [
        .macro(
            name: "WallpaperMacroPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "WallpaperMacros",
            dependencies: ["WallpaperMacroPlugin"]
        ),
        .target(
            name: "Wallpaper",
            dependencies: [
                "ObservableDefaults",
                "WallpaperMacros"
            ],
            resources: [
                .process("Metal")
            ]
        ),
        .testTarget(
            name: "WallpaperMacroTests",
            dependencies: [
                "WallpaperMacroPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
