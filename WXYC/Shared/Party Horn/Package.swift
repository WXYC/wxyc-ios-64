// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PartyHorn",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .watchOS(.v26),
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "PartyHorn",
            targets: ["PartyHorn"]),
    ],
    dependencies: [
        .package(url: "https://github.com/twostraws/Vortex.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "PartyHorn",
            dependencies: ["Vortex"],
            resources: [
                .process("Resources")
            ]),
    ]
)
