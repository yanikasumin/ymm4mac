import XCTest
@testable import YMM4Core

// MARK: - 偽の実装（合成実行部の検証用）

private final class EventLog {
    var events: [String] = []
    func add(_ event: String) { events.append(event) }
    func index(of event: String) -> Int? { events.firstIndex(of: event) }
}

private struct FakeError: Error {}

/// 連鎖の処理器。呼び出しを共有ログへ記録し、DrawDescription の Z を
/// 決まった量だけ書き換える（連鎖的な書き換えの確認用）。
private final class FakeChainProcessor: VideoEffectProcessor {
    let name: String
    let log: EventLog
    var output: ImageReference?
    var zDelta: Double = 0
    var errorOnUpdate: Error?
    private(set) var setInputCalls: [ImageReference?] = []
    private(set) var updateDescriptions: [EffectDescription] = []
    private(set) var disposed = false

    init(name: String, log: EventLog) {
        self.name = name
        self.log = log
        self.output = ImageReference(label: "\(name)-out")
    }

    func setInput(_ image: ImageReference?) {
        setInputCalls.append(image)
        log.add("\(name).setInput")
    }

    func clearInput() {
        log.add("\(name).clearInput")
    }

    func update(_ description: EffectDescription) throws -> DrawDescription {
        log.add("\(name).update")
        updateDescriptions.append(description)
        if let errorOnUpdate { throw errorOnUpdate }
        var result = description.drawDescription
        result.draw.z += zDelta
        return result
    }

    func dispose() {
        disposed = true
        log.add("\(name).dispose")
    }
}

private final class FakeDefinition: VideoEffectDefinition {
    let name: String
    let log: EventLog
    var isEnabled = true
    var zDelta: Double = 0
    var errorOnUpdate: Error?
    private(set) var processors: [FakeChainProcessor] = []

    init(name: String, log: EventLog) {
        self.name = name
        self.log = log
    }

    func createProcessor() -> any VideoEffectProcessor {
        log.add("\(name).createProcessor")
        let processor = FakeChainProcessor(name: name, log: log)
        processor.zDelta = zDelta
        processor.errorOnUpdate = errorOnUpdate
        processors.append(processor)
        return processor
    }
}

/// DrawingEffect（アイテム変形）の偽実装。
private final class FakeDrawingEffect: DrawingEffectProcessor {
    let name: String
    let log: EventLog
    var output: ImageReference?
    var errorOnUpdate: Error?
    private(set) var setInputCalls: [ImageReference?] = []
    private(set) var updateCount = 0

    init(name: String, log: EventLog) {
        self.name = name
        self.log = log
        self.output = ImageReference(label: "\(name)-out")
    }

    func setInput(_ image: ImageReference?) {
        setInputCalls.append(image)
        log.add("\(name).setInput")
    }

    func clearInput() {}

    func update(_ description: EffectDescription) throws -> DrawDescription {
        updateCount += 1
        if let errorOnUpdate { throw errorOnUpdate }
        return description.drawDescription
    }

    func dispose() {}
}

private final class FakeChainSource: Source {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    var errorOnUpdate: Error?
    private(set) var updateCount = 0
    private(set) var lastDescription: TimelineItemSourceDescription?
    private(set) var disposed = false

    func update(_ description: TimelineItemSourceDescription) throws {
        updateCount += 1
        lastDescription = description
        if let errorOnUpdate { throw errorOnUpdate }
    }

    func dispose() {
        disposed = true
    }
}

private final class FakeFrameBufferSource: FrameBufferSource {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    var input: ImageReference?
    var frameSize = PixelSize(width: 0, height: 0)
    var clearBackground = true
    private(set) var updateCount = 0
    private(set) var lastDescription: TimelineItemSourceDescription?
    private(set) var disposed = false

    func update(_ description: TimelineItemSourceDescription) throws {
        updateCount += 1
        lastDescription = description
    }

    func dispose() {
        disposed = true
    }
}

private final class FakeTachieSource: TachieSource {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    var activeVoice: VoiceItem?
    var activeFaces: [any FaceItem] = []
    private(set) var disposed = false

    func update(_ description: TimelineItemSourceDescription) throws {}

    func dispose() {
        disposed = true
    }
}

/// 描画先の記録用実装。自身の操作列（ops）と共有ログの両方へ残す。
private final class RecordingRenderTarget: RenderTarget {
    let image: ImageReference
    let name: String
    let log: EventLog
    private(set) var ops: [String] = []
    private(set) var disposed = false

    init(name: String, log: EventLog) {
        self.name = name
        self.log = log
        self.image = ImageReference(label: name)
    }

    private func record(_ op: String) {
        ops.append(op)
        log.add("\(name).\(op)")
    }

    func beginDraw() { record("begin") }
    func clear() { record("clear") }

