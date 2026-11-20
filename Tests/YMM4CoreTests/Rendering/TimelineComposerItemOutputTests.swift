import XCTest
@testable import YMM4Core

/// BoundsQuadProviding に適合する偽の DrawingEffect（FE-R1-023-B）。
/// 独自四隅の有無・返す四隅・確定説明へ書き込む回転を差し替えられる。
private final class QuadFakeDrawingEffect: DrawingEffectProcessor, BoundsQuadProviding {
    var output: ImageReference? = ImageReference(label: "quad-de-out")
    var providesCustomBoundsQuad = false
    var quadResult: [Vector2]?
    var rotationZ: Double = 0

    func setInput(_ image: ImageReference?) {}
    func clearInput() {}
    func update(_ description: EffectDescription) throws -> DrawDescription {
        var result = description.drawDescription
        result.rotation.z = rotationZ
        return result
    }
    func boundsQuad() -> [Vector2]? { quadResult }
    func dispose() {}
}

/// TimelineComposer.itemOutputs（FE-R1-023-A）の契約:
/// 直近の Update で描画されたアイテム別の出力を、描画順（背面から
/// 前面）のまま、タイムライン内インデックスつきで公開する。
/// 本家 TimelineItemRects の材料に相当し、TransitionItem は本家
/// どおり除外する。描画出力の無いアイテムは、代替描画のトークンが
/// 存在しても hasDrawnContent が false になり、当たり判定可能な
/// 矩形として扱われないことが分かる形にする（監査の検証条件）。
final class TimelineComposerItemOutputTests: XCTestCase {

    private final class Fixture {
        let log = CompositionEventLog()
        let factory: RecordingTargetFactory
        let provider = FakeEffectProvider()
        let timeline = Timeline()
        var sources: [ObjectIdentifier: any Source] = [:]

        init() {
            factory = RecordingTargetFactory(log: log)
        }

        func registerSource(_ source: any Source, for item: BaseItem & VideoItemProperties) {
            sources[ObjectIdentifier(item)] = source
        }

        func makeComposer() -> TimelineComposer {
            let sources = sources
            let provider = provider
            let factory = factory
            return TimelineComposer(
                scene: TimelineScene(timeline: timeline),
                targetFactory: factory,
                sourceProvider: { item in
                    if let source = sources[ObjectIdentifier(item)] {
                        return source
                    }
                    let source = FakeChainSource()
                    source.outputs = [StandardSourceOutput(
                        output: ImageReference(label: "img"),
                        drawingEffect: CompositionFakeDrawingEffect(
                            name: "DE", log: CompositionEventLog()
                        )
                    )]
                    return source
                },
                effectProvider: provider
            )
        }
    }

    private func makeSource(log: CompositionEventLog, imageLabel: String) -> FakeChainSource {
        let source = FakeChainSource()
        source.outputs = [StandardSourceOutput(
            output: ImageReference(label: imageLabel),
            drawingEffect: CompositionFakeDrawingEffect(name: "DE-\(imageLabel)", log: log)
        )]
        return source
    }

