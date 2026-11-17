import XCTest
@testable import YMM4Core

// MARK: - 偽の実装（Source 契約の検証用）

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
