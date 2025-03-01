// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "UI",
    platforms: [
        .iOS(.v18), .watchOS(.v11)
    ],
    products: [
        .library(name: "UI", targets: ["UI"])
    ],
    dependencies: [
        .package(path: "../Logger"),
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "UI",
            dependencies: [
                "Logger",
                "Core"
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
            ]
        )
    ]
)
