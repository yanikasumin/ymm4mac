// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YMM4Mac",
    products: [
        .library(name: "YMM4Core", targets: ["YMM4Core"]),
    ],
    targets: [
        // モデル層。Foundation のみに依存し、macOS 専用フレームワークは使わない。
        .target(name: "YMM4Core"),
        .testTarget(name: "YMM4CoreTests", dependencies: ["YMM4Core"]),
    ]
)