    func fillRect(_ rect: RectF, color: Color) {
        record("fillRect(\(rect.left),\(rect.top),\(rect.right),\(rect.bottom),a=\(color.alpha))")
    }

    func drawImage(_ image: ImageReference) {
        record("draw(\(image.label))")
    }

    func drawImage(_ image: ImageReference, blend: Blend, interpolation: InterpolationMode) {
        record("drawBlend(\(image.label))")
    }

    func endDraw() { record("end") }
    func close() { record("close") }

    func dispose() {
        disposed = true
        record("dispose")
    }
}

private final class RecordingTargetFactory: RenderTargetFactory {
    let log: EventLog
    private(set) var targets: [RecordingRenderTarget] = []

    init(log: EventLog) {
        self.log = log
    }

    func makeTarget() -> any RenderTarget {
        let target = RecordingRenderTarget(name: "T\(targets.count + 1)", log: log)
        targets.append(target)
        return target
    }
}

private final class FakeEffectProvider: EffectPairProvider {
    var ownPairs: [ObjectIdentifier: [EffectPair]] = [:]
    /// グループごとの定義列。組は呼び出し時に渡された子位置・子総数で構築する
    /// （実物の供給元と同じ作法）。
    var groupDefinitions: [ObjectIdentifier: [any VideoEffectDefinition]] = [:]
    var facePairs: [ObjectIdentifier: [EffectPair]] = [:]
    private(set) var groupCalls: [(group: GroupItem, childIndex: Int, childCount: Int)] = []

    func ownEffectPairs(for item: BaseItem & VideoItemProperties) -> [EffectPair] {
        ownPairs[ObjectIdentifier(item)] ?? []
    }

    func groupEffectPairs(for group: GroupItem, childIndex: Int, childCount: Int) -> [EffectPair] {
        groupCalls.append((group, childIndex, childCount))
        return (groupDefinitions[ObjectIdentifier(group)] ?? []).map {
            EffectPair(timeSource: group, definition: $0, groupIndex: childIndex, groupCount: childCount)
        }
    }

    func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair] {
        facePairs[ObjectIdentifier(faceItem)] ?? []
    }
}

private final class FakeAlphaMask: AlphaMaskEffect {
    var output: ImageReference? = ImageReference(label: "mask-out")
    private(set) var inputs: [Int: ImageReference?] = [:]
    private(set) var disposed = false

    func setInput(_ index: Int, _ image: ImageReference?) {
        inputs[index] = image
    }

    func dispose() {
        disposed = true
    }
}

private final class FakeAlphaMaskFactory: AlphaMaskEffectFactory {
    private(set) var masks: [FakeAlphaMask] = []

    func makeAlphaMaskEffect() -> any AlphaMaskEffect {
        let mask = FakeAlphaMask()
        masks.append(mask)
        return mask
    }
}

private func makeItemDescription(
    timelineFrame: Int = 0, itemFrame: Int = 0, itemLength: Int = 90, layer: Int = 0
) -> TimelineItemSourceDescription {
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 1920, height: 1080),
        timelinePosition: FramePosition(frame: timelineFrame, fps: 30),
        timelineDuration: FramePosition(frame: 900, fps: 30),
        fps: 30,
        usage: .paused,
        sceneId: UUID(),
        scenes: []
    )
    return TimelineItemSourceDescription(base, itemFrame: itemFrame, itemLength: itemLength, layer: layer)
}

private func makeVisualItem<T: VisualItem>(
    _ item: T, frame: Int = 0, length: Int = 90, layer: Int = 0, group: Int = 0
) -> T {
    item.frame = frame
    item.length = length
    item.layer = layer
    item.group = group
    return item
}

// MARK: - EffectedItemSource（連鎖）

final class EffectedItemSourceTests: XCTestCase {

    private struct Fixture {
        let log = EventLog()
        let factory: RecordingTargetFactory
        let provider = FakeEffectProvider()
        let item: TextItem
        let source = FakeChainSource()
        let drawingEffect: FakeDrawingEffect
        let sourceImage = ImageReference(label: "src-img")

        init() {
            factory = RecordingTargetFactory(log: log)
            item = makeVisualItem(TextItem())
            drawingEffect = FakeDrawingEffect(name: "DE", log: log)
            source.outputs = [StandardSourceOutput(output: sourceImage, drawingEffect: drawingEffect)]
        }

        func makeEffected(applyItemTransform: Bool = true) -> EffectedItemSource {
            EffectedItemSource(
                item: item,
                source: source,
                targetFactory: factory,
                effectProvider: provider,
                applyItemTransform: applyItemTransform
            )
        }
    }

