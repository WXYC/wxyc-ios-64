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
            ]
            // Note: OpenNSFW.mlmodelc is NOT bundled here to avoid duplication.
            // The model is included only in the main app target and seeded to
            // the shared app group container for widget access.
        )
    ]
)
