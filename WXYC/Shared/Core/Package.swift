// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v18), .watchOS(.v11), .macOS(.v10_14)
    ],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [
        .package(name: "OpenNSFW", path: "../OpenNSFW"),
        .package(name: "Logger", path: "../Logger")
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                "OpenNSFW",
                "Logger"
            ]
        )
    ]
)
