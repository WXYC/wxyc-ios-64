// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
        .iOS(.v18), .watchOS(.v9)
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
