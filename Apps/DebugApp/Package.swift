// swift-tools-version: 6.0
import PackageDescription

// YMM4Core の検証用デバッグアプリ。製品 UI ではなく、読み込み・評価の
// ステップ実行と目視確認のための殻。最低対応 OS は製品と同じ macOS 26.0（CR-001）。
let package = Package(
    name: "YMM4MacDebug",
    platforms: [
        .macOS("26.0"),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "YMM4MacDebug",
            dependencies: [
                .product(name: "YMM4Core", package: "YMM4Mac"),
                .product(name: "YMM4GPU", package: "YMM4Mac"),
            ]
        ),
    ]
)
