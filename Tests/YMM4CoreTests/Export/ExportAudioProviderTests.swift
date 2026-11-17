import XCTest

@testable import YMM4Core

/// MAC-0026: 書き出し音声供給（TimelineExportAudioProvider）の検証。
/// 実ミックス（TimelineAudioMixer）→ ラウドネス解析 → DynamicsProcessor
/// の接続と、フレーム単位のサンプル件数（累積式）を固定する。
final class ExportAudioProviderTests: XCTestCase {

    private func makeTimeline(
        items: [BaseItem], fps: Int = 30, hz: Int = 48_000
    ) -> Timeline {
        let timeline = Timeline()
        var info = VideoInfo()
        info.fps = fps
        info.hz = hz
        timeline.videoInfo = info
        timeline.items = items
        timeline.refreshTimelineLengthAndMaxLayer()
        return timeline
    }

    private func makeProvider(
        value: Float, itemLength: Int = 30, hz: Int = 48_000, fps: Int = 30,
        providerFrames: Int
    ) -> TimelineExportAudioProvider {
        let factory = MapPCMProviderFactory()
        factory.providers["a"] = constantProvider(
            value, frames: providerFrames, hz: hz
        )
        let timeline = makeTimeline(
            items: [makeAudioItem(filePath: "a", length: itemLength)],
            fps: fps, hz: hz
        )
        return TimelineExportAudioProvider(
            timeline: timeline,
            factory: AudioSourceFactory(providerFactory: factory)
        )
    }

    // MARK: - 素通し（ピークが 0 dBFS 以下なら倍率は両方とも 1）

    func testPassthroughWhenPeakBelowZeroDb() throws {
        let provider = makeProvider(value: 0.5, providerFrames: 48_000)
        XCTAssertEqual(provider.analysisResult.volumeRate, 1, accuracy: 1e-6)
        XCTAssertEqual(provider.analysisResult.compressorRate, 1, accuracy: 1e-6)
        XCTAssertEqual(provider.analysisResult.peakDb, -6.02, accuracy: 0.01)

        var total = 0
        for frame in 0..<30 {
            let samples = try provider.audioSamples(forFrame: frame)
            XCTAssertEqual(samples.count, 3_200)
            total += samples.count
            if frame == 0 || frame == 15 || frame == 29 {
                for sample in samples {
                    XCTAssertEqual(sample, 0.5, accuracy: 1e-6)
                }
            }
        }
        XCTAssertEqual(total, 96_000)
    }

    // MARK: - ラウドネス経路（DownMaximumVolume がピークを 0 dBFS へ下げる）

    func testDownMaximumVolumeScalesOverPeak() throws {
        let provider = makeProvider(value: 2.0, providerFrames: 48_000)
        // ピーク +6.02 dB → 倍率 0.5（解析パスで確定する）。
        XCTAssertEqual(provider.analysisResult.volumeRate, 0.5, accuracy: 1e-3)
        XCTAssertEqual(provider.analysisResult.compressorRate, 1, accuracy: 1e-6)

        let samples = try provider.audioSamples(forFrame: 10)
        XCTAssertEqual(samples.count, 3_200)
        for sample in samples {
            XCTAssertEqual(sample, 1.0, accuracy: 1e-3)
        }
    }

    // MARK: - フレームごとの件数（累積式。Hz が FPS で割り切れない場合）

    func testSampleCountsFollowCumulativeFormula() throws {
        // 11025 Hz / 30 FPS: フレームあたり [734, 736, 734, 736, ...]。
        let provider = makeProvider(
            value: 0.25, itemLength: 90, hz: 11_025, providerFrames: 33_075
        )
        let expected = [734, 736, 734, 736]
        var total = 0
        for frame in 0..<90 {
            let samples = try provider.audioSamples(forFrame: frame)
            if frame < expected.count {
                XCTAssertEqual(samples.count, expected[frame])
            }
            total += samples.count
        }
        XCTAssertEqual(total, 66_150)
    }

    // MARK: - 連続しないフレーム指定（シーク経路）

    func testNonSequentialFrameSeeks() throws {
        let provider = makeProvider(value: 0.5, providerFrames: 48_000)
        let frameFive = try provider.audioSamples(forFrame: 5)
        XCTAssertEqual(frameFive.count, 3_200)
        for sample in frameFive {
            XCTAssertEqual(sample, 0.5, accuracy: 1e-6)
        }
        let frameZero = try provider.audioSamples(forFrame: 0)
        XCTAssertEqual(frameZero.count, 3_200)
        for sample in frameZero {
            XCTAssertEqual(sample, 0.5, accuracy: 1e-6)
        }
    }

    // MARK: - 解析の省略（EX17-05: 解析不要設定では素材を読まない）

    private final class CountingPCMProvider: PCMProvider {
        private let base: InMemoryPCMProvider
        private(set) var readCalls = 0

