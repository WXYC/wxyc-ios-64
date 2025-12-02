// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RequestService",
    platforms: [
        .iOS("18.4"),
        .watchOS(.v11),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "RequestService",
            targets: ["RequestService"]
        ),
    ],
    dependencies: [
        .package(path: "../Secrets"),
        .package(path: "../Analytics"),
        .package(path: "../Logger"),
        .package(path: "../WXUI"),
    ],
    targets: [
        .target(
            name: "RequestService",
            dependencies: [
                "Secrets",
                "Analytics",
                "Logger",
                "WXUI",
            ]
        ),
        .testTarget(
            name: "RequestServiceTests",
            dependencies: ["RequestService"]
        ),
    ]
)


