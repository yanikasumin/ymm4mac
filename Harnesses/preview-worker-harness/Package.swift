// swift-tools-version: 6.0
import PackageDescription

// R6-02 の受け入れ実測ハーネス。本物の PreviewRenderWorker
// （PreviewCore）を実プロジェクトで駆動し、要求・上書き・描画・
// 配信の計数と表示遅延を測る（第11ラウンド R11-07 の処分として、
// 概念再現ではなく実コードを通す）。
let package = Package(
    name: "preview-worker-harness",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../../Apps/DebugApp"),
    ],
    targets: [
        .executableTarget(
            name: "harness",
            dependencies: [
                .product(name: "YMM4Core", package: "YMM4Mac"),
                .product(name: "YMM4GPU", package: "YMM4Mac"),
                .product(name: "PreviewCore", package: "DebugApp"),
            ]
        ),
    ]
)
