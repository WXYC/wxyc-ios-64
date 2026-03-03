// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Caching",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "Caching", targets: ["Caching"])],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "Caching",
            dependencies: ["Core", "Logger"]
        ),
        .testTarget(
            name: "CachingTests",
            dependencies: ["Caching"]
        )
    ]
)
