import XCTest
@testable import YMM4Core

// MARK: - テスト用の供給元（AudioPipelineTests と同じ流儀）

private final class DriftProviderFactory: PCMProviderFactory {
    var providers: [String: PCMProvider] = [:]

    func createProvider(filePath: String?, audioTrackIndex: Int) -> PCMProvider? {
        guard let filePath else { return nil }
        return providers[filePath]
    }
}

/// フレーム番号をそのまま値にしたランプ波形（L = R = フレーム番号）。
/// 出力サンプルの値から「いま何フレーム目の素材が鳴っているか」を
/// 直接読み取れるため、内容位置のドリフト測定に使う。
/// Float32 で整数を正確に表せるのは 2^24 フレームまでで、それを超える
/// 測定点では表現誤差（ulp）が最大で 1 フレーム程度乗る。許容幅は
/// その分を見込んで設定し、ドリフトの有無は「偏差の時間変化」で判定する。
private func rampProvider(frames: Int, hz: Int) -> InMemoryPCMProvider {
    var samples: [Float] = []
    samples.reserveCapacity(frames * 2)
    for frame in 0..<frames {
        samples.append(Float(frame))
        samples.append(Float(frame))
    }
    return InMemoryPCMProvider(samples: samples, hz: hz)
}

private func constantAnimation(_ value: Double) -> Animation {
    Animation(
        defaultValue: value, minValue: -100_000, maxValue: 100_000,
        animationType: .none, values: [AnimationValue(value)]
    )
}

private func makeAudioItem(
    filePath: String, frame: Int = 0, length: Int = 30, layer: Int = 0
) -> AudioItem {
    let item = AudioItem()
    item.frame = frame
    item.length = length
    item.layer = layer
    item.filePath = filePath
    item.volume = constantAnimation(100)
    item.pan = constantAnimation(0)
    return item
}

private func makeTimeline(items: [BaseItem], fps: Int = 30, hz: Int = 48_000) -> Timeline {
    let timeline = Timeline()
    var info = VideoInfo()
    info.fps = fps
    info.hz = hz
    timeline.videoInfo = info
    timeline.items = items
    timeline.refreshTimelineLengthAndMaxLayer()
    return timeline
}

/// 時間軸ドリフトの実測テスト群。
///
/// 測定方法: ランプ素材（値 = 素材フレーム番号）をチェーンへ通し、
/// 1 秒ずつ読み進めながら節目（1 分 / 3 分 / 5 分）で
/// (a) ストリームの `position` が理論サンプル数と一致するか、
/// (b) 出力最終フレームの値が含意する素材フレーム位置と、本家式から
///     導かれる理論位置との差（フレーム単位）
/// を記録する。累積ドリフトがあれば (b) の差は時間とともに増える。
///
/// 実測結果の要約（2026-11-17、修正後の値。詳細は
/// analysis-notes/AUDIO-FIDELITY-PLAN.md と作業報告）:
/// - 位置カウンタは全チェーンで 5 分まで 0 サンプル誤差。
/// - 内容位置の偏差は、修正前はシーク往復の量子化で最大 -1 フレーム
///   （系統的・非累積）だったが、InMemoryPCMProvider のシーク丸め
///   修正後は Float32 表現誤差の範囲（±0.1 フレーム程度）に収まった。
final class AudioDriftTests: XCTestCase {

    // MARK: - シーク往復の着地精度（ドリフトの主因だった箇所）

