import XCTest
@testable import YMM4Core

// MARK: - 偽の実装（Source 契約の検証用）

private final class FakeDrawingEffect: DrawingEffectProcessor {
    var output: ImageReference?
    private(set) var input: ImageReference?
    private(set) var clearInputCallCount = 0
    private(set) var disposed = false

    func setInput(_ image: ImageReference?) {
        input = image
    }

    func clearInput() {
        clearInputCallCount += 1
        input = nil
    }

    func update(_ description: EffectDescription) -> DrawDescription {
        description.drawDescription
    }

    func dispose() {
        disposed = true
    }
}

private final class FakeSource: Source {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    private(set) var lastDescription: TimelineItemSourceDescription?
    private(set) var updateCount = 0
    private(set) var disposed = false

    func update(_ description: TimelineItemSourceDescription) {
        lastDescription = description
        updateCount += 1
    }

    func dispose() {
        disposed = true
    }
}

private final class FakePlaneSplitOrdering: PlaneSplitOrdering {
    var requiresResult = true
    var sortResult: [PlaneSplitFragment]?
    private(set) var sortCallCount = 0

    func requiresOrdering(_ a: [Vector3], _ b: [Vector3]) -> Bool {
        requiresResult
    }

    func sort(quads: [[Vector3]]) -> [PlaneSplitFragment]? {
        sortCallCount += 1
        return sortResult
    }
}

private func makeBaseDescription() -> TimelineSourceDescription {
    TimelineSourceDescription(
        screenSize: PixelSize(width: 1920, height: 1080),
        timelinePosition: FramePosition(frame: 0, fps: 30),
        timelineDuration: FramePosition(frame: 900, fps: 30),
        fps: 30,
        usage: .paused,
        sceneId: UUID(),
        scenes: []
    )
}

private func makeItem(
    _ item: BaseItem, frame: Int, length: Int, layer: Int, group: Int = 0, hidden: Bool = false
) -> BaseItem {
    item.frame = frame
    item.length = length
    item.layer = layer
    item.group = group
    item.isHidden = hidden
    return item
}

// MARK: - Source 契約

final class SourceContractTests: XCTestCase {

    func testSourceReceivesDescriptionOnUpdate() {
        let source = FakeSource()
        let effect = FakeDrawingEffect()
        let image = ImageReference(label: "fake")
        source.outputs = [StandardSourceOutput(output: image, drawingEffect: effect)]

        let itemDescription = TimelineItemSourceDescription(
            makeBaseDescription(), itemFrame: 15, itemLength: 60, layer: 3
        )
        source.update(itemDescription)

        XCTAssertEqual(source.updateCount, 1)
        XCTAssertEqual(source.lastDescription?.itemPosition.frame, 15)
        XCTAssertEqual(source.lastDescription?.itemDuration.frame, 60)
        XCTAssertEqual(source.lastDescription?.layer, 3)
        XCTAssertEqual(source.lastDescription?.fps, 30)
        XCTAssertEqual(source.outputs.count, 1)
        XCTAssertTrue(source.outputs[0].output === image)
        XCTAssertTrue(source.outputs[0].drawingEffect === effect)
        XCTAssertEqual(source.outputs[0].timeOffset, .zero)
        XCTAssertEqual(source.outputs[0].durationOffset, .zero)
    }

    func testStandardSourceOutputDisposesOwnedEffect() {
        let effect = FakeDrawingEffect()
        effect.setInput(ImageReference())
        let output = StandardSourceOutput(
            output: ImageReference(), drawingEffect: effect, dontDispose: false
        )
        output.dispose()
        XCTAssertEqual(effect.clearInputCallCount, 1)
        XCTAssertTrue(effect.disposed)
        // 二重に呼んでも破棄は1回だけ。
        output.dispose()
        XCTAssertEqual(effect.clearInputCallCount, 1)
    }