    func testChainReuseSkipsSetInputWhenInputUnchanged() throws {
        let fixture = Fixture()
        let definition = FakeDefinition(name: "A", log: fixture.log)
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definition),
        ]
        let effected = fixture.makeEffected()

        try effected.update(makeItemDescription())
        try effected.update(makeItemDescription(itemFrame: 1))

        // 処理器は1回だけ生成され、入力参照が同じ間は SetInput を再発行しない。
        // Update は毎回呼ばれる。
        XCTAssertEqual(definition.processors.count, 1)
        XCTAssertEqual(definition.processors[0].setInputCalls.count, 1)
        XCTAssertEqual(definition.processors[0].updateDescriptions.count, 2)
    }

    func testChainReplacementDisposesOldAfterNewUpdate() throws {
        let fixture = Fixture()
        let definitionA = FakeDefinition(name: "A", log: fixture.log)
        let definitionB = FakeDefinition(name: "B", log: fixture.log)
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definitionA),
        ]
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())

        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definitionB),
        ]
        try effected.update(makeItemDescription(itemFrame: 1))

        // 新しい処理器の SetInput → Update が完了してから旧処理器が破棄される。
        let log = fixture.log
        let newUpdate = try XCTUnwrap(log.index(of: "B.update"))
        let oldClear = try XCTUnwrap(log.index(of: "A.clearInput"))
        let oldDispose = try XCTUnwrap(log.index(of: "A.dispose"))
        XCTAssertLessThan(newUpdate, oldClear)
        XCTAssertLessThan(oldClear, oldDispose)
        XCTAssertTrue(definitionA.processors[0].disposed)
    }

    func testChainDrawDescriptionChaining() throws {
        let fixture = Fixture()
        let definitionA = FakeDefinition(name: "A", log: fixture.log)
        definitionA.zDelta = 10
        let definitionB = FakeDefinition(name: "B", log: fixture.log)
        definitionB.zDelta = 20
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definitionA),
            EffectPair(timeSource: fixture.item, definition: definitionB),
        ]
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())

        // 各段の Update の戻り値が次段へ渡り、最終値が DrawDescription になる。
        XCTAssertEqual(definitionB.processors[0].updateDescriptions[0].drawDescription.draw.z, 10)
        XCTAssertEqual(effected.drawDescription.draw.z, 30)
    }

    func testChainSetInputReissuedWhenInputChanges() throws {
        let fixture = Fixture()
        let definition = FakeDefinition(name: "A", log: fixture.log)
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definition),
        ]
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())

        // Source の出力画像が差し替わると、再利用でも SetInput が再発行される。
        let newImage = ImageReference(label: "src-img-2")
        fixture.source.outputs = [StandardSourceOutput(output: newImage, drawingEffect: fixture.drawingEffect)]
        try effected.update(makeItemDescription(itemFrame: 1))

        XCTAssertEqual(definition.processors.count, 1)
        XCTAssertEqual(definition.processors[0].setInputCalls.count, 2)
        XCTAssertTrue(definition.processors[0].setInputCalls[1] === newImage)
    }

    func testChainShrinkDisposesTail() throws {
        let fixture = Fixture()
        let definitionA = FakeDefinition(name: "A", log: fixture.log)
        let definitionB = FakeDefinition(name: "B", log: fixture.log)
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definitionA),
            EffectPair(timeSource: fixture.item, definition: definitionB),
        ]
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())

        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definitionA),
        ]
        try effected.update(makeItemDescription(itemFrame: 1))

        // 縮小は末尾から: B の処理器だけが ClearInput → Dispose される。
        XCTAssertTrue(definitionB.processors[0].disposed)
        XCTAssertFalse(definitionA.processors[0].disposed)
        XCTAssertEqual(definitionA.processors.count, 1)
    }

    func testDisabledEffectIsSkipped() throws {
        let fixture = Fixture()
        let definition = FakeDefinition(name: "A", log: fixture.log)
        definition.isEnabled = false
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definition),
        ]
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())

        XCTAssertEqual(definition.processors.count, 0)
        XCTAssertNotNil(effected.output)
    }

    func testZeroOutputsProducesValidOutput() throws {
        let fixture = Fixture()
        fixture.source.outputs = []
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())

        // 出力0件でも有効な出力参照を返し、透明な 1x1 矩形が描かれる。
        XCTAssertNotNil(effected.output)
        XCTAssertEqual(effected.drawDescription.opacity, 0)
        let target = fixture.factory.targets[0]
        XCTAssertTrue(target.ops.contains("fillRect(0.0,0.0,1.0,1.0,a=0)"))
    }

    func testSourceFailureKeepsOldOutput() throws {
        let fixture = Fixture()
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())
        let firstOutput = effected.output

        fixture.source.errorOnUpdate = FakeError()
        XCTAssertThrowsError(try effected.update(makeItemDescription(itemFrame: 1)))
        // Source.Update の失敗では UpdateEffects へ進まず、旧 Output は無事。
        XCTAssertTrue(effected.output === firstOutput)
        XCTAssertFalse(fixture.factory.targets[0].disposed)
    }

    func testChainFailureKeepsOldOutput() throws {
        let fixture = Fixture()
        let definition = FakeDefinition(name: "A", log: fixture.log)
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definition),
        ]
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())
        let firstOutput = effected.output

        definition.processors[0].errorOnUpdate = FakeError()
        XCTAssertThrowsError(try effected.update(makeItemDescription(itemFrame: 1))) { error in
            // 連鎖途中の失敗は包まれず、そのまま伝播する。
            XCTAssertTrue(error is FakeError)
        }
        XCTAssertTrue(effected.output === firstOutput)
        XCTAssertFalse(fixture.factory.targets[0].disposed)
    }

    func testDrawingEffectFailureIsWrapped() throws {
        let fixture = Fixture()
        let definition = FakeDefinition(name: "A", log: fixture.log)
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definition),
        ]
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription())
        let firstOutput = effected.output

        fixture.drawingEffect.errorOnUpdate = FakeError()
        XCTAssertThrowsError(try effected.update(makeItemDescription(itemFrame: 1))) { error in
            guard let wrapped = error as? EffectedItemError,
                  case let .drawingEffectUpdateFailed(itemTypeName, effectCount, _, _) = wrapped
            else {
                return XCTFail("DrawingEffect の失敗は EffectedItemError で包まれるはず: \(error)")
            }
            XCTAssertEqual(itemTypeName, TextItem.typeName)
            XCTAssertEqual(effectCount, 1)
        }
        XCTAssertTrue(effected.output === firstOutput)
    }

    func testApplyItemTransformFalseUsesPreRenderOutput() throws {
        let fixture = Fixture()
        let effected = fixture.makeEffected(applyItemTransform: false)
        try effected.update(makeItemDescription())

        // 変形なしでは DrawingEffect は使われず、連鎖の素の出力が合成される。
        XCTAssertEqual(fixture.drawingEffect.setInputCalls.count, 0)
        XCTAssertEqual(fixture.drawingEffect.updateCount, 0)
        let target = fixture.factory.targets[0]
        XCTAssertTrue(target.ops.contains("draw(src-img)"))
        XCTAssertFalse(target.ops.contains("draw(DE-out)"))
    }

    func testFadeAndOpacityEvaluation() throws {
        let fixture = Fixture()
        fixture.item.opacity = Animation(defaultValue: 50, minValue: 0, maxValue: 100)
        fixture.item.x = Animation(defaultValue: 10, minValue: -100_000, maxValue: 100_000)
        fixture.item.fadeIn = 1.0
        let effected = fixture.makeEffected()

        // アイテム内 15 フレーム（= 0.5 秒）: フェードイン係数 0.5、
        // 不透明度は 50/100 × 0.5 = 0.25。
        try effected.update(makeItemDescription(itemFrame: 15, itemLength: 90))
        XCTAssertEqual(effected.drawDescription.opacity, 0.25, accuracy: 1e-9)
        XCTAssertEqual(effected.drawDescription.draw.x, 10, accuracy: 1e-9)
    }

    func testClippingUsesAlphaMask() throws {
        let fixture = Fixture()
        fixture.item.isClippingWithObjectAbove = true
        let maskFactory = FakeAlphaMaskFactory()
        let effected = EffectedItemSource(
            item: fixture.item,
            source: fixture.source,
            targetFactory: fixture.factory,
            effectProvider: fixture.provider,
            alphaMaskFactory: maskFactory
        )
        try effected.update(makeItemDescription())

        // 合成結果がマスクの入力0へ渡り、出力はマスク側の出力になる。
        XCTAssertEqual(maskFactory.masks.count, 1)
        let mask = maskFactory.masks[0]
        XCTAssertTrue(mask.inputs[0] ?? nil === fixture.factory.targets[0].image)
        XCTAssertTrue(effected.output === mask.output)

        // SetAlphaMask は入力1へ届く。
        let maskImage = ImageReference(label: "previous")
        effected.setAlphaMask(maskImage)
        XCTAssertTrue(mask.inputs[1] ?? nil === maskImage)
    }

    func testEffectDescriptionGroupIndexAndTimeSource() throws {
        let fixture = Fixture()
        let group = makeVisualItem(GroupItem(), frame: 90, length: 200, layer: 0)
        let definition = FakeDefinition(name: "G", log: fixture.log)
        let effected = fixture.makeEffected()
        effected.parentEffects = [
            EffectPair(timeSource: group, definition: definition, groupIndex: 2, groupCount: 5),
        ]
        // タイムライン位置 130、アイテム開始 100（アイテム内位置 30）。
        fixture.item.frame = 100
        try effected.update(makeItemDescription(timelineFrame: 130, itemFrame: 30))

        let description = definition.processors[0].updateDescriptions[0]
        XCTAssertEqual(description.groupIndex, 2)
        XCTAssertEqual(description.groupCount, 5)
        XCTAssertEqual(description.inputIndex, 0)
        XCTAssertEqual(description.inputCount, 1)
        // アイテム内位置はタイムライン位置 − 時間基準（グループ）の開始。
        XCTAssertEqual(description.itemDescription.itemPosition.frame, 130 - 90)
        XCTAssertEqual(description.itemDescription.itemDuration.frame, 200)
    }

    func testEffectDescriptionTimeOffsets() throws {
        let fixture = Fixture()
        fixture.item.frame = 100
        fixture.source.outputs = [StandardSourceOutput(
            output: fixture.sourceImage,
            drawingEffect: fixture.drawingEffect,
            timeOffset: TimeSpanValue(seconds: 0.5)
        )]
        let definition = FakeDefinition(name: "A", log: fixture.log)
        fixture.provider.ownPairs[ObjectIdentifier(fixture.item)] = [
            EffectPair(timeSource: fixture.item, definition: definition),
        ]
        let effected = fixture.makeEffected()
        try effected.update(makeItemDescription(timelineFrame: 130, itemFrame: 30))

        // TimeOffset 0.5 秒 = 15 フレームが位置と長さの両方へ加わる。
        let description = definition.processors[0].updateDescriptions[0]
        XCTAssertEqual(description.itemDescription.itemPosition.frame, 130 - 100 + 15)
        XCTAssertEqual(description.itemDescription.itemDuration.frame, 90 + 15)
    }
}

