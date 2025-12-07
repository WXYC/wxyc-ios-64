// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Caching",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "Caching", targets: ["Caching"])],
    dependencies: [
        .package(name: "Analytics", path: "../Analytics"),
        .package(name: "Core", path: "../Core"),
        .package(name: "Logger", path: "../Logger"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.35.0")),
    ],
    targets: [
        .target(
            name: "Caching",
            dependencies: [
                "Analytics",
                "Core",
                "Logger",
                .product(name: "PostHog", package: "posthog-ios")
            ]
        ),
        .testTarget(
            name: "CachingTests",
            dependencies: ["Caching"]
        )
    ]
)

