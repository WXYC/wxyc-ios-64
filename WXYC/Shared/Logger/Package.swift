// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
        .iOS(.v18), .watchOS(.v11), .macOS(.v10_14)
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