// MARK: - TimelineGroupResolver

final class TimelineGroupResolverTests: XCTestCase {

    private func makeGroup(
        layer: Int, range: Int = 50, group: Int = 0, isGroupOnly: Bool = false,
        isComposite: Bool = false, hidden: Bool = false
    ) -> GroupItem {
        let item = GroupItem()
        item.frame = 0
        item.length = 90
        item.layer = layer
        item.group = group
        item.groupRange = range
        item.isGroupOnly = isGroupOnly
        item.isComposite = isComposite
        item.isHidden = hidden
        return item
    }

    func testParentOrderAndCompositeCutoff() {
        let groupA = makeGroup(layer: 0)
        let composite = makeGroup(layer: 3, isComposite: true)
        let groupB = makeGroup(layer: 5)
        let item = makeVisualItem(TextItem(), layer: 10)
        let resolver = TimelineGroupResolver(
            items: [groupA, composite, groupB, item], isLayerVisible: { _ in true }
        )

        // レイヤー降順に並べ、合成グループに当たったところで打ち切る。
        let parents = resolver.parentGroups(of: item)
        XCTAssertEqual(parents.count, 1)
        XCTAssertTrue(parents[0] === groupB)
        // 子の列挙は親列に含まれる場合だけ。
        XCTAssertEqual(resolver.children(of: groupB).count, 1)
        XCTAssertTrue(resolver.children(of: groupB)[0] === item)
        XCTAssertEqual(resolver.children(of: groupA).count, 0)
    }

