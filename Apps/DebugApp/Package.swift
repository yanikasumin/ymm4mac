// swift-tools-version: 6.0
import PackageDescription

// YMM4Core の検証用デバッグアプリ。製品 UI ではなく、読み込み・評価の
// ステップ実行と目視確認のための殻。最低対応 OS は製品と同じ macOS 26.0（CR-001）。
let package = Package(
    name: "YMM4MacDebug",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(name: "PreviewCore", targets: ["PreviewCore"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        // プレビュー合成のセッションと描画ワーカー。実行ファイルから
        // 分離し、順序制御を単体テストで検証できるようにした（R6-02、
        // 第11ラウンド R11-01 の処分）。
        .target(
            name: "PreviewCore",
            dependencies: [
                .product(name: "YMM4Core", package: "YMM4Mac"),
                .product(name: "YMM4GPU", package: "YMM4Mac"),
            ]
        ),
        .executableTarget(
            name: "YMM4MacDebug",
            dependencies: [
                "PreviewCore",
                .product(name: "YMM4Core", package: "YMM4Mac"),
                .product(name: "YMM4GPU", package: "YMM4Mac"),
            ]
        ),
        .testTarget(
            name: "PreviewCoreTests",
            dependencies: [
                "PreviewCore",
                .product(name: "YMM4Core", package: "YMM4Mac"),
            ]
        ),
    ]
)
