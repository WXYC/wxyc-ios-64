// swift-tools-version:6.0

import PackageDescription

@available(iOS 18.0, tvOS 11.0, watchOS 11.0, visionOS 1.0, *)
let package = Package(
    name: "UI",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "UI", targets: ["UI"])
    ],
    dependencies: [
        .package(path: "../Logger")
    ],
    targets: [
        .target(
            name: "UI",
            dependencies: [
                "Logger"
            ]
        )
    ]
)
