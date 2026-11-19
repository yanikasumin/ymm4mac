import XCTest
@testable import YMM4Core

/// FFmpeg 音声供給の実バイナリテスト（Issue #70 段階3）。
///
/// 実物の ffmpeg / ffprobe が無い環境では XCTSkip。素材はテスト内で
/// 生成する: 48kHz・3秒・ステレオの WAV（インパルスをフレーム
/// 72000 と 140000 に配置）を各形式へ符号化し、供給経由の読み取りで
/// 「インパルス位置のズレ0サンプル・総フレーム数一致」（段階2前
/// 実測の音声14ケースと同じ意味論）を固定する。
final class FFmpegAudioRealBinaryTests: XCTestCase {
    private let sampleRate = 48000
    private let totalFrames = 144000
    private let firstImpulse = 72000
    private let secondImpulse = 140000

    // MARK: - 素材生成

    /// 16bit ステレオ WAV を書く。impulses はフレーム位置の列。
    private func writeWAV(
        to url: URL, impulses: [Int], totalFrames: Int
    ) throws {
        var data = Data()
        let byteCount = totalFrames * 4
        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [UInt8]("RIFF".utf8))
        appendUInt32(UInt32(36 + byteCount))
        data.append(contentsOf: [UInt8]("WAVE".utf8))
        data.append(contentsOf: [UInt8]("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(2)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 4))
        appendUInt16(4)
        appendUInt16(16)
        data.append(contentsOf: [UInt8]("data".utf8))
        appendUInt32(UInt32(byteCount))
        let impulseSet = Set(impulses)
        for frame in 0..<totalFrames {
            let value: Int16 = impulseSet.contains(frame) ? 29000 : 0
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        try data.write(to: url)
    }

    private func runFFmpeg(
        _ ffmpegPath: String, _ arguments: [String]
    ) throws {
        let result = try FoundationProcessOutputRunner().run(
            executablePath: ffmpegPath, arguments: arguments
        )
        XCTAssertEqual(
            result.terminationStatus, 0,
            "ffmpeg 失敗: \(result.standardErrorText)"
        )
    }

    private struct Fixture {
        var directory: URL
        var factory: FFmpegPCMProviderFactory
        var registry: MediaAvailabilityRegistry
    }

    private func makeFixture() throws -> Fixture {
        let resolution = FFmpegBinaryResolver().resolveAll()
        try XCTSkipUnless(
            resolution.isComplete,
            "ffmpeg / ffprobe が解決できない環境のため実バイナリテストを省略"
        )
        let ffmpegPath = try XCTUnwrap(resolution.ffmpeg?.path)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFmpegAudioRealBinaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let wav = directory.appendingPathComponent("impulse.wav")
        try writeWAV(
            to: wav, impulses: [firstImpulse, secondImpulse],
            totalFrames: totalFrames
        )
        let wavB = directory.appendingPathComponent("impulse_b.wav")
        try writeWAV(to: wavB, impulses: [96000], totalFrames: totalFrames)

        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-i", wav.path, "-c:a", "aac",
            directory.appendingPathComponent("impulse.m4a").path,
        ])
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-i", wav.path, "-c:a", "libopus",
            directory.appendingPathComponent("impulse.ogg").path,
        ])
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-i", wav.path, "-c:a", "libmp3lame",
            directory.appendingPathComponent("impulse.mp3").path,
        ])
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-i", wav.path, "-c:a", "flac",
            directory.appendingPathComponent("impulse.mkv").path,
        ])
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y",
            "-i", wav.path, "-i", wavB.path,
            "-map", "0:a", "-map", "1:a", "-c:a", "flac",
            directory.appendingPathComponent("dual.mkv").path,
        ])
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-i", wav.path, "-c:a", "aac",
            "-output_ts_offset", "3.5",
            directory.appendingPathComponent("offset.ts").path,
        ])

        let registry = MediaAvailabilityRegistry()
        let factory = FFmpegPCMProviderFactory(
            baseDirectory: directory, resolution: resolution, registry: registry
        )
        return Fixture(directory: directory, factory: factory, registry: registry)
    }

    // MARK: - 読み取りヘルパ

    /// 供給を終端まで読み切り、左チャンネルの要素列を返す。
    private func readAll(_ provider: PCMProvider) -> [Float] {
        var result: [Float] = []
        var buffer = [Float](repeating: 0, count: 8192)
        while true {
            let produced = provider.read(
                into: &buffer, offset: 0, count: buffer.count
            )
            if produced == 0 { break }
            for frame in 0..<(produced / 2) {
                result.append(buffer[frame * 2])
            }
            if produced < buffer.count { break }
        }
        return result
    }

    /// 期待位置の前後ウィンドウ内での argmax。損失符号化では
    /// インパルスの再現振幅が位置ごとにわずかに異なるため、全体の
    /// argmax ではなく「期待位置の近傍でピークが立つか」で位置の
    /// 正確さを見る（実測ハーネスと同じ考え方）。
    private func argmaxNear(_ samples: [Float], center: Int, radius: Int = 2000) -> Int {
        let lower = max(0, center - radius)
        let upper = min(samples.count, center + radius)
        var best = lower
        var bestValue: Float = 0
        for index in lower..<upper where abs(samples[index]) > bestValue {
            bestValue = abs(samples[index])
            best = index
        }
        return best
    }

    // MARK: - 形式ごとの精度

    private func assertImpulseAccuracy(fileName: String) throws {
        let fixture = try makeFixture()
        let provider = try XCTUnwrap(
            fixture.factory.createProvider(filePath: fileName, audioTrackIndex: 0),
            "\(fileName) の供給が作れませんでした"
        )
        XCTAssertEqual(provider.hz, sampleRate)
        let samples = readAll(provider)
        XCTAssertEqual(samples.count, totalFrames, "\(fileName) の総フレーム数")
        XCTAssertEqual(
            argmaxNear(samples, center: firstImpulse), firstImpulse,
            "\(fileName) のインパルス位置"
        )
        XCTAssertEqual(
            argmaxNear(samples, center: secondImpulse), secondImpulse,
            "\(fileName) の第2インパルス位置"
        )
        // 終端後の読み取りは 0。
        var buffer = [Float](repeating: 0, count: 16)
        XCTAssertEqual(provider.read(into: &buffer, offset: 0, count: 16), 0)
    }

    func testM4AImpulseAccuracy() throws { try assertImpulseAccuracy(fileName: "impulse.m4a") }
    func testOggImpulseAccuracy() throws { try assertImpulseAccuracy(fileName: "impulse.ogg") }
    func testMP3ImpulseAccuracy() throws { try assertImpulseAccuracy(fileName: "impulse.mp3") }
    func testMKVImpulseAccuracy() throws { try assertImpulseAccuracy(fileName: "impulse.mkv") }

    // MARK: - シーク後の位置

    func testSeekThenReadPosition() throws {
        let fixture = try makeFixture()
        let provider = try XCTUnwrap(
            fixture.factory.createProvider(filePath: "impulse.m4a", audioTrackIndex: 0)
        )
        provider.seek(toTime: TimeSpanValue(seconds: 1.0))
        var collected: [Float] = []
        var buffer = [Float](repeating: 0, count: 8192)
        while collected.count < sampleRate {
            let produced = provider.read(
                into: &buffer, offset: 0, count: buffer.count
            )
            if produced == 0 { break }
            let frames = min(produced / 2, sampleRate - collected.count)
            for frame in 0..<frames {
                collected.append(buffer[frame * 2])
            }
        }
        XCTAssertEqual(collected.count, sampleRate)
        XCTAssertEqual(argmaxNear(collected, center: firstImpulse - sampleRate), firstImpulse - sampleRate)
    }

    // MARK: - 複数トラック

    func testSecondAudioTrackSelection() throws {
        let fixture = try makeFixture()
        let provider = try XCTUnwrap(
            fixture.factory.createProvider(filePath: "dual.mkv", audioTrackIndex: 1)
        )
        let samples = readAll(provider)
        XCTAssertEqual(samples.count, totalFrames)
        XCTAssertEqual(argmaxNear(samples, center: 96000), 96000)
    }

    // MARK: - TS（開始オフセット＋出力シーク方式）

    func testTSWithStartOffset() throws {
        let fixture = try makeFixture()
        let provider = try XCTUnwrap(
            fixture.factory.createProvider(filePath: "offset.ts", audioTrackIndex: 0)
        )
        let samples = readAll(provider)
        // TS には AAC のプライミングを打ち消す編集リストが無いため、
        // ファイル自体のタイムラインでインパルスは 1024 フレーム
        // 後ろにある（生成時の性質。供給はファイルの提示時刻を
        // そのまま論理位置へ写す）。総量もパディング分だけ多い。
        XCTAssertEqual(samples.count, 145408)
        XCTAssertEqual(argmaxNear(samples, center: firstImpulse + 1024), firstImpulse + 1024)

        provider.seek(toTime: TimeSpanValue(seconds: 1.0))
        var collected: [Float] = []
        var buffer = [Float](repeating: 0, count: 8192)
        while collected.count < sampleRate {
            let produced = provider.read(
                into: &buffer, offset: 0, count: buffer.count
            )
            if produced == 0 { break }
            let frames = min(produced / 2, sampleRate - collected.count)
            for frame in 0..<frames {
                collected.append(buffer[frame * 2])
            }
        }
        XCTAssertEqual(argmaxNear(collected, center: firstImpulse + 1024 - sampleRate), firstImpulse + 1024 - sampleRate)
    }
}
