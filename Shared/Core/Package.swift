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
    ]
)
