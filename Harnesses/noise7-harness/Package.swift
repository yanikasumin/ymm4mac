// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "noise7-harness",
    platforms: [.macOS("26.0")],
    dependencies: [
        // チェックアウト先のフォルダ名に依存しないよう
        // パッケージ名を明示する。
        .package(name: "YMM4Mac", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "harness",
            dependencies: [
                .product(name: "YMM4Core", package: "YMM4Mac"),
                .product(name: "YMM4GPU", package: "YMM4Mac"),
            ],
            path: "Sources/harness"
        )
    ]
)
