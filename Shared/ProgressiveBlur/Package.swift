// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ProgressiveBlur",
  platforms: [
    .iOS("18.4"),
    .watchOS(.v11),
    .macOS(.v15)
  ],
  products: [
    .library(
      name: "ProgressiveBlur",
      targets: ["ProgressiveBlur"]
    )
  ],
  targets: [
    .target(
      name: "ProgressiveBlur",
      resources: [.process("ProgressiveBlur.metal")]
    )
  ]
)