    func testGroupOnlyMatchingAndHiddenGroup() {
        let groupOnly = makeGroup(layer: 0, group: 7, isGroupOnly: true)
        let hidden = makeGroup(layer: 0, hidden: true)
        let matching = makeVisualItem(TextItem(), layer: 1, group: 7)
        let notMatching = makeVisualItem(TextItem(), layer: 1, group: 0)
        let resolver = TimelineGroupResolver(
            items: [groupOnly, hidden, matching, notMatching], isLayerVisible: { _ in true }
        )

        XCTAssertEqual(resolver.parentGroups(of: matching).count, 1)
        XCTAssertEqual(resolver.parentGroups(of: notMatching).count, 0)
    }

    func testLayerVisibilityFilter() {
        let group = makeGroup(layer: 2)
        let item = makeVisualItem(TextItem(), layer: 3)
        let resolver = TimelineGroupResolver(
            items: [group, item], isLayerVisible: { $0 != 2 }
        )
        XCTAssertEqual(resolver.parentGroups(of: item).count, 0)
    }
}

// MARK: - TimelineComposer

final class TimelineComposerTests: XCTestCase {

    private final class Fixture {
        let log = EventLog()
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

        func makeComposer(alphaMaskFactory: (any AlphaMaskEffectFactory)? = nil) -> TimelineComposer {
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
                        drawingEffect: FakeDrawingEffect(name: "DE", log: EventLog())
                    )]
                    return source
                },
                effectProvider: provider,
                alphaMaskFactory: alphaMaskFactory
            )
        }
    }

    private func makeSource(log: EventLog, imageLabel: String) -> FakeChainSource {
        let source = FakeChainSource()
        source.outputs = [StandardSourceOutput(
            output: ImageReference(label: imageLabel),
            drawingEffect: FakeDrawingEffect(name: "DE-\(imageLabel)", log: log)
        )]
        return source
    }

    func testOutOfRangeItemResourceDisposed() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 30, layer: 0)
        fixture.timeline.items = [item]
        let source = makeSource(log: fixture.log, imageLabel: "img")
        fixture.registerSource(source, for: item)
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)
        XCTAssertFalse(source.disposed)

        // フレーム 60 ではアイテムは範囲外になり、実行部はその場で破棄される。
        try composer.update(time: TimeSpanValue(seconds: 2), usage: .paused)
        XCTAssertTrue(source.disposed)
        XCTAssertNotNil(composer.output)
    }

    func testParentEffectsRebuiltEachUpdate() throws {
        let fixture = Fixture()
        let group = makeVisualItem(GroupItem(), frame: 0, length: 90, layer: 0)
        group.groupRange = 5
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 2)
        fixture.timeline.items = [group, item]
        let definition = FakeDefinition(name: "G", log: fixture.log)
        fixture.provider.groupDefinitions[ObjectIdentifier(group)] = [definition]
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)
        XCTAssertEqual(definition.processors.count, 1)
        XCTAssertEqual(fixture.provider.groupCalls.count, 1)
        XCTAssertEqual(fixture.provider.groupCalls[0].childIndex, 0)
        XCTAssertEqual(fixture.provider.groupCalls[0].childCount, 1)

        // グループを隠すと親エフェクトは再構築で消え、処理器は破棄される。
        group.isHidden = true
        try composer.update(time: TimeSpanValue(seconds: 1), usage: .paused)
        XCTAssertTrue(definition.processors[0].disposed)
        XCTAssertEqual(fixture.provider.groupCalls.count, 1)
    }

    func testOwnEffectsBeforeGroupEffects() throws {
        let fixture = Fixture()
        let group = makeVisualItem(GroupItem(), frame: 0, length: 90, layer: 0)
        group.groupRange = 5
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 2)
        fixture.timeline.items = [group, item]
        let own = FakeDefinition(name: "OWN", log: fixture.log)
        let groupDefinition = FakeDefinition(name: "GRP", log: fixture.log)
        fixture.provider.ownPairs[ObjectIdentifier(item)] = [
            EffectPair(timeSource: item, definition: own),
        ]
        fixture.provider.groupDefinitions[ObjectIdentifier(group)] = [groupDefinition]
        let composer = fixture.makeComposer()
        try composer.update(time: .zero, usage: .paused)

        let ownCreate = try XCTUnwrap(fixture.log.index(of: "OWN.createProcessor"))
        let groupCreate = try XCTUnwrap(fixture.log.index(of: "GRP.createProcessor"))
        XCTAssertLessThan(ownCreate, groupCreate)
        // グループエフェクトには子位置と子総数が渡る。
        let description = groupDefinition.processors[0].updateDescriptions[0]
        XCTAssertEqual(description.groupIndex, 0)
        XCTAssertEqual(description.groupCount, 1)
    }

    func testDrawOrderFollowsOrdering() throws {
        let fixture = Fixture()
        let itemA = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 2)
        let itemB = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 1)
        fixture.timeline.items = [itemA, itemB]
        fixture.registerSource(makeSource(log: fixture.log, imageLabel: "imgA"), for: itemA)
        fixture.registerSource(makeSource(log: fixture.log, imageLabel: "imgB"), for: itemB)
        let composer = fixture.makeComposer()
        try composer.update(time: .zero, usage: .paused)

        // アイテム側の描画先が選定順（A, B）に作られ、合成側が最後。
        // 描画順序はレイヤー昇順のため B の出力が先に描かれる。
        let targets = fixture.factory.targets
        XCTAssertEqual(targets.count, 3)
        let composition = targets[2]
        XCTAssertEqual(composition.ops, [
            "begin",
            "clear",
            "drawBlend(\(targets[1].image.label))",
            "drawBlend(\(targets[0].image.label))",
            "end",
            "close",
        ])
        XCTAssertTrue(composer.output === composition.image)
    }

    func testBackgroundFillAndEmptyTimelineMarker() throws {
        let fixture = Fixture()
        fixture.timeline.videoInfo = VideoInfo(
            backgroundColor: Color(alpha: 255, red: 255, green: 0, blue: 0)
        )
        let composer = fixture.makeComposer()
        try composer.update(time: .zero, usage: .paused)

        // 背景は Clear ではなく中心矩形として描かれ、何も描かれなかった
        // 場合は空矩形の目印が入る。
        let target = fixture.factory.targets[0]
        XCTAssertEqual(target.ops, [
            "begin",
            "clear",
            "fillRect(-960.0,-540.0,960.0,540.0,a=255)",
            "fillRect(0.0,0.0,0.0,0.0,a=0)",
            "end",
            "close",
        ])
    }

    func testItemUpdateFailureIsWrappedAndKeepsOutput() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 5, length: 40, layer: 3, group: 2)
        item.remark = "対象"
        fixture.timeline.items = [item]
        let source = makeSource(log: fixture.log, imageLabel: "img")
        fixture.registerSource(source, for: item)
        let composer = fixture.makeComposer()

        try composer.update(time: TimeSpanValue(seconds: 0.2), usage: .paused)
        let firstOutput = composer.output
        XCTAssertNotNil(firstOutput)

        source.errorOnUpdate = FakeError()
        XCTAssertThrowsError(try composer.update(time: TimeSpanValue(seconds: 0.3), usage: .paused)) { error in
            guard let wrapped = error as? TimelineCompositionError,
                  case let .itemUpdateFailed(itemTypeName, label, frame, length, layer, group, _) = wrapped
            else {
                return XCTFail("アイテム情報つきで包まれるはず: \(error)")
            }
            XCTAssertEqual(itemTypeName, TextItem.typeName)
            // Label は備考から導出される（本家 Label と同じ形式）。
            XCTAssertEqual(label, " / 対象")
            XCTAssertEqual(frame, 5)
            XCTAssertEqual(length, 40)
            XCTAssertEqual(layer, 3)
            XCTAssertEqual(group, 2)
        }
        // 並列更新の失敗では旧合成結果の参照は保持される。
        XCTAssertTrue(composer.output === firstOutput)
    }

    func testFrameBufferBoundary() throws {
        let fixture = Fixture()
        let frameBufferItem = makeVisualItem(FrameBufferItem(), frame: 0, length: 90, layer: 0)
        let normalItem = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 1)
        fixture.timeline.items = [frameBufferItem, normalItem]
        let frameBufferSource = FakeFrameBufferSource()
        frameBufferSource.clearBackground = false
        frameBufferSource.outputs = [StandardSourceOutput(
            output: ImageReference(label: "fb-img"),
            drawingEffect: FakeDrawingEffect(name: "DE-fb", log: fixture.log)
        )]
        fixture.registerSource(frameBufferSource, for: frameBufferItem)
        fixture.registerSource(makeSource(log: fixture.log, imageLabel: "imgN"), for: normalItem)
        let composer = fixture.makeComposer()

        try composer.update(time: .zero, usage: .paused)

        // 並列更新では FrameBuffer は更新されない（合成フェーズで更新される）。
        XCTAssertEqual(frameBufferSource.updateCount, 1)
        XCTAssertEqual(frameBufferSource.lastDescription?.itemPosition.frame, 0)
        XCTAssertEqual(frameBufferSource.lastDescription?.itemDuration.frame, 90)
        XCTAssertEqual(frameBufferSource.frameSize, PixelSize(width: 1920, height: 1080))

        // 描画先の流れ: T1 = 通常アイテム側、T2 = 境界で閉じられて
        // FrameBuffer へ渡った合成、T3 = FrameBuffer アイテム側、
        // T4 = 境界後の合成（最終出力）。
        let targets = fixture.factory.targets
        XCTAssertEqual(targets.count, 4)
        XCTAssertTrue(frameBufferSource.input === targets[1].image)
        XCTAssertEqual(targets[1].ops, [
            "begin",
            "clear",
            "fillRect(0.0,0.0,0.0,0.0,a=0)",
            "end",
            "close",
        ])
        XCTAssertEqual(targets[3].ops, [
            "begin",
            "clear",
            "draw(\(targets[1].image.label))",
            "drawBlend(\(targets[2].image.label))",
            "drawBlend(\(targets[0].image.label))",
            "end",
            "close",
        ])
        XCTAssertTrue(composer.output === targets[3].image)

        // 次回 Update の合成開始時点で、前回の蓄積（T2）と合成結果（T4）が
        // 解放される。
        try composer.update(time: TimeSpanValue(seconds: 1), usage: .paused)
        XCTAssertTrue(targets[1].disposed)
        XCTAssertTrue(targets[3].disposed)
    }

    func testTachieFaceResolution() throws {
        let fixture = Fixture()
        let character = Character()
        let tachie = makeVisualItem(TachieItem(), frame: 0, length: 90, layer: 1)
        tachie.character = character
        let face = TachieFaceItem()
        face.frame = 0
        face.length = 90
        face.layer = 2
        face.character = character
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 90
        voice.layer = 3
        voice.character = character
        fixture.timeline.items = [tachie, face, voice]

        let tachieSource = FakeTachieSource()
        tachieSource.outputs = [StandardSourceOutput(
            output: ImageReference(label: "tachie-img"),
            drawingEffect: FakeDrawingEffect(name: "DE-t", log: fixture.log)
        )]
        fixture.registerSource(tachieSource, for: tachie)
        let faceDefinition = FakeDefinition(name: "FACE", log: fixture.log)
        fixture.provider.facePairs[ObjectIdentifier(voice)] = [
            EffectPair(timeSource: voice, definition: faceDefinition),
        ]
        let composer = fixture.makeComposer()
        try composer.update(time: .zero, usage: .paused)

        // 声は最初の VoiceItem、顔列はレイヤー降順。
        XCTAssertTrue(tachieSource.activeVoice === voice)
        XCTAssertEqual(tachieSource.activeFaces.count, 2)
        XCTAssertTrue(tachieSource.activeFaces[0] as? VoiceItem === voice)
        XCTAssertTrue(tachieSource.activeFaces[1] as? TachieFaceItem === face)
        // 先頭の顔（声）のエフェクトが立ち絵の親エフェクトになる。
        XCTAssertEqual(faceDefinition.processors.count, 1)
    }

    func testComposerDisposeDisposesResources() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [item]
        let source = makeSource(log: fixture.log, imageLabel: "img")
        fixture.registerSource(source, for: item)
        let composer = fixture.makeComposer()
        try composer.update(time: .zero, usage: .paused)

        composer.dispose()
        XCTAssertTrue(source.disposed)
        XCTAssertNil(composer.output)
    }
}

