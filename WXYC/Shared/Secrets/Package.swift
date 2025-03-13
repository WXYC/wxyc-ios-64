// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Secrets",
    platforms: [
        .iOS(.v18), .watchOS(.v11), .macOS(.v10_14)
    ],
    products: [
        .library(
            name: "Secrets",
            targets: ["Secrets"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/p-x9/ObfuscateMacro.git", .upToNextMajor(from: "0.10.0")),
    ],
    targets: [
        .target(
            name: "Secrets",
            dependencies: [
                .product(name: "ObfuscateMacro", package: "ObfuscateMacro")
            ]
        ),
    ]
)
