// swift-tools-version: 6.0
import PackageDescription

// TRIM55 検証用ハーネス（Mac 実機・ヘッドレス）。
// 提示開始時刻を持つ素材（開始オフセット付き・AAC のエンコーダ
// 遅延付き等）を実供給元で読み、音の開始位置（論理フレーム）と
// 全長が本家の意味論（論理 0 = 素材の提示開始時刻）と一致するか
// 実測する（Issue #55 の完了条件）。
// リポジトリルートのパッケージ（YMM4Mac）を相対パスで参照する。
let package = Package(
    name: "trim55-harness",
    platforms: [
        .macOS("26.0"),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "vdiag",
            dependencies: []
        ),
        .executableTarget(
            name: "diag",
            dependencies: []
        ),
        .executableTarget(
            name: "harness",
            dependencies: [
                .product(name: "YMM4Core", package: "YMM4Mac"),
                .product(name: "YMM4GPU", package: "YMM4Mac"),
            ]
        ),
    ]
)
