import XCTest
@testable import YMM4Core

// MARK: - テスト用の供給元

private final class MapProviderFactory: PCMProviderFactory {
    var providers: [String: PCMProvider] = [:]

    func createProvider(filePath: String?, audioTrackIndex: Int) -> PCMProvider? {
        guard let filePath else { return nil }
        return providers[filePath]
    }
}

private func constantProvider(
    _ value: Float, frames: Int, hz: Int = 48_000
) -> InMemoryPCMProvider {
    InMemoryPCMProvider(
        samples: [Float](repeating: value, count: frames * 2), hz: hz
    )
}

/// フレーム番号をそのまま値にしたランプ波形（L = R = フレーム番号）。
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
    filePath: String, frame: Int = 0, length: Int = 30, layer: Int = 0,
    volume: Double = 100
) -> AudioItem {
    let item = AudioItem()
    item.frame = frame
    item.length = length
    item.layer = layer
    item.filePath = filePath
    item.volume = constantAnimation(volume)
    item.pan = constantAnimation(0)
    return item
}

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

final class AudioPipelineTests: XCTestCase {

    // MARK: - 基底ストリーム / ファイル適応

    func testFileAudioStreamBasics() {
        let provider = rampProvider(frames: 48_000, hz: 48_000)
        let stream = FileAudioStream(provider: provider)
        XCTAssertEqual(stream.hz, 48_000)
        XCTAssertEqual(stream.duration, 96_000)

        var buffer = [Float](repeating: 0, count: 8)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 8), 8)
        XCTAssertEqual(buffer, [0, 0, 1, 1, 2, 2, 3, 3])
        XCTAssertEqual(stream.position, 8)
        // 終端では 0 を返す。
        stream.seek(to: stream.duration)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 8), 0)

        // シークは時刻（tick）経由のため、tick に割り切れる位置で確認する。
        stream.seek(to: 9_600)
        XCTAssertEqual(stream.position, 9_600)
        var tail = [Float](repeating: 0, count: 4)
        XCTAssertEqual(stream.read(into: &tail, offset: 0, count: 4), 4)
        XCTAssertEqual(tail, [4_800, 4_800, 4_801, 4_801])

        // プロバイダが無い場合は無音（Hz 48000、長さ 0）。
        let silent = FileAudioStream(provider: nil)
        XCTAssertEqual(silent.hz, 48_000)
        XCTAssertEqual(silent.duration, 0)
        XCTAssertEqual(silent.read(into: &buffer, offset: 0, count: 8), 0)
    }

    // MARK: - VolumePan

    func testVolumePanGainAndPanLaw() {
        // 音量 50% → 利得 0.5。パン +100 → 左 0 / 右は利得そのまま。
        let stream = VolumePanStream(
            itemDuration: TimeSpanValue(seconds: 1),
            volume: constantAnimation(50),
            pan: constantAnimation(100),
            fadeIn: 0, fadeOut: 0
        )
        stream.input = FileAudioStream(provider: constantProvider(1, frames: 48_000))
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 4)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 4), 4)
        XCTAssertEqual(buffer[0], 0, accuracy: 1e-6)
        XCTAssertEqual(buffer[1], 0.5, accuracy: 1e-6)

        // パン -100 → 左は利得そのまま / 右 0。
        let leftStream = VolumePanStream(
            itemDuration: TimeSpanValue(seconds: 1),
            volume: constantAnimation(50),
            pan: constantAnimation(-100),
            fadeIn: 0, fadeOut: 0
        )
        leftStream.input = FileAudioStream(provider: constantProvider(1, frames: 48_000))
        leftStream.seek(to: 0)
        XCTAssertEqual(leftStream.read(into: &buffer, offset: 0, count: 4), 4)
        XCTAssertEqual(buffer[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(buffer[1], 0, accuracy: 1e-6)
    }

    func testVolumePanMuteShortcut() {
        let stream = VolumePanStream(
            itemDuration: TimeSpanValue(seconds: 1),
            volume: constantAnimation(0),
            pan: constantAnimation(0),
            fadeIn: 0, fadeOut: 0
        )
        stream.input = FileAudioStream(provider: constantProvider(1, frames: 48_000))
        XCTAssertEqual(stream.duration, 0)
        stream.seek(to: 0)
        var buffer = [Float](repeating: 9, count: 4)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 4), 0)
        XCTAssertEqual(buffer, [9, 9, 9, 9])
    }

    func testVolumePanFadeInOut() {
        // 2 秒のアイテム、フェードイン 1 秒・フェードアウト 1 秒、音量 100。
        let stream = VolumePanStream(
            itemDuration: TimeSpanValue(seconds: 2),
            volume: constantAnimation(100),
            pan: constantAnimation(0),
            fadeIn: 1, fadeOut: 1
        )
        stream.input = FileAudioStream(provider: constantProvider(1, frames: 96_000))
        stream.seek(to: 0)
        let count = 96_000 * 2
        var buffer = [Float](repeating: 0, count: count)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: count), count)
        // t = 0 → 0、t = 0.5 → 0.5、t = 1.0 → 1、t = 1.5 → 0.5。
        XCTAssertEqual(buffer[0], 0, accuracy: 1e-4)
        XCTAssertEqual(buffer[24_000 * 2], 0.5, accuracy: 1e-3)
        XCTAssertEqual(buffer[48_000 * 2], 1, accuracy: 1e-3)
        XCTAssertEqual(buffer[72_000 * 2], 0.5, accuracy: 1e-3)
    }

    // MARK: - チェーン（EffectedAudioItemSource）

    func testEffectedSourceNegativePositionAndDurationClamp() {
        let factory = MapProviderFactory()
        factory.providers["a"] = constantProvider(0.8, frames: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "a")
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        XCTAssertEqual(stream.hz, 48_000)

        // 負位置から読むと前半は書かれず（0 のまま）、後半に音が来る。
        stream.seek(to: -48_000)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        XCTAssertEqual(buffer[0], 0)
        XCTAssertEqual(buffer[47_999], 0)
        XCTAssertEqual(buffer[48_000], 0.8, accuracy: 1e-6)
        XCTAssertEqual(buffer[95_999], 0.8, accuracy: 1e-6)
        XCTAssertEqual(stream.position, 48_000)

        // アイテム長（1 秒）を超えた読み取りは打ち切られる。
        stream.seek(to: 0)
        var longBuffer = [Float](repeating: 0, count: 192_000)
        XCTAssertEqual(stream.read(into: &longBuffer, offset: 0, count: 192_000), 96_000)
    }

    func testPlaybackRateConstantDouble() {
        let factory = MapProviderFactory()
        factory.providers["r"] = rampProvider(frames: 96_000, hz: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "r")
        item.playbackRate = 200
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 400)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 400), 400)
        // 出力フレーム j は入力フレーム 2j。
        XCTAssertEqual(buffer[0], 0, accuracy: 1e-4)
        XCTAssertEqual(buffer[100 * 2], 200, accuracy: 1e-3)
        XCTAssertEqual(buffer[99 * 2], 198, accuracy: 1e-3)
    }

    func testContentOffsetShiftsStart() {
        let factory = MapProviderFactory()
        // 値 = 経過秒になるランプ（フレーム番号 / Hz）。
        var samples: [Float] = []
        for frame in 0..<96_000 {
            let value = Float(frame) / 48_000
            samples.append(value)
            samples.append(value)
        }
        factory.providers["o"] = InMemoryPCMProvider(samples: samples, hz: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "o")
        item.contentOffset = TimeSpanValue(seconds: 0.5)
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 4)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 4), 4)
        XCTAssertEqual(buffer[0], 0.5, accuracy: 1e-4)
    }

    func testLoopWrapsContent() {
        let factory = MapProviderFactory()
        factory.providers["l"] = constantProvider(0.8, frames: 12_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "l")
        item.isLooped = true
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        // 0.25 秒の素材が 1 秒分繰り返され、全区間が 0.8。
        XCTAssertTrue(buffer.allSatisfy { abs($0 - 0.8) < 1e-6 })
    }

    func testVariableRateIdentityAndDouble() {
        let factory = MapProviderFactory()
        factory.providers["v"] = rampProvider(frames: 100, hz: 100)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)

        // 値が一定でも型が「なし」でなければ可変経路を通る。
        let identityItem = makeAudioItem(filePath: "v")
        identityItem.playbackRate2 = Animation(
            defaultValue: 100, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(100), AnimationValue(100)]
        )
        let identity = sourceFactory.effectedStream(for: identityItem, hz: 100, fps: 30)!
        identity.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 200)
        XCTAssertEqual(identity.read(into: &buffer, offset: 0, count: 200), 200)
        XCTAssertEqual(buffer[50 * 2], 50, accuracy: 1e-3)
        XCTAssertEqual(buffer[99 * 2], 99, accuracy: 1e-3)

        let doubleItem = makeAudioItem(filePath: "v")
        doubleItem.playbackRate2 = Animation(
            defaultValue: 200, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(200), AnimationValue(200)]
        )
        let doubled = sourceFactory.effectedStream(for: doubleItem, hz: 100, fps: 30)!
        doubled.seek(to: 0)
        var shortBuffer = [Float](repeating: 0, count: 200)
        // 素材 1 秒を 2 倍速で消費するため、0.5 秒（100 サンプル）で尽きる。
        XCTAssertEqual(doubled.read(into: &shortBuffer, offset: 0, count: 200), 100)
        XCTAssertEqual(shortBuffer[25 * 2], 50, accuracy: 1e-3)
        XCTAssertEqual(shortBuffer[49 * 2], 98, accuracy: 1e-3)
    }

    // MARK: - 個別処理器

    func testEchoImpulseResponse() {
        var samples = [Float](repeating: 0, count: 96_000)
        samples[0] = 1
        samples[1] = 1
        let echo = EchoAudioStream(
            interval: TimeSpanValue(seconds: 0.1), attenuation: 0.5
        )
        echo.input = FileAudioStream(
            provider: InMemoryPCMProvider(samples: samples, hz: 48_000)
        )
        XCTAssertEqual(echo.repeatCount, 7)
        XCTAssertEqual(echo.duration, 96_000 + 9_600 * 7)
        echo.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 9_600 * 4)
        XCTAssertEqual(echo.read(into: &buffer, offset: 0, count: buffer.count), buffer.count)
        XCTAssertEqual(buffer[0], 1, accuracy: 1e-6)
        XCTAssertEqual(buffer[9_600], 0.5, accuracy: 1e-6)
        XCTAssertEqual(buffer[19_200], 0.25, accuracy: 1e-6)
        XCTAssertEqual(buffer[28_800], 0.125, accuracy: 1e-6)
    }

    func testReverseStream() {
        let reverse = ReverseAudioStream()
        reverse.input = FileAudioStream(provider: rampProvider(frames: 4, hz: 4))
        XCTAssertEqual(reverse.duration, 8)
        reverse.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 8)
        XCTAssertEqual(reverse.read(into: &buffer, offset: 0, count: 8), 8)
        XCTAssertEqual(buffer, [3, 3, 2, 2, 1, 1, 0, 0])
    }

    func testResamplerDurationAndInterpolation() {
        // 24kHz → 48kHz: 長さは 2 倍。DC はそのまま、ランプは中点が補間される。
        let dc = ResamplerStream(toHz: 48_000)
        dc.input = FileAudioStream(provider: constantProvider(0.75, frames: 24_000, hz: 24_000))
        XCTAssertEqual(dc.duration, 96_000)
        dc.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(dc.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        XCTAssertEqual(buffer[0], 0.75, accuracy: 1e-6)
        XCTAssertEqual(buffer[48_000], 0.75, accuracy: 1e-6)
        // 最終フレームだけは終端の無音側へ補間される。
        XCTAssertEqual(buffer[95_998], 0.75, accuracy: 1e-6)

        let ramp = ResamplerStream(toHz: 200)
        ramp.input = FileAudioStream(provider: rampProvider(frames: 100, hz: 100))
        ramp.seek(to: 0)
        var rampBuffer = [Float](repeating: 0, count: 8)
        XCTAssertEqual(ramp.read(into: &rampBuffer, offset: 0, count: 8), 8)
        XCTAssertEqual(rampBuffer[3 * 2], 1.5, accuracy: 1e-6)

        // 同一 Hz は素通し。
        let passthrough = ResamplerStream(toHz: 100)
        passthrough.input = FileAudioStream(provider: rampProvider(frames: 100, hz: 100))
        XCTAssertEqual(passthrough.duration, 200)
        passthrough.seek(to: 0)
        XCTAssertEqual(passthrough.read(into: &rampBuffer, offset: 0, count: 8), 8)
        XCTAssertEqual(rampBuffer[3 * 2], 3, accuracy: 1e-6)
    }

    func testSegmentGate() {
        let gate = SegmentGateStream(
            input: FileAudioStream(provider: constantProvider(1, frames: 48_000)),
            allowedRanges: [(start: 100, end: 200)]
        )
        gate.seek(to: 0)
        var buffer = [Float](repeating: 9, count: 300)
        XCTAssertEqual(gate.read(into: &buffer, offset: 0, count: 300), 300)
        XCTAssertEqual(buffer[0], 0)
        XCTAssertEqual(buffer[99], 0)
        XCTAssertEqual(buffer[100], 1)
        XCTAssertEqual(buffer[199], 1)
        XCTAssertEqual(buffer[200], 0)
        XCTAssertEqual(buffer[299], 0)
    }

    // MARK: - タイムラインミックス

    func testMixerAddsItemsWithLayerVolume() {
        let factory = MapProviderFactory()
        factory.providers["a"] = constantProvider(0.5, frames: 48_000)
        factory.providers["b"] = constantProvider(0.25, frames: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let first = makeAudioItem(filePath: "a", layer: 0)
        let second = makeAudioItem(filePath: "b", layer: 1)
        let timeline = makeTimeline(items: [first, second])
        let mixer = TimelineAudioMixer(timeline: timeline, factory: sourceFactory)
        XCTAssertEqual(mixer.duration, 96_000)

        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        XCTAssertEqual(buffer[0], 0.75, accuracy: 1e-6)
        XCTAssertEqual(buffer[95_999], 0.75, accuracy: 1e-6)

        // レイヤー音量 50% のレイヤーは半分になる。
        timeline.layerSettings.items = [LayerSetting(layer: 1, volume: 50)]
        mixer.seek(to: 0)
        var halved = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &halved, offset: 0, count: 96_000), 96_000)
        XCTAssertEqual(halved[0], 0.625, accuracy: 1e-6)
    }

    func testMixerIntervalBoundaries() {
        let factory = MapProviderFactory()
        factory.providers["a"] = constantProvider(0.8, frames: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        // 1 秒目から 1 秒間だけ鳴るアイテム。タイムラインは 2 秒。
        let item = makeAudioItem(filePath: "a", frame: 30, length: 30)
        let spacer = makeAudioItem(filePath: "a", frame: 0, length: 60)
        spacer.isHidden = true
        let timeline = makeTimeline(items: [spacer, item])
        XCTAssertEqual(timeline.length, 60)
        let mixer = TimelineAudioMixer(timeline: timeline, factory: sourceFactory)

        var buffer = [Float](repeating: 0, count: 192_000)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 192_000), 192_000)
        XCTAssertEqual(buffer[0], 0)
        XCTAssertEqual(buffer[95_999], 0)
        XCTAssertEqual(buffer[96_000], 0.8, accuracy: 1e-6)
        XCTAssertEqual(buffer[191_999], 0.8, accuracy: 1e-6)

        // 途中へシークしても同じ区間が得られる。
        mixer.seek(to: 96_000)
        var tail = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &tail, offset: 0, count: 96_000), 96_000)
        XCTAssertEqual(tail[0], 0.8, accuracy: 1e-6)
    }

    func testMixerExcludesHiddenLayer() {
        let factory = MapProviderFactory()
        factory.providers["a"] = constantProvider(0.8, frames: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "a", layer: 3)
        let timeline = makeTimeline(items: [item])
        timeline.layerSettings.items = [LayerSetting(layer: 3, isHidden: true)]
        let mixer = TimelineAudioMixer(timeline: timeline, factory: sourceFactory)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0 })
    }

    // MARK: - グループバス

    func testGroupBusRoutesFullyOwnedItem() {
        let factory = MapProviderFactory()
        factory.providers["a"] = constantProvider(0.6, frames: 48_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let group = GroupItem()
        group.frame = 0
        group.length = 30
        group.layer = 0
        group.groupRange = 50
        group.isAudioComposite = true
        let child = makeAudioItem(filePath: "a", frame: 0, length: 30, layer: 1)
        let timeline = makeTimeline(items: [group, child])

        let resolver = AudioGroupResolver(items: timeline.items) { _ in true }
        let segments = resolver.segments(for: child)
        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].owner === group)

        let mixer = TimelineAudioMixer(timeline: timeline, factory: sourceFactory)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        // バス経由で 1 回だけ鳴る（二重加算なら 1.2 になる）。
        XCTAssertEqual(buffer[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(buffer[95_999], 0.6, accuracy: 1e-6)
    }

    func testGroupBusPartialOverlapSplitsAtBoundary() {
        let factory = MapProviderFactory()
        factory.providers["a"] = constantProvider(0.6, frames: 96_000)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let group = GroupItem()
        group.frame = 0
        group.length = 30
        group.layer = 0
        group.groupRange = 50
        group.isAudioComposite = true
        // 0.5 秒〜1.5 秒のアイテム。前半はバス、後半はトップレベル。
        let child = makeAudioItem(filePath: "a", frame: 15, length: 30, layer: 1)
        let timeline = makeTimeline(items: [group, child])
        XCTAssertEqual(timeline.length, 45)

        let mixer = TimelineAudioMixer(timeline: timeline, factory: sourceFactory)
        var buffer = [Float](repeating: 0, count: 144_000)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 144_000), 144_000)
        XCTAssertEqual(buffer[0], 0)                        // アイテム開始前
        XCTAssertEqual(buffer[48_000], 0.6, accuracy: 1e-6)  // バス区間（0.5 秒〜）
        XCTAssertEqual(buffer[95_999], 0.6, accuracy: 1e-6)
        XCTAssertEqual(buffer[96_000], 0.6, accuracy: 1e-6)  // トップレベル区間（1 秒〜）
        XCTAssertEqual(buffer[143_999], 0.6, accuracy: 1e-6)
    }

    // MARK: - シーン / ボイス

    func testSceneItemPullsNestedTimeline() {
        let factory = MapProviderFactory()
        factory.providers["a"] = constantProvider(0.4, frames: 48_000)
        let nestedItem = makeAudioItem(filePath: "a")
        let nested = makeTimeline(items: [nestedItem])
        let sourceFactory = AudioSourceFactory(
            providerFactory: factory,
            sceneTimelineResolver: { _ in nested }
        )
        let sceneItem = SceneItem()
        sceneItem.frame = 0
        sceneItem.length = 30
        sceneItem.volume = constantAnimation(100)
        let timeline = makeTimeline(items: [sceneItem])
        let mixer = TimelineAudioMixer(timeline: timeline, factory: sourceFactory)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        XCTAssertEqual(buffer[0], 0.4, accuracy: 1e-6)
        XCTAssertEqual(buffer[95_999], 0.4, accuracy: 1e-6)
    }

    func testVoiceItemThroughUpsampler() {
        let factory = MapProviderFactory()
        let sourceFactory = AudioSourceFactory(
            providerFactory: factory,
            voiceProviderResolver: { _ in constantProvider(0.3, frames: 24_000, hz: 24_000) }
        )
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 30
        voice.volume = constantAnimation(100)
        voice.pan = constantAnimation(0)
        let timeline = makeTimeline(items: [voice])
        let mixer = TimelineAudioMixer(timeline: timeline, factory: sourceFactory)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        // 24kHz → 48kHz のアップサンプリングを経ても DC は保たれる
        // （境界付近の過渡を避けて中央で確認）。
        XCTAssertEqual(buffer[48_000], 0.3, accuracy: 1e-3)
        XCTAssertEqual(buffer[60_000], 0.3, accuracy: 1e-3)
    }
}
