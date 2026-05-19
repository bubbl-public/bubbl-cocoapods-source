// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BubblSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "BubblSDK", targets: ["BubblSDK"])
    ],
    targets: [
        .target(
            name: "BubblSDK",
            path: "Sources/BubblSDK",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(name: "BubblSDKTests", dependencies: ["BubblSDK"], path: "Tests/BubblSDKTests")
    ]
)
