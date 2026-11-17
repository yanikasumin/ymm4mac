// swift-tools-version: 6.0
import PackageDescription

// MAC-0026 検証用ハーネス（Mac 実機・ヘッドレス）。
// リポジトリルートのパッケージ（YMM4Mac）を相対パスで参照する。
let package = Package(
    name: "mac0026-harness",
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
