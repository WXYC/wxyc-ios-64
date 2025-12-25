// swift-tools-version: 6.2

import PackageDescription
import Foundation

// Check if pre-built XCFramework exists
let xcframeworkPath = "Secrets.xcframework"
let useXCFramework = FileManager.default.fileExists(atPath: xcframeworkPath)

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
            path: xcframeworkPath
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
