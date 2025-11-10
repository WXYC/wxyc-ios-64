// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Secrets",
    platforms: [
        .iOS(.v18), .watchOS(.v9)
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
