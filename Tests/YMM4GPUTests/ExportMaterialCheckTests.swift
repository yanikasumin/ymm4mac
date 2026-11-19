#if os(macOS)
import XCTest
import YMM4Core
import YMM4GPU

/// 書き出しの素材失敗判定（Issue #70 段階4）。
///
/// キー収集と種別仕分けは純粋に、書き出しの失敗扱いは実バイナリ
/// （ffmpeg）と実 Metal で固定する。必要素材が失敗状態なら
/// 書き出しは失敗として終わり、黙って素材抜けの動画を作らない。
final class ExportMaterialCheckTests: XCTestCase {
    private var directory: URL!
    private var resolution: FFmpegBinaryResolution!

    override func setUpWithError() throws {
        resolution = FFmpegBinaryResolver().resolveAll()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportMaterialCheckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeTimeline(items: [BaseItem]) -> Timeline {
        let timeline = Timeline()
        timeline.videoInfo = VideoInfo(fps: 30, hz: 48_000, width: 320, height: 180)
        timeline.items = items
        timeline.refreshTimelineLengthAndMaxLayer()
        return timeline
    }

    private func failure(
        _ kind: MediaAvailabilityFailureKind
    ) -> MediaAvailabilityFailure {
        MediaAvailabilityFailure(kind: kind, detail: "test", occurredAt: Date())
    }

    // MARK: - キー収集と仕分け（純粋）

    /// 対象タイムラインとシーン経由のタイムラインから、台帳対象の
    /// 素材だけを解決済みパスで集め、重複を除く。
    func testRequiredMaterialKeysCollectsAcrossScenes() {
        let video = VideoItem()
        video.filePath = "movie.mkv"
        let sameVideo = VideoItem()
        sameVideo.filePath = "movie.mkv"
        let audio = AudioItem()
        audio.filePath = "/abs/song.mp3"
        let voiceEmpty = VoiceItem()
        voiceEmpty.hatsuon = ""
        let voice = VoiceItem()
        voice.hatsuon = "voice.wav"
        let image = ImageItem()
        image.filePath = "pic.png"

        let sceneTimeline = Timeline()
        let sceneAudio = AudioItem()
        sceneAudio.filePath = "scene-audio.flac"
        sceneTimeline.items = [sceneAudio]
        let scene = SceneItem()
        scene.sceneId = sceneTimeline.id

        let timeline = makeTimeline(items: [
            video, sameVideo, audio, voiceEmpty, voice, image, scene,
        ])
        let keys = ExportMaterialCheck.requiredMaterialKeys(
            timeline: timeline, timelines: [timeline, sceneTimeline],
            baseDirectory: directory
        )
        XCTAssertEqual(
            Set(keys.map(\.filePath)),
            [
                directory.appendingPathComponent("movie.mkv").path,
                "/abs/song.mp3",
                directory.appendingPathComponent("voice.wav").path,
                directory.appendingPathComponent("scene-audio.flac").path,
            ]
        )
    }

    /// 失敗の仕分け: 途中失敗だけが警告側、それ以外は中止側。
    /// 未試行・読み込み中・利用可は数えない。
    func testEvaluateSplitsBlockingAndMidStream() {
        let registry = MediaAvailabilityRegistry()
        let base = directory.path
        let notFound = MediaMaterialKey(filePath: "\(base)/a.mkv")
        let decodeFailed = MediaMaterialKey(filePath: "\(base)/b.mkv")
        let midStream = MediaMaterialKey(filePath: "\(base)/c.mkv")
        let available = MediaMaterialKey(filePath: "\(base)/d.mkv")
        let loading = MediaMaterialKey(filePath: "\(base)/e.mkv")
        let untouched = MediaMaterialKey(filePath: "\(base)/f.mkv")
        registry.markFailed(for: notFound, failure: failure(.fileNotFound))
        registry.markFailed(
            for: decodeFailed, failure: failure(.unsupportedOrDecodeFailed)
        )
        registry.markFailed(for: midStream, failure: failure(.midStreamFailure))
        registry.markAvailable(for: available)
        registry.beginLoading(for: loading)

        let evaluation = ExportMaterialCheck.evaluate(
            registry: registry,
            keys: [notFound, decodeFailed, midStream, available, loading, untouched]
        )
        XCTAssertEqual(
            Set(evaluation.blocking.map(\.filePath)),
            [notFound.filePath, decodeFailed.filePath]
        )
        XCTAssertEqual(evaluation.midStream.map(\.filePath), [midStream.filePath])
        XCTAssertTrue(
            ExportMaterialCheck.blockingMessage(evaluation.blocking)
                .contains("a.mkv")
        )
    }

    // MARK: - 実書き出し

    private func generateVideo() throws -> String {
        try XCTSkipUnless(
            resolution.isComplete,
            "ffmpeg / ffprobe が解決できない環境のため実バイナリテストを省略"
        )
        let ffmpegPath = try XCTUnwrap(resolution.ffmpeg?.path)
        let outputPath = directory.appendingPathComponent("clip.mp4").path
        let result = try FoundationProcessOutputRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-v", "error", "-y", "-f", "lavfi",
                "-i", "testsrc2=size=320x180:rate=30:duration=1",
                "-c:v", "libx264", "-crf", "18", "-preset", "veryfast",
                "-pix_fmt", "yuv420p", outputPath,
            ]
        )
        XCTAssertEqual(result.terminationStatus, 0, result.standardErrorText)
        return outputPath
    }

    private func makeExporter(
        timeline: Timeline, support: FFmpegMediaSupport
    ) throws -> TimelineExporter {
        do {
            return try TimelineExporter(
                timeline: timeline, timelines: [timeline],
                baseDirectory: directory, mediaSupport: support
            )
        } catch let error as MetalInitializationError {
            throw XCTSkip("Metal を初期化できない環境のため省略: \(error.userMessage)")
        }
    }

    private func makeExportTimeline(videoPath: String) -> Timeline {
        let video = VideoItem()
        video.filePath = videoPath
        video.frame = 0
        video.length = 15
        return makeTimeline(items: [video])
    }

    /// 事前判定: 必要素材が失敗状態なら、writer を作らずに
    /// 書き出しが失敗として終わり、成果物も生じない。
    func testExportFailsBeforeStartWhenRequiredMaterialFailed() throws {
        let videoPath = try generateVideo()
        let support = FFmpegMediaSupport()
        support.registry.markFailed(
            for: MediaMaterialKey(filePath: videoPath),
            failure: failure(.unsupportedOrDecodeFailed)
        )
        let exporter = try makeExporter(
            timeline: makeExportTimeline(videoPath: videoPath), support: support
        )
        XCTAssertTrue(exporter.mediaSupport === support)
        let outputPath = directory.appendingPathComponent("out.mp4").path
        let outcome = try exporter.run(
            outputPath: outputPath,
            ffmpegPath: try XCTUnwrap(resolution.ffmpeg?.path)
        )
        XCTAssertEqual(outcome.completion, .failed)
        XCTAssertEqual(outcome.framesWritten, 0)
        XCTAssertFalse(outcome.outputProduced)
        XCTAssertTrue(
            outcome.error?.message.contains("clip.mp4") ?? false,
            outcome.error?.message ?? "no error"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputPath))
        exporter.dispose()
    }

    /// 事後判定: 書き出し中に失敗が判明した素材があれば、完了した
    /// 書き出しも失敗として扱う。
    func testExportFailsWhenMaterialFailsDuringExport() throws {
        let videoPath = try generateVideo()
        let support = FFmpegMediaSupport()
        let exporter = try makeExporter(
            timeline: makeExportTimeline(videoPath: videoPath), support: support
        )
        let outputPath = directory.appendingPathComponent("out.mp4").path
        var marked = false
        let outcome = try exporter.run(
            outputPath: outputPath,
            ffmpegPath: try XCTUnwrap(resolution.ffmpeg?.path),
            onProgress: { _, _ in
                if !marked {
                    marked = true
                    support.registry.markFailed(
                        for: MediaMaterialKey(filePath: videoPath),
                        failure: self.failure(.unsupportedOrDecodeFailed)
                    )
                }
            }
        )
        XCTAssertTrue(marked)
        XCTAssertEqual(outcome.completion, .failed)
        XCTAssertNotNil(outcome.error)
        exporter.dispose()
    }

    /// 途中失敗は書き出しを止めず、警告として残す。
    func testExportCompletesWithWarningOnMidStreamFailure() throws {
        let videoPath = try generateVideo()
        let support = FFmpegMediaSupport()
        let exporter = try makeExporter(
            timeline: makeExportTimeline(videoPath: videoPath), support: support
        )
        let outputPath = directory.appendingPathComponent("out.mp4").path
        var marked = false
        let outcome = try exporter.run(
            outputPath: outputPath,
            ffmpegPath: try XCTUnwrap(resolution.ffmpeg?.path),
            onProgress: { _, _ in
                if !marked {
                    marked = true
                    support.registry.markFailed(
                        for: MediaMaterialKey(filePath: videoPath),
                        failure: self.failure(.midStreamFailure)
                    )
                }
            }
        )
        XCTAssertTrue(marked)
        XCTAssertEqual(outcome.completion, .completed)
        XCTAssertNil(outcome.error)
        XCTAssertNotNil(outcome.warning)
        exporter.dispose()
    }
}
#endif