    func testSeekRoundTripLandsOnRequestedFrame() {
        // FileAudioStream のシークは Position → tick → 素材シークの
        // 往復になる。着地がずれると、それを窓越しに読む全ての
        // リサンプラ系処理器の内容がその分だけずれる。
        for hz in [48_000, 44_100] {
            let stream = FileAudioStream(provider: rampProvider(frames: hz * 3, hz: hz))
            for targetFrame in [0, 1, 2, 3, 100, 8192, 8193, 16384, 44100, 48000, 100_000] {
                stream.seek(to: targetFrame * 2)
                var buffer = [Float](repeating: -1, count: 2)
                XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 2), 2)
                XCTAssertEqual(
                    buffer[0], Float(targetFrame),
                    "hz=\(hz) frame=\(targetFrame) で着地がずれた"
                )
            }
        }
    }

    // MARK: - リサンプル跨ぎチェーン（44.1kHz 素材 → 48kHz タイムライン）

    func testResamplerChainDriftFiveMinutes() {
        let factory = DriftProviderFactory()
        factory.providers["song"] = rampProvider(frames: 44_100 * 305, hz: 44_100)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        // 9000 フレーム @30fps = 5 分。素材は 44.1kHz（CD 音源の想定）。
        let item = makeAudioItem(filePath: "song", length: 9000)
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)

        var deviations: [Int: Double] = [:]
        var total = 0
        var buffer = [Float](repeating: 0, count: 96_000)
        for second in 1...300 {
            let read = stream.read(into: &buffer, offset: 0, count: 96_000)
            XCTAssertEqual(read, 96_000, "second=\(second) で読み取りが短くなった")
            total += read
            if second == 60 || second == 180 || second == 300 {
                XCTAssertEqual(stream.position, second * 96_000)
                let outFrame = second * 48_000 - 1
                let theory = Double(outFrame) * 44_100.0 / 48_000.0
                let implied = Double(buffer[95_998])
                deviations[second] = implied - theory
            }
        }
        XCTAssertEqual(total, 28_800_000)
        // 終端では 0 を返す（アイテム長で正確に打ち切られる）。
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 96_000), 0)

        // 偏差は Float32 表現誤差の範囲内（5 分点では素材フレームが
        // 2^23 を超え ulp = 1 になるため 0.75 まで許す）。
        for (second, dev) in deviations {
            XCTAssertLessThanOrEqual(
                abs(dev), 0.75, "second=\(second) の内容偏差が大きい: \(dev)"
            )
        }
        // ドリフト = 偏差の増分。1 分→5 分で増えていないこと。
        let growth = abs((deviations[300] ?? 0) - (deviations[60] ?? 0))
        XCTAssertLessThanOrEqual(growth, 0.5, "内容偏差が時間で増えている: \(growth)")
    }

    /// 書き出しの実経路は 1 フレーム単位の読み取りになる。読み取り
    /// 粒度が変わっても位置・内容がずれないことを 3 分で確認する。
    func testResamplerChainDriftPerFrameReads() {
        let factory = DriftProviderFactory()
        factory.providers["song"] = rampProvider(frames: 44_100 * 185, hz: 44_100)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "song", length: 5400)
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)

        // 30fps なので 1 フレーム = 3200 サンプル。
        var buffer = [Float](repeating: 0, count: 3200)
        var deviations: [Int: Double] = [:]
        for frame in 1...5400 {
            let read = stream.read(into: &buffer, offset: 0, count: 3200)
            XCTAssertEqual(read, 3200, "frame=\(frame) で読み取りが短くなった")
            if frame == 1800 || frame == 5400 {
                let outFrame = frame * 1600 - 1
                let theory = Double(outFrame) * 44_100.0 / 48_000.0
                deviations[frame] = Double(buffer[3198]) - theory
            }
        }
        XCTAssertEqual(stream.position, 5400 * 3200)
        for (frame, dev) in deviations {
            XCTAssertLessThanOrEqual(abs(dev), 0.75, "frame=\(frame) の内容偏差: \(dev)")
        }
    }

    // MARK: - タイムラインミキサー（48kHz 同 Hz・等速の素通し経路）

    func testMixerDriftFiveMinutes() {
        let factory = DriftProviderFactory()
        factory.providers["song"] = rampProvider(frames: 48_000 * 305, hz: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "song", length: 9000)
        let mixer = TimelineAudioMixer(
            timeline: makeTimeline(items: [item]), factory: sourceFactory
        )
        XCTAssertEqual(mixer.duration, 28_800_000)

        for second in 1...300 {
            // ミキサーは加算式（呼び出し側が 0 初期化する契約）なので
            // チャンクごとに新しいバッファを使う。
            var buffer = [Float](repeating: 0, count: 96_000)
            let read = mixer.read(into: &buffer, offset: 0, count: 96_000)
            XCTAssertEqual(read, 96_000, "second=\(second)")
            if second == 60 || second == 180 || second == 300 {
                XCTAssertEqual(mixer.position, second * 96_000)
                // 素通し経路では値 = タイムラインフレーム番号そのもの。
                // 5 分点では Float32 の ulp が 1 になるため 1.5 まで許す。
                let expected = Float(second * 48_000 - 1)
                XCTAssertEqual(buffer[95_998], expected, accuracy: 1.5)
                XCTAssertEqual(buffer[0], Float((second - 1) * 48_000), accuracy: 1.5)
            }
        }
    }

    // MARK: - 定速 200%（PlaybackRateStream）

    func testPlaybackRateDrift() {
        let rate = PlaybackRateStream(rate: 2)
        rate.input = FileAudioStream(
            provider: rampProvider(frames: 44_100 * 245, hz: 44_100)
        )
        rate.seek(to: 0)
        var deviations: [Int: Double] = [:]
        var buffer = [Float](repeating: 0, count: 88_200)
        // 出力 120 秒（素材消費 240 秒）。節目は 60 秒と 120 秒。
        for second in 1...120 {
            let read = rate.read(into: &buffer, offset: 0, count: 88_200)
            XCTAssertEqual(read, 88_200, "second=\(second)")
            if second == 60 || second == 120 {
                XCTAssertEqual(rate.position, second * 88_200)
                let outFrame = second * 44_100 - 1
                deviations[second] = Double(buffer[88_198]) - Double(outFrame) * 2
            }
        }
        for (second, dev) in deviations {
            XCTAssertLessThanOrEqual(abs(dev), 0.75, "second=\(second) の内容偏差: \(dev)")
        }
        let growth = abs((deviations[120] ?? 0) - (deviations[60] ?? 0))
        XCTAssertLessThanOrEqual(growth, 0.5, "内容偏差が時間で増えている: \(growth)")
    }

    // MARK: - 可変速（100% → 200% 線形、3 分）

    func testVariableRateDriftThreeMinutes() {
        let factory = DriftProviderFactory()
        factory.providers["v"] = rampProvider(frames: 48_000 * 280, hz: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "v", length: 5400)
        item.playbackRate2 = Animation(
            defaultValue: 100, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(100), AnimationValue(200)]
        )
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        // 理論位置は本家式の合成（PlaybackRateMap の台形積分）で導く。
        let table = PlaybackRateMap(rate: item.playbackRate2)
            .table(itemLength: 5400, fps: 30)
        stream.seek(to: 0)

        var deviations: [Int: Double] = [:]
        var buffer = [Float](repeating: 0, count: 96_000)
        for second in 1...180 {
            let read = stream.read(into: &buffer, offset: 0, count: 96_000)
            XCTAssertEqual(read, 96_000, "second=\(second)")
            if second == 60 || second == 120 || second == 180 {
                XCTAssertEqual(stream.position, second * 96_000)
                let outFrame = second * 48_000 - 1
                let ticks = stream.positionToTimeTicks(outFrame * 2)
                let theory = table.getConsumedTicks(timeTicks: ticks)
                    * 48_000.0 / 10_000_000.0
                deviations[second] = Double(buffer[95_998]) - theory
            }
        }
        for (second, dev) in deviations {
            XCTAssertLessThanOrEqual(abs(dev), 0.75, "second=\(second) の内容偏差: \(dev)")
        }
        let growth = abs((deviations[180] ?? 0) - (deviations[60] ?? 0))
        XCTAssertLessThanOrEqual(growth, 0.5, "内容偏差が時間で増えている: \(growth)")
    }

    // MARK: - グループバス経由（1 分）

    func testGroupBusDriftOneMinute() {
        let factory = DriftProviderFactory()
        factory.providers["a"] = rampProvider(frames: 48_000 * 65, hz: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let group = GroupItem()
        group.frame = 0
        group.length = 1800
        group.layer = 0
        group.groupRange = 50
        group.isAudioComposite = true
        let child = makeAudioItem(filePath: "a", length: 1800, layer: 1)
        let mixer = TimelineAudioMixer(
            timeline: makeTimeline(items: [group, child]), factory: sourceFactory
        )

        for second in 1...60 {
            var buffer = [Float](repeating: 0, count: 96_000)
            let read = mixer.read(into: &buffer, offset: 0, count: 96_000)
            XCTAssertEqual(read, 96_000, "second=\(second)")
            if second == 20 || second == 40 || second == 60 {
                XCTAssertEqual(mixer.position, second * 96_000)
                // バス経由でも内容はアイテムのフレーム番号そのもの。
                XCTAssertEqual(
                    buffer[95_998], Float(second * 48_000 - 1), accuracy: 0.5
                )
            }
        }
    }
}
