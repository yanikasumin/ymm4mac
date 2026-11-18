#if os(macOS)
import Foundation
import XCTest
@testable import YMM4GPU
import YMM4Core

/// 実時間再生（Issue #52）の検証。
///
/// 供給元（PlaybackAudioSource）はミキサーとメーターの実接続を
/// 既知 PCM で検証する。エンジン本体は音声デバイスに依存するため、
/// ここでは位置計算の純粋関数と、停止中の状態遷移（シーク・
/// クランプ・現在フレーム同期）だけを検証し、実再生の同期精度は
/// Mac 実機での実測に委ねる（台帳に記録）。
final class PlaybackAudioSourceTests: XCTestCase {

    private final class MapFactory: PCMProviderFactory {
        var providers: [String: PCMProvider] = [:]
        func createProvider(filePath: String?, audioTrackIndex: Int) -> PCMProvider? {
            guard let filePath else { return nil }
            return providers[filePath]
        }
    }

    private func constantAnimation(_ value: Double) -> Animation {
        Animation(
            defaultValue: value, minValue: -100_000, maxValue: 100_000,
            animationType: .none, values: [AnimationValue(value)]
        )
    }

    /// 3 秒のタイムライン（fps 30）に定数 0.5 の音声アイテムを置く。
    private func makeSource() -> PlaybackAudioSource {
        let factory = MapFactory()
        factory.providers["a"] = InMemoryPCMProvider(
            samples: [Float](repeating: 0.5, count: 48_000 * 2 * 3),
            hz: 48_000
        )
        let item = AudioItem()
        item.frame = 0
        item.length = 90
        item.layer = 0
        item.filePath = "a"
        item.volume = constantAnimation(100)
        item.pan = constantAnimation(0)
        let timeline = Timeline()
        var info = VideoInfo()
        info.fps = 30
        info.hz = 48_000
        timeline.videoInfo = info
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let mixer = TimelineAudioMixer(timeline: timeline, factory: sourceFactory)
        return PlaybackAudioSource(mixer: mixer, levelMeter: SoundLevelMeter())
    }

