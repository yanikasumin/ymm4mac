import XCTest
@testable import YMM4Core

/// 実バイナリ依存のテスト（分離・明示）。
///
/// 実物の ffmpeg / ffprobe が解決できる環境でのみ実行し、
/// 無い環境では XCTSkip で明示的に飛ばす。フィクスチャ中心の
/// 通常テスト（FFmpegBinaryResolverTests / FFmpegProbeTests）とは
/// 別ファイルに分離してある。
final class FFmpegRealBinaryTests: XCTestCase {
    private func resolvedToolchain() throws -> FFmpegBinaryResolution {
        let resolution = FFmpegBinaryResolver().resolveAll()
        try XCTSkipUnless(
            resolution.isComplete,
            "ffmpeg / ffprobe が解決できない環境のため実バイナリテストを省略"
        )
        return resolution
    }

    func testRealToolchainVerifies() throws {
        let resolution = try resolvedToolchain()
        let verification = FFmpegToolchainVerifier().verify(resolution: resolution)
        XCTAssertTrue(verification.isUsable, "検証結果: \(verification)")
        XCTAssertFalse(verification.ffmpeg.version?.version.isEmpty ?? true)
        XCTAssertFalse(verification.ffprobe.version?.version.isEmpty ?? true)
    }

    func testRealProbeOfGeneratedWav() throws {
        let resolution = try resolvedToolchain()
        let ffmpegPath = try XCTUnwrap(resolution.ffmpeg?.path)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFmpegRealBinaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavPath = directory.appendingPathComponent("tone.wav").path

        // 48kHz ステレオ・1秒の無音 WAV を実 ffmpeg で生成する。
        let generation = try FoundationProcessOutputRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
                "-t", "1", "-y", wavPath,
            ]
        )
        XCTAssertEqual(generation.terminationStatus, 0, generation.standardErrorText)

        let result = try FFmpegProber().probe(path: wavPath, resolution: resolution)
        XCTAssertEqual(result.formatName, "wav")
        XCTAssertEqual(result.duration, TimeSpanValue(seconds: 1.0))
        let audio = try XCTUnwrap(result.primaryAudioStream)
        XCTAssertEqual(audio.sampleRate, 48000)
        XCTAssertEqual(audio.channels, 2)
    }
}
