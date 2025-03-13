// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Secrets",
    products: [
        .library(
            name: "Secrets",
            targets: ["Secrets"]
        ),
    ],
    targets: [
        .target(name: "Secrets"),
    ]
)
