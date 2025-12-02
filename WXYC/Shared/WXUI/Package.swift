// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WXUI",
    platforms: [
        .iOS("18.4"),
        .watchOS(.v11),
        .macOS(.v15)
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

