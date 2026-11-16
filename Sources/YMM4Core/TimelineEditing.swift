import Foundation

/// タイムラインの編集操作。本家 `Timeline` の編集系メソッドに対応する。
///
/// 意味論は本家の実コードを正とする。特に重要な性質:
/// - `tryAddItems` の原子的保証は `items` へのコミット段階のみで、
///   前処理（SetFPS・衝突解決・グループ ID 再発行）は入力アイテム自体を
///   書き換える。失敗しても入力は書き換わったまま戻る。
/// - 衝突時のレイヤー探索順は「希望位置から増加方向に 999 まで、
///   次に最小レイヤーから希望位置の直前まで」。
/// - 移動は失敗ではなく `getMovableDeltaFrame` でデルタを縮小する。
/// - グループは単独になると Group = 0 に解散する。

/// 参照同一性で要素を含むか（本家の ImmutableList.Except 等は参照等価）。
func containsIdentity(_ list: [BaseItem], _ item: BaseItem) -> Bool {
    list.contains(where: { $0 === item })
}

/// 参照同一性で対象を除いた配列。
func excludingIdentities(_ list: [BaseItem], _ targets: [BaseItem]) -> [BaseItem] {
    list.filter { element in !containsIdentity(targets, element) }
}

public extension Timeline {
    // MARK: - 基本操作（本家 AddItems / ReplaceItems / MoveItems / DeleteItems）

    /// アイテムを追加し、Length / MaxLayer のキャッシュを広げる。
    func addItems(_ newItems: [BaseItem]) {
        items = items + newItems
        expandTimelineLengthAndMaxLayer()
    }

    /// アイテムを置き換え、Length / MaxLayer のキャッシュを広げる。
    func replaceItems(removing: [BaseItem], adding: [BaseItem]) {
        items = excludingIdentities(items, removing) + adding
        expandTimelineLengthAndMaxLayer()
    }

    /// アイテムを移動し、Length / MaxLayer のキャッシュを広げる。
    func moveItems(_ targets: [BaseItem], deltaFrame: Int, deltaLayer: Int) {
        for item in targets {
            item.frame += deltaFrame
            item.layer += deltaLayer
        }
        expandTimelineLengthAndMaxLayer()
    }

    /// 衝突検証なしで削除し、Length / MaxLayer を再計算する。
    func deleteItemsWithoutCollisionValidation(_ targets: [BaseItem]) {
        items = excludingIdentities(items, targets)
        refreshTimelineLengthAndMaxLayer()
    }

    /// アイテムを削除する。本家 `DeleteItems`。
    func deleteItems(_ targets: [BaseItem]) {
        if !targets.isEmpty {
            deleteItemsWithoutCollisionValidation(targets)
        }
    }

    /// 選択中アイテムとそのグループを削除する。
    func deleteSelectedAndGroupedItems() {
        let targets = selectedAndGroupedItems
        if !targets.isEmpty {
            deleteItemsWithoutCollisionValidation(targets)
        }
    }

    // MARK: - 移動可能性と移動量の縮小

    /// 指定デルタで移動できるか。本家 `IsMovable`。
    ///
    /// 判定は「移動先レイヤーで、移動後区間と重なる他アイテムが無いこと」と
    /// 「フレーム・レイヤーが範囲 [0, 999] を出ないこと」。
    func isMovable(_ targets: [BaseItem], deltaFrame: Int, deltaLayer: Int) -> Bool {
        if targets.contains(where: {
            $0.frame + deltaFrame < 0 || $0.layer + deltaLayer < 0 || $0.layer + deltaLayer > 999
        }) {
            return false
        }
        let others = excludingIdentities(items, targets)
        for item in targets {
            for other in others where other.layer == item.layer + deltaLayer {
                if other.intersectsWith(frame: item.frame + deltaFrame, length: item.length) {
                    return false
                }
            }
        }
        return true
    }