// MARK: - 映像アイテムの範囲（MAC-0011）

final class VideoItemScopeTests: XCTestCase {

    /// 映像アイテムの範囲は本家 IVideoItem の実装範囲どおり:
    /// VisualItem 系譜 + VoiceItem + TransitionItem。TachieFaceItem と
    /// AudioItem は含まない。
    func testVideoItemEquivalentScope() {
        XCTAssertTrue(isVideoItemEquivalent(TextItem()))
        XCTAssertTrue(isVideoItemEquivalent(TachieItem()))
        XCTAssertTrue(isVideoItemEquivalent(VoiceItem()))
        XCTAssertTrue(isVideoItemEquivalent(TransitionItem()))
        XCTAssertFalse(isVideoItemEquivalent(TachieFaceItem()))
        XCTAssertFalse(isVideoItemEquivalent(AudioItem()))
    }

    /// PickFaceItems の対象（TachieFaceItem / VoiceItem が IFaceItem で
    /// ある点）は、映像アイテム範囲の是正後も本家どおり維持される。
    func testPickFaceItemsScopeUnchanged() {
        let timeline = Timeline()
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 90
        voice.layer = 2
        let face = TachieFaceItem()
        face.frame = 0
        face.length = 90
        face.layer = 3
        let text = TextItem()
        text.frame = 0
        text.length = 90
        text.layer = 1
        timeline.items = [voice, face, text]

        let picked = CompositeItemPicker().pickFaceItems(in: timeline, frame: 0)
        XCTAssertEqual(
            Set(picked.map { ObjectIdentifier($0) }),
            [ObjectIdentifier(voice), ObjectIdentifier(face)]
        )
    }

