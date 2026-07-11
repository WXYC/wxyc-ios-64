// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Concerts",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "Concerts", targets: ["Concerts"]),
        .library(name: "ConcertsTesting", targets: ["ConcertsTesting"]),
    ],
    targets: [
        .target(
            name: "Concerts"
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
            ]
        )
    ]
)
