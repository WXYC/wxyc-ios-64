// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v18), .watchOS(.v11), .macOS(.v10_14)
    ],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [
        .package(name: "OpenNSFW", path: "../OpenNSFW"),
        .package(name: "Logger", path: "../Logger"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.20.0")),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                "OpenNSFW",
                "Logger",
                .product(name: "PostHog", package: "posthog-ios")
            ]
        )
    ]
)
