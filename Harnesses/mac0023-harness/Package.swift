// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac0023-harness",
    platforms: [.macOS("26.0")],
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