    func testStandardSourceOutputDoesNotDisposeBorrowedEffect() {
        let effect = FakeDrawingEffect()
        let output = StandardSourceOutput(
            output: ImageReference(), drawingEffect: effect, dontDispose: true
        )
        output.dispose()
        XCTAssertEqual(effect.clearInputCallCount, 0)
        XCTAssertFalse(effect.disposed)
    }

    func testItemDescriptionInheritsRenderScaleFromParentItemDescription() {
        var parent = TimelineItemSourceDescription(
            makeBaseDescription(), itemFrame: 0, itemLength: 90, layer: 0
        )
        parent.renderScale = 2.5
        let child = TimelineItemSourceDescription(parent, itemFrame: 10, itemLength: 30, layer: 1)
        XCTAssertEqual(child.renderScale, 2.5)
        XCTAssertEqual(child.itemPosition.fps, 30)

        let fromBase = TimelineItemSourceDescription(
            makeBaseDescription(), itemFrame: 0, itemLength: 90, layer: 0
        )
        XCTAssertEqual(fromBase.renderScale, 1)
    }

    func testComposeRenderScale() {
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: nil, itemScale: 2),
            2
        )
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: 2, itemScale: 0.5),
            1
        )
        // 不正なアイテムスケールは 1 として扱う。
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: 2, itemScale: 0),
            2
        )
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: 2, itemScale: .nan),
            2
        )
        // 不正な親スケールは 1 として扱う。
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: -1, itemScale: 3),
            3
        )
        // 積が float の最大値を超える場合は 1。
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: 1e38, itemScale: 1e38),
            1
        )
    }

    func testFramePositionTime() {
        XCTAssertEqual(FramePosition(frame: 30, fps: 30).time, 1.0, accuracy: 1e-9)
        XCTAssertEqual(FramePosition(frame: 45, fps: 30).time, 1.5, accuracy: 1e-9)
    }
}

// MARK: - アイテム選択

final class ItemPickerTests: XCTestCase {

    private func makeTimeline(_ items: [BaseItem], hiddenLayers: [Int] = []) -> Timeline {
        let timeline = Timeline()
        timeline.items = items
        timeline.layerSettings.items = hiddenLayers.map {
            LayerSetting(layer: $0, isHidden: true)
        }
        return timeline
    }

    func testPickItemsBasicFiltering() {
        let inside = makeItem(TextItem(), frame: 10, length: 20, layer: 0)
        let outside = makeItem(TextItem(), frame: 100, length: 10, layer: 0)
        let hiddenItem = makeItem(TextItem(), frame: 10, length: 20, layer: 1, hidden: true)
        let hiddenLayerItem = makeItem(TextItem(), frame: 10, length: 20, layer: 2)
        let timeline = makeTimeline(
            [inside, outside, hiddenItem, hiddenLayerItem], hiddenLayers: [2]
        )
        let picked = CompositeItemPicker().pickItems(in: timeline, frame: 15)
        XCTAssertEqual(picked.count, 1)
        XCTAssertTrue(picked[0] === inside)
    }

    func testPickItemsExcludesCompositeChildren() {
        let group = GroupItem()
        _ = makeItem(group, frame: 0, length: 100, layer: 0)
        group.isComposite = true
        group.groupRange = 5
        let child = makeItem(TextItem(), frame: 0, length: 100, layer: 2)
        let unrelated = makeItem(TextItem(), frame: 0, length: 100, layer: 9)
        let timeline = makeTimeline([group, child, unrelated])

        let picked = CompositeItemPicker().pickItems(in: timeline, frame: 10)
        XCTAssertEqual(picked.count, 2)
        XCTAssertTrue(picked.contains { $0 === group })
        XCTAssertTrue(picked.contains { $0 === unrelated })
        XCTAssertFalse(picked.contains { $0 === child })
    }

    func testPickItemsDoesNotExcludeChildrenOfNonCompositeGroup() {
        let group = GroupItem()
        _ = makeItem(group, frame: 0, length: 100, layer: 0)
        group.isComposite = false
        group.groupRange = 5
        let child = makeItem(TextItem(), frame: 0, length: 100, layer: 2)
        let timeline = makeTimeline([group, child])

        let picked = CompositeItemPicker().pickItems(in: timeline, frame: 10)
        XCTAssertEqual(picked.count, 2)
    }

