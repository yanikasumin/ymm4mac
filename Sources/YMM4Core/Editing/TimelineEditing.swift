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
}
