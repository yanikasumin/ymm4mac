import XCTest
@testable import YMM4Core

// MARK: - 合成グループ

final class CompositeGroupTests: XCTestCase {

    private func makeGroup(
        frame: Int = 0, length: Int = 90, layer: Int, range: Int = 10,
        isComposite: Bool = true
    ) -> GroupItem {
        let group = GroupItem()
        group.frame = frame
        group.length = length
        group.layer = layer
        group.groupRange = range
        group.isComposite = isComposite
        return group
    }

    private func makeChild<T: VisualItem>(_ item: T, frame: Int = 0, length: Int = 90, layer: Int) -> T {
        item.frame = frame
        item.length = length
        item.layer = layer
        return item
    }

    /// 外側・内側の合成器とアイテムごとの RecordingStubSource をまとめた検証環境。
    private final class Fixture {
        let timeline = Timeline()
        let factory = StubTargetFactory()
        let provider = StubEffectProvider()
        private(set) var stubSources: [ObjectIdentifier: RecordingStubSource] = [:]
        private(set) var providerCalls: [ObjectIdentifier] = []

        func composer(picker: any ItemPicker) -> TimelineComposer {
            TimelineComposer(
                scene: TimelineScene(timeline: timeline),
                picker: picker,
                targetFactory: factory,
                sourceProvider: { [self] item in
                    providerCalls.append(ObjectIdentifier(item))
                    if let source = stubSources[ObjectIdentifier(item)] {
                        return source
                    }
                    let source = RecordingStubSource(imageLabel: "img")
                    stubSources[ObjectIdentifier(item)] = source
                    return source
                },
                effectProvider: provider
            )
        }

        func source(for item: BaseItem) -> RecordingStubSource? {
            stubSources[ObjectIdentifier(item)]
        }
    }

    /// 外側の合成では、合成グループの子はグループが代表し、子自身は
    /// 資源を持たない（本家 UpdateResources の規則）。
    func testOuterComposerRepresentsChildrenByGroupOnly() throws {
        let fixture = Fixture()
        let group = makeGroup(layer: 0, range: 10)
        let child = makeChild(ShapeItem(), layer: 1)
        let outside = makeChild(ShapeItem(), layer: 20)
        fixture.timeline.items = [group, child, outside]

        let composer = fixture.composer(picker: CompositeItemPicker())
        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(fixture.source(for: group)?.updateCount, 1)
        XCTAssertEqual(fixture.source(for: outside)?.updateCount, 1)
        // 子の Source は生成すらされない。
        XCTAssertNil(fixture.source(for: child))
        XCTAssertFalse(fixture.providerCalls.contains(ObjectIdentifier(child)))
        // 最終描画先へ描かれるのはグループと範囲外アイテムの2件だけ。
        XCTAssertEqual(fixture.factory.targets.last?.drawBlendCount, 2)
    }

    /// グループ束縛の選定では、内部合成はグループの子だけを対象にし、
    /// グループ自身と範囲外は対象にならない。
    func testInnerComposerComposesOnlyGroupChildren() throws {
        let fixture = Fixture()
        let group = makeGroup(layer: 0, range: 10)
        let child = makeChild(ShapeItem(), layer: 1)
        let outside = makeChild(ShapeItem(), layer: 20)
        fixture.timeline.items = [group, child, outside]

        let composer = fixture.composer(picker: CompositeItemPicker(groupItem: group))
        try composer.update(time: .zero, usage: .paused)

        XCTAssertEqual(fixture.source(for: child)?.updateCount, 1)
        XCTAssertNil(fixture.source(for: group))
        XCTAssertNil(fixture.source(for: outside))
        XCTAssertEqual(fixture.factory.targets.last?.drawBlendCount, 1)
    }

    /// 内部選定のフレームはグループ末尾でクランプされる（本家
    /// CompositeItemPicker）。グループ終了後の時刻でも、末尾フレームで
    /// 子が選ばれる。
    func testInnerPickerClampsFrameToGroupEnd() throws {
        let fixture = Fixture()
        let group = makeGroup(frame: 10, length: 30, layer: 0, range: 10)
        let child = makeChild(ShapeItem(), frame: 10, length: 30, layer: 1)
        fixture.timeline.items = [group, child]

        let composer = fixture.composer(picker: CompositeItemPicker(groupItem: group))
        // タイムラインのフレーム 50（グループはフレーム 39 で終了）。
        try composer.update(time: TimeSpanValue(seconds: 50.0 / 30.0), usage: .paused)

        XCTAssertEqual(fixture.source(for: child)?.updateCount, 1)
    }