    func testGroupPickerSelectsChildrenOnlyAndClampsFrame() {
        let group = GroupItem()
        _ = makeItem(group, frame: 100, length: 50, layer: 0)
        group.isComposite = true
        group.groupRange = 3
        // グループ末尾（149）を含む子と、末尾を含まない子。
        let atEnd = makeItem(TextItem(), frame: 140, length: 20, layer: 1)
        let early = makeItem(TextItem(), frame: 100, length: 10, layer: 1)
        // レイヤー範囲外のアイテムは子にならない。
        let outOfRange = makeItem(TextItem(), frame: 140, length: 20, layer: 9)
        let timeline = makeTimeline([group, atEnd, early, outOfRange])

        // フレーム 500 はグループ末尾 149 にクランプされる。
        let picked = CompositeItemPicker(groupItem: group).pickItems(in: timeline, frame: 500)
        XCTAssertEqual(picked.count, 1)
        XCTAssertTrue(picked[0] === atEnd)
    }

    func testGroupPickerGroupOnlyMatching() {
        let group = GroupItem()
        _ = makeItem(group, frame: 0, length: 100, layer: 0, group: 7)
        group.isComposite = true
        group.isGroupOnly = true
        group.groupRange = 5
        let matching = makeItem(TextItem(), frame: 0, length: 100, layer: 1, group: 7)
        let notMatching = makeItem(TextItem(), frame: 0, length: 100, layer: 2, group: 0)
        let timeline = makeTimeline([group, matching, notMatching])

        let picked = CompositeItemPicker(groupItem: group).pickItems(in: timeline, frame: 10)
        XCTAssertEqual(picked.count, 1)
        XCTAssertTrue(picked[0] === matching)
    }

    func testTransitionRuleExcludesItemsBelowHighestTransition() {
        let low = makeItem(TextItem(), frame: 0, length: 100, layer: 2)
        let transition = makeItem(TransitionItem(), frame: 0, length: 100, layer: 5)
        let sameLayer = makeItem(TextItem(), frame: 0, length: 100, layer: 5)
        let high = makeItem(TextItem(), frame: 0, length: 100, layer: 8)
        let timeline = makeTimeline([low, transition, sameLayer, high])

        let picked = CompositeItemPicker().pickItems(in: timeline, frame: 10)
        XCTAssertEqual(picked.count, 3)
        XCTAssertFalse(picked.contains { $0 === low })
        XCTAssertTrue(picked.contains { $0 === transition })
        XCTAssertTrue(picked.contains { $0 === sameLayer })
        XCTAssertTrue(picked.contains { $0 === high })
    }

    func testTransitionRuleIgnoresTransitionInsideCompositeGroup() {
        let group = GroupItem()
        _ = makeItem(group, frame: 0, length: 100, layer: 0, group: 7)
        group.isComposite = true
        group.isGroupOnly = true
        group.groupRange = 10
        // 合成グループの子であるトランジションは基準にならない。
        let childTransition = makeItem(TransitionItem(), frame: 0, length: 100, layer: 8, group: 7)
        // グループの子でない低レイヤーのアイテムは、子のトランジションに
        // 引きずられて除外されない。
        let low = makeItem(TextItem(), frame: 0, length: 100, layer: 2, group: 0)
        let timeline = makeTimeline([group, childTransition, low])

        let picked = CompositeItemPicker().pickItems(in: timeline, frame: 10)
        XCTAssertTrue(picked.contains { $0 === low })
        XCTAssertFalse(picked.contains { $0 === childTransition })
    }

