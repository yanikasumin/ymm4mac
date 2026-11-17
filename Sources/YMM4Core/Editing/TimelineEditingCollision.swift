import Foundation

public extension Timeline {
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
}
