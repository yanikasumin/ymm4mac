import XCTest
@testable import YMM4Core

// MAC-0019: エフェクト定義層のコーデック／合成への接続の検証。
//
// 保持形式は生保持（[PreservedObject]）のままとし、型付き復元は消費側
// （TypedEffectPairProvider）で行う。ここでは
// - TimelineComposer / EffectedItemSource の既定の供給元が型付き供給元に
//   なっていて、既知エフェクトが実際に連鎖へ適用されること
// - 定義へ所有アイテムのキーフレーム文脈が伝播し、変更時に再伝播すること
// - コーデック往復（固定点）が接続後も変わらないこと
// を確認する。

private func makeDescription(
    itemFrame: Int = 0, itemLength: Int = 90
) -> TimelineItemSourceDescription {
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 1920, height: 1080),
        timelinePosition: FramePosition(frame: itemFrame, fps: 30),
        timelineDuration: FramePosition(frame: 900, fps: 30),
        fps: 30,
        usage: .paused,
        sceneId: UUID(),
        scenes: []
    )
    return TimelineItemSourceDescription(
        base, itemFrame: itemFrame, itemLength: itemLength, layer: 0
    )
}

/// 不透明度エフェクト（乗算 50%）の生保持オブジェクト。定義の encode で
/// 作るため、レジストリの decode が確実に受け付ける形になる。
private func opacityEffectRaw() -> PreservedObject {
    let definition = OpacityEffectDefinition()
    definition.opacity.values = [AnimationValue(50)]
    return VideoEffectRegistry.encode(definition)
}

private func zoomEffectRaw() -> PreservedObject {
    let definition = ZoomEffectDefinition()
    definition.zoom.values = [AnimationValue(100), AnimationValue(200)]
    return VideoEffectRegistry.encode(definition)
}

// MARK: - 既定の供給元による連鎖適用

final class EffectWiringTests: XCTestCase {

    func testDefaultProviderAppliesTypedEffectInChain() throws {
        let item = TextItem()
        item.frame = 0
        item.length = 90
        item.layer = 0
        item.videoEffects = [opacityEffectRaw()]

        let source = StubSource()
        source.outputs = [StandardSourceOutput(
            output: ImageReference(label: "src"),
            drawingEffect: PassThroughDrawingEffect()
        )]

        // effectProvider を渡さない（既定 = TypedEffectPairProvider）。
        let effected = EffectedItemSource(
            item: item, source: source, targetFactory: StubTargetFactory()
        )
        try effected.update(makeDescription())
        // アイテム不透明度 100% × エフェクト 50%（乗算）。
        XCTAssertEqual(effected.drawDescription.opacity, 0.5, accuracy: 1e-9)

        // 対照: 素通しの供給元ではエフェクトは効かない。
        let bypassed = EffectedItemSource(
            item: item, source: source, targetFactory: StubTargetFactory(),
            effectProvider: EmptyEffectPairProvider()
        )
        try bypassed.update(makeDescription())
        XCTAssertEqual(bypassed.drawDescription.opacity, 1.0, accuracy: 1e-9)
    }

