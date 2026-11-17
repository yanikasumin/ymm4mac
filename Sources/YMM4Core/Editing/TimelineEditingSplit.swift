import Foundation

public extension Timeline {
    // MARK: - 分割（本家 SplitItems 系）

    /// 分割対象になるアイテム。本家 `GetSplitTargets` の条件。
    static func splitTargets(_ targets: [BaseItem], frame: Int) -> [BaseItem] {
        targets.filter { 1 < $0.length && $0.frame != frame && $0.contains(frame: frame) }
    }

    /// 分割の核処理。本家 `SplitItemsCore`。
    ///
    /// 左右の断片集合について、タイムライン全体を種としてグループ ID を
    /// 再発行する（分割で単独になったグループは解散する）。
    func splitItemsCore(
        timelineItems: [BaseItem], targets: [BaseItem], frame: Int
    ) -> (removes: [BaseItem], adds: [BaseItem]) {
        if targets.isEmpty { return ([], []) }
        let targetsToSplit = Self.splitTargets(targets, frame: frame)
        if targetsToSplit.isEmpty { return ([], []) }
        var adds: [BaseItem] = []
        for target in targetsToSplit {
            let (left, right) = target.split(atRelativeFrame: frame - target.frame)
            adds.append(left)
            adds.append(right)
        }
        let source = excludingIdentities(targets, targetsToSplit) + adds
        let lefts = source.filter { $0.frame + $0.length <= frame }
        let rights = source.filter { frame <= $0.frame }
        renewGroupIDs(lefts, allItems: timelineItems)
        renewGroupIDs(rights, allItems: timelineItems)
        return (targetsToSplit, adds)
    }

    /// アイテム群を指定フレームで分割する。本家 `SplitItems`。
    ///
    /// 分割後の選択はモードに従う。Center モードは連続する分割の
    /// 履歴（splitFrames）を使い、2回目以降は「前回と今回の間の断片」を
    /// 選択する。戻り値は分割後の対象集合。
    @discardableResult
    func splitItems(
        _ targets: [BaseItem], frame: Int, mode: ItemSplitSelectionMode
    ) -> [BaseItem] {
        if targets.isEmpty { return [] }
        if prevSplitItems.contains(where: { prev in !targets.contains(where: { $0 === prev }) }) {
            splitFrames.removeAll()
        }
        splitFrames.append(frame)
        let (removes, adds) = splitItemsCore(timelineItems: items, targets: targets, frame: frame)
        replaceItems(removing: removes, adding: adds)
        let postSplit = excludingIdentities(targets, removes) + adds
        let lefts = postSplit.filter { $0.frame + $0.length <= frame }
        let rights = postSplit.filter { frame <= $0.frame }
        switch mode {
        case .none:
            selectItems([])
            splitFrames.removeAll()
        case .leftOnly:
            selectItems(lefts)
            splitFrames.removeAll()
        case .rightOnly:
            selectItems(rights)
            splitFrames.removeAll()
        case .both:
            selectItems(postSplit)
            splitFrames.removeAll()
        case .center:
            if splitFrames.count >= 2 {
                let from = splitFrames.min() ?? frame
                let to = splitFrames.max() ?? frame
                splitFrames.removeAll()
                selectItems(postSplit.filter { $0.frame == from || $0.frame + $0.length == to })
                prevSplitItems = selectedItems
            } else {
                selectItems(postSplit)
                prevSplitItems = selectedItems
            }
        }
        return postSplit
    }

    /// 選択中アイテムとそのグループを指定フレームで分割する。
    func splitSelectedAndGroupedItems(frame: Int, mode: ItemSplitSelectionMode) {
        splitItems(selectedAndGroupedItems, frame: frame, mode: mode)
    }

    // MARK: - フレームレート変更（本家 ChangeFrameRate）

    /// フレームレートを変更する。本家 `ChangeFrameRate(oldFps, newFps)`。
    ///
    /// 各アイテムの Frame / Length / キーフレーム位置を比率で換算し
    /// （切り捨て）、キーフレームの単調性と範囲を修復する。換算後に
    /// 同一レイヤーで重なりが生じたレイヤーには空レイヤーを挿入し、
    /// 重なるアイテムを後ろのフレームから順に下へずらす。影響範囲に
    /// ある GroupItem の GroupRange は広がる。CurrentFrame は整数演算で
    /// 換算する。
    func changeFrameRate(oldFps: Int, newFps: Int) {
        for item in items {
            Self.changeFrameRate(item: item, oldFps: oldFps, newFps: newFps)
        }
        var maxLayerValue = items.map { $0.layer }.max() ?? 0
        var layer = 0
        while layer <= maxLayerValue {
            defer { layer += 1 }
            let layerItems = items.filter { $0.layer == layer }
            if !Self.hasOverlappingItems(layerItems) {
                continue
            }
            maxLayerValue += 1
            layerSettings.insert(layerSettings.setting(forLayer: layer))
            let sorted = items.filter { $0.layer == layer }
                .sorted { $0.frame > $1.frame }
            for item in sorted {
                let overlaps = sorted.contains(where: { other in
                    other !== item && other.layer == layer
                        && item.intersectsWith(frame: other.frame, length: other.length)
                })
                if overlaps {
                    item.layer += 1
                }
            }
            for groupItem in items.compactMap({ $0 as? GroupItem })
            where groupItem.layer <= layer && layer <= groupItem.layer + groupItem.groupRange {
                groupItem.groupRange = min(999, groupItem.groupRange + 1)
            }
        }
        currentFrame = currentFrame * newFps / oldFps
        refreshTimelineLengthAndMaxLayer()
    }

    /// 1アイテムのフレームレート換算とキーフレーム修復。
    private static func changeFrameRate(item: BaseItem, oldFps: Int, newFps: Int) {
        let rate = Double(newFps) / Double(oldFps)
        item.frame = Int(Double(item.frame) * rate)
        item.length = Int(max(1.0, Double(item.length) * rate))
        var frames = item.keyFrames.frames.map { Int(Double($0) * rate) }
        // 前方向: 単調増加を回復する（前の値 + 1 以上へ引き上げる）
        var previous = 0
        for index in frames.indices {
            if frames[index] <= previous {
                frames[index] += previous - frames[index] + 1
            }
            previous = frames[index]
        }
        // 後方向: Length 未満へ引き下げる
        var limit = item.length
        var index = frames.count - 1
        while index >= 0 {
            if limit <= frames[index] {
                frames[index] -= frames[index] - limit + 1
            }
            limit = frames[index]
            index -= 1
        }
        // 先頭が 0 以下なら全体をずらして Length を伸ばす
        if let first = frames.first, first <= 0 {
            let delta = -first + 1
            item.length += delta
            frames = frames.map { $0 + delta }
        }
        item.setKeyFrames(KeyFrames(frames: frames))
        item.setFPS(newFps)
    }

    /// フレーム順に並べたとき隣接ペアが重なるか。本家 `HasOverlappingItems`。
    private static func hasOverlappingItems(_ targets: [BaseItem]) -> Bool {
        let sorted = targets.sorted { $0.frame < $1.frame }
        for index in 0..<max(0, sorted.count - 1) {
            if sorted[index].frame + sorted[index].length > sorted[index + 1].frame {
                return true
            }
        }
        return false
    }
}
