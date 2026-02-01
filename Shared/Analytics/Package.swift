// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

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
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.0.0"..<"603.0.0"),
    ],
    targets: [
        .macro(
            name: "AnalyticsMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Analytics",
            dependencies: [
                "AnalyticsMacros",
                "Secrets",
                .product(name: "PostHog", package: "posthog-ios"),
            ]
        ),
        .target(
            name: "AnalyticsTesting",
            dependencies: ["Analytics"]
        ),
        .testTarget(
            name: "AnalyticsTests",
            dependencies: ["Analytics"]
        ),
        .testTarget(
            name: "AnalyticsMacrosTests",
            dependencies: [
                "AnalyticsMacros",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
