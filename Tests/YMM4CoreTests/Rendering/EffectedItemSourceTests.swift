import XCTest
@testable import YMM4Core

// MARK: - EffectedItemSource（連鎖）

final class EffectedItemSourceTests: XCTestCase {

    private struct Fixture {
        let log = CompositionEventLog()
        let factory: RecordingTargetFactory
        let provider = FakeEffectProvider()
        let item: TextItem
        let source = FakeChainSource()
        let drawingEffect: CompositionFakeDrawingEffect
        let sourceImage = ImageReference(label: "src-img")

        init() {
            factory = RecordingTargetFactory(log: log)
            item = makeVisualItem(TextItem())
            drawingEffect = CompositionFakeDrawingEffect(name: "DE", log: log)
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
