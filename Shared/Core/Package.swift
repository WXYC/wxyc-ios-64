// swift-tools-version:6.0

import PackageDescription

//@available(iOS 18.0, tvOS 11.0, watchOS 11.0, visionOS 1.0, *)
let package = Package(
  name: "Core",
  platforms: [
    .iOS("18.0")
  ],
  products: [
    .library(name: "Core", targets: ["Core"])
  ],
  dependencies: [
    .package(name: "OpenNSFW", path: "../OpenNSFW"),
    .package(name: "Logger", path: "../Logger")
  ],
  targets: [
    .target(
      name: "Core",
      dependencies: [
        "OpenNSFW",
        "Logger"
      ],
      linkerSettings: [
//          .linkedFramework("UIKit"),
//          .linkedFramework("Foundation"),
          .linkedFramework("Dispatch"),
      ]
    )
  ]
)
