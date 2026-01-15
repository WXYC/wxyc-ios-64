// swift-tools-version: 6.2

import PackageDescription
import Foundation

// Check if pre-built XCFramework exists using absolute path derived from Package.swift location.
// This ensures the check works regardless of the current working directory when SwiftPM evaluates this manifest.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let xcframeworkAbsolutePath = packageDir.appendingPathComponent("Secrets.xcframework").path
let useXCFramework = FileManager.default.fileExists(atPath: xcframeworkAbsolutePath)

let package = Package(
    name: "Secrets",
    platforms: [
        .iOS("18.4"), .watchOS(.v9), .macOS(.v15)
    ],
    products: [
        .library(
            name: "Secrets",
            targets: ["Secrets"]
        ),
    ],
    dependencies: useXCFramework ? [] : [
        .package(url: "https://github.com/p-x9/ObfuscateMacro.git", .upToNextMajor(from: "0.10.0")),
    ],
    targets: useXCFramework ? [
        .binaryTarget(
            name: "Secrets",
            path: "Secrets.xcframework"  // Relative path works here since it's resolved from package root
        ),
    ] : [
        .target(
            name: "Secrets",
            dependencies: [
                .product(name: "ObfuscateMacro", package: "ObfuscateMacro")
            ]
        ),
    ]
)
