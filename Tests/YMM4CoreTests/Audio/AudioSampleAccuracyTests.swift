import XCTest
@testable import YMM4Core

private func makeTimeline(items: [BaseItem]) -> Timeline {
    let timeline = Timeline()
    var info = VideoInfo()
    info.fps = 30
    info.hz = 48_000
    timeline.videoInfo = info
    timeline.items = items
    timeline.refreshTimelineLengthAndMaxLayer()
    return timeline
}

/// チェーン各段の境界におけるサンプル精度のテスト群。
///
/// 対象は、シーク直後・ループ境界・エコーの反復境界・グループバスの
/// 区間分割点・ウィンドウ補充境界（InputFrameWindow の 8192 フレーム
/// 境界）で、出力サンプルの値と位置が本家式から導かれる理論どおりか。
/// 実測の結論（2026-11-17）: いずれの境界も理論どおりで、tick 量子化に
/// 起因する最大 1 フレームの系統的ずれは素材シークの丸め修正で解消した。
/// 残る量子化（アイテム開始位置とゲート境界）は本家式そのものに由来し、
/// その値自体を理論として固定する。
final class AudioSampleAccuracyTests: XCTestCase {

    // MARK: - シーク直後（リサンプラ）

    func testResamplerAccuracyImmediatelyAfterSeek() {
        let resampler = ResamplerStream(toHz: 48_000)
        resampler.input = FileAudioStream(
            provider: rampProvider(frames: 44_100 * 30, hz: 44_100)
        )
        resampler.seek(to: 100_000 * 2)
        var buffer = [Float](repeating: 0, count: 400)
        XCTAssertEqual(resampler.read(into: &buffer, offset: 0, count: 400), 400)
        // 出力フレーム 100000 の理論素材位置は 100000 * 44100/48000。
        let theory = 100_000.0 * 44_100.0 / 48_000.0
        XCTAssertEqual(Double(buffer[0]), theory, accuracy: 0.05)
        XCTAssertEqual(Double(buffer[100 * 2]), theory + 100 * 44_100.0 / 48_000.0, accuracy: 0.05)
    }

    // MARK: - アップサンプラのウィンドウ補充境界

