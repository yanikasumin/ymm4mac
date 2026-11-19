import XCTest
@testable import YMM4Core

/// ffprobe の出力を差し替えるテスト用ランナー。
final class FakeAudioProbeRunner: ProcessOutputRunning, @unchecked Sendable {
    var output: ProcessOutput?
    var launchError: Error?

    func run(executablePath: String, arguments: [String]) throws -> ProcessOutput {
        if let launchError { throw launchError }
        guard let output else {
            throw NSError(domain: "FakeAudioProbeRunner", code: 1)
        }
        return output
    }
}

/// FFmpeg 音声 Factory のテスト（Issue #70 段階3）。
/// プローブは JSON を差し替え、デコードプロセスはフェイクで、
/// 選択・失敗記録・試行の意味論だけを見る（実バイナリは別ファイル）。
final class FFmpegPCMProviderFactoryTests: XCTestCase {
    private let twoTrackJSON = """
        {
          "streams": [
            {"index": 0, "codec_type": "video", "codec_name": "h264",
             "width": 320, "height": 180, "start_time": "0.000000",
             "duration": "2.000000"},
            {"index": 1, "codec_type": "audio", "codec_name": "aac",
             "sample_rate": "48000", "channels": 2,
             "start_time": "0.000000", "duration": "2.000000"},
            {"index": 2, "codec_type": "audio", "codec_name": "flac",
             "sample_rate": "22050", "channels": 1,
             "start_time": "0.000000", "duration": "2.000000"}
          ],
          "format": {"format_name": "matroska,webm",
                     "start_time": "0.000000", "duration": "2.000000"}
        }
        """

    private let videoOnlyJSON = """
        {
          "streams": [
            {"index": 0, "codec_type": "video", "codec_name": "h264",
             "width": 320, "height": 180, "start_time": "0.000000",
             "duration": "2.000000"}
          ],
          "format": {"format_name": "mov,mp4,m4a,3gp,3g2,mj2",
                     "start_time": "0.000000", "duration": "2.000000"}
        }
        """

    private func makeResolution(complete: Bool = true) -> FFmpegBinaryResolution {
        guard complete else {
            return FFmpegBinaryResolution(ffmpeg: nil, ffprobe: nil)
        }
        return FFmpegBinaryResolution(
            ffmpeg: ResolvedFFmpegTool(
                toolName: "ffmpeg", path: "/dev/ffmpeg", source: .development
            ),
            ffprobe: ResolvedFFmpegTool(
                toolName: "ffprobe", path: "/dev/ffprobe", source: .development
            )
        )
    }

    /// 指定レートで 1024 フレームずつのチャンク列（絶対開始 0）。
    private func makeChunks(sampleRate: Int, count: Int = 200) -> [FakeAudioProcess.ChunkSpec] {
        (0..<count).map { index in
            FakeAudioProcess.ChunkSpec(
                startSeconds: Double(index * 1024) / Double(sampleRate),
                samples: [Float](repeating: 0.25, count: 1024 * 2)
            )
        }
    }

    private func makeFactory(
        probeJSON: String?,
        registry: MediaAvailabilityRegistry?,
        processFactory: FakeAudioProcessFactory,
        fileExists: Bool = true,
        probeLaunchError: Error? = nil
    ) -> FFmpegPCMProviderFactory {
        let runner = FakeAudioProbeRunner()
        if let probeJSON {
            runner.output = ProcessOutput(
                terminationStatus: 0,
                standardOutput: Data(probeJSON.utf8),
                standardError: Data()
            )
        }
        runner.launchError = probeLaunchError
        return FFmpegPCMProviderFactory(
            baseDirectory: URL(fileURLWithPath: "/proj"),
            resolution: makeResolution(),
            registry: registry,
            prober: FFmpegProber(runner: runner),
            processFactory: processFactory,
            fileExists: { _ in fileExists }
        )
    }

    private func failedKind(
        _ registry: MediaAvailabilityRegistry, path: String = "/proj/a.mkv"
    ) -> MediaAvailabilityFailureKind? {
        registry.state(for: MediaMaterialKey(filePath: path)).failure?.kind
    }

    // MARK: - トラック選択

    func testSelectsRequestedTrack() {
        let processFactory = FakeAudioProcessFactory()
        processFactory.allChunks = makeChunks(sampleRate: 22050)
        let factory = makeFactory(
            probeJSON: twoTrackJSON, registry: nil, processFactory: processFactory
        )
        let provider = factory.createProvider(filePath: "a.mkv", audioTrackIndex: 1)
        XCTAssertEqual(provider?.hz, 22050)
        XCTAssertEqual(processFactory.requests.first?.audioStreamIndex, 2)
    }

    func testFirstTrackByDefault() {
        let processFactory = FakeAudioProcessFactory()
        processFactory.allChunks = makeChunks(sampleRate: 48000)
        let factory = makeFactory(
            probeJSON: twoTrackJSON, registry: nil, processFactory: processFactory
        )
        let provider = factory.createProvider(filePath: "a.mkv", audioTrackIndex: 0)
        XCTAssertEqual(provider?.hz, 48000)
        XCTAssertEqual(processFactory.requests.first?.audioStreamIndex, 1)
    }