    /// 移動可能なデルタへ縮小する。本家 `GetMovableDeltaFrame`。
    ///
    /// まず範囲外を境界まで戻し、それでも衝突する場合は衝突相手までの
    /// 距離の最大分だけフレームデルタを縮める。フレームデルタが 0 で
    /// 動けない場合はレイヤーデルタを 0 へ1つずつ寄せる。
    /// 本家では「移動不可なのに衝突相手が無い」場合は例外になる。
    /// ここでは到達不能なはずの分岐として fatalError にする。
    func getMovableDeltaFrame(
        _ targets: [BaseItem], deltaLayer: Int, deltaFrame: Int, extraDeltaFrame: Int
    ) -> (deltaLayer: Int, deltaFrame: Int) {
        var deltaLayer = deltaLayer
        var dFrame = deltaFrame + extraDeltaFrame
        while true {
            if isMovable(targets, deltaFrame: dFrame, deltaLayer: deltaLayer)
                || (dFrame == 0 && deltaLayer == 0) {
                return (deltaLayer, dFrame)
            }
            if dFrame == 0 {
                // 本家は Math.Sign(deltaLayer) * -1 を加える。
                // ここに来る時点で deltaLayer != 0（0 なら上で return 済み）。
                deltaLayer += deltaLayer > 0 ? -1 : 1
                dFrame = deltaFrame
                continue
            }
            let minFrame = targets.map { $0.frame + dFrame }.min() ?? 0
            let minLayer = targets.map { $0.layer + deltaLayer }.min() ?? 0
            let maxLayerValue = targets.map { $0.layer + deltaLayer }.max() ?? 0
            if dFrame < 0 && minFrame < 0 {
                dFrame += -minFrame
                continue
            }
            if deltaLayer < 0 && minLayer < 0 {
                deltaLayer += -minLayer
                continue
            }
            if 0 < deltaLayer && maxLayer < maxLayerValue {
                deltaLayer -= maxLayerValue - maxLayer
                continue
            }
            let others = excludingIdentities(items, targets)
            var distances: [Int] = []
            for item in targets {
                for other in others where item.layer + deltaLayer == other.layer {
                    if other.intersectsWith(frame: item.frame + dFrame, length: item.length) {
                        if dFrame <= 0 {
                            distances.append(other.frame + other.length - (item.frame + dFrame))
                        } else {
                            distances.append(item.frame + item.length + dFrame - other.frame)
                        }
                    }
                }
            }
            guard let maxDistance = distances.max() else {
                fatalError("IsMovableがfalseなのに被りアイテムが見つかりません")
            }
            dFrame = dFrame > 0 ? max(0, dFrame - maxDistance) : min(0, dFrame + maxDistance)
        }
    }

    /// 選択中アイテムとそのグループを、可能な範囲へ縮小して移動する。
    /// 本家 `MoveSelectedAndGroupedItems`。
    func moveSelectedAndGroupedItems(deltaFrame: Int, deltaLayer: Int, extraDeltaFrame: Int = 0) {
        let targets = selectedAndGroupedItems
        if !targets.isEmpty && (deltaLayer != 0 || deltaFrame != 0) {
            let adjusted = getMovableDeltaFrame(
                targets, deltaLayer: deltaLayer, deltaFrame: deltaFrame,
                extraDeltaFrame: extraDeltaFrame
            )
            moveItems(targets, deltaFrame: adjusted.deltaFrame, deltaLayer: adjusted.deltaLayer)
        }
    }

    // MARK: - 追加（本家 TryAddItems）

    /// アイテム群を追加する。本家 `TryAddItems`。
    ///
    /// 前処理として各アイテムへ FPS を注入し、アイテム同士の衝突を
    /// レイヤーを上げて解消し、グループ ID を再発行する（入力自体が
    /// 書き換わる）。その後、レイヤーオフセットを希望位置から増加方向、
    /// 次に最小側から希望位置の直前まで試し、最初に移動可能な位置へ
    /// コミットする。全て失敗した場合は何も追加せず false を返す
    /// （ただし前処理による入力の書き換えは戻らない）。
    @discardableResult
    func tryAddItems(
        _ newItems: [BaseItem], frame: Int, layer: Int, isItemSelectionEnabled: Bool = true
    ) -> Bool {
        if newItems.isEmpty { return true }
        for item in newItems {
            item.setFPS(videoInfo.fps)
        }
        Self.resolveItemCollisionInItems(newItems)
        renewGroupIDs(newItems)
        let minFrame = newItems.map { $0.frame }.min() ?? 0
        let minLayer = newItems.map { $0.layer }.min() ?? 0
        let maxLayerOfItems = newItems.map { $0.layer }.max() ?? 0
        let deltaFrame = frame - minFrame
        let desiredOffset = layer - minLayer
        var offset = desiredOffset
        while offset <= 999 - maxLayerOfItems {
            if isMovable(newItems, deltaFrame: deltaFrame, deltaLayer: offset) {
                moveItems(newItems, deltaFrame: deltaFrame, deltaLayer: offset)
                addItems(newItems)
                if isItemSelectionEnabled {
                    selectItems(newItems)
                }
                return true
            }
            offset += 1
        }
        offset = -minLayer
        while offset < desiredOffset {
            if isMovable(newItems, deltaFrame: deltaFrame, deltaLayer: offset) {
                moveItems(newItems, deltaFrame: deltaFrame, deltaLayer: offset)
                addItems(newItems)
                if isItemSelectionEnabled {
                    selectItems(newItems)
                }
                return true
            }
            offset += 1
        }
        return false
    }

