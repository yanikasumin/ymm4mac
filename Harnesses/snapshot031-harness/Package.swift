// swift-tools-version: 6.0
import PackageDescription

// FE-R1-031 の計測専用ハーネス。プレビュー用スナップショット生成
// （Project.makeExportSnapshot）の内訳と所要時間、ワーカーへの
// モデル差し替え往復を、製品コードを変更せずに実測する。
// 計測仕様は docs/IMPLEMENTATION_LOG.md の FE-R1-031 節を参照。
let package = Package(
    name: "snapshot031-harness",
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
