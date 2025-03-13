// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Analytics",
    platforms: [
        .iOS(.v18), .watchOS(.v11), .macOS(.v10_14)
    ],
    products: [
        .library(name: "Analytics", targets: ["Analytics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.20.0")),
    ],
    targets: [
        .target(
            name: "Analytics",
            dependencies: [
                .product(name: "PostHog", package: "posthog-ios")
            ]
        ),
//        .testTarget(
//            name: "AnalyticsTests",
//            dependencies: [
//                "Analytics",
//                .product(name: "PostHog", package: "posthog-ios")
//            ]
//        ),
    ]
)
