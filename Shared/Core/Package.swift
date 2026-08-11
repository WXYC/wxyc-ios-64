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
            ],
            // README.md documents this target and deliberately sits beside the
            // code it inventories. SwiftPM treats any non-source file under
            // Sources/ as an undeclared resource, so without this it warns on
            // every build of Core — and Core builds in seven packages.
            exclude: ["README.md"]
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
