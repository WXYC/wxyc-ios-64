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
        .package(path: "../AnalyticsMacros"),
        .package(path: "../Logger"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.20.0")),
    ],
    targets: [
        .target(
            name: "Analytics",
            dependencies: [
                .product(name: "AnalyticsMacros", package: "AnalyticsMacros"),
                "Logger",
                .product(name: "PostHog", package: "posthog-ios"),
            ]
        ),
        .target(
            name: "AnalyticsTesting",
            dependencies: ["Analytics"]
        ),
        .testTarget(
            name: "AnalyticsTests",
            dependencies: ["Analytics", "AnalyticsTesting"]
        ),
    ]
)