    /// グループのエフェクトは合成結果全体へ一度だけ適用され、子へは
    /// 流れない。親エフェクト経路（GroupEffects）は合成グループで
    /// 打ち切られるため、内側でも外側でも子の連鎖には現れない。
    func testGroupEffectAppliesOnceToCompositeOutput() throws {
        let fixture = Fixture()
        let group = makeGroup(layer: 0, range: 10)
        let child = makeChild(ShapeItem(), layer: 1)
        fixture.timeline.items = [group, child]

        // グループ自身のエフェクト（合成結果全体へ効く）と、親エフェクト
        // 経路で供給されるはずの定義（子へ流れるなら現れる）を用意する。
        let wholeDefinition = StubDefinition(zDelta: 10)
        let leakedDefinition = StubDefinition()
        let childDefinition = StubDefinition()
        fixture.provider.ownPairs[ObjectIdentifier(group)] = [
            EffectPair(timeSource: group, definition: wholeDefinition),
        ]
        fixture.provider.groupDefinitions[ObjectIdentifier(group)] = [leakedDefinition]
        fixture.provider.ownPairs[ObjectIdentifier(child)] = [
            EffectPair(timeSource: child, definition: childDefinition),
        ]

        // 内側（子の合成）と外側（グループの合成）を順に回す。
        let inner = fixture.composer(picker: CompositeItemPicker(groupItem: group))
        try inner.update(time: .zero, usage: .paused)
        let outer = fixture.composer(picker: CompositeItemPicker())
        try outer.update(time: .zero, usage: .paused)

        // 全体エフェクトの処理器は外側で1つだけ生成され、入力1件に
        // 一度だけ適用される。
        XCTAssertEqual(wholeDefinition.processors.count, 1)
        XCTAssertEqual(wholeDefinition.processors[0].updateDescriptions.count, 1)
        XCTAssertEqual(wholeDefinition.processors[0].updateDescriptions[0].inputCount, 1)
        // 親エフェクト経路は両側とも呼ばれず、子の連鎖にも混ざらない。
        XCTAssertTrue(fixture.provider.groupCalls.isEmpty)
        XCTAssertEqual(leakedDefinition.processors.count, 0)
        // 子自身のエフェクトは内側で通常どおり適用され、その入力の
        // DrawDescription にグループの z 変更は乗っていない。
        XCTAssertEqual(childDefinition.processors.count, 1)
        XCTAssertEqual(
            childDefinition.processors[0].updateDescriptions[0].drawDescription.draw.z, 0
        )
    }

    /// 入れ子: 外側グループの内部選定は内側グループを代表として含み、
    /// その子（孫）は含まない。内側グループの内部選定は孫を含む。
    /// 解決側でも親列は合成グループで打ち切られる。
    func testNestedCompositeGroups() throws {
        let fixture = Fixture()
        let outerGroup = makeGroup(layer: 0, range: 30)
        let innerGroup = makeGroup(layer: 5, range: 10)
        let grandchild = makeChild(ShapeItem(), layer: 6)
        let directChild = makeChild(ShapeItem(), layer: 2)
        fixture.timeline.items = [outerGroup, innerGroup, grandchild, directChild]
        let timeline = fixture.timeline

        // 選定の階層。
        let all = CompositeItemPicker().pickItems(in: timeline, frame: 0)
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0] === outerGroup)
        let outerChildren = CompositeItemPicker(groupItem: outerGroup)
            .pickItems(in: timeline, frame: 0)
        XCTAssertEqual(outerChildren.count, 2)
        XCTAssertTrue(outerChildren.contains { $0 === innerGroup })
        XCTAssertTrue(outerChildren.contains { $0 === directChild })
        XCTAssertFalse(outerChildren.contains { $0 === grandchild })
        let innerChildren = CompositeItemPicker(groupItem: innerGroup)
            .pickItems(in: timeline, frame: 0)
        XCTAssertEqual(innerChildren.count, 1)
        XCTAssertTrue(innerChildren[0] === grandchild)

        // 解決の打ち切り: 孫・内側グループ・直接の子のいずれも、合成
        // グループを親として持たない（合成グループの効果は子へ流れない）。
        let resolver = TimelineGroupResolver(items: timeline.items) { _ in true }
        XCTAssertTrue(resolver.parentGroups(of: grandchild).isEmpty)
        XCTAssertTrue(resolver.parentGroups(of: innerGroup).isEmpty)
        XCTAssertTrue(resolver.parentGroups(of: directChild).isEmpty)
        XCTAssertTrue(resolver.children(of: outerGroup).isEmpty)

        // 合成器でも同じ階層になる: 最内側の合成器だけが孫を更新する。
        let innermost = fixture.composer(picker: CompositeItemPicker(groupItem: innerGroup))
        try innermost.update(time: .zero, usage: .paused)
        XCTAssertEqual(fixture.source(for: grandchild)?.updateCount, 1)
        XCTAssertNil(fixture.source(for: directChild))
    }
}
