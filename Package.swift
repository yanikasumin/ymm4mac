// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YMM4Mac",
    platforms: [
        // 製品の最低対応 OS（CR-001）。Linux では無視され、テストは従来どおり通る。
        .macOS("26.0"),
    ],
    products: [
        .library(name: "YMM4Core", targets: ["YMM4Core"]),
        .library(name: "YMM4GPU", targets: ["YMM4GPU"]),
    ],
    targets: [
        // モデル層。Foundation のみに依存し、macOS 専用フレームワークは使わない。
        .target(name: "YMM4Core"),
        // GPU 実行層（Metal）。全ソースを #if os(macOS) で包み、Linux では
        // 空モジュールになる（`swift test` は従来どおり Linux で通る）。
        .target(name: "YMM4GPU", dependencies: ["YMM4Core"]),
        .testTarget(name: "YMM4CoreTests", dependencies: ["YMM4Core"]),
        // GPU 実行層のテスト。対象モジュールは Linux では空になるため、
        // テストも #if os(macOS) で囲み、実質的には Mac でのみ走る。
        .testTarget(name: "YMM4GPUTests", dependencies: ["YMM4GPU"]),
    ]
)
