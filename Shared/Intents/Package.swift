// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WXYCIntents",
    platforms: [
        .iOS("18.4"), .watchOS(.v11), .macOS(.v15)
    ],
    products: [
        .library(name: "WXYCIntents", targets: ["WXYCIntents"]),
    ],
    dependencies: [
        .package(name: "Logger", path: "../Logger"),
        .package(name: "Playback", path: "../Playback"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.35.0")),
    ],
    targets: [
        .target(
            name: "WXYCIntents",
            dependencies: [
                "Logger",
                "Playback",
                .product(name: "PostHog", package: "posthog-ios"),
            ],
            path: "Sources/Intents"
        ),
    ]
)
