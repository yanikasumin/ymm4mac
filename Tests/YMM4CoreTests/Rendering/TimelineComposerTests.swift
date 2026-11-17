import XCTest
@testable import YMM4Core

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
                        drawingEffect: CompositionFakeDrawingEffect(name: "DE", log: CompositionEventLog())
                    )]
                    return source
                },
                effectProvider: provider,
                alphaMaskFactory: alphaMaskFactory
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

    // MAC-0021: 描画先の close() が失敗したら合成全体が失敗として伝わり、
    // 不完全な画像が出力として公開されない（3つの close 呼び出し箇所を
    // それぞれ観測する）。
    func testItemTargetCloseFailurePropagates() throws {
        let fixture = Fixture()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        fixture.timeline.items = [item]
        fixture.registerSource(makeSource(log: fixture.log, imageLabel: "img"), for: item)
        fixture.factory.closeError = FakeError()
        let composer = fixture.makeComposer()

        XCTAssertThrowsError(try composer.update(time: .zero, usage: .paused))
        XCTAssertNil(composer.output)
        // 失敗したアイテム側の描画先は公開されず、その場で解放される。
        XCTAssertTrue(fixture.factory.targets[0].disposed)
    }

    func testComposerTargetCloseFailurePropagates() throws {
        // アイテムが無いタイムラインでは合成側の描画先だけが作られるため、
        // TimelineComposer 自身の close の失敗を直接観測できる。
        let fixture = Fixture()
        fixture.factory.closeError = FakeError()
        let composer = fixture.makeComposer()

        XCTAssertThrowsError(try composer.update(time: .zero, usage: .paused))
        XCTAssertNil(composer.output)
    }

    func testFrameBufferBoundaryCloseFailurePropagates() throws {
        let fixture = Fixture()
        let frameBufferItem = makeVisualItem(FrameBufferItem(), frame: 0, length: 90, layer: 0)
        let normalItem = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 1)
        fixture.timeline.items = [frameBufferItem, normalItem]
        let frameBufferSource = FakeFrameBufferSource()
        frameBufferSource.clearBackground = false
        frameBufferSource.outputs = [StandardSourceOutput(
            output: ImageReference(label: "fb-img"),
            drawingEffect: CompositionFakeDrawingEffect(name: "DE-fb", log: fixture.log)
        )]
        fixture.registerSource(frameBufferSource, for: frameBufferItem)
        fixture.registerSource(makeSource(log: fixture.log, imageLabel: "imgN"), for: normalItem)
        // 境界で閉じられる合成側の描画先（T2）だけを失敗させる。
        fixture.factory.closeError = FakeError()
        fixture.factory.closeErrorTargetNumbers = [2]
        let composer = fixture.makeComposer()

        XCTAssertThrowsError(try composer.update(time: .zero, usage: .paused))
        XCTAssertNil(composer.output)
        // 境界の失敗は FrameBuffer の実行部更新へ進まない。
        XCTAssertEqual(frameBufferSource.updateCount, 0)
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
            drawingEffect: CompositionFakeDrawingEffect(name: "DE-fb", log: fixture.log)
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
            drawingEffect: CompositionFakeDrawingEffect(name: "DE-t", log: fixture.log)
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
