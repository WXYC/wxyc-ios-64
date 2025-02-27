// swift-tools-version:6.0

import PackageDescription

@available(iOS 18.0, tvOS 11.0, watchOS 11.0, visionOS 1.0, *)
let package = Package(
    name: "OpenNSFW",
    platforms: [
        .iOS(.v18)
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
