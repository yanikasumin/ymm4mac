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

    // MARK: - 削除して詰める（本家 DeleteAndMove / DeleteAndMoveAll）

    /// 選択中アイテムとそのグループを削除し、同じレイヤーの後続アイテムを
    /// 詰める。本家 `DeleteAndMove`。
    ///
    /// 対象ごとに、その対象と同じレイヤーで対象の終了位置以降に始まる
    /// アイテムを対象の長さだけ前へ詰めてから、対象を削除する。
    /// 戻り値は操作後の現在フレームの候補（本家では呼び出し側が
    /// プレビューをシークするために使う）。式は対象ごとに
    /// 「現在フレームが対象の開始より後ろにあれば開始位置まで戻す」であり、
    /// `deleteAndMoveAll` の「空き区間と重なる分だけ引く」式とは非対称だが、
    /// 本家の実コードがそうなっているためそのまま再現する。
    @discardableResult
    func deleteAndMove() -> Int {
        let targets = selectedAndGroupedItems
        if items.isEmpty || targets.isEmpty {
            return currentFrame
        }
        var newFrame = currentFrame
        for item in targets {
            for other in items where other.layer == item.layer
                && item.frame + item.length <= other.frame {
                other.frame -= item.length
            }
            newFrame -= max(newFrame - item.frame, 0)
        }
        deleteItemsWithoutCollisionValidation(targets)
        refreshTimelineLengthAndMaxLayer()
        return newFrame
    }

    /// 選択中アイテムとそのグループを削除し、全レイヤーの後続アイテムを
    /// 詰める。本家 `DeleteAndMoveAll`。
    ///
    /// 対象を1つ削除するごとに、削除区間のうち「残っているどのアイテム
    /// にも覆われていない部分」（空き区間）を求め、空き区間の後ろにある
    /// 全レイヤーのアイテムを空き区間の長さだけ前へ詰める。覆われている
    /// 部分は詰めないため、削除区間をまたぐ他レイヤーのアイテムがあると
    /// 詰まり方が変わる。空き区間同士は後ろのものから順に適用する。
    /// 戻り値は操作後の現在フレームの候補で、空き区間と重なる分だけ
    /// 前へ戻る。
    @discardableResult
    func deleteAndMoveAll() -> Int {
        let targets = selectedAndGroupedItems
        if items.isEmpty || targets.isEmpty {
            return currentFrame
        }
        var newFrame = currentFrame
        for item in targets {
            items = items.filter { $0 !== item }
            var spaces: [(x: Int, length: Int)] = [(x: item.frame, length: item.length)]
            for other in items {
                spaces = spaces.flatMap { Self.remainingSpace($0, coveredBy: other) }
            }
            for space in spaces.sorted(by: { $0.x > $1.x }) {
                for other in items where space.x + space.length <= other.frame {
                    other.frame -= space.length
                }
            }
            for space in spaces {
                newFrame -= max(min(space.x + space.length, newFrame) - space.x, 0)
            }
        }
        refreshTimelineLengthAndMaxLayer()
        return newFrame
    }

    /// 区間から、アイテムに覆われていない部分を取り出す。
    /// 本家 `DeleteAndMoveAll` 内のローカル関数 `GetSpace`。
    private static func remainingSpace(
        _ space: (x: Int, length: Int), coveredBy item: BaseItem
    ) -> [(x: Int, length: Int)] {
        let x = space.x
        let length = space.length
        if item.frame <= x && x + length <= item.frame + item.length {
            return []
        }
        if item.frame + item.length <= x || x + length <= item.frame {
            return [space]
        }
        return [
            (x: x, length: item.frame - x),
            (x: item.frame + item.length, length: x + length - (item.frame + item.length)),
        ].filter { $0.length > 0 }
    }

    // MARK: - 長さ変更（本家 ChangeSelectedAndGroupedItemsLength 系）

    /// フレーム数を時間へ換算する。本家 `VideoInfo.GetTimeFrom`。
    private func timeSpanFromFrames(_ frame: Int) -> TimeSpanValue {
        let ticks = (Double(frame) * 10_000_000 / Double(videoInfo.fps))
            .rounded(.toNearestOrAwayFromZero)
        return TimeSpanValue(ticks: Int64(ticks))
    }

    /// 全キーフレームを一律にずらす。本家の `KeyFrames.SetFrame` による
    /// 一括置換は置換イベントが値を変えないため、この形と等価
    /// （ChangeFrameRate の一括置換と同じ判断）。
    private func shiftKeyFrames(_ item: BaseItem, by delta: Int) {
        if delta != 0 && !item.keyFrames.frames.isEmpty {
            item.setKeyFrames(KeyFrames(frames: item.keyFrames.frames.map { $0 + delta }))
        }
    }

    /// 選択中アイテムとそのグループの長さを変更する。
    /// 本家 `ChangeSelectedAndGroupedItemsLength`。
    ///
    /// 実際に適用される変化量は `getExpandableDeltaLength` で制限され、
    /// 制限後の量が 0 なら何もしない。head = true は開始側
    /// （開始フレームが動き、終了フレームは固定）、head = false は
    /// 終了側（長さだけが変わる）。
    func changeSelectedAndGroupedItemsLength(
        deltaX: Int, head: Bool, neighborAffect: NeighborAffectMode
    ) {
        let targets = selectedAndGroupedItems
        if targets.isEmpty { return }
        let expandableDeltaLength = getExpandableDeltaLength(
            targets, deltaLength: deltaX, head: head, neighborAffect: neighborAffect
        )
        if expandableDeltaLength != 0 {
            if head {
                changeItemsStart(
                    targets, deltaLength: expandableDeltaLength, neighborAffect: neighborAffect
                )
            } else {
                changeItemsEnd(
                    targets, deltaLength: expandableDeltaLength, neighborAffect: neighborAffect
                )
            }
        }
    }

    /// 適用可能な長さ変化量を求める。本家 `GetExpandableDeltaLength`。
    ///
    /// 符号の意味は head で反転する。head では正が開始側の短縮
    /// （開始が後ろへ動く）、負が開始側への伸長。head = false では
    /// 負が終了側の短縮、正が終了側への伸長。
    /// 短縮は「長さと端のキーフレームまで」だけが制限で、隣接は見ない。
    /// 伸長は隣接アイテム（none: その手前まで。stretch: 隣接が切り取り
    /// 可能な分まで）と、開始側ではフレーム 0 の境界で制限される。
    /// 本家は対象が空だと例外になるため、到達不能な前提として扱う。
    func getExpandableDeltaLength(
        _ targets: [BaseItem], deltaLength: Int, head: Bool,
        neighborAffect: NeighborAffectMode
    ) -> Int {
        if deltaLength == 0 { return 0 }
        guard !targets.isEmpty else {
            fatalError("GetExpandableDeltaLength の対象は1つ以上必要です")
        }
        if deltaLength > 0 && head {
            var limit = targets.map { $0.length }.min() ?? 0
            for item in targets where !item.keyFrames.frames.isEmpty {
                limit = min(limit, item.keyFrames.frames.first ?? limit)
            }
            // 本家: limit - deltaLength >= 1 なら deltaLength、でなければ limit - 1。
            // Int.min / Int.max を使う再帰呼び出しでも溢れない形に変形している。
            return deltaLength <= limit - 1 ? deltaLength : limit - 1
        }
        if deltaLength < 0 && !head {
            var limit = targets.map { $0.length }.min() ?? 0
            for item in targets where !item.keyFrames.frames.isEmpty {
                limit = min(limit, item.length - (item.keyFrames.frames.last ?? 0))
            }
            // 本家: limit + deltaLength >= 1 なら deltaLength、でなければ -limit + 1。
            return deltaLength >= 1 - limit ? deltaLength : -limit + 1
        }
        if head {
            // deltaLength < 0: 開始側への伸長
            switch neighborAffect {
            case .none, .stretch:
                var constraints: [Int] = []
                for item in targets {
                    for other in items where other !== item && other.layer == item.layer
                        && other.frame + other.length <= item.frame
                        && item.frame + deltaLength < other.frame + other.length {
                        let gap = item.frame - (other.frame + other.length)
                        if neighborAffect == .stretch {
                            let overshoot =
                                item.frame + deltaLength - (other.frame + other.length)
                            constraints.append(
                                gap - max(getTrimmableLength(other), overshoot)
                            )
                        } else {
                            constraints.append(gap)
                        }
                    }
                    if item.frame + deltaLength < 0 {
                        constraints.append(item.frame)
                    }
                }
                return constraints.isEmpty ? deltaLength : -constraints.min()!
            case .default, .unknown:
                // 本家は Default の伸長で NotImplementedException になる。
                // ViewModel が none / stretch へ解決してから渡すため到達不能。
                fatalError("NeighborAffectMode.Default は長さ変更の伸長へ渡されません")
            }
        }
        // head = false かつ deltaLength > 0: 終了側への伸長
        switch neighborAffect {
        case .none, .stretch:
            var constraints: [Int] = []
            for item in targets {
                for other in items where other !== item && other.layer == item.layer
                    && item.frame + item.length <= other.frame
                    && other.frame < item.frame + item.length + deltaLength {
                    let gap = other.frame - (item.frame + item.length)
                    if neighborAffect == .stretch {
                        let overshoot = item.frame + item.length + deltaLength - other.frame
                        constraints.append(gap + min(getTrimmableLength2(other), overshoot))
                    } else {
                        constraints.append(gap)
                    }
                }
            }
            return constraints.isEmpty ? deltaLength : constraints.min()!
        case .default, .unknown:
            fatalError("NeighborAffectMode.Default は長さ変更の伸長へ渡されません")
        }
    }

    /// アイテム（とそのグループ）が終了側から切り取れる量（0 以下の値）。
    /// 本家 `GetExpandableDeltaLength` 内のローカル関数 `GetTrimmableLength`。
    private func getTrimmableLength(_ item: BaseItem) -> Int {
        getExpandableDeltaLength(
            getItemsAndGroupedItems([item]),
            deltaLength: Int.min, head: false, neighborAffect: .none
        )
    }

    /// アイテム（とそのグループ）が開始側から切り取れる量（0 以上の値）。
    /// 本家 `GetTrimmableLength2`。
    private func getTrimmableLength2(_ item: BaseItem) -> Int {
        getExpandableDeltaLength(
            getItemsAndGroupedItems([item]),
            deltaLength: Int.max, head: true, neighborAffect: .none
        )
    }

    /// 開始側の長さ変更を適用する。本家 `ChangeItemsStart`。
    ///
    /// 各対象の Frame を deltaLength だけ動かし Length を逆向きに変える
    /// （終了フレームは不変）。開始位置の移動に合わせ、ContentOffset は
    /// 移動分の消費だけ進み（再生速度が定数なら先頭レートで換算、
    /// 非定数なら積分テーブルで換算）、0 未満にはならないよう丸められる。
    /// キーフレームは -deltaLength ずれる。
    /// stretch では、伸長で重なった左隣の終了側を重なり分だけ切り取り、
    /// 短縮で元の開始位置に接していた左隣を deltaLength だけ伸ばす
    /// （いずれも左隣のグループ全員に同じ長さ変更が及ぶ）。
    func changeItemsStart(
        _ targets: [BaseItem], deltaLength: Int, neighborAffect: NeighborAffectMode
    ) {
        let timeFrom = timeSpanFromFrames(deltaLength)
        for item in targets {
            item.frame += deltaLength
            item.length -= deltaLength
            let rateMap = PlaybackRateMap(rate: item.playbackRate2)
            let timeSpan: TimeSpanValue
            if rateMap.isConstant {
                // 分割時の ContentOffset 換算と同じ形（tick 精度で換算する）
                let scaled = (Double(timeFrom.ticks)
                    * abs(item.playbackRate2.firstValue) / 100.0).rounded(.awayFromZero)
                timeSpan = TimeSpanValue(ticks: Int64(scaled))
            } else {
                // item.length は変更済みのため、+ deltaLength で変更前の長さになる
                let consumed = rateMap.getConsumedContent(
                    time: timeFrom, itemLength: item.length + deltaLength,
                    fps: videoInfo.fps
                )
                let sign: Int64 = deltaLength > 0 ? 1 : (deltaLength < 0 ? -1 : 0)
                timeSpan = TimeSpanValue(ticks: abs(consumed.ticks) * sign)
            }
            if TimeSpanValue.zero <= item.contentOffset + timeSpan {
                item.contentOffset = item.contentOffset + timeSpan
            } else {
                item.contentOffset = .zero
            }
            shiftKeyFrames(item, by: -deltaLength)
            if neighborAffect == .stretch {
                for other in items where other !== item && other.layer == item.layer {
                    if deltaLength < 0 {
                        if other.frame + other.length <= item.frame
                            || item.frame + item.length <= other.frame {
                            continue
                        }
                        let overlap = other.frame + other.length - item.frame
                        other.length -= overlap
                        for grouped in getGroupedItems([other]) {
                            grouped.length -= overlap
                        }
                    } else {
                        if other.frame + other.length != item.frame - deltaLength {
                            continue
                        }
                        other.length += deltaLength
                        for grouped in getGroupedItems([other]) {
                            grouped.length += deltaLength
                        }
                    }
                }
            }
        }
        expandTimelineLengthAndMaxLayer()
    }

    /// 終了側の長さ変更を適用する。本家 `ChangeItemsEnd`。
    ///
    /// 各対象の Length だけを変える（対象自身の開始フレーム・
    /// ContentOffset・キーフレームは変わらない）。
    /// stretch では、短縮で元の終了位置に接していた右隣を開始側から
    /// 切り取って前へ詰め、伸長で重なった右隣を重なり分だけ後ろへ
    /// ずらす（いずれも右隣のグループ全員に及ぶ）。右隣の ContentOffset
    /// とキーフレームも開始位置の移動に合わせて動く。短縮側の
    /// ContentOffset は 0 未満にならないよう丸められるが、伸長側の
    /// ずらしでは丸めも再生速度の換算もない（本家の実コードどおり）。
    func changeItemsEnd(
        _ targets: [BaseItem], deltaLength: Int, neighborAffect: NeighborAffectMode
    ) {
        let timeFrom = timeSpanFromFrames(deltaLength)
        for item in targets {
            item.length += deltaLength
            if neighborAffect != .stretch { continue }
            for other in items where other !== item && other.layer == item.layer {
                if deltaLength < 0 {
                    // item.length は変更済み: - deltaLength で変更前の終了位置に戻る
                    if other.frame != item.frame + item.length - deltaLength {
                        continue
                    }
                    other.frame += deltaLength
                    other.length -= deltaLength
                    other.contentOffset = TimeSpanValue(
                        ticks: max(0, other.contentOffset.ticks + timeFrom.ticks)
                    )
                    shiftKeyFrames(other, by: -deltaLength)
                    for grouped in getGroupedItems([other]) {
                        grouped.frame += deltaLength
                        grouped.length -= deltaLength
                        grouped.contentOffset = TimeSpanValue(
                            ticks: max(0, grouped.contentOffset.ticks + timeFrom.ticks)
                        )
                        shiftKeyFrames(grouped, by: -deltaLength)
                    }
                } else {
                    if other.frame + other.length <= item.frame
                        || item.frame + item.length <= other.frame {
                        continue
                    }
                    let overlap = item.frame + item.length - other.frame
                    let overlapTime = timeSpanFromFrames(overlap)
                    other.frame += overlap
                    other.length -= overlap
                    other.contentOffset = other.contentOffset + overlapTime
                    shiftKeyFrames(other, by: -overlap)
                    for grouped in getGroupedItems([other]) {
                        grouped.frame += overlap
                        grouped.length -= overlap
                        grouped.contentOffset = grouped.contentOffset + overlapTime
                        shiftKeyFrames(grouped, by: -overlap)
                    }
                }
            }
        }
        expandTimelineLengthAndMaxLayer()
    }

    // MARK: - スナップ（本家 GetSnappedDelta）

    /// 移動量をスナップ先へ吸着させる。本家 `GetSnappedDelta`。
    ///
    /// 吸着先の候補は、基準レイヤー以外の近傍レイヤー（layerDistance
    /// 以内）にある他アイテムの開始・終了・キーフレーム位置と、
    /// extraSnapPoints と、現在フレーム。移動対象の代表点
    /// （snapTargetFrames）に frameDelta を加えた位置との距離が
    /// frameDistance 以内の候補のうち最も近いものを選び、選ばれた
    /// 代表点が候補へ一致するよう補正した移動量を返す。候補が無ければ
    /// frameDelta をそのまま返す。同距離では、本家の安定ソートと
    /// 同じく列挙順の早い方を採る。候補の列挙順は本家に合わせ
    /// 「開始位置、終了位置、extraSnapPoints、キーフレーム位置、
    /// 現在フレーム」の順とする。
    func getSnappedDelta(
        snapTargetFrames: [Int], baseLayer: Int, frameDelta: Int,
        frameDistance: Int, layerDistance: Int,
        ignoreItems: [BaseItem], extraSnapPoints: [Int] = []
    ) -> Int {
        if snapTargetFrames.isEmpty { return frameDelta }
        let targetPoints = snapTargetFrames.map { $0 + frameDelta }
        let sources = excludingIdentities(items, ignoreItems).filter {
            $0.layer - layerDistance <= baseLayer
                && baseLayer <= $0.layer + layerDistance
                && $0.layer != baseLayer
        }
        var candidates: [Int] = []
        var seen: Set<Int> = []
        func addCandidate(_ point: Int) {
            if seen.insert(point).inserted {
                candidates.append(point)
            }
        }
        for item in sources { addCandidate(item.frame) }
        for item in sources { addCandidate(item.frame + item.length) }
        for point in extraSnapPoints { addCandidate(point) }
        for item in sources {
            for keyFrame in item.keyFrames.frames {
                addCandidate(item.frame + keyFrame)
            }
        }
        addCandidate(currentFrame)
        var snapPoint: Int?
        var snapDistance = Int.max
        for point in candidates {
            let distance = targetPoints.map { abs(point - $0) }.min() ?? Int.max
            if distance <= frameDistance && distance < snapDistance {
                snapDistance = distance
                snapPoint = point
            }
        }
        guard let snapPoint else { return frameDelta }
        var nearestTarget = targetPoints[0]
        var nearestDistance = Int.max
        for target in targetPoints {
            let distance = abs(snapPoint - target)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestTarget = target
            }
        }
        return snapPoint - nearestTarget + frameDelta
    }

    // MARK: - 空間を詰める削除（本家 DeleteItemSpace 系）

    /// 指定レイヤーの指定フレーム位置にある空間を詰める。
    /// 本家 `DeleteItemSpace`。
    ///
    /// 詰める量は「frame 以前に終わる同レイヤーアイテムの最大終了位置」から
    /// 「frame より後に始まる同レイヤーアイテムの最小開始位置」までの間隔で、
    /// frame 自体がアイテム内部にある場合はそのアイテムの終了位置が起点に
    /// なる。後続の同レイヤーアイテムを全てその分だけ前へずらす。
    /// 本家は後続アイテムが無いと LINQ の Min() で例外になる（呼び出し側の
    /// CanDeleteItemSpace が前提条件を保証する）。Swift では後続が無ければ
    /// 何もしない（MAC-0007 の入口 no-op と同じ判断）。
    func deleteItemSpace(layer: Int, frame: Int) {
        let coveredEnd = items
            .filter { $0.layer == layer }
            .map { $0.frame + $0.length }
            .filter { $0 <= frame }
            .max() ?? 0
        let nextStarts = items.filter { $0.layer == layer && frame < $0.frame }
        guard let nextStart = nextStarts.map({ $0.frame }).min() else {
            return
        }
        let gap = nextStart - coveredEnd
        for item in items where item.layer == layer && frame < item.frame {
            item.frame -= gap
        }
        refreshTimelineLengthAndMaxLayer()
    }

    /// 全レイヤーの指定フレーム位置にある空間を詰める。
    /// 本家 `DeleteTimelineSpace`。戻り値は詰めた量。
    ///
    /// frame 以後に始まる全アイテムを「最小の開始位置 − frame」だけ前へ
    /// ずらす。本家は対象アイテムが無いと例外になるが、Swift では 0 を
    /// 返して何もしない。
    @discardableResult
    func deleteTimelineSpace(frame: Int) -> Int {
        let laterItems = items.filter { frame <= $0.frame }
        guard let firstStart = laterItems.map({ $0.frame }).min() else {
            return 0
        }
        let shift = firstStart - frame
        for item in items where frame <= item.frame {
            item.frame -= shift
        }
        refreshTimelineLengthAndMaxLayer()
        return shift
    }

    /// フレーム順に並んだアイテム列の空間を全て詰める共通処理。
    /// 本家 `DeleteAllLayerSpaces` / `DeleteAllTimelineSpaces` のループ。
    ///
    /// coveredEnd は「ここまでアイテムで覆われている」位置、accumulatedShift
    /// は累積の詰め量。先頭のアイテムもフレーム 0 へ寄る（先行空間も詰める）。
    /// DeleteAllTimelineSpaces ではレイヤーをまたいで処理するため、
    /// coveredEnd は全レイヤー通算の最大終了位置になる。
    private static func compactAllSpaces(_ sortedItems: [BaseItem]) {
        var coveredEnd = 0
        var accumulatedShift = 0
        for item in sortedItems {
            let adjustedStart = item.frame - accumulatedShift
            if coveredEnd < adjustedStart {
                accumulatedShift += adjustedStart - coveredEnd
            }
            item.frame -= accumulatedShift
            coveredEnd = max(coveredEnd, item.frame + item.length)
        }
    }

    /// 指定レイヤーの空間を全て詰める。本家 `DeleteAllLayerSpaces`。
    func deleteAllLayerSpaces(layer: Int) {
        let sorted = items
            .filter { $0.layer == layer }
            .sorted { $0.frame < $1.frame }
        if sorted.isEmpty { return }
        Self.compactAllSpaces(sorted)
        refreshTimelineLengthAndMaxLayer()
    }

    /// 全レイヤーの空間を全て詰める。本家 `DeleteAllTimelineSpaces`。
    func deleteAllTimelineSpaces() {
        let sorted = items.sorted { $0.frame < $1.frame }
        if sorted.isEmpty { return }
        Self.compactAllSpaces(sorted)
        refreshTimelineLengthAndMaxLayer()
    }

    /// 選択範囲のうち、他アイテムに覆われていない孤立区間を削除する。
    /// 本家 `DeleteIsolatedRanges`。
    ///
    /// 選択＋グループの範囲 [from, to) について、選択外アイテムと重なる
    /// 部分は残し、重ならない部分にある選択アイテムだけを削除する
    /// （境界をまたぐ選択アイテムは境界で分割してから判定する）。
    /// 削除後は from 以後の全アイテムを、to を上限として前へ詰める。
    /// 本家は選択が空だと Min() で例外になるため、Swift では選択が
    /// 空なら何もしない。
    func deleteIsolatedRanges() {
        var builderItems = items
        var builderSelected = selectedAndGroupedItems
        if builderSelected.isEmpty { return }
        let from = builderSelected.map { $0.frame }.min() ?? 0
        let to = builderSelected.map { $0.frame + $0.length }.max() ?? 0
        let others = excludingIdentities(items, builderSelected)
            .filter { $0.frame + $0.length > from && to > $0.frame }
            .sorted { $0.frame < $1.frame }
        // 本家は ImmutableList のビルダー2つ（全体と選択）へ同じ
        // Remove/Add を適用する。ここでは配列の写しへ同じ操作を行う。
        func applySplit(at frame: Int) {
            let (removes, adds) = splitItemsCore(
                timelineItems: builderItems, targets: builderSelected, frame: frame
            )
            builderItems = excludingIdentities(builderItems, removes) + adds
            builderSelected = excludingIdentities(builderSelected, removes) + adds
        }
        var current = from
        for other in others {
            if current < other.frame {
                applySplit(at: current)
                applySplit(at: other.frame)
                let doomed = builderSelected.filter {
                    current <= $0.frame && $0.frame + $0.length <= other.frame
                }
                builderItems = excludingIdentities(builderItems, doomed)
                builderSelected = excludingIdentities(builderSelected, doomed)
            }
            current = max(current, other.frame + other.length)
        }
        if current < to {
            applySplit(at: current)
            applySplit(at: to)
            let doomed = builderSelected.filter {
                current <= $0.frame && $0.frame + $0.length <= to
            }
            builderItems = excludingIdentities(builderItems, doomed)
            builderSelected = excludingIdentities(builderSelected, doomed)
        }
        // 詰め: from 以後のアイテムを前へ寄せる。ただし to − shift を
        // 超えては寄せない（範囲外だった後続は to の分までしか詰まらない）。
        let targets = builderItems
            .filter { from <= $0.frame }
            .sorted { $0.frame < $1.frame }
        current = from
        var accumulatedShift = 0
        for item in targets {
            let candidate = min(item.frame - accumulatedShift, to - accumulatedShift)
            if current < candidate {
                accumulatedShift += candidate - current
            }
            item.frame -= accumulatedShift
            current = max(current, item.frame + item.length)
        }
        items = builderItems
        selectedItems = builderSelected
        refreshTimelineLengthAndMaxLayer()
    }
}
