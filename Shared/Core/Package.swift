// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS("18.4"),
        .watchOS(.v11),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Core",
            targets: ["Core"]
        ),
        .library(
            name: "CoreTesting",
            targets: ["CoreTesting"]
        )
    ],
    dependencies: [
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                "Logger",
            ]
        ),
        .target(
            name: "CoreTesting",
            dependencies: [
                "Core",
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                "CoreTesting",
                .product(name: "LoggerTesting", package: "Logger"),
            ]
        ),
    ]
)
