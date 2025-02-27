// swift-tools-version:6.0

import PackageDescription

@available(iOS 18.0, tvOS 11.0, watchOS 11.0, visionOS 1.0, *)
let package = Package(
    name: "Logger",
    platforms: [
        .iOS(.v18),
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