    // MARK: - 衝突解決（本家 ResolveItemCollision 系）

    /// アイテム同士の衝突を、レイヤーを上げて解消する（集合内のみ）。
    /// 本家 `ResolveItemCollisionInItems`。
    static func resolveItemCollisionInItems(_ targets: [BaseItem]) {
        for item in targets {
            while targets.contains(where: {
                $0 !== item && $0.layer == item.layer
                    && $0.intersectsWith(frame: item.frame, length: item.length)
            }) {
                item.layer += 1
            }
        }
    }

    /// 衝突解消で試すレイヤーデルタの列。本家の列挙順そのまま:
    /// 0, +1, …, +(998 - layer), 0, -1, …, -(layer - 1)。
    private static func collisionDeltas(fromLayer layer: Int) -> [Int] {
        let upward = Array(0..<max(0, 999 - layer))
        let downward = (0..<max(0, layer)).map { -$0 }
        return upward + downward
    }

    /// 単一アイテムの衝突をレイヤー移動で解消する。本家 `ResolveItemCollision(IItem)`。
    func resolveItemCollision(_ item: BaseItem) {
        let delta = Self.collisionDeltas(fromLayer: item.layer).first(where: {
            isMovable([item], deltaFrame: 0, deltaLayer: $0)
        }) ?? 0
        item.layer += delta
    }

    /// アイテム群の衝突を解消する。本家 `ResolveItemCollision(IEnumerable)`。
    /// まず群全体を同じデルタで動かし、その後で個別に解消する。
    func resolveItemCollision(_ targets: [BaseItem]) {
        if targets.isEmpty { return }
        let baseLayer = targets[0].layer
        let delta = Self.collisionDeltas(fromLayer: baseLayer).first(where: {
            isMovable(targets, deltaFrame: 0, deltaLayer: $0)
        }) ?? 0
        for item in targets {
            item.layer += delta
        }
        for item in targets {
            resolveItemCollision(item)
        }
    }

    /// 全アイテムをグループ単位で衝突解消する。本家 `ResolveAllItemsCollision`。
    func resolveAllItemsCollision() {
        var groupOrder: [Int] = []
        for item in items where !groupOrder.contains(item.group) {
            groupOrder.append(item.group)
        }
        for group in groupOrder {
            resolveItemCollision(items.filter { $0.group == group })
        }
    }

    // MARK: - グループ ID（本家 RenewGroupIDs 系）

    private func seedPublishedGroupIndex(_ allItems: [BaseItem]) {
        publishedGroupIndex = max(publishedGroupIndex, allItems.map { $0.group }.max() ?? 0)
    }

    private func getNewGroupIDs(count: Int, allItems: [BaseItem]?) -> [Int] {
        seedPublishedGroupIndex(allItems ?? items)
        var result: [Int] = []
        for _ in 0..<count {
            publishedGroupIndex += 1
            result.append(publishedGroupIndex)
        }
        return result
    }

    /// グループ ID を再発行する。本家 `RenewGroupIDs`。
    ///
    /// 対象集合内で2つ以上あるグループには新しい ID を割り当て、
    /// 単独のグループは 0 に解散する。発行カウンタは `allItems`
    /// （既定はタイムライン全体）の最大グループ番号から種を取る。
    func renewGroupIDs(_ targets: [BaseItem], allItems: [BaseItem]? = nil) {
        var groups: [Int] = []
        for item in targets where item.group != 0 {
            if !groups.contains(item.group) {
                groups.append(item.group)
            }
        }
        let newIDs = getNewGroupIDs(count: groups.count, allItems: allItems)
        for (index, group) in groups.enumerated() {
            let members = targets.filter { $0.group == group }
            let assigned = members.count > 1 ? newIDs[index] : 0
            for member in members {
                member.group = assigned
            }
        }
    }

    /// 選択中アイテムとそのグループを1つの新しいグループにする。
    /// 本家 `GroupSlectedAndGroupedItems`（綴りは本家どおりではない）。
    func groupSelectedAndGroupedItems() {
        let newID = getNewGroupIDs(count: 1, allItems: nil)[0]
        for item in selectedAndGroupedItems {
            item.group = newID
        }
    }

    /// 選択中アイテムとそのグループを解散する。本家 `UngroupSelectedAndGroupedItems`。
    func ungroupSelectedAndGroupedItems() {
        for item in selectedAndGroupedItems {
            item.group = 0
        }
    }

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
