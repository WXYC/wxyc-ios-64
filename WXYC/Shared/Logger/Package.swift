// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
        .iOS("18.4"), .watchOS(.v9), .macOS(.v15)
    ],
    products: [
        .library(name: "Logger", targets: ["Logger"]
        ),
    ],
    dependencies: [
        
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
