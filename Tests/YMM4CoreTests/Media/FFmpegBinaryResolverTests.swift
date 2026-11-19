import XCTest
@testable import YMM4Core

/// バイナリ解決層のテスト。ファイルシステムには触れず、実行可能
/// 判定を注入して探索順だけを固定する。
final class FFmpegBinaryResolverTests: XCTestCase {
    private func resolver(
        executables: Set<String>,
        bundled: [String] = ["/bundle"],
        configured: [String: String] = [:],
        development: [String] = ["/opt/homebrew/bin"],
        pathValue: String? = "/usr/bin:/bin"
    ) -> FFmpegBinaryResolver {
        FFmpegBinaryResolver(
            bundledDirectories: bundled,
            configuredPaths: configured,
            developmentDirectories: development,
            environmentPathValue: pathValue,
            isExecutable: { executables.contains($0) }
        )
    }

    func testBundledWinsOverAllOthers() {
        let resolver = resolver(
            executables: [
                "/bundle/ffmpeg", "/configured/ffmpeg",
                "/opt/homebrew/bin/ffmpeg", "/usr/bin/ffmpeg",
            ],
            configured: ["ffmpeg": "/configured/ffmpeg"]
        )
        let resolved = resolver.resolve(tool: "ffmpeg")
        XCTAssertEqual(resolved?.path, "/bundle/ffmpeg")
        XCTAssertEqual(resolved?.source, .bundled)
    }

    func testConfiguredWinsOverDevelopmentAndPath() {
        let resolver = resolver(
            executables: ["/configured/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/usr/bin/ffmpeg"],
            configured: ["ffmpeg": "/configured/ffmpeg"]
        )
        let resolved = resolver.resolve(tool: "ffmpeg")
        XCTAssertEqual(resolved?.path, "/configured/ffmpeg")
        XCTAssertEqual(resolved?.source, .configured)
    }

    func testConfiguredNonExecutableFallsThroughToDevelopment() {
        // 明示パスが実行可能でなければ「無い」ものとして次へ進む。
        let resolver = resolver(
            executables: ["/opt/homebrew/bin/ffmpeg"],
            configured: ["ffmpeg": "/missing/ffmpeg"]
        )
        let resolved = resolver.resolve(tool: "ffmpeg")
        XCTAssertEqual(resolved?.path, "/opt/homebrew/bin/ffmpeg")
        XCTAssertEqual(resolved?.source, .development)
    }

    func testDevelopmentWinsOverPath() {
        let resolver = resolver(executables: ["/opt/homebrew/bin/ffprobe", "/bin/ffprobe"])
        let resolved = resolver.resolve(tool: "ffprobe")
        XCTAssertEqual(resolved?.path, "/opt/homebrew/bin/ffprobe")
        XCTAssertEqual(resolved?.source, .development)
    }

    func testPathFallback() {
        let resolver = resolver(executables: ["/bin/ffmpeg"])
        let resolved = resolver.resolve(tool: "ffmpeg")
        XCTAssertEqual(resolved?.path, "/bin/ffmpeg")
        XCTAssertEqual(resolved?.source, .environmentPath)
    }

    func testNotFoundReturnsNil() {
        let resolver = resolver(executables: [])
        XCTAssertNil(resolver.resolve(tool: "ffmpeg"))
        let all = resolver.resolveAll()
        XCTAssertNil(all.ffmpeg)
        XCTAssertNil(all.ffprobe)
        XCTAssertFalse(all.isComplete)
    }

    func testResolveAllIsPerToolIndependent() {
        // ffmpeg だけ見つかる場合は ffprobe は nil のまま。
        let resolver = resolver(executables: ["/opt/homebrew/bin/ffmpeg"])
        let all = resolver.resolveAll()
        XCTAssertEqual(all.ffmpeg?.path, "/opt/homebrew/bin/ffmpeg")
        XCTAssertNil(all.ffprobe)
        XCTAssertFalse(all.isComplete)
    }

    func testNilPathValueSkipsPathSearch() {
        let resolver = resolver(executables: ["/bin/ffmpeg"], pathValue: nil)
        XCTAssertNil(resolver.resolve(tool: "ffmpeg"))
    }
}

// MARK: - バージョン検証

private final class FakeProcessOutputRunner: ProcessOutputRunning, @unchecked Sendable {
    var outputsByPath: [String: ProcessOutput] = [:]
    /// 起動例外を起こすパスの集合（パスごとに失敗を再現する）。
    var launchErrorPaths: Set<String> = []
    private(set) var calls: [(path: String, arguments: [String])] = []

    func run(executablePath: String, arguments: [String]) throws -> ProcessOutput {
        calls.append((executablePath, arguments))
        if launchErrorPaths.contains(executablePath) {
            throw NSError(domain: "FakeRunner", code: 2)
        }
        guard let output = outputsByPath[executablePath] else {
            throw NSError(domain: "FakeRunner", code: 1)
        }
        return output
    }
}

