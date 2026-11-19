import XCTest
@testable import YMM4Core

final class TimelineEditingLengthTests: XCTestCase {
    private func makeItem(frame: Int, length: Int, layer: Int, group: Int = 0) -> TextItem {
        let item = TextItem()
        item.frame = frame
        item.length = length
        item.layer = layer
        item.group = group
        return item
    }

    // MARK: - DeleteAndMove

    /// DeleteAndMove は同じレイヤーの後続だけを詰める。
    func testDeleteAndMoveShiftsSameLayerOnly() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0)
        let b = makeItem(frame: 20, length: 10, layer: 0)
        let c = makeItem(frame: 20, length: 10, layer: 1)
        timeline.items = [a, b, c]
        timeline.selectItems([a])
        timeline.deleteAndMove()
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertEqual(b.frame, 10)
        XCTAssertEqual(c.frame, 20)
    }

    /// DeleteAndMove の現在フレームは「対象の開始位置まで戻す」式
    /// （本家の実コードどおり。DeleteAndMoveAll の式とは非対称）。
    func testDeleteAndMovePlayheadGoesToDeletedStart() {
        let timeline = Timeline()
        let a = makeItem(frame: 10, length: 10, layer: 0)
        timeline.items = [a]
        timeline.selectItems([a])
        timeline.currentFrame = 25
        // 25 - max(25 - 10, 0) = 10（区間の長さだけ引くのではない）
        XCTAssertEqual(timeline.deleteAndMove(), 10)

        let timeline2 = Timeline()
        let b = makeItem(frame: 10, length: 10, layer: 0)
        timeline2.items = [b]
        timeline2.selectItems([b])
        timeline2.currentFrame = 5
        // 対象より手前にある場合は動かない
        XCTAssertEqual(timeline2.deleteAndMove(), 5)
    }

    /// 同じレイヤーで複数選択すると、詰めが累積する。
    func testDeleteAndMoveMultipleSelectionAccumulates() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0)
        let b = makeItem(frame: 20, length: 10, layer: 0)
        let c = makeItem(frame: 50, length: 10, layer: 0)
        timeline.items = [a, b, c]
        timeline.selectItems([a, b])
        timeline.deleteAndMove()
        XCTAssertEqual(timeline.items.count, 1)
        // A の削除で 40、B（10へ移動済み）の削除でさらに詰めて 30
        XCTAssertEqual(c.frame, 30)
    }

    /// グループはまとめて削除され、各レイヤーで詰めが起きる。
    func testDeleteAndMoveGroupedItems() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0, group: 1)
        let b = makeItem(frame: 0, length: 20, layer: 1, group: 1)
        let c = makeItem(frame: 30, length: 10, layer: 0)
        let d = makeItem(frame: 30, length: 10, layer: 1)
        timeline.items = [a, b, c, d]
        timeline.selectItems([a])
        timeline.deleteAndMove()
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertEqual(c.frame, 20)
        XCTAssertEqual(d.frame, 10)
    }

    /// 選択が無い場合と空タイムラインでは現在フレームがそのまま返る。
    func testDeleteAndMoveWithoutSelection() {
        let timeline = Timeline()
        timeline.currentFrame = 7
        XCTAssertEqual(timeline.deleteAndMove(), 7)
        let a = makeItem(frame: 0, length: 10, layer: 0)
        timeline.items = [a]
        XCTAssertEqual(timeline.deleteAndMove(), 7)
        XCTAssertEqual(timeline.items.count, 1)
        XCTAssertEqual(timeline.deleteAndMoveAll(), 7)
        XCTAssertEqual(timeline.items.count, 1)
    }

    // MARK: - DeleteAndMoveAll

    /// DeleteAndMoveAll は全レイヤーの後続を詰め、現在フレームは
    /// 空き区間と重なる分だけ戻る。
    func testDeleteAndMoveAllShiftsAllLayers() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0)
        let b = makeItem(frame: 20, length: 10, layer: 0)
        let c = makeItem(frame: 20, length: 10, layer: 1)
        timeline.items = [a, b, c]
        timeline.selectItems([a])
        timeline.currentFrame = 25
        XCTAssertEqual(timeline.deleteAndMoveAll(), 15)
        XCTAssertEqual(b.frame, 10)
        XCTAssertEqual(c.frame, 10)
    }

    /// 削除区間が他レイヤーのアイテムに覆われている部分は詰めない。
    func testDeleteAndMoveAllCoveredSpaceIsNotShifted() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0)
        let cover = makeItem(frame: 0, length: 30, layer: 1)
        let b = makeItem(frame: 40, length: 10, layer: 0)
        timeline.items = [a, cover, b]
        timeline.selectItems([a])
        timeline.currentFrame = 25
        // 区間 (0, 10) は cover に完全に覆われるため空き区間は無く、
        // 何も詰まらず現在フレームも動かない
        XCTAssertEqual(timeline.deleteAndMoveAll(), 25)
        XCTAssertEqual(b.frame, 40)
        XCTAssertEqual(timeline.items.count, 2)
    }

    /// 部分的に覆われた場合は、覆われていない部分だけが詰まる。
    /// 覆っているアイテム自体も空き区間の後ろにあれば詰めの対象になる
    /// （本家は Items 全体へ適用する）。
    func testDeleteAndMoveAllPartiallyCoveredSpace() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0)
        let cover = makeItem(frame: 5, length: 10, layer: 1)
        let b = makeItem(frame: 20, length: 10, layer: 2)
        timeline.items = [a, cover, b]
        timeline.selectItems([a])
        timeline.currentFrame = 25
        // 空き区間は (0, 5) のみ。frame >= 5 のものが 5 詰まる
        XCTAssertEqual(timeline.deleteAndMoveAll(), 20)
        XCTAssertEqual(cover.frame, 0)
        XCTAssertEqual(b.frame, 15)
    }

    // MARK: - 長さ変更（開始側）

    /// 開始側の短縮: 終了フレームは固定で、ContentOffset は定数レートの
    /// 消費分だけ進み、キーフレームは開始の移動に連動する。
    func testChangeItemsStartShrink() {
        let timeline = Timeline()
        let item = makeItem(frame: 10, length: 30, layer: 0)
        item.keyFrames = KeyFrames(frames: [15])
        timeline.items = [item]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 10, head: true, neighborAffect: .none
        )
        XCTAssertEqual(item.frame, 20)
        XCTAssertEqual(item.length, 20)
        XCTAssertEqual(item.keyFrames.frames, [5])
        // 10 フレーム = 3,333,333 tick（30fps、レート 100%）
        XCTAssertEqual(item.contentOffset.ticks, 3_333_333)
    }

    /// 開始側の短縮は先頭キーフレームの手前までしか進まない
    /// （キーフレームが相対位置 1 以上に残るよう制限される）。
    func testChangeItemsStartShrinkLimitedByFirstKeyFrame() {
        let timeline = Timeline()
        let item = makeItem(frame: 10, length: 30, layer: 0)
        item.keyFrames = KeyFrames(frames: [5])
        timeline.items = [item]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 10, head: true, neighborAffect: .none
        )
        // 制限は min(30, 5) - 1 = 4
        XCTAssertEqual(item.frame, 14)
        XCTAssertEqual(item.length, 26)
        XCTAssertEqual(item.keyFrames.frames, [1])
    }

    /// 開始側の伸長（None）は左隣の終了位置までで止まる。
    func testChangeItemsStartExpandBlockedByNeighbor() {
        let timeline = Timeline()
        let neighbor = makeItem(frame: 0, length: 10, layer: 0)
        let item = makeItem(frame: 20, length: 10, layer: 0)
        timeline.items = [neighbor, item]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: -15, head: true, neighborAffect: .none
        )
        XCTAssertEqual(item.frame, 10)
        XCTAssertEqual(item.length, 20)
        XCTAssertEqual(neighbor.length, 10)
    }

    /// 開始側の伸長はフレーム 0 で止まる。
    func testChangeItemsStartExpandClampedAtFrameZero() {
        let timeline = Timeline()
        let item = makeItem(frame: 5, length: 10, layer: 0)
        timeline.items = [item]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: -10, head: true, neighborAffect: .none
        )
        XCTAssertEqual(item.frame, 0)
        XCTAssertEqual(item.length, 15)
    }

    /// Stretch の開始側伸長では、重なった左隣の終了側が切り取られる。
    /// 左隣のグループ全員にも同じ長さ変更が及ぶ。
    func testChangeItemsStartStretchTrimsNeighbor() {
        let timeline = Timeline()
        let neighbor = makeItem(frame: 0, length: 20, layer: 0, group: 7)
        let mate = makeItem(frame: 100, length: 20, layer: 5, group: 7)
        let item = makeItem(frame: 20, length: 10, layer: 0)
        timeline.items = [neighbor, mate, item]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: -8, head: true, neighborAffect: .stretch
        )
        XCTAssertEqual(item.frame, 12)
        XCTAssertEqual(item.length, 18)
        XCTAssertEqual(neighbor.length, 12)
        XCTAssertEqual(mate.length, 12)
        XCTAssertEqual(mate.frame, 100)
    }

    /// Stretch の開始側短縮では、接していた左隣がその分だけ伸びる。
    func testChangeItemsStartStretchExtendsNeighbor() {
        let timeline = Timeline()
        let neighbor = makeItem(frame: 0, length: 10, layer: 0)
        let item = makeItem(frame: 10, length: 20, layer: 0)
        timeline.items = [neighbor, item]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 5, head: true, neighborAffect: .stretch
        )
        XCTAssertEqual(item.frame, 15)
        XCTAssertEqual(item.length, 15)
        XCTAssertEqual(neighbor.length, 15)
    }

    /// 非定数レートでの開始側短縮では、ContentOffset が積分テーブルで
    /// 換算される（分割の非定数ケースと同じレート形状）。
    func testChangeItemsStartWithNonConstantPlaybackRate() {
        let timeline = Timeline()
        let item = TextItem()
        item.frame = 0
        item.length = 90
        item.keyFrames = KeyFrames(frames: [45])
        item.playbackRate2.animationType = .linear
        item.playbackRate2.values = [AnimationValue(100), AnimationValue(200), AnimationValue(100)]
        timeline.items = [item]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 30, head: true, neighborAffect: .none
        )
        XCTAssertEqual(item.frame, 30)
        XCTAssertEqual(item.length, 60)
        XCTAssertEqual(item.keyFrames.frames, [15])
        // 0..30 フレームの平均レートは 133.33% で、消費は 1 秒分の
        // 1.3333 倍 = 13,333,333 tick
        XCTAssertEqual(item.contentOffset.ticks, 13_333_333, accuracy: 5)
    }

    // MARK: - 長さ変更（終了側）

    /// 終了側の短縮は末尾キーフレームの分までしか進まない。
    /// 対象自身の ContentOffset とキーフレームは変わらない。
    func testChangeItemsEndShrinkLimitedByLastKeyFrame() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 30, layer: 0)
        item.keyFrames = KeyFrames(frames: [25])
        timeline.items = [item]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: -10, head: false, neighborAffect: .none
        )
        // 制限は -(min(30, 30 - 25) - 1) = -4
        XCTAssertEqual(item.length, 26)
        XCTAssertEqual(item.keyFrames.frames, [25])
        XCTAssertEqual(item.contentOffset.ticks, 0)
    }

    /// 終了側の伸長（None）は右隣の開始位置までで止まる。
    func testChangeItemsEndExpandBlockedByNeighbor() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 10, layer: 0)
        let neighbor = makeItem(frame: 15, length: 10, layer: 0)
        timeline.items = [item, neighbor]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 10, head: false, neighborAffect: .none
        )
        XCTAssertEqual(item.length, 15)
        XCTAssertEqual(neighbor.frame, 15)
    }

    /// Stretch の終了側短縮では、接していた右隣が開始側から切り取られ、
    /// ContentOffset（0 で丸め）とキーフレームも連動する。
    func testChangeItemsEndStretchPullsNeighbor() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 20, layer: 0)
        let neighbor = makeItem(frame: 20, length: 10, layer: 0)
        neighbor.keyFrames = KeyFrames(frames: [3])
        timeline.items = [item, neighbor]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: -5, head: false, neighborAffect: .stretch
        )
        XCTAssertEqual(item.length, 15)
        XCTAssertEqual(neighbor.frame, 15)
        XCTAssertEqual(neighbor.length, 15)
        // -5 フレーム分を加えると負になるため 0 に丸められる
        XCTAssertEqual(neighbor.contentOffset.ticks, 0)
        XCTAssertEqual(neighbor.keyFrames.frames, [8])
    }

    /// Stretch の終了側伸長では、重なった右隣が重なり分だけ後ろへ
    /// ずれる。ContentOffset は丸めなしで加算される。伸長量そのものも、
    /// 右隣が開始側から切り取れる量（先頭キーフレームの手前まで）で
    /// 制限される。
    func testChangeItemsEndStretchPushesNeighbor() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 20, layer: 0)
        let neighbor = makeItem(frame: 20, length: 10, layer: 0)
        neighbor.keyFrames = KeyFrames(frames: [3])
        timeline.items = [item, neighbor]
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 5, head: false, neighborAffect: .stretch
        )
        // 右隣の切り取り可能量は min(10, 3) - 1 = 2 のため、伸長は 2 に制限される
        XCTAssertEqual(item.length, 22)
        XCTAssertEqual(neighbor.frame, 22)
        XCTAssertEqual(neighbor.length, 8)
        // 2 フレーム = 666,667 tick（30fps）
        XCTAssertEqual(neighbor.contentOffset.ticks, 666_667)
        XCTAssertEqual(neighbor.keyFrames.frames, [1])
    }

    /// 変化量 0 と選択なしでは何も起きない。
    func testChangeItemsLengthNoopCases() {
        let timeline = Timeline()
        let item = makeItem(frame: 10, length: 20, layer: 0)
        timeline.items = [item]
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 5, head: true, neighborAffect: .none
        )
        XCTAssertEqual(item.frame, 10)
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 0, head: true, neighborAffect: .none
        )
        XCTAssertEqual(item.frame, 10)
        XCTAssertEqual(item.length, 20)
    }

    // MARK: - 空間を詰める削除（DeleteItemSpace 系）

    /// DeleteItemSpace: 詰める量は「前に終わるアイテムの終了位置」から
    /// 「次のアイテムの開始位置」までの間隔。他レイヤーは動かない。
    func testDeleteItemSpaceBasic() {
        let timeline = Timeline()
        let before = makeItem(frame: 0, length: 100, layer: 0)
        let after = makeItem(frame: 200, length: 50, layer: 0)
        let last = makeItem(frame: 400, length: 50, layer: 0)
        let otherLayer = makeItem(frame: 200, length: 50, layer: 1)
        timeline.items = [before, after, last, otherLayer]
        timeline.deleteItemSpace(layer: 0, frame: 120)
        XCTAssertEqual(before.frame, 0)
        XCTAssertEqual(after.frame, 100)
        XCTAssertEqual(last.frame, 300)
        XCTAssertEqual(otherLayer.frame, 200)
        XCTAssertEqual(timeline.length, 350)
    }

    /// DeleteItemSpace: frame が全アイテムより前なら、先頭アイテムの
    /// 開始位置までの間隔が詰まる（起点は既定の 0）。
    func testDeleteItemSpaceBeforeAllItems() {
        let timeline = Timeline()
        let first = makeItem(frame: 100, length: 50, layer: 0)
        let second = makeItem(frame: 200, length: 50, layer: 0)
        timeline.items = [first, second]
        timeline.deleteItemSpace(layer: 0, frame: 0)
        XCTAssertEqual(first.frame, 0)
        XCTAssertEqual(second.frame, 100)
    }

    /// DeleteItemSpace: 後続アイテムが無ければ何もしない
    /// （本家は例外になる前提条件外の呼び出しへの防御）。
    func testDeleteItemSpaceWithoutFollowingItem() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 100, layer: 0)
        timeline.items = [item]
        timeline.deleteItemSpace(layer: 0, frame: 200)
        XCTAssertEqual(item.frame, 0)
    }

    /// DeleteTimelineSpace: 全レイヤーの後続が詰まり、詰めた量が返る。
    /// 判定は開始位置だけに基づく（frame 以前に始まるアイテムは動かない）。
    func testDeleteTimelineSpace() {
        let timeline = Timeline()
        let before = makeItem(frame: 0, length: 100, layer: 0)
        let after = makeItem(frame: 200, length: 50, layer: 1)
        let last = makeItem(frame: 400, length: 50, layer: 0)
        timeline.items = [before, after, last]
        let shift = timeline.deleteTimelineSpace(frame: 150)
        XCTAssertEqual(shift, 50)
        XCTAssertEqual(before.frame, 0)
        XCTAssertEqual(after.frame, 150)
        XCTAssertEqual(last.frame, 350)
        // frame 以後に始まるアイテムが無ければ 0 で何もしない
        XCTAssertEqual(timeline.deleteTimelineSpace(frame: 1000), 0)
        XCTAssertEqual(last.frame, 350)
    }

    /// DeleteAllLayerSpaces: 先行空間も含めて全ての間隔が詰まる。
    func testDeleteAllLayerSpaces() {
        let timeline = Timeline()
        let first = makeItem(frame: 50, length: 50, layer: 0)
        let second = makeItem(frame: 200, length: 50, layer: 0)
        let third = makeItem(frame: 300, length: 100, layer: 0)
        let otherLayer = makeItem(frame: 500, length: 50, layer: 1)
        timeline.items = [first, second, third, otherLayer]
        timeline.deleteAllLayerSpaces(layer: 0)
        XCTAssertEqual(first.frame, 0)
        XCTAssertEqual(second.frame, 50)
        XCTAssertEqual(third.frame, 100)
        XCTAssertEqual(otherLayer.frame, 500)
    }

    /// DeleteAllTimelineSpaces: 被覆の判定はレイヤーをまたぐ
    /// （全アイテムをフレーム順に処理し、終了位置の最大で判定する）。
    func testDeleteAllTimelineSpacesAcrossLayers() {
        let timeline = Timeline()
        let first = makeItem(frame: 100, length: 50, layer: 0)
        let second = makeItem(frame: 150, length: 50, layer: 1)
        let third = makeItem(frame: 400, length: 50, layer: 0)
        timeline.items = [first, second, third]
        timeline.deleteAllTimelineSpaces()
        // first は 0 へ。second は first の終了 (50) に接する位置 50 へ。
        // third は被覆最大 100 まで詰まって 100 へ。
        XCTAssertEqual(first.frame, 0)
        XCTAssertEqual(second.frame, 50)
        XCTAssertEqual(third.frame, 100)
    }

    /// DeleteIsolatedRanges: 他アイテムが無い選択範囲は丸ごと削除される。
    func testDeleteIsolatedRangesRemovesIsolatedSelection() {
        let timeline = Timeline()
        let first = makeItem(frame: 100, length: 50, layer: 0)
        let second = makeItem(frame: 200, length: 50, layer: 0)
        timeline.items = [first, second]
        timeline.selectItems([first, second])
        timeline.deleteIsolatedRanges()
        XCTAssertTrue(timeline.items.isEmpty)
        XCTAssertTrue(timeline.selectedItems.isEmpty)
    }

    /// DeleteIsolatedRanges: 他アイテムに覆われた部分は残り、
    /// 覆われていない前後の部分だけが削除され、残りは前へ詰まる。
    func testDeleteIsolatedRangesKeepsCoveredPart() throws {
        let timeline = Timeline()
        let selected = makeItem(frame: 100, length: 200, layer: 0)
        let cover = makeItem(frame: 150, length: 100, layer: 1)
        timeline.items = [selected, cover]
        timeline.selectItems([selected])
        timeline.deleteIsolatedRanges()
        // 選択アイテムは 150...250 の部分だけが残り、カバー側と一緒に
        // 100 へ詰まる
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertEqual(cover.frame, 100)
        let remaining = try XCTUnwrap(timeline.selectedItems.first)
        XCTAssertEqual(remaining.frame, 100)
        XCTAssertEqual(remaining.length, 100)
        XCTAssertEqual(remaining.layer, 0)
    }

    /// DeleteIsolatedRanges: 選択が空なら何もしない。
    func testDeleteIsolatedRangesWithoutSelection() {
        let timeline = Timeline()
        let item = makeItem(frame: 100, length: 50, layer: 0)
        timeline.items = [item]
        timeline.deleteIsolatedRanges()
        XCTAssertEqual(timeline.items.count, 1)
        XCTAssertEqual(item.frame, 100)
    }

    // MARK: - ドラッグ確定時の長さ再計算（FE-R9-001）

    /// 移動は長さキャッシュを Expand（広げるだけ）するため、末尾の
    /// アイテムを手前へ動かしてもキャッシュは縮まない。アプリ層は
    /// ドラッグ確定時に refreshTimelineLengthAndMaxLayer を呼び、
    /// 実際の最終フレーム・最大レイヤーへ一致させる契約。
    func testRefreshAfterMoveShrinksLengthAndMaxLayerCache() {
        let timeline = Timeline()
        let item = makeItem(frame: 80, length: 20, layer: 5)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 100)
        XCTAssertEqual(timeline.maxLayer, 5)
        timeline.selectItems([item])
        timeline.moveSelectedAndGroupedItems(deltaFrame: -40, deltaLayer: -3)
        XCTAssertEqual(item.frame, 40)
        XCTAssertEqual(item.layer, 2)
        // 移動だけではキャッシュは縮まない（Expand のみ）。
        XCTAssertEqual(timeline.length, 100)
        XCTAssertEqual(timeline.maxLayer, 5)
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 60)
        XCTAssertEqual(timeline.maxLayer, 2)
    }

    /// 終了側トリムで末尾アイテムを短縮した場合も、確定時の再計算で
    /// キャッシュが実際の終了フレームへ縮む。
    func testRefreshAfterEndTrimShrinksLengthCache() {
        let timeline = Timeline()
        let item = makeItem(frame: 80, length: 20, layer: 0)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 100)
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: -10, head: false, neighborAffect: .none
        )
        XCTAssertEqual(item.length, 10)
        XCTAssertEqual(timeline.length, 100)
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 90)
    }

    /// 開始側トリムは終了フレームを動かさないため、再計算後も長さは
    /// 終了フレームどおり（過剰に縮まない）。
    func testRefreshAfterHeadTrimKeepsLengthAtEndFrame() {
        let timeline = Timeline()
        let item = makeItem(frame: 80, length: 20, layer: 0)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: 10, head: true, neighborAffect: .none
        )
        XCTAssertEqual(item.frame, 90)
        XCTAssertEqual(item.length, 10)
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 100)
    }

    /// Stretch の終了側短縮では右隣が伸びて接するため、再計算後の
    /// 長さは両者の終了フレームの最大と一致する。
    func testRefreshAfterStretchTrimMatchesComputedLength() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 20, layer: 0)
        let neighbor = makeItem(frame: 20, length: 10, layer: 0)
        timeline.items = [item, neighbor]
        timeline.refreshTimelineLengthAndMaxLayer()
        timeline.selectItems([item])
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: -5, head: false, neighborAffect: .stretch
        )
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, timeline.computeCurrentLength())
        XCTAssertEqual(timeline.length, 30)
    }

    /// 後方への移動では再計算しても長さは実際の終了フレームのまま
    /// （縮む方向にだけ効き、広がった分は保持される）。
    func testRefreshAfterMoveLaterKeepsExpandedLength() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 20, layer: 0)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        timeline.selectItems([item])
        timeline.moveSelectedAndGroupedItems(deltaFrame: 50, deltaLayer: 0)
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 70)
    }
}
