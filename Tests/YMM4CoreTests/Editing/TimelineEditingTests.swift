import XCTest
@testable import YMM4Core

final class TimelineEditingTests: XCTestCase {
    private func makeItem(frame: Int, length: Int, layer: Int, group: Int = 0) -> TextItem {
        let item = TextItem()
        item.frame = frame
        item.length = length
        item.layer = layer
        item.group = group
        return item
    }

    // MARK: - 衝突解決の探索順

    /// 希望レイヤーが塞がっていれば増加方向を先に探す。
    func testResolveItemCollisionPrefersUpward() {
        let timeline = Timeline()
        let blocker5 = makeItem(frame: 0, length: 100, layer: 5)
        let blocker6 = makeItem(frame: 0, length: 100, layer: 6)
        let item = makeItem(frame: 10, length: 50, layer: 5)
        timeline.items = [blocker5, blocker6, item]
        timeline.resolveItemCollision(item)
        // 7 が空いていて 4 も空いているが、増加方向が優先される
        XCTAssertEqual(item.layer, 7)
    }

    /// 増加方向が 999 まで塞がっている場合だけ減少方向へ回る。
    func testResolveItemCollisionWrapsToDownward() {
        let timeline = Timeline()
        var items: [BaseItem] = []
        for layer in 5...998 {
            items.append(makeItem(frame: 0, length: 100, layer: layer))
        }
        let item = makeItem(frame: 10, length: 50, layer: 5)
        items.append(item)
        timeline.items = items
        timeline.resolveItemCollision(item)
        XCTAssertEqual(item.layer, 4)
    }

    /// TryAddItems でも同じ探索順（希望→増加→最小側から希望の直前）。
    func testTryAddItemsLayerSearchOrder() {
        let timeline = Timeline()
        var blockers: [BaseItem] = []
        for layer in [0, 1, 2] + Array(5...999) {
            blockers.append(makeItem(frame: 0, length: 100, layer: layer))
        }
        timeline.items = blockers
        let item = makeItem(frame: 0, length: 10, layer: 0)
        let added = timeline.tryAddItems([item], frame: 0, layer: 5)
        XCTAssertTrue(added)
        // 5...999 は塞がり、0,1,2 も塞がっているため、最小側の探索で 3 に落ちる
        XCTAssertEqual(item.layer, 3)
        XCTAssertTrue(timeline.items.contains(where: { $0 === item }))
    }

    /// TryAddItems の前処理: アイテム同士の衝突はレイヤーを上げて解消され、
    /// グループ ID は再発行される（単独グループは解散する）。
    func testTryAddItemsPreprocessing() {
        let timeline = Timeline()
        let first = makeItem(frame: 0, length: 50, layer: 0, group: 5)
        let second = makeItem(frame: 25, length: 50, layer: 0, group: 5)
        let solo = makeItem(frame: 200, length: 10, layer: 3, group: 9)
        XCTAssertTrue(timeline.tryAddItems([first, second], frame: 0, layer: 0))
        // ResolveItemCollisionInItems は「自分と重なる他者がいる側」を
        // 上げるため、先に処理される first が上がる（本家の挙動）
        XCTAssertEqual(first.layer, 1)
        XCTAssertEqual(second.layer, 0)
        // 2つのグループは新しい ID（種 0 から発行して 1）へ再発行される
        XCTAssertEqual(first.group, 1)
        XCTAssertEqual(second.group, 1)

        XCTAssertTrue(timeline.tryAddItems([solo], frame: 200, layer: 3))
        // 単独グループは解散する
        XCTAssertEqual(solo.group, 0)
    }

    /// 全レイヤーが塞がっている場合は追加されず false。ただし前処理による
    /// 入力の書き換え（グループ解散）は戻らない（本家の意味論）。
    func testTryAddItemsFailureKeepsPreprocessingMutation() {
        let timeline = Timeline()
        var blockers: [BaseItem] = []
        for layer in 0...999 {
            blockers.append(makeItem(frame: 0, length: 10_000, layer: layer))
        }
        timeline.items = blockers
        let item = makeItem(frame: 0, length: 10, layer: 0, group: 7)
        XCTAssertFalse(timeline.tryAddItems([item], frame: 0, layer: 0))
        XCTAssertFalse(timeline.items.contains(where: { $0 === item }))
        XCTAssertEqual(item.group, 0)
    }

