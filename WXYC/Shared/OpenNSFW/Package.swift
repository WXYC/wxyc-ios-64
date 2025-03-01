// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "OpenNSFW",
    platforms: [
        .iOS(.v18), .watchOS(.v11), .macOS(.v10_14)
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
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
            ]
        )
    ]
)
