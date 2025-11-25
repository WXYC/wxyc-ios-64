// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicShareKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "MusicShareKit",
            targets: ["MusicShareKit"]),
    ],
    targets: [
        .target(
            name: "MusicShareKit"),
        .testTarget(
            name: "MusicShareKitTests",
            dependencies: ["MusicShareKit"]),
    ]
)