    /// 描画順（レイヤー昇順 = 背面から前面）と、タイムライン内
    /// インデックスの対応が保たれる。タイムラインの並びと描画順を
    /// わざと逆にして、両者が混同されていないことを固定する。
    func testItemOutputsFollowDrawOrderAndCarryTimelineIndices() throws {
        let fixture = Fixture()
        let front = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 5)
        let back = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [front, back]
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(composer.itemOutputs.count, 2)
        // 背面（レイヤー 0 = タイムラインのインデックス 1）が先。
        XCTAssertEqual(composer.itemOutputs[0].itemIndex, 1)
        // 前面（レイヤー 5 = タイムラインのインデックス 0）が後。
        XCTAssertEqual(composer.itemOutputs[1].itemIndex, 0)
        XCTAssertTrue(composer.itemOutputs.allSatisfy { $0.hasDrawnContent })
        XCTAssertTrue(composer.itemOutputs.allSatisfy { $0.output != nil })
    }

    /// 出力が0件のアイテムは、代替描画（透明な 1×1 矩形）の
    /// トークンが存在しても描画内容なしとして区別できる
    /// （監査の検証条件: 描画出力が無いアイテムを当たり判定可能な
    /// 矩形として扱わない）。
    func testItemWithNoSourceOutputsHasNoDrawnContent() throws {
        let fixture = Fixture()
        let empty = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        let normal = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 1)
        fixture.timeline.items = [empty, normal]
        let emptySource = FakeChainSource()
        emptySource.outputs = []
        fixture.registerSource(emptySource, for: empty)
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(composer.itemOutputs.count, 2)
        let emptyOutput = composer.itemOutputs.first { $0.itemIndex == 0 }
        XCTAssertNotNil(emptyOutput)
        // 代替描画のトークンは存在するが、内容は描かれていない。
        XCTAssertNotNil(emptyOutput?.output)
        XCTAssertEqual(emptyOutput?.hasDrawnContent, false)
        let normalOutput = composer.itemOutputs.first { $0.itemIndex == 1 }
        XCTAssertEqual(normalOutput?.hasDrawnContent, true)
    }

    /// TransitionItem は本家 TimelineItemRects どおり除外される。
    /// テキストはトランジションより上のレイヤーに置く（ピッカーの
    /// トランジション規則で、最大トランジション層より下のアイテム
    /// は描画対象自体から外れるため）。
    func testTransitionItemIsExcluded() throws {
        let fixture = Fixture()
        let transition = TransitionItem()
        transition.frame = 0
        transition.length = 90
        transition.layer = 5
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 10)
        fixture.timeline.items = [transition, item]
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(composer.itemOutputs.count, 1)
        XCTAssertEqual(composer.itemOutputs.first?.itemIndex, 1)
    }

    /// フレーム範囲外のアイテムは含まれず、範囲に入ると現れる。
    func testOutOfFrameItemIsNotIncluded() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 60, length: 30, layer: 0)
        fixture.timeline.items = [item]
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)
        XCTAssertTrue(composer.itemOutputs.isEmpty)

        // フレーム 60（2秒）では範囲内になる。
        try composer.update(time: TimeSpanValue(seconds: 2), usage: .paused)
        XCTAssertEqual(composer.itemOutputs.count, 1)
        XCTAssertEqual(composer.itemOutputs.first?.itemIndex, 0)
    }

    /// 当たり判定用の四隅（FE-R1-023-B）: 回転・カメラ・独自四隅の
    /// いずれも無いアイテムでは quad は nil になる（本家
    /// GetTransformedBoundsQuad のゲート。消費側は矩形の四隅で
    /// 代替する）。
    func testQuadIsNilWhenGateIsClosed() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [item]
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(composer.itemOutputs.count, 1)
        XCTAssertNil(composer.itemOutputs.first?.quad)
    }

    /// 独自四隅を持つ DrawingEffect（マスク等）では、回転が無くても
    /// 四隅がそのまま運ばれる。
    func testCustomProviderQuadIsCarriedWithoutRotation() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [item]
        let effect = QuadFakeDrawingEffect()
        effect.providesCustomBoundsQuad = true
        effect.quadResult = Self.sampleQuad
        let source = FakeChainSource()
        source.outputs = [StandardSourceOutput(
            output: ImageReference(label: "img"), drawingEffect: effect
        )]
        fixture.registerSource(source, for: item)
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(composer.itemOutputs.first?.quad, Self.sampleQuad)
    }

    /// 通常の DrawingEffect でも、回転がある場合は四隅が運ばれる
    /// （ゲートは確定説明の回転で開く）。
    func testStandardProviderQuadIsCarriedWhenRotated() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [item]
        let effect = QuadFakeDrawingEffect()
        effect.rotationZ = 30
        effect.quadResult = Self.sampleQuad
        let source = FakeChainSource()
        source.outputs = [StandardSourceOutput(
            output: ImageReference(label: "img"), drawingEffect: effect
        )]
        fixture.registerSource(source, for: item)
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(composer.itemOutputs.first?.quad, Self.sampleQuad)
    }

    /// ゲートが開いても、DrawingEffect が四隅を返せない場合は
    /// アイテム全体の四隅が nil になる（本家は null を返す）。
    func testProviderReturningNilQuadMakesItemQuadNil() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [item]
        let effect = QuadFakeDrawingEffect()
        effect.providesCustomBoundsQuad = true
        effect.quadResult = nil
        let source = FakeChainSource()
        source.outputs = [StandardSourceOutput(
            output: ImageReference(label: "img"), drawingEffect: effect
        )]
        fixture.registerSource(source, for: item)
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(composer.itemOutputs.count, 1)
        XCTAssertNil(composer.itemOutputs.first?.quad)
    }

    /// 出力が複数のアイテムでは、各出力の四隅が最初の四隅の
    /// 局所座標系で統合されて運ばれる（本家 UnionQuads）。
    func testMultipleOutputsQuadIsUnioned() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [item]
        let first = QuadFakeDrawingEffect()
        first.providesCustomBoundsQuad = true
        first.quadResult = [
            Vector2(x: 0, y: 0), Vector2(x: 10, y: 0),
            Vector2(x: 10, y: 10), Vector2(x: 0, y: 10),
        ]
        let second = QuadFakeDrawingEffect()
        second.providesCustomBoundsQuad = true
        second.quadResult = [
            Vector2(x: 20, y: 0), Vector2(x: 30, y: 0),
            Vector2(x: 30, y: 10), Vector2(x: 20, y: 10),
        ]
        let source = FakeChainSource()
        source.outputs = [
            StandardSourceOutput(
                output: ImageReference(label: "img-1"), drawingEffect: first
            ),
            StandardSourceOutput(
                output: ImageReference(label: "img-2"), drawingEffect: second
            ),
        ]
        fixture.registerSource(source, for: item)
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(composer.itemOutputs.first?.quad, [
            Vector2(x: 0, y: 0), Vector2(x: 30, y: 0),
            Vector2(x: 30, y: 10), Vector2(x: 0, y: 10),
        ])
    }

    private static let sampleQuad: [Vector2] = [
        Vector2(x: -50, y: -25), Vector2(x: 50, y: -25),
        Vector2(x: 50, y: 25), Vector2(x: -50, y: 25),
    ]

    /// Update が失敗した場合、itemOutputs は前回の成功時の値のまま
    /// 残る（消費側は Update の成否と組で読む契約）。
    func testFailedUpdateKeepsPreviousItemOutputs() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [item]
        let source = makeSource(log: fixture.log, imageLabel: "img")
        fixture.registerSource(source, for: item)
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)
        XCTAssertEqual(composer.itemOutputs.count, 1)

        source.errorOnUpdate = FakeError()
        XCTAssertThrowsError(try composer.update(time: .zero, usage: .paused))
        XCTAssertEqual(composer.itemOutputs.count, 1)
        XCTAssertEqual(composer.itemOutputs.first?.itemIndex, 0)
    }
}