private func versionOutput(_ banner: String) -> ProcessOutput {
    ProcessOutput(
        terminationStatus: 0,
        standardOutput: Data((banner + "\n").utf8),
        standardError: Data()
    )
}

final class FFmpegToolchainVerifierTests: XCTestCase {
    private func resolution(
        ffmpegPath: String? = "/dev/ffmpeg", ffprobePath: String? = "/dev/ffprobe"
    ) -> FFmpegBinaryResolution {
        FFmpegBinaryResolution(
            ffmpeg: ffmpegPath.map {
                ResolvedFFmpegTool(toolName: "ffmpeg", path: $0, source: .development)
            },
            ffprobe: ffprobePath.map {
                ResolvedFFmpegTool(toolName: "ffprobe", path: $0, source: .development)
            }
        )
    }

    func testBothUsable() {
        let runner = FakeProcessOutputRunner()
        runner.outputsByPath["/dev/ffmpeg"] = versionOutput(
            "ffmpeg version 9.0.2 Copyright (c) 2000-2026 the FFmpeg developers"
        )
        runner.outputsByPath["/dev/ffprobe"] = versionOutput(
            "ffprobe version 9.0.2 Copyright (c) 2007-2026 the FFmpeg developers"
        )
        let result = FFmpegToolchainVerifier(runner: runner).verify(resolution: resolution())
        XCTAssertTrue(result.isUsable)
        XCTAssertEqual(result.ffmpeg.version?.version, "9.0.2")
        XCTAssertEqual(result.ffmpeg.version?.path, "/dev/ffmpeg")
        XCTAssertEqual(result.ffprobe.version?.version, "9.0.2")
        XCTAssertEqual(runner.calls.map(\.arguments), [["-version"], ["-version"]])
    }

    func testNotResolved() {
        let runner = FakeProcessOutputRunner()
        let result = FFmpegToolchainVerifier(runner: runner)
            .verify(resolution: resolution(ffmpegPath: nil, ffprobePath: nil))
        XCTAssertFalse(result.isUsable)
        XCTAssertEqual(result.ffmpeg.failure, .notResolved)
        XCTAssertEqual(result.ffmpeg.toolName, "ffmpeg")
        XCTAssertEqual(result.ffprobe.failure, .notResolved)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testLaunchFailure() {
        let runner = FakeProcessOutputRunner()
        runner.launchErrorPaths = ["/dev/ffmpeg"]
        runner.outputsByPath["/dev/ffprobe"] = versionOutput("ffprobe version 9.0.2")
        let result = FFmpegToolchainVerifier(runner: runner).verify(resolution: resolution())
        XCTAssertFalse(result.isUsable)
        guard case .launchFailed = result.ffmpeg.failure else {
            return XCTFail("launchFailed を期待した: \(String(describing: result.ffmpeg.failure))")
        }
        XCTAssertTrue(result.ffprobe.isUsable)
    }

    func testNonZeroExit() {
        let runner = FakeProcessOutputRunner()
        runner.outputsByPath["/dev/ffmpeg"] = ProcessOutput(
            terminationStatus: 1, standardOutput: Data(), standardError: Data()
        )
        runner.outputsByPath["/dev/ffprobe"] = versionOutput("ffprobe version 9.0.2")
        let result = FFmpegToolchainVerifier(runner: runner).verify(resolution: resolution())
        XCTAssertEqual(result.ffmpeg.failure, .nonZeroExit(1))
        XCTAssertFalse(result.isUsable)
    }

    func testUnparsableBanner() {
        let runner = FakeProcessOutputRunner()
        runner.outputsByPath["/dev/ffmpeg"] = versionOutput("some unrelated banner")
        runner.outputsByPath["/dev/ffprobe"] = versionOutput("ffprobe version 9.0.2")
        let result = FFmpegToolchainVerifier(runner: runner).verify(resolution: resolution())
        XCTAssertEqual(result.ffmpeg.failure, .unparsableVersionOutput)
    }

    func testVersionTokenParsing() {
        XCTAssertEqual(
            FFmpegToolVersion.versionToken(
                fromBannerLine: "ffmpeg version 9.0.2 Copyright (c) 2000-2026", toolName: "ffmpeg"
            ),
            "9.0.2"
        )
        XCTAssertEqual(
            FFmpegToolVersion.versionToken(
                fromBannerLine: "ffprobe version 7.1.1", toolName: "ffprobe"
            ),
            "7.1.1"
        )
        XCTAssertNil(
            FFmpegToolVersion.versionToken(
                fromBannerLine: "ffmpeg version 9.0.2", toolName: "ffprobe"
            )
        )
        XCTAssertNil(FFmpegToolVersion.versionToken(fromBannerLine: "", toolName: "ffmpeg"))
    }
}
