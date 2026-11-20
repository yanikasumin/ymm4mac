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

    // MARK: - グループ解除の戻り値（未保存フラグの発火判定用）

    /// グループ化された選択を解除すると true を返し、全員の group が 0 になる。
    func testUngroupSelectedAndGroupedItemsReturnsTrueWhenDissolved() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 90, layer: 0, group: 3)
        let b = makeItem(frame: 200, length: 10, layer: 0, group: 3)
        timeline.items = [a, b]
        timeline.selectItems([a])
        XCTAssertTrue(timeline.ungroupSelectedAndGroupedItems())
        XCTAssertEqual(a.group, 0)
        XCTAssertEqual(b.group, 0)
    }

    /// 未グループの選択へ解除を実行しても何も変わらず、false を返す。
    /// アプリメニューのように表示条件の無い経路から実行されても、
    /// 呼び出し側が未保存フラグを立てずに済むための約束。
    func testUngroupSelectedAndGroupedItemsReturnsFalseWhenNotGrouped() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 90, layer: 0)
        timeline.items = [a]
        timeline.selectItems([a])
        XCTAssertFalse(timeline.ungroupSelectedAndGroupedItems())
        XCTAssertEqual(a.group, 0)
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

    // MARK: - 選択ヘルパ（本家 SelectItem / ToggleSelectionStatus / SelectBetweenItems）

    func testSelectItemAndToggleSelectionStatus() {
        let timeline = Timeline()
        let a = makeItem(frame: 0, length: 10, layer: 0)
        let b = makeItem(frame: 20, length: 10, layer: 0)
        timeline.items = [a, b]
        timeline.selectItem(a)
        XCTAssertEqual(timeline.selectedItems.count, 1)
        XCTAssertTrue(timeline.selectedItems.first === a)
        timeline.toggleSelectionStatus(b)
        XCTAssertEqual(timeline.selectedItems.count, 2)
        timeline.toggleSelectionStatus(a)
        XCTAssertEqual(timeline.selectedItems.count, 1)
        XCTAssertTrue(timeline.selectedItems.first === b)
    }

    /// アンカー（選択先頭）から対象までの矩形内が選択になる。
    /// 並びはアンカー→中間（Items の順）→対象。
    func testSelectBetweenItemsToItem() {
        let timeline = Timeline()
        let anchor = makeItem(frame: 0, length: 10, layer: 0)
        let middle = makeItem(frame: 15, length: 10, layer: 1)
        let outside = makeItem(frame: 15, length: 10, layer: 3)
        let target = makeItem(frame: 30, length: 10, layer: 1)
        timeline.items = [anchor, middle, outside, target]
        timeline.selectItem(anchor)
        timeline.selectBetweenItems(to: target)
        XCTAssertEqual(timeline.selectedItems.count, 3)
        XCTAssertTrue(timeline.selectedItems[0] === anchor)
        XCTAssertTrue(timeline.selectedItems[1] === middle)
        XCTAssertTrue(timeline.selectedItems[2] === target)
    }

    /// 選択が空なら対象だけが選択になる（本家 SelectBetweenItems の頭）。
    func testSelectBetweenItemsWithEmptySelection() {
        let timeline = Timeline()
        let target = makeItem(frame: 30, length: 10, layer: 1)
        timeline.items = [target]
        timeline.selectBetweenItems(to: target)
        XCTAssertEqual(timeline.selectedItems.count, 1)
        XCTAssertTrue(timeline.selectedItems.first === target)
    }

    /// 矩形（フレーム×レイヤー）版: レイヤー範囲外と区間外は入らない。
    func testSelectBetweenItemsRect() {
        let timeline = Timeline()
        let inside = makeItem(frame: 12, length: 5, layer: 1)
        let layerOut = makeItem(frame: 12, length: 5, layer: 2)
        let frameOut = makeItem(frame: 40, length: 5, layer: 1)
        timeline.items = [inside, layerOut, frameOut]
        timeline.selectBetweenItems(fromFrame: 10, fromLayer: 0, toFrame: 20, toLayer: 1)
        XCTAssertEqual(timeline.selectedItems.count, 1)
        XCTAssertTrue(timeline.selectedItems.first === inside)
    }

    // MARK: - 複製（本家 UnsafeCloneWithoutCollision）

    /// 複製は同じ位置に増え、選択は元の側に残り、グループは再発行される。
    func testUnsafeCloneWithoutCollision() {
        let timeline = Timeline()
        let a = makeItem(frame: 10, length: 20, layer: 1, group: 5)
        let b = makeItem(frame: 40, length: 20, layer: 1, group: 5)
        let other = makeItem(frame: 100, length: 10, layer: 0)
        timeline.items = [a, b, other]
        timeline.selectItem(a)
        timeline.unsafeCloneWithoutCollision()
        XCTAssertEqual(timeline.items.count, 5)
        // 選択は元の2つのまま（複製は選択されない）
        XCTAssertEqual(timeline.selectedItems.count, 1)
        XCTAssertTrue(timeline.selectedItems.first === a)
        let clones = timeline.items.filter { $0 !== a && $0 !== b && $0 !== other }
        XCTAssertEqual(clones.count, 2)
        // 複製は元の位置・レイヤー・長さを保つ
        XCTAssertTrue(clones.contains(where: { $0.frame == 10 && $0.layer == 1 && $0.length == 20 }))
        XCTAssertTrue(clones.contains(where: { $0.frame == 40 && $0.layer == 1 && $0.length == 20 }))
        // グループは元の 5 とは別の新しい ID で、複製同士は同じ ID
        XCTAssertNotEqual(clones[0].group, 0)
        XCTAssertNotEqual(clones[0].group, 5)
        XCTAssertEqual(clones[0].group, clones[1].group)
        XCTAssertEqual(a.group, 5)
    }

    /// 選択が空なら何も増えない。
    func testUnsafeCloneWithoutCollisionEmptySelection() {
        let timeline = Timeline()
        timeline.items = [makeItem(frame: 0, length: 10, layer: 0)]
        timeline.unsafeCloneWithoutCollision()
        XCTAssertEqual(timeline.items.count, 1)
    }
}