    // MARK: - グループ移動のデルタ縮小

    /// 移動先で衝突する場合は衝突相手の手前までデルタが縮小される。
    func testGroupMoveShrinksDeltaFrame() {
        let timeline = Timeline()
        let a = makeItem(frame: 10, length: 10, layer: 0, group: 1)
        let b = makeItem(frame: 30, length: 10, layer: 0, group: 1)
        let blocker = makeItem(frame: 100, length: 10, layer: 0)
        timeline.items = [a, b, blocker]
        timeline.selectItems([a])
        timeline.moveSelectedAndGroupedItems(deltaFrame: 95, deltaLayer: 0)
        // 移動先でブロッカー (100..110) と重なるのは A (105..115) だけ。
        // 距離 15 の分だけデルタが縮み、95 - 15 = 80 になる
        XCTAssertEqual(a.frame, 90)
        XCTAssertEqual(b.frame, 110)
    }

    /// フレーム 0 未満へはみ出す移動は境界まで縮小される。
    func testGroupMoveClampsAtFrameZero() {
        let timeline = Timeline()
        let a = makeItem(frame: 10, length: 10, layer: 0, group: 1)
        timeline.items = [a]
        timeline.selectItems([a])
        timeline.moveSelectedAndGroupedItems(deltaFrame: -50, deltaLayer: 0)
        XCTAssertEqual(a.frame, 0)
    }

    // MARK: - 分割のキーフレーム連動

    /// キーフレーム対応型は切断位置の値で値列が再構築され、
    /// 非対応型の値列は変わらない。右側の ContentOffset は定数レートの
    /// 消費分だけ進む。
    func testSplitKeyFrameLinkage() {
        let timeline = Timeline()
        let item = TextItem()
        item.frame = 0
        item.length = 90
        item.keyFrames = KeyFrames(frames: [20, 50])
        item.x.animationType = .linear
        item.x.values = [0, 20, 50, 90].map { AnimationValue($0) }
        item.y.animationType = .random
        item.y.values = [AnimationValue(5), AnimationValue(15)]
        timeline.items = [item]

        let result = timeline.splitItems([item], frame: 35, mode: .both)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(timeline.items.count, 2)
        let left = timeline.items[0]
        let right = timeline.items[1]

        XCTAssertEqual(left.frame, 0)
        XCTAssertEqual(left.length, 35)
        XCTAssertEqual(left.keyFrames.frames, [20])
        let leftText = left as? TextItem
        XCTAssertEqual(leftText?.x.values.map { $0.value }, [0, 20, 35])

        XCTAssertEqual(right.frame, 35)
        XCTAssertEqual(right.length, 55)
        XCTAssertEqual(right.keyFrames.frames, [15])
        let rightText = right as? TextItem
        XCTAssertEqual(rightText?.x.values.map { $0.value }, [35, 50, 90])

        // キーフレーム非対応型（ランダム移動）の値列は変わらない
        XCTAssertEqual(leftText?.y.values.map { $0.value }, [5, 15])
        XCTAssertEqual(rightText?.y.values.map { $0.value }, [5, 15])

        // 定数レート 100% のため、右側の開始位置は 35 フレーム分進む
        XCTAssertEqual(right.contentOffset.ticks, 11_666_667)
        XCTAssertEqual(left.contentOffset.ticks, 0)
    }

    /// 非定数レートの分割では、右側の ContentOffset が積分テーブルから
    /// 求めた素材時刻になる。
    func testSplitWithNonConstantPlaybackRate() {
        let timeline = Timeline()
        let item = TextItem()
        item.frame = 0
        item.length = 90
        item.keyFrames = KeyFrames(frames: [45])
        // 再生速度: 100% → (45フレームで) 200% → 100% の直線変化
        item.playbackRate2.animationType = .linear
        item.playbackRate2.values = [AnimationValue(100), AnimationValue(200), AnimationValue(100)]
        item.contentLength = TimeSpanValue(ticks: 30_000_000) // 3秒
        timeline.items = [item]

        let result = timeline.splitItems([item], frame: 45, mode: .none)
        XCTAssertEqual(result.count, 2)
        let right = timeline.items[1]
        // 0..45 フレームの平均レートは 150% なので、消費は
        // 1.5 秒分 = 22,500,000 tick（台形積分は線形レートで厳密）
        XCTAssertEqual(right.contentOffset.ticks, 22_500_000, accuracy: 10)
    }

