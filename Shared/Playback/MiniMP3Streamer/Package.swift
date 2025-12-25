// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MiniMP3Streamer",
    platforms: [
        .iOS("18.4"),
        .macOS(.v15),
        .tvOS(.v18),
        // watchOS supported - MiniMP3 doesn't require AudioToolbox
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "MiniMP3Streamer",
            targets: ["MiniMP3Streamer"]),
    ],
    targets: [
        .target(
            name: "CMiniMP3",
            path: "Sources/CMiniMP3",
            publicHeadersPath: "include",
            cSettings: [
                .define("MINIMP3_FLOAT_OUTPUT"),
            ]
        ),
        .target(
            name: "MiniMP3Streamer",
            dependencies: [
                "CMiniMP3",
            ],
            path: "Sources/MiniMP3Streamer"),
        .testTarget(
            name: "MiniMP3StreamerTests",
            dependencies: ["MiniMP3Streamer"],
            path: "Tests/MiniMP3StreamerTests"),
    ]
)