    func testDefaultComposerRunsGroupAndOwnPairs() throws {
        let timeline = Timeline()
        let group = GroupItem()
        group.frame = 0
        group.length = 90
        group.layer = 0
        group.groupRange = 50
        group.isComposite = false
        group.videoEffects = [opacityEffectRaw()]
        let text = TextItem()
        text.frame = 0
        text.length = 90
        text.layer = 1
        text.videoEffects = [zoomEffectRaw()]
        timeline.items = [group, text]

        // effectProvider を渡さない（既定 = TypedEffectPairProvider）。
        // グループの親エフェクト供給と GroupedDrawing の自動追加を含む
        // 一連の合成が例外なく完了することを確認する。
        let composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: StubTargetFactory(),
            sourceProvider: { _ in
                let source = StubSource()
                source.outputs = [StandardSourceOutput(
                    output: ImageReference(label: "src"),
                    drawingEffect: PassThroughDrawingEffect()
                )]
                return source
            }
        )
        try composer.update(time: .zero, usage: .paused)
        XCTAssertNotNil(composer.output)
    }

    // MARK: - キーフレーム文脈の伝播

    func testKeyFramesPropagateToDefinitionsAndRepropagateOnChange() {
        let provider = TypedEffectPairProvider()

        let item = TextItem()
        item.keyFrames = KeyFrames(frames: [0, 45])
        item.videoEffects = [zoomEffectRaw()]
        let pairs = provider.ownEffectPairs(for: item)
        XCTAssertEqual(pairs.count, 1)
        let zoom = pairs[0].definition as? ZoomEffectDefinition
        XCTAssertNotNil(zoom)
        XCTAssertEqual(zoom?.zoom.keyFrames.frames, [0, 45])

        // 所有アイテムの KeyFrames が変わったら、同じ定義インスタンスへ
        // 再伝播される（定義は作り直されない）。
        item.keyFrames = KeyFrames(frames: [10, 20, 30])
        let pairs2 = provider.ownEffectPairs(for: item)
        XCTAssertTrue(pairs[0].definition as AnyObject === pairs2[0].definition as AnyObject)
        XCTAssertEqual(zoom?.zoom.keyFrames.frames, [10, 20, 30])

        // グループの自前エフェクトにはグループの KeyFrames が届く。
        let group = GroupItem()
        group.keyFrames = KeyFrames(frames: [5])
        group.videoEffects = [opacityEffectRaw()]
        let groupPairs = provider.groupEffectPairs(for: group, childIndex: 0, childCount: 1)
        let opacity = groupPairs[0].definition as? OpacityEffectDefinition
        XCTAssertNotNil(opacity)
        XCTAssertEqual(opacity?.opacity.keyFrames.frames, [5])

        // 顔エフェクトには顔アイテムの KeyFrames が届く。
        let face = TachieFaceItem()
        face.keyFrames = KeyFrames(frames: [7])
        face.tachieFaceEffects = [zoomEffectRaw()]
        let facePairs = provider.faceEffectPairs(for: face)
        let faceZoom = facePairs[0].definition as? ZoomEffectDefinition
        XCTAssertNotNil(faceZoom)
        XCTAssertEqual(faceZoom?.zoom.keyFrames.frames, [7])
    }

    // MARK: - コーデック往復と消費側復元

    func testCodecRoundTripKeepsRawHoldingAndProviderDecodes() throws {
        let project = Project()
        let timeline = Timeline()
        let text = TextItem()
        text.frame = 0
        text.length = 90
        text.layer = 0
        text.videoEffects = [
            opacityEffectRaw(),
            PreservedObject(.object([
                (key: "$type", value: .string("Some.Plugin.Effect, SomePlugin")),
                (key: "Custom", value: .number(1.5)),
            ])),
        ]
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 90
        voice.layer = 1
        voice.videoEffects = [zoomEffectRaw()]
        timeline.items = [text, voice]
        project.timelines.append(timeline)

        let text1 = YmmpCodec.encode(project)
        let (decoded, _) = try YmmpCodec.decode(text1)
        let decodedText = decoded.timelines[0].items[0] as? TextItem
        XCTAssertNotNil(decodedText)
        // 保持は生保持のまま（既知・未知とも要素がそのまま残る）。
        XCTAssertEqual(decodedText?.videoEffects.count, 2)

        // 消費側では既知だけが型付きで復元され、未知は連鎖へ出ない。
        let provider = TypedEffectPairProvider()
        let pairs = provider.ownEffectPairs(for: decodedText!)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(pairs[0].definition is OpacityEffectDefinition)

        // VoiceItem の JimakuVideoEffects も自前エフェクトとして復元される。
        let decodedVoice = decoded.timelines[0].items[1] as? VoiceItem
        XCTAssertNotNil(decodedVoice)
        let voicePairs = provider.ownEffectPairs(for: decodedVoice!)
        XCTAssertEqual(voicePairs.count, 1)
        XCTAssertTrue(voicePairs[0].definition is ZoomEffectDefinition)

        // 固定点: 接続後もエンコード結果は変わらない。
        let text2 = YmmpCodec.encode(decoded)
        XCTAssertEqual(text1, text2)
        XCTAssertTrue(text2.contains("Some.Plugin.Effect, SomePlugin"))
    }
}
