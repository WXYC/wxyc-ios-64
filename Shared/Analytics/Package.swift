// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Analytics",
    platforms: [
        .iOS("18.4"), .watchOS(.v11), .macOS(.v15)
    ],
    products: [
        .library(name: "Analytics", targets: ["Analytics"]),
        .library(name: "AnalyticsTesting", targets: ["AnalyticsTesting"]),
    ],
    dependencies: [
        .package(path: "../Secrets"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.20.0")),
    ],
    targets: [
        .target(
            name: "Analytics",
            dependencies: [
                "Secrets",
                .product(name: "PostHog", package: "posthog-ios"),
            ]
        ),
        .target(
            name: "AnalyticsTesting",
            dependencies: ["Analytics"]
        ),
    ]
)
