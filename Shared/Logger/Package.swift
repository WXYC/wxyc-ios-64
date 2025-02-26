// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
      .iOS("18.0"),
    ],
    products: [
        .library(
            name: "Logger",
            targets: ["Logger"]
        ),
    ],
    targets: [
        .target(
            name: "Logger",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