    /// TimelineComposer の資源対象が本家 IVideoItem の範囲に一致する:
    /// VoiceItem / TransitionItem は資源を持って更新され、TachieFaceItem は
    /// 資源を持たない（Source が要求されない）。
    func testComposerResourceScope() throws {
        let log = EventLog()
        let factory = RecordingTargetFactory(log: log)
        let timeline = Timeline()
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 90
        voice.layer = 2
        let transition = TransitionItem()
        transition.frame = 0
        transition.length = 90
        transition.layer = 1
        let face = TachieFaceItem()
        face.frame = 0
        face.length = 90
        face.layer = 3
        timeline.items = [voice, transition, face]

        var requested: [ObjectIdentifier] = []
        var sources: [ObjectIdentifier: FakeChainSource] = [:]
        let composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: factory,
            sourceProvider: { item in
                requested.append(ObjectIdentifier(item))
                let source = FakeChainSource()
                source.outputs = [StandardSourceOutput(
                    output: ImageReference(label: "img"),
                    drawingEffect: FakeDrawingEffect(name: "DE", log: log)
                )]
                sources[ObjectIdentifier(item)] = source
                return source
            }
        )
        try composer.update(time: .zero, usage: .paused)

        XCTAssertTrue(requested.contains(ObjectIdentifier(voice)))
        XCTAssertTrue(requested.contains(ObjectIdentifier(transition)))
        XCTAssertEqual(sources[ObjectIdentifier(voice)]?.updateCount, 1)
        XCTAssertEqual(sources[ObjectIdentifier(transition)]?.updateCount, 1)
        XCTAssertFalse(requested.contains(ObjectIdentifier(face)))
        XCTAssertNotNil(composer.output)

        // 範囲外になると VoiceItem の実行部もその場で破棄される。
        try composer.update(time: TimeSpanValue(seconds: 10), usage: .paused)
        XCTAssertEqual(sources[ObjectIdentifier(voice)]?.disposed, true)
        XCTAssertEqual(sources[ObjectIdentifier(transition)]?.disposed, true)
    }
}
