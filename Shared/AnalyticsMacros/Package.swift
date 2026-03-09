// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "AnalyticsMacros",
    platforms: [
        .iOS("18.4"), .watchOS(.v11), .macOS(.v15)
    ],
    products: [
        .library(name: "AnalyticsMacros", targets: ["AnalyticsMacros"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.0.0"..<"603.0.0"),
    ],
    targets: [
        .target(
            name: "AnalyticsMacros",
            dependencies: ["AnalyticsMacrosPlugin"]
        ),
        .macro(
            name: "AnalyticsMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "AnalyticsMacrosTests",
            dependencies: [
                "AnalyticsMacrosPlugin",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
