// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SemanticIndex",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "SemanticIndex", targets: ["SemanticIndex"])],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "Caching", path: "../Caching"),
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "SemanticIndex",
            dependencies: ["Core", "Caching", "Logger"]
        ),
        .testTarget(
            name: "SemanticIndexTests",
            dependencies: ["SemanticIndex", "Caching"]
        )
    ]
)
