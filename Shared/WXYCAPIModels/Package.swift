// swift-tools-version:6.2
import PackageDescription
let package = Package(
    name: "WXYCAPIModels",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "WXYCAPIModels", targets: ["WXYCAPIModels"])],
    targets: [.target(name: "WXYCAPIModels", path: "Sources/WXYCAPIModels")]
)