    /// 分割で単独になったグループは解散する。
    /// グループ ID の再発行は「分割対象＋断片」の集合に対して左右別々に
    /// 行われる（本家 SplitItemsCore の意味論）。
    func testSplitDissolvesSingleGroups() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 90, layer: 0, group: 3)
        let b = makeItem(frame: 200, length: 10, layer: 0, group: 3)
        timeline.items = [a, b]
        // グループごと分割する（本家の SplitSelectedAndGroupedItems の経路）
        timeline.splitItems([a, b], frame: 35, mode: .none)
        let left = timeline.items.first(where: { $0.frame == 0 })
        let right = timeline.items.first(where: { $0.frame == 35 })
        // 左断片は左側集合で単独になるため解散する
        XCTAssertEqual(left?.group, 0)
        // 右断片と b は右側集合で組を維持し、新しい ID へ再発行される
        XCTAssertNotEqual(right?.group, 0)
        XCTAssertNotEqual(right?.group, 3)
        XCTAssertEqual(right?.group, b.group)
    }

    // MARK: - ChangeFrameRate

    func testChangeFrameRateUp() {
        let timeline = Timeline()
        let item = makeItem(frame: 10, length: 30, layer: 0)
        item.keyFrames = KeyFrames(frames: [10, 20])
        timeline.items = [item]
        timeline.currentFrame = 45
        timeline.changeFrameRate(oldFps: 30, newFps: 60)
        XCTAssertEqual(item.frame, 20)
        XCTAssertEqual(item.length, 60)
        XCTAssertEqual(item.keyFrames.frames, [20, 40])
        XCTAssertEqual(timeline.currentFrame, 90)
    }

    func testChangeFrameRateDown() {
        let timeline = Timeline()
        let item = makeItem(frame: 10, length: 30, layer: 0)
        item.keyFrames = KeyFrames(frames: [10, 20])
        timeline.items = [item]
        timeline.currentFrame = 45
        timeline.changeFrameRate(oldFps: 30, newFps: 24)
        XCTAssertEqual(item.frame, 8)
        XCTAssertEqual(item.length, 24)
        XCTAssertEqual(item.keyFrames.frames, [8, 16])
        // CurrentFrame は整数演算: 45 * 24 / 30 = 36
        XCTAssertEqual(timeline.currentFrame, 36)
    }

    /// 縮小でキーフレームが潰れた場合は単調性を回復するよう修復される。
    func testChangeFrameRateRepairsKeyFrames() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 30, layer: 0)
        item.keyFrames = KeyFrames(frames: [1, 2])
        timeline.items = [item]
        timeline.changeFrameRate(oldFps: 30, newFps: 24)
        // 換算後は [0, 1] になるが、前方向修復で [1, 2] になる
        XCTAssertEqual(item.keyFrames.frames, [1, 2])
        XCTAssertEqual(item.length, 24)
    }

    /// 換算後に同一レイヤーで重なった場合は空レイヤーが挿入され、
    /// 重なるアイテムが下へずれる。
    func testChangeFrameRateInsertsLayerOnOverlap() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0)
        let b = makeItem(frame: 9, length: 10, layer: 0)
        timeline.items = [a, b]
        timeline.changeFrameRate(oldFps: 30, newFps: 24)
        XCTAssertEqual(a.layer, 0)
        XCTAssertEqual(b.layer, 1)
        XCTAssertEqual(timeline.layerSettings.items.map { $0.layer }, [0])
    }

    // MARK: - 削除

    /// 削除では Length / MaxLayer のキャッシュが再計算される。
    func testDeleteItemsRefreshesCache() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0)
        let b = makeItem(frame: 20, length: 10, layer: 5)
        let c = makeItem(frame: 40, length: 10, layer: 0)
        timeline.items = [a, b, c]
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 50)
        XCTAssertEqual(timeline.maxLayer, 5)
        timeline.deleteItems([b])
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertEqual(timeline.length, 50)
        XCTAssertEqual(timeline.maxLayer, 0)
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

    // MARK: - スナップ（GetSnappedDelta）

    /// 近傍レイヤーの他アイテムの終了位置へ吸着する。
    func testGetSnappedDeltaSnapsToNeighborEnd() {
        let timeline = Timeline()
        let moving = makeItem(frame: 50, length: 10, layer: 0)
        let other = makeItem(frame: 40, length: 20, layer: 1)
        timeline.items = [moving, other]
        timeline.currentFrame = 0
        // 代表点 50 に +8 した 58 が、other の終了 60 へ吸着する
        let delta = timeline.getSnappedDelta(
            snapTargetFrames: [50], baseLayer: 0, frameDelta: 8,
            frameDistance: 5, layerDistance: 1, ignoreItems: [moving]
        )
        XCTAssertEqual(delta, 10)
        XCTAssertEqual(50 + delta, 60)
    }

    /// 同じレイヤーのアイテムと、layerDistance の外のアイテムは
    /// 候補にならない。
    func testGetSnappedDeltaIgnoresSameAndFarLayers() {
        let timeline = Timeline()
        let moving = makeItem(frame: 50, length: 10, layer: 0)
        let sameLayer = makeItem(frame: 40, length: 20, layer: 0)
        let farLayer = makeItem(frame: 40, length: 20, layer: 3)
        timeline.items = [moving, sameLayer, farLayer]
        timeline.currentFrame = 0
        let delta = timeline.getSnappedDelta(
            snapTargetFrames: [50], baseLayer: 0, frameDelta: 8,
            frameDistance: 5, layerDistance: 1, ignoreItems: [moving]
        )
        XCTAssertEqual(delta, 8)
    }

    /// 現在フレームも吸着先の候補になる。
    func testGetSnappedDeltaSnapsToCurrentFrame() {
        let timeline = Timeline()
        let moving = makeItem(frame: 50, length: 10, layer: 0)
        timeline.items = [moving]
        timeline.currentFrame = 60
        let delta = timeline.getSnappedDelta(
            snapTargetFrames: [50], baseLayer: 0, frameDelta: 8,
            frameDistance: 5, layerDistance: 1, ignoreItems: [moving]
        )
        XCTAssertEqual(delta, 10)
    }

    /// 他アイテムのキーフレーム位置も候補になる。
    func testGetSnappedDeltaSnapsToKeyFrame() {
        let timeline = Timeline()
        let moving = makeItem(frame: 50, length: 10, layer: 0)
        let other = makeItem(frame: 40, length: 30, layer: 1)
        other.keyFrames = KeyFrames(frames: [18])
        timeline.items = [moving, other]
        timeline.currentFrame = 0
        // キーフレーム絶対位置 58 は代表点 58 と一致するため移動量は不変
        let delta = timeline.getSnappedDelta(
            snapTargetFrames: [50], baseLayer: 0, frameDelta: 8,
            frameDistance: 5, layerDistance: 1, ignoreItems: [moving]
        )
        XCTAssertEqual(delta, 8)
    }

    /// extraSnapPoints も候補になり、ignoreItems のアイテムは候補から
    /// 外れる。代表点が空なら移動量はそのまま返る。
    func testGetSnappedDeltaExtraPointsAndIgnores() {
        let timeline = Timeline()
        let moving = makeItem(frame: 50, length: 10, layer: 0)
        let ignored = makeItem(frame: 40, length: 20, layer: 1)
        timeline.items = [moving, ignored]
        timeline.currentFrame = 0
        // ignored の終了 60 は候補から外れるが、extraSnapPoints の 60 は残る
        let delta = timeline.getSnappedDelta(
            snapTargetFrames: [50], baseLayer: 0, frameDelta: 8,
            frameDistance: 5, layerDistance: 1,
            ignoreItems: [moving, ignored], extraSnapPoints: [60]
        )
        XCTAssertEqual(delta, 10)
        XCTAssertEqual(
            timeline.getSnappedDelta(
                snapTargetFrames: [], baseLayer: 0, frameDelta: 8,
                frameDistance: 5, layerDistance: 1, ignoreItems: [moving]
            ),
            8
        )
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
}
