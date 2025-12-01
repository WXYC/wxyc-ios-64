// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "Core",
            targets: ["Core"]
        )
    ],
    dependencies: [
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Logger", path: "../Logger"),
        .package(name: "OpenNSFW", path: "../OpenNSFW"),
        .package(name: "Secrets", path: "../Secrets"),
        
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.35.0")),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                "Analytics",
                "Logger",
                "OpenNSFW",
                "Secrets",

                .product(name: "PostHog", package: "posthog-ios")
            ],
            resources: [
                .process("Models and Services/Playlist Service/Playlist Detail Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        )
    ]
)