    func testPickFaceItems() {
        let voice = makeItem(VoiceItem(), frame: 0, length: 100, layer: 0)
        let face = makeItem(TachieFaceItem(), frame: 0, length: 100, layer: 1)
        let text = makeItem(TextItem(), frame: 0, length: 100, layer: 2)
        let hiddenVoice = makeItem(VoiceItem(), frame: 0, length: 100, layer: 3, hidden: true)
        let timeline = makeTimeline([voice, face, text, hiddenVoice])

        let picked = CompositeItemPicker().pickFaceItems(in: timeline, frame: 10)
        XCTAssertEqual(picked.count, 2)
        XCTAssertTrue(picked.contains { $0 === voice })
        XCTAssertTrue(picked.contains { $0 === face })
    }

    func testTransitionItemPickerBeforeUsesPreviousFrame() {
        let transition = makeItem(TransitionItem(), frame: 100, length: 30, layer: 5)
        // フレーム 99 を含むが 100 を含まないアイテム。
        let beforeOnly = makeItem(TextItem(), frame: 90, length: 10, layer: 1)
        // フレーム 100 を含むが 99 を含まないアイテム。
        let afterOnly = makeItem(TextItem(), frame: 100, length: 10, layer: 2)
        // トランジション以上のレイヤーは常に対象外。
        let above = makeItem(TextItem(), frame: 90, length: 30, layer: 6)
        let timeline = makeTimeline([transition, beforeOnly, afterOnly, above])

        let before = TransitionItemPicker(transitionItem: transition as! TransitionItem, isBefore: true)
            .pickItems(in: timeline, frame: 100)
        XCTAssertEqual(before.count, 1)
        XCTAssertTrue(before[0] === beforeOnly)

        let after = TransitionItemPicker(transitionItem: transition as! TransitionItem, isBefore: false)
            .pickItems(in: timeline, frame: 100)
        XCTAssertEqual(after.count, 1)
        XCTAssertTrue(after[0] === afterOnly)
    }

    func testTransitionItemPickerParentCompositeRestriction() {
        let group = GroupItem()
        _ = makeItem(group, frame: 0, length: 100, layer: 0, group: 7)
        group.isComposite = true
        group.isGroupOnly = true
        group.groupRange = 5
        let transition = makeItem(TransitionItem(), frame: 10, length: 30, layer: 3, group: 7)
        // 親グループの子（グループ番号一致）は対象、非子は対象外。
        let child = makeItem(TextItem(), frame: 0, length: 100, layer: 1, group: 7)
        let notChild = makeItem(TextItem(), frame: 0, length: 100, layer: 2, group: 0)
        let timeline = makeTimeline([group, transition, child, notChild])

        let picked = TransitionItemPicker(
            transitionItem: transition as! TransitionItem, isBefore: false
        ).pickItems(in: timeline, frame: 20)
        XCTAssertEqual(picked.count, 1)
        XCTAssertTrue(picked[0] === child)
    }
}

// MARK: - 描画順序とセグメント構築

final class DrawOrderingTests: XCTestCase {

    private func makeDescription(z: Double) -> DrawDescription {
        var description = DrawDescription.empty
        description.draw = Vector3(x: 0, y: 0, z: z)
        return description
    }

    private func makeResource(
        layer: Int,
        alwaysOnTop: Bool = false,
        zOrderEnabled: Bool = true,
        isFrameBufferSource: Bool = false,
        descriptions: [DrawDescription] = [],
        quad: [Vector3]? = nil
    ) -> OrderedDrawResource {
        let item = TextItem()
        item.layer = layer
        return OrderedDrawResource(
            item: item,
            alwaysOnTop: alwaysOnTop,
            zOrderEnabled: zOrderEnabled,
            layer: layer,
            isFrameBufferSource: isFrameBufferSource,
            drawDescriptions: descriptions,
            planeSplitQuad: quad
        )
    }