    func testReadReturnsMixedSamplesAndFeedsLevelMeter() {
        let source = makeSource()
        source.seek(toTime: .zero)
        var buffer = [Float](repeating: 0, count: 48_000 * 2)
        let readCount = source.read(into: &buffer, offset: 0, count: buffer.count)
        XCTAssertEqual(readCount, buffer.count)
        // アイテム音量 100・レイヤー音量 100 のため、素材の値がそのまま出る。
        XCTAssertEqual(buffer[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(buffer[buffer.count - 1], 0.5, accuracy: 1e-6)
        // 1 秒分の窓がメーターへ通っている。
        source.levelMeter.setCurrentPosition(
            TimeSpanValue(seconds: 1), isDecayed: false
        )
        XCTAssertEqual(source.levelMeter.left.current.peak, -6.0206, accuracy: 0.001)
        XCTAssertEqual(source.levelMeter.right.current.peak, -6.0206, accuracy: 0.001)
    }

    func testReadPastEndReturnsSilence() {
        let source = makeSource()
        source.seek(toTime: .zero)
        var buffer = [Float](repeating: 0, count: 48_000 * 2)
        // 3 秒分を読み切る。
        for _ in 0..<3 {
            XCTAssertEqual(
                source.read(into: &buffer, offset: 0, count: buffer.count),
                buffer.count
            )
        }
        // 終端以降は無音が要求分だけ返り続ける（本家の供給方式）。
        var tail = [Float](repeating: 1, count: 48_000 * 2)
        let readCount = source.read(into: &tail, offset: 0, count: tail.count)
        XCTAssertEqual(readCount, tail.count)
        XCTAssertTrue(tail.allSatisfy { $0 == 0 })
    }

    func testSeekRestartsStreamAndMeter() {
        let source = makeSource()
        source.seek(toTime: .zero)
        var buffer = [Float](repeating: 0, count: 48_000 * 2)
        _ = source.read(into: &buffer, offset: 0, count: buffer.count)
        _ = source.read(into: &buffer, offset: 0, count: buffer.count)
        source.seek(toTime: .zero)
        var again = [Float](repeating: 0, count: 48_000 * 2)
        let readCount = source.read(into: &again, offset: 0, count: again.count)
        XCTAssertEqual(readCount, again.count)
        XCTAssertEqual(again[0], 0.5, accuracy: 1e-6)
        // シークでメーターの蓄積は破棄され、現在値は保持される
        // （本家 SoundLevelMeter.Seek の規則）。
        source.levelMeter.setCurrentPosition(
            TimeSpanValue(seconds: 1), isDecayed: false
        )
        XCTAssertEqual(source.levelMeter.left.current.peak, -6.0206, accuracy: 0.001)
    }

    func testSmallReadsAcrossRingBoundary() {
        let source = makeSource()
        source.seek(toTime: .zero)
        // 窓（1 秒）やリング（2 秒）の境界を跨ぐ小刻みな読み取りでも
        // 内容が欠けないことを確認する。
        var collected: [Float] = []
        var chunk = [Float](repeating: 0, count: 1_000)
        for _ in 0..<200 {
            let readCount = source.read(into: &chunk, offset: 0, count: chunk.count)
            XCTAssertEqual(readCount, chunk.count)
            collected.append(contentsOf: chunk[..<readCount])
        }
        XCTAssertEqual(collected.count, 200_000)
        XCTAssertTrue(collected.allSatisfy { abs($0 - 0.5) < 1e-6 })
    }
}

final class RealtimePlaybackEngineTests: XCTestCase {

    private func makeEngine(currentFrame: Int = 0) -> (RealtimePlaybackEngine, Timeline) {
        let timeline = Timeline()
        var info = VideoInfo()
        info.fps = 30
        info.hz = 48_000
        timeline.videoInfo = info
        let item = AudioItem()
        item.frame = 0
        item.length = 300
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        timeline.currentFrame = currentFrame
        let factory = AudioSourceFactory(
            providerFactory: AVFoundationPCMProviderFactory(baseDirectory: nil)
        )
        let mixer = TimelineAudioMixer(timeline: timeline, factory: factory)
        let source = PlaybackAudioSource(mixer: mixer, levelMeter: SoundLevelMeter())
        return (RealtimePlaybackEngine(timeline: timeline, source: source), timeline)
    }

    func testPositionCalculation() {
        // 開始 10 秒 + 48000 フレーム（1 秒）= 11 秒。
        // consumedSamples はプレイヤーのサンプル時刻（フレーム数）。
        let result = RealtimePlaybackEngine.position(
            startPosition: TimeSpanValue(seconds: 10),
            consumedSamples: 48_000,
            hz: 48_000,
            maxPosition: TimeSpanValue(seconds: 30)
        )
        XCTAssertEqual(result.seconds, 11, accuracy: 1e-9)
    }

    func testPositionClampsToMaxPosition() {
        let result = RealtimePlaybackEngine.position(
            startPosition: TimeSpanValue(seconds: 10),
            consumedSamples: 48_000 * 100,
            hz: 48_000,
            maxPosition: TimeSpanValue(seconds: 10.5)
        )
        XCTAssertEqual(result.seconds, 10.5, accuracy: 1e-9)
    }

    func testInitialPositionFollowsTimelineCurrentFrame() {
        let (engine, _) = makeEngine(currentFrame: 45)
        // 45 フレーム @30fps = 1.5 秒。
        XCTAssertEqual(engine.position.seconds, 1.5, accuracy: 1e-9)
        XCTAssertEqual(engine.currentFrame, 45)
        engine.dispose()
    }

    func testSeekClampsAndSyncsCurrentFrame() {
        let (engine, timeline) = makeEngine()
        engine.seek(toFrame: 150)
        XCTAssertEqual(engine.currentFrame, 150)
        XCTAssertEqual(timeline.currentFrame, 150)
        engine.seek(toFrame: -10)
        XCTAssertEqual(engine.currentFrame, 0)
        XCTAssertEqual(timeline.currentFrame, 0)
        // タイムライン長（300 フレーム）で制限される。
        engine.seek(toFrame: 999_999)
        XCTAssertEqual(engine.currentFrame, 300)
        engine.dispose()
    }

    func testStopReturnsToZero() {
        let (engine, timeline) = makeEngine()
        engine.seek(toFrame: 90)
        engine.stop()
        XCTAssertEqual(engine.currentFrame, 0)
        XCTAssertEqual(timeline.currentFrame, 0)
        XCTAssertFalse(engine.isPlaying)
        engine.dispose()
    }
}
#endif