        init(value: Float, frames: Int, hz: Int = 48_000) {
            base = InMemoryPCMProvider(
                samples: [Float](repeating: value, count: frames * 2), hz: hz
            )
        }

        var hz: Int { base.hz }
        var duration: TimeSpanValue { base.duration }

        func seek(toTime time: TimeSpanValue) {
            base.seek(toTime: time)
        }

        func read(into buffer: inout [Float], offset: Int, count: Int) -> Int {
            readCalls += 1
            return base.read(into: &buffer, offset: offset, count: count)
        }
    }

    private func makeCountingSetup(
        loudness: LoudnessNormalizationSettings,
        compressor: CompressorSettings
    ) -> (provider: TimelineExportAudioProvider, counting: CountingPCMProvider) {
        let counting = CountingPCMProvider(value: 0.5, frames: 48_000)
        let factory = MapPCMProviderFactory()
        factory.providers["a"] = counting
        let timeline = makeTimeline(items: [makeAudioItem(filePath: "a")])
        let provider = TimelineExportAudioProvider(
            timeline: timeline,
            factory: AudioSourceFactory(providerFactory: factory),
            loudness: loudness,
            compressor: compressor
        )
        return (provider, counting)
    }

    func testNoReadsWhenLoudnessAndCompressorDisabled() throws {
        let (provider, counting) = makeCountingSetup(
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .disabled)
        )
        // 解析が省略され、初期化までに素材は一切読まれない
        XCTAssertEqual(counting.readCalls, 0)
        XCTAssertFalse(provider.analysisResult.analysisPerformed)
        XCTAssertEqual(provider.analysisResult.volumeRate, 1, accuracy: 1e-6)
        XCTAssertEqual(provider.analysisResult.compressorRate, 1, accuracy: 1e-6)
        // 書き出し側の読み取りは通常どおり行われる
        let samples = try provider.audioSamples(forFrame: 0)
        XCTAssertEqual(samples.count, 3_200)
        XCTAssertGreaterThan(counting.readCalls, 0)
    }

    func testNoReadsWhenCustomRatio() {
        let (provider, counting) = makeCountingSetup(
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .custom, ratio: 2.5)
        )
        XCTAssertEqual(counting.readCalls, 0)
        XCTAssertFalse(provider.analysisResult.analysisPerformed)
        XCTAssertEqual(provider.analysisResult.compressorRate, 2.5, accuracy: 1e-6)
        XCTAssertEqual(provider.analysisResult.volumeRate, 1, accuracy: 1e-6)
    }

    func testReadsHappenWhenAnalysisRequired() {
        // 対照: 既定設定（解析あり）では初期化の解析パスで素材が読まれる。
        // 読み取り回数を数えるフェイクが経路に介在することの確認も兼ねる
        let (provider, counting) = makeCountingSetup(
            loudness: LoudnessNormalizationSettings(),
            compressor: CompressorSettings()
        )
        XCTAssertGreaterThan(counting.readCalls, 0)
        XCTAssertTrue(provider.analysisResult.analysisPerformed)
    }

    // MARK: - セッション統合（実音声供給＋記録ライター）

    private final class CapturingWriter: VideoFileWriting {
        var supportedStreams: VideoWriterSupportedStreams { [.video, .audio] }
        var isGPUFrameSupported: Bool { false }
        var videoFrames = 0
        var audioSampleTotal = 0
        var finalizeCount = 0

        func writeVideoFrame(_ frame: ExportVideoFrameBuffer) throws {
            videoFrames += 1
        }

        func writeAudioSamples(_ samples: [Float]) throws {
            audioSampleTotal += samples.count
        }

        func finalize() throws {
            finalizeCount += 1
        }
    }

    private struct ConstantVideoProvider: VideoFrameProviding {
        func fillFrame(_ frame: Int, into buffer: ExportVideoFrameBuffer) throws {
            for index in buffer.bytes.indices { buffer.bytes[index] = 0xFF }
        }
    }

    func testSessionWithRealAudioProvider() {
        let audioProvider = makeProvider(value: 0.5, providerFrames: 48_000)
        let writer = CapturingWriter()
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: ExportSession.Configuration(
                outputPath: "unused.mp4",
                videoInfo: audioProvider.timeline.videoInfo,
                frameRange: 0..<30
            ),
            videoProvider: ConstantVideoProvider(),
            audioProvider: audioProvider
        )
        XCTAssertEqual(outcome.completion, .completed)
        XCTAssertEqual(outcome.framesWritten, 30)
        XCTAssertTrue(outcome.outputProduced)
        XCTAssertEqual(writer.videoFrames, 30)
        XCTAssertEqual(writer.audioSampleTotal, 96_000)
        XCTAssertEqual(writer.finalizeCount, 1)
    }
}