    private func sampleQuad() -> [Vector3] {
        [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 100, y: 0, z: 0),
            Vector3(x: 100, y: 50, z: 0),
            Vector3(x: 0, y: 50, z: 0),
        ]
    }

    func testZIndexFromTranslation() {
        // 原点 → 平行移動 z=100 → 透視（w = 1 - 0.001z）で 100 / 0.9。
        let z = DrawOrdering.zIndex(of: [makeDescription(z: 100)])
        XCTAssertEqual(z, 100.0 / 0.9, accuracy: 1e-9)
    }

    func testZIndexIsMaxAndEmptyIsZero() {
        XCTAssertEqual(DrawOrdering.zIndex(of: []), 0)
        let z = DrawOrdering.zIndex(of: [makeDescription(z: 10), makeDescription(z: 100)])
        XCTAssertEqual(z, 100.0 / 0.9, accuracy: 1e-9)
    }

    func testZIndexIgnoresRotationAndInvertAtOrigin() {
        var rotated = makeDescription(z: 100)
        rotated.rotation = Vector3(x: 30, y: 45, z: 90)
        rotated.invert = true
        XCTAssertEqual(DrawOrdering.zIndex(of: [rotated]), 100.0 / 0.9, accuracy: 1e-9)
    }

    func testZIndexAppliesCamera() {
        var description = makeDescription(z: 100)
        description.camera = .createTranslation(x: 0, y: 0, z: 50)
        // (100 + 50) / (1 - 0.001 * 150)
        XCTAssertEqual(DrawOrdering.zIndex(of: [description]), 150.0 / 0.85, accuracy: 1e-9)
    }

    func testOrderingThreeKeys() {
        // キー: AlwaysOnTop（後ろ）→ ZIndex → Layer。同キーは入力順を保持。
        let a = makeResource(layer: 3, descriptions: [makeDescription(z: 0)])
        let b = makeResource(layer: 1, descriptions: [makeDescription(z: 0)])
        let c = makeResource(layer: 9, descriptions: [makeDescription(z: 50)])
        let d = makeResource(layer: 0, alwaysOnTop: true, descriptions: [makeDescription(z: -100)])
        // ZOrder 無効は Z が大きくても 0 として扱われる。
        let e = makeResource(layer: 2, zOrderEnabled: false, descriptions: [makeDescription(z: 500)])

        let ordered = DrawOrdering.ordered([a, b, c, d, e])
        XCTAssertEqual(ordered.map { $0.layer }, [1, 2, 3, 9, 0])
    }

    func testPlaneSplitQuadIdentity() {
        let quad = DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 0, top: 0, right: 100, bottom: 50)
            ),
        ])
        XCTAssertEqual(quad, sampleQuad())
    }

    func testPlaneSplitQuadUnionsBoundsAcrossOutputs() {
        let quad = DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 0, top: 0, right: 50, bottom: 50)
            ),
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 50, top: 0, right: 100, bottom: 50)
            ),
        ])
        XCTAssertEqual(quad, sampleQuad())
    }

    func testPlaneSplitQuadNilCases() {
        // 出力0件。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: []))
        // ワールド変換なし。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: nil,
                inputBounds: RectF(left: 0, top: 0, right: 100, bottom: 50)
            ),
        ]))
        // 出力間で変換が一致しない。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 0, top: 0, right: 50, bottom: 50)
            ),
            PlaneSplitOutputGeometry(
                worldTransform: .createTranslation(x: 1, y: 0, z: 0),
                inputBounds: RectF(left: 50, top: 0, right: 100, bottom: 50)
            ),
        ]))
        // 入力境界が取れない。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(worldTransform: .identity, inputBounds: nil),
        ]))
        // 統合した境界が空。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 10, top: 0, right: 10, bottom: 50)
            ),
        ]))
        // 変換後の Z が 999 を超える。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .createTranslation(x: 0, y: 0, z: 1000),
                inputBounds: RectF(left: 0, top: 0, right: 100, bottom: 50)
            ),
        ]))
        // 変換で潰れて平面をなさない。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .createScale(x: 0, y: 0, z: 1, center: .zero),
                inputBounds: RectF(left: 0, top: 0, right: 100, bottom: 50)
            ),
        ]))
    }

    func testSegmentBuilderNonJoinableBecomesSingle() {
        let builder = DrawSegmentBuilder()
        let disabled = makeResource(layer: 0, zOrderEnabled: false, quad: sampleQuad())
        let frameBuffer = makeResource(layer: 1, isFrameBufferSource: true, quad: sampleQuad())
        let segments = builder.buildSegments(from: [disabled, frameBuffer])
        XCTAssertEqual(segments.count, 2)
        for segment in segments {
            guard case .single = segment else {
                return XCTFail("単独描画になるはず")
            }
        }
    }

    func testSegmentBuilderFallsBackToSequentialWithNullOrdering() {
        let builder = DrawSegmentBuilder()
        let resources = (0..<3).map { makeResource(layer: $0, quad: sampleQuad()) }
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 3)
        for segment in segments {
            guard case .single = segment else {
                return XCTFail("BSP 未実装では逐次描画へフォールバックするはず")
            }
        }
    }

    func testSegmentBuilderPlaneSplitWithFakeOrdering() {
        let ordering = FakePlaneSplitOrdering()
        ordering.sortResult = [
            PlaneSplitFragment(resourceIndex: 0, hasCuts: false),
            PlaneSplitFragment(resourceIndex: 1, hasCuts: true),
        ]
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = (0..<2).map { makeResource(layer: $0, quad: sampleQuad()) }
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 1)
        guard case .planeSplit(let run, let fragments) = segments[0] else {
            return XCTFail("平面分割セグメントになるはず")
        }
        XCTAssertEqual(run.count, 2)
        XCTAssertEqual(fragments.count, 2)
        XCTAssertEqual(ordering.sortCallCount, 1)
    }

    func testSegmentBuilderSortNilFallsBack() {
        let ordering = FakePlaneSplitOrdering()
        ordering.sortResult = nil
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = (0..<2).map { makeResource(layer: $0, quad: sampleQuad()) }
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(ordering.sortCallCount, 1)
    }

    func testSegmentBuilderRequiresOrderingFalseSkipsSort() {
        let ordering = FakePlaneSplitOrdering()
        ordering.requiresResult = false
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = (0..<2).map { makeResource(layer: $0, quad: sampleQuad()) }
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(ordering.sortCallCount, 0)
    }

    func testSegmentBuilderSplitsRunAtNilQuad() {
        let ordering = FakePlaneSplitOrdering()
        ordering.sortResult = [
            PlaneSplitFragment(resourceIndex: 0, hasCuts: false),
            PlaneSplitFragment(resourceIndex: 1, hasCuts: false),
        ]
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = [
            makeResource(layer: 0, quad: sampleQuad()),
            makeResource(layer: 1, quad: sampleQuad()),
            makeResource(layer: 2, quad: nil),
            makeResource(layer: 3, quad: sampleQuad()),
            makeResource(layer: 4, quad: sampleQuad()),
        ]
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 3)
        guard case .planeSplit(let firstRun, _) = segments[0],
              case .single(let middle) = segments[1],
              case .planeSplit(let lastRun, _) = segments[2]
        else {
            return XCTFail("平面分割・単独・平面分割の列になるはず")
        }
        XCTAssertEqual(firstRun.map { $0.layer }, [0, 1])
        XCTAssertEqual(middle.layer, 2)
        XCTAssertEqual(lastRun.map { $0.layer }, [3, 4])
    }

    func testSegmentBuilderRunBrokenByAlwaysOnTopChange() {
        let ordering = FakePlaneSplitOrdering()
        ordering.sortResult = [
            PlaneSplitFragment(resourceIndex: 0, hasCuts: false),
            PlaneSplitFragment(resourceIndex: 1, hasCuts: false),
        ]
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = [
            makeResource(layer: 0, alwaysOnTop: false, quad: sampleQuad()),
            makeResource(layer: 1, alwaysOnTop: true, quad: sampleQuad()),
        ]
        let segments = builder.buildSegments(from: resources)
        // IsAlwaysOnTop が変わるためランは分かれ、それぞれ1件で単独描画。
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(ordering.sortCallCount, 0)
    }
}
