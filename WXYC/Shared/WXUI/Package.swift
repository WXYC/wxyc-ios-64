// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WXUI",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "WXUI",
            targets: ["WXUI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WXUI",
            dependencies: []
        ),
        .testTarget(
            name: "WXUITests",
            dependencies: ["WXUI"]),
    ]
)

