// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Concerts",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "Concerts", targets: ["Concerts"]),
        .library(name: "ConcertsTesting", targets: ["ConcertsTesting"]),
    ],
    dependencies: [
        .package(name: "Core", path: "../Core"),
        .package(name: "Logger", path: "../Logger"),
    ],
    targets: [
        .target(
            name: "Concerts",
            dependencies: ["Core", "Logger"]
        ),
        .target(
            name: "ConcertsTesting",
            dependencies: ["Concerts"]
        ),
        .testTarget(
            name: "ConcertsTests",
            dependencies: [
                "Concerts",
                "ConcertsTesting",
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)