    func testUpsamplerAccuracyAcrossWindowRefill() {
        // VoiceItem 24kHz → 48kHz。理論の入力位置は本家式
        // in = out / rate + 1 / (2 * rate) - 0.5 = out/2 - 0.25。
        // 出力フレーム 16384 以降は入力ウィンドウの補充（8192 フレーム
        // 境界）を跨ぐため、補充時のシークずれがあればここに出る。
        let factory = MapPCMProviderFactory()
        let sourceFactory = AudioSourceFactory(
            providerFactory: factory,
            voiceProviderResolver: { _ in rampProvider(frames: 24_000 * 3, hz: 24_000) }
        )
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 30
        voice.volume = constantAnimation(100)
        voice.pan = constantAnimation(0)
        let stream = sourceFactory.effectedStream(for: voice, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        for outFrame in [100, 1000, 10_000, 16_384, 20_000, 40_000] {
            let theory = Double(outFrame) / 2 - 0.25
            XCTAssertEqual(
                Double(buffer[outFrame * 2]), theory, accuracy: 0.05,
                "outFrame=\(outFrame)"
            )
        }
    }

    // MARK: - 倍率リサンプラ経路（低 Hz 素材 + 高速再生）

    func testByRateChainAccuracy() {
        // 16kHz 素材 + 200%: チェーンは Resampler(byRate 2) →
        // PlaybackRate(2) → Resampler(48k) になる。理論の素材位置は
        // 出力フレーム j に対して 2j/3（16kHz フレーム）。
        let factory = MapPCMProviderFactory()
        factory.providers["low"] = rampProvider(frames: 16_000 * 40, hz: 16_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "low", length: 600)
        item.playbackRate = 200
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 96_000)
        for second in 1...10 {
            XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 96_000), 96_000)
            let outFrame = second * 48_000 - 1
            let theory = Double(outFrame) * 2.0 / 3.0
            XCTAssertEqual(
                Double(buffer[95_998]), theory, accuracy: 0.1, "second=\(second)"
            )
        }
    }

    // MARK: - ループ境界

    func testLoopBoundaryIsSampleExact() {
        // 処理器単体: 4 フレーム素材の繰り返しがフレーム単位で正確。
        let loop = LoopAudioStream(isEnabled: true)
        loop.input = FileAudioStream(provider: rampProvider(frames: 4, hz: 48_000))
        loop.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 24)
        XCTAssertEqual(loop.read(into: &buffer, offset: 0, count: 24), 24)
        XCTAssertEqual(
            buffer,
            [0, 0, 1, 1, 2, 2, 3, 3, 0, 0, 1, 1, 2, 2, 3, 3, 0, 0, 1, 1, 2, 2, 3, 3]
        )

        // チェーン経由: 4800 フレーム（0.1 秒）素材を 1 秒ループ。
        let factory = MapPCMProviderFactory()
        factory.providers["l"] = rampProvider(frames: 4800, hz: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "l", length: 30)
        item.isLooped = true
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var longBuffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(stream.read(into: &longBuffer, offset: 0, count: 96_000), 96_000)
        for frame in [0, 4799, 4800, 4801, 9599, 9600, 12_345, 47_999] {
            XCTAssertEqual(
                longBuffer[frame * 2], Float(frame % 4800), "frame=\(frame)"
            )
        }
    }

    // MARK: - シークのタイブレーク（0.5 フレームちょうど）

    func testSeekTieBreakRoundsToEvenFrame() {
        // 44.1kHz では tick がちょうど半フレームに当たる位置が存在する:
        // 50000 tick = 220.5 フレーム、150000 tick = 661.5 フレーム。
        // InMemoryPCMProvider.seek の最近傍丸め（偶数丸め）では
        // 220.5 → 220（下の偶数）、661.5 → 662（上の偶数）へ着地する
        // （A16-QA 追加提案への対応、2026-11-17）。
        let provider = rampProvider(frames: 44_100, hz: 44_100)
        var buffer = [Float](repeating: 0, count: 2)
        provider.seek(toTime: TimeSpanValue(ticks: 50_000))
        XCTAssertEqual(provider.read(into: &buffer, offset: 0, count: 2), 2)
        XCTAssertEqual(buffer, [220, 220])
        provider.seek(toTime: TimeSpanValue(ticks: 150_000))
        XCTAssertEqual(provider.read(into: &buffer, offset: 0, count: 2), 2)
        XCTAssertEqual(buffer, [662, 662])
    }

    // MARK: - 44.1kHz で量子化されるループ長

    func testLoopPeriodQuantizedByTimeSpanRoundTripAt44100() {
        // 4411 フレーム（8822 サンプル）の 44.1kHz 素材は、Duration が
        // TimeSpan 往復（PositionToTime → TimeToPosition、いずれも本家式
        // の切り捨て）を通るため、ストリーム上の全長は 8820 サンプル
        // （4410 フレーム）になる。ループのシーク折り返しはこの周期で
        // 起きる。一方、読み取り側の折り返しは本家 LoopEffect と同じく
        // 短い読み取り駆動であり、物理末尾（8822 サンプル）で起きる
        // （A16-QA 追加提案への対応、2026-11-17）。
        let provider = rampProvider(frames: 4411, hz: 44_100)
        let fileStream = FileAudioStream(provider: provider)
        XCTAssertEqual(fileStream.duration, 8820)

        let loop = LoopAudioStream(isEnabled: true)
        loop.input = fileStream
        var buffer = [Float](repeating: 0, count: 2)
        // 周期ちょうどへのシークは先頭へ折り返す。
        loop.seek(to: 8820)
        XCTAssertEqual(loop.read(into: &buffer, offset: 0, count: 2), 2)
        XCTAssertEqual(buffer, [0, 0])
        // 周期 + 200 サンプルは素材フレーム 100 へ着地する
        // （PositionToTime → 最近傍丸めの往復でもサンプル厳密）。
        loop.seek(to: 8820 + 200)
        XCTAssertEqual(loop.read(into: &buffer, offset: 0, count: 2), 2)
        XCTAssertEqual(buffer, [100, 100])

        // 読み取り側: 物理末尾を跨ぐと先頭へ戻る。
        loop.seek(to: 0)
        var longBuffer = [Float](repeating: 0, count: 8822 + 4)
        XCTAssertEqual(
            loop.read(into: &longBuffer, offset: 0, count: 8822 + 4), 8822 + 4
        )
        XCTAssertEqual(longBuffer[8820], 4410)
        XCTAssertEqual(longBuffer[8821], 4410)
        XCTAssertEqual(Array(longBuffer[8822..<8826]), [0, 0, 1, 1])
    }

    // MARK: - エコーの反復境界

    func testEchoTapsAndSeekConsistency() {
        let samples: [Float] = {
            var values = [Float](repeating: 0, count: 96_000)
            values[0] = 1
            values[1] = 1
            return values
        }()
        func makeEcho() -> EchoAudioStream {
            let echo = EchoAudioStream(
                interval: TimeSpanValue(seconds: 0.1), attenuation: 0.5
            )
            echo.input = FileAudioStream(
                provider: InMemoryPCMProvider(samples: samples, hz: 48_000)
            )
            return echo
        }

        // タップ値: 位置 9600*k の振幅は 0.5^k（k = 0..7、repeatCount = 7）。
        let sequential = makeEcho()
        sequential.seek(to: 0)
        var all = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(sequential.read(into: &all, offset: 0, count: 96_000), 96_000)
        var expectedTap: Float = 1
        for tap in 0...7 {
            XCTAssertEqual(all[9600 * tap], expectedTap, accuracy: 1e-6, "tap=\(tap)")
            expectedTap *= 0.5
        }

        // シークで同じ位置へ跳んでも、逐次読みとビット単位で一致する
        // （エコーの先行生成による状態再現が正確なことの確認）。
        // 窓はタップ位置と反復境界（effectLength = 67200）を跨ぐものを含む。
        for windowStart in [9500, 28_700, 67_100, 67_200, 80_000] {
            let reference = makeEcho()
            reference.seek(to: 0)
            var scratch = [Float](repeating: 0, count: 4096)
            var remaining = windowStart
            while remaining > 0 {
                let chunk = min(remaining, 4096)
                remaining -= reference.read(into: &scratch, offset: 0, count: chunk)
            }
            var expected = [Float](repeating: 0, count: 400)
            _ = reference.read(into: &expected, offset: 0, count: 400)

            let seeked = makeEcho()
            seeked.seek(to: windowStart)
            var actual = [Float](repeating: 0, count: 400)
            _ = seeked.read(into: &actual, offset: 0, count: 400)
            XCTAssertEqual(expected, actual, "window=\(windowStart) でシーク再現がずれた")
        }
    }

    // MARK: - セグメントゲートの境界（tick で割り切れないフレーム差）

    func testSegmentGateAtTickQuantizedBoundary() {
        // フレーム差 16（30fps）は tick で割り切れず、本家式
        // FrameDeltaToPosition の結果はフレーム厳密値 51200 ではなく
        // 51198 になる。この量子化自体が本家式の帰結であり、ゲートは
        // その位置で開き、内容はゲート位置と一致したフレームを返す。
        let boundary = AudioGroupStreamBuilder.frameDeltaToPosition(16, fps: 30, hz: 48_000)
        XCTAssertEqual(boundary, 51_198)

        let gate = SegmentGateStream(
            input: FileAudioStream(
                provider: rampProvider(frames: 48_000, hz: 48_000, offset: 1000)
            ),
            allowedRanges: [(start: boundary, end: 96_000)]
        )
        gate.seek(to: 0)
        var buffer = [Float](repeating: -5, count: 96_000)
        XCTAssertEqual(gate.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        // 区間外はゲート自身が 0 で埋める（センチネル -5 が残らない）。
        XCTAssertEqual(buffer[51_196], 0)
        XCTAssertEqual(buffer[51_197], 0)
        // 境界位置の内容は素材フレーム 25599（= 51198 / 2）。
        XCTAssertEqual(buffer[51_198], 25_599 + 1000)
        XCTAssertEqual(buffer[51_200], 25_600 + 1000)
    }

    // MARK: - グループバスの区間分割点

    func testGroupSplitContentContinuity() {
        // 子アイテム（フレーム 15〜45）の前半を音声合成グループが所有し、
        // 後半がトップレベルになる構成。分割点で内容が連続し、
        // 二重加算も欠落も無いことをランプで確認する。
        // グループ長 31 は tick で割り切れない分割点のケース。
        for groupLength in [30, 31] {
            let factory = MapPCMProviderFactory()
            factory.providers["a"] = rampProvider(frames: 48_000 * 3, hz: 48_000)
            let sourceFactory = AudioSourceFactory(providerFactory: factory)
            let group = GroupItem()
            group.frame = 0
            group.length = groupLength
            group.layer = 0
            group.groupRange = 50
            group.isAudioComposite = true
            let child = makeAudioItem(filePath: "a", frame: 15, length: 30, layer: 1)
            let mixer = TimelineAudioMixer(
                timeline: makeTimeline(items: [group, child]), factory: sourceFactory
            )
            var buffer = [Float](repeating: 0, count: 144_000)
            XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 144_000), 144_000)

            // タイムラインフレーム t の内容はアイテム内フレーム (t - 15)。
            // 1 タイムラインフレーム = 1600 音声フレーム。
            let boundarySample = groupLength * 3200
            let expectedAtBoundary = Float((groupLength - 15) * 1600)
            XCTAssertEqual(
                buffer[boundarySample], expectedAtBoundary,
                "groupLength=\(groupLength) の分割点で内容がずれた"
            )
            XCTAssertEqual(buffer[boundarySample - 2], expectedAtBoundary - 1)
            XCTAssertEqual(buffer[boundarySample + 2], expectedAtBoundary + 1)
        }
    }

    // MARK: - ミキサーのアイテム開始位置（tick 量子化）

    func testMixerItemStartPositionQuantization() {
        // フレーム 7 開始のアイテム: FrameToTime(7) = 2333333 tick
        // （真値 2333333.33… の丸め）→ TimeToPosition で 22398 サンプル。
        // 内容は映像グリッド（22400）より 2 サンプル = 1 フレーム早く
        // 始まる。これは本家式（FrameToTime の AwayFromZero 丸め +
        // TimeToPosition の偶数切り捨て）から導かれる値そのもので、
        // 実装の逸脱ではない。tick で割り切れるフレーム 30 では正確。
        let factory = MapPCMProviderFactory()
        factory.providers["a"] = rampProvider(frames: 48_000 * 3, hz: 48_000, offset: 1000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)

        let item7 = makeAudioItem(filePath: "a", frame: 7, length: 30)
        let mixer7 = TimelineAudioMixer(
            timeline: makeTimeline(items: [item7]), factory: sourceFactory
        )
        var buffer = [Float](repeating: 0, count: 96_000)
        _ = mixer7.read(into: &buffer, offset: 0, count: 96_000)
        var firstSound = -1
        for index in buffer.indices where buffer[index] != 0 {
            firstSound = index
            break
        }
        XCTAssertEqual(firstSound, 22_398)
        XCTAssertEqual(buffer[22_398], 1000) // 素材フレーム 0

        let item30 = makeAudioItem(filePath: "a", frame: 30, length: 30)
        let mixer30 = TimelineAudioMixer(
            timeline: makeTimeline(items: [item30]), factory: sourceFactory
        )
        var buffer30 = [Float](repeating: 0, count: 192_000)
        _ = mixer30.read(into: &buffer30, offset: 0, count: 192_000)
        XCTAssertEqual(buffer30[95_999], 0)
        XCTAssertEqual(buffer30[96_000], 1000)
    }

    // MARK: - アイテム終端の長さ（アイテム打ち切りとタイムライン長の一致）

    func testItemLengthClampMatchesTimelineDuration() {
        // 1801 フレーム @30fps は tick で割り切れない長さ。アイテム側の
        // 打ち切り（EffectedAudioItemSource）とタイムライン長
        // （TimelineAudioMixer.duration）が同じサンプル数になること。
        let factory = MapPCMProviderFactory()
        factory.providers["a"] = rampProvider(frames: 48_000 * 65, hz: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "a", length: 1801)
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var total = 0
        var buffer = [Float](repeating: 0, count: 96_000)
        while true {
            let read = stream.read(into: &buffer, offset: 0, count: 96_000)
            if read == 0 { break }
            total += read
        }
        // FrameToTime(1801) = 600333333 tick から導かれる値。
        XCTAssertEqual(total, 5_763_198)

        let mixer = TimelineAudioMixer(
            timeline: makeTimeline(items: [makeAudioItem(filePath: "a", length: 1801)]),
            factory: sourceFactory
        )
        XCTAssertEqual(mixer.duration, total)
    }
}
