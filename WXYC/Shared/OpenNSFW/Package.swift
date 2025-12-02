// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "OpenNSFW",
    platforms: [
        .iOS("18.4"), .watchOS(.v11), .macOS(.v15)
    ],
    products: [
        .library(name: "OpenNSFW", targets: ["OpenNSFW"])
    ],
    dependencies: [
        .package(path: "../Logger")
    ],
    targets: [
        .target(
            name: "OpenNSFW",
            dependencies: [
                "Logger"
            ],
            resources: [
                .copy("OpenNSFW.mlmodelc")
            ]
        )
    ]
)