    func testOutOfRangeTrackFallsBackToFirst() {
        let processFactory = FakeAudioProcessFactory()
        processFactory.allChunks = makeChunks(sampleRate: 48000)
        let factory = makeFactory(
            probeJSON: twoTrackJSON, registry: nil, processFactory: processFactory
        )
        let provider = factory.createProvider(filePath: "a.mkv", audioTrackIndex: 9)
        XCTAssertEqual(provider?.hz, 48000)
        XCTAssertEqual(processFactory.requests.first?.audioStreamIndex, 1)
    }

    func testMarksAvailableAfterSuccessfulTrial() {
        let processFactory = FakeAudioProcessFactory()
        processFactory.allChunks = makeChunks(sampleRate: 48000)
        let registry = MediaAvailabilityRegistry()
        let factory = makeFactory(
            probeJSON: twoTrackJSON, registry: registry, processFactory: processFactory
        )
        XCTAssertNotNil(factory.createProvider(filePath: "a.mkv", audioTrackIndex: 0))
        XCTAssertEqual(
            registry.state(for: MediaMaterialKey(filePath: "/proj/a.mkv")),
            .available
        )
    }

    // MARK: - 失敗経路

    func testMissingFileRecordsFileNotFound() {
        let processFactory = FakeAudioProcessFactory()
        let registry = MediaAvailabilityRegistry()
        let factory = makeFactory(
            probeJSON: twoTrackJSON, registry: registry,
            processFactory: processFactory, fileExists: false
        )
        XCTAssertNil(factory.createProvider(filePath: "a.mkv", audioTrackIndex: 0))
        XCTAssertEqual(failedKind(registry), .fileNotFound)
    }

    func testMissingFFmpegRecordsUnavailable() {
        let processFactory = FakeAudioProcessFactory()
        let registry = MediaAvailabilityRegistry()
        let runner = FakeAudioProbeRunner()
        let factory = FFmpegPCMProviderFactory(
            baseDirectory: URL(fileURLWithPath: "/proj"),
            resolution: makeResolution(complete: false),
            registry: registry,
            prober: FFmpegProber(runner: runner),
            processFactory: processFactory,
            fileExists: { _ in true }
        )
        XCTAssertNil(factory.createProvider(filePath: "a.mkv", audioTrackIndex: 0))
        XCTAssertEqual(failedKind(registry), .ffmpegUnavailable)
    }

    func testProbeFailureRecordsUnsupported() {
        let processFactory = FakeAudioProcessFactory()
        let registry = MediaAvailabilityRegistry()
        let factory = makeFactory(
            probeJSON: nil, registry: registry, processFactory: processFactory,
            probeLaunchError: NSError(domain: "test", code: 1)
        )
        XCTAssertNil(factory.createProvider(filePath: "a.mkv", audioTrackIndex: 0))
        XCTAssertEqual(failedKind(registry), .unsupportedOrDecodeFailed)
    }

    /// 音声ストリームの不在は復号の失敗ではない（段階4で是正）。
    /// 映像だけの素材は正当な素材であり、台帳が映像・音声の両
    /// 経路で共有されるため、失敗を記録すると映像側の利用可否
    /// （UI の警告・書き出しの失敗判定）まで汚染される。
    /// AVFoundation 側もトラックが無ければ記録しない。
    func testNoAudioStreamsReturnsNilWithoutRecordingFailure() {
        let processFactory = FakeAudioProcessFactory()
        let registry = MediaAvailabilityRegistry()
        let factory = makeFactory(
            probeJSON: videoOnlyJSON, registry: registry, processFactory: processFactory
        )
        XCTAssertNil(factory.createProvider(filePath: "a.mkv", audioTrackIndex: 0))
        XCTAssertNil(failedKind(registry))
        XCTAssertEqual(
            registry.state(for: MediaMaterialKey(filePath: "/proj/a.mkv")),
            .notAttempted
        )
    }

    func testTrialFailureReturnsNil() {
        let processFactory = FakeAudioProcessFactory()
        processFactory.allChunks = []
        let registry = MediaAvailabilityRegistry()
        let factory = makeFactory(
            probeJSON: twoTrackJSON, registry: registry, processFactory: processFactory
        )
        XCTAssertNil(factory.createProvider(filePath: "a.mkv", audioTrackIndex: 0))
        XCTAssertEqual(failedKind(registry), .unsupportedOrDecodeFailed)
    }

    func testRelativePathResolvedAgainstBaseDirectory() {
        let processFactory = FakeAudioProcessFactory()
        processFactory.allChunks = makeChunks(sampleRate: 48000)
        let registry = MediaAvailabilityRegistry()
        let factory = makeFactory(
            probeJSON: twoTrackJSON, registry: registry, processFactory: processFactory
        )
        XCTAssertNotNil(factory.createProvider(filePath: "sub/a.mkv", audioTrackIndex: 0))
        XCTAssertEqual(
            registry.state(for: MediaMaterialKey(filePath: "/proj/sub/a.mkv")),
            .available
        )
    }
}
