// swift-tools-version: 6.0
import PackageDescription

// STREAM54 検証用ハーネス（Mac 実機・ヘッドレス）。
// 1 時間級の WAV 素材をストリーミング供給元で読み切り、常駐メモリが
// 素材長に比例して増えないことを実測する（Issue #54 の完了条件）。
// リポジトリルートのパッケージ（YMM4Mac）を相対パスで参照する。
let package = Package(
    name: "stream54-harness",
    platforms: [
        .macOS("26.0"),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "harness",
            dependencies: [
                .product(name: "YMM4Core", package: "YMM4Mac"),
                .product(name: "YMM4GPU", package: "YMM4Mac"),
            ]
        ),
    ]
)
