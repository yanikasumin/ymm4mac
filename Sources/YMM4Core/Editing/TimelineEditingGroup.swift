import Foundation

public extension Timeline {
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
    ///
    /// 実際に解散した（group が 0 でないアイテムがあった）かを返す。
    /// 呼び出し側が未保存フラグの発火を実際の変更有無で判定するための
    /// 約束（FE-R33-131-02 の戻り値判定と同じ形）。
    @discardableResult
    func ungroupSelectedAndGroupedItems() -> Bool {
        var changed = false
        for item in selectedAndGroupedItems {
            if item.group != 0 {
                item.group = 0
                changed = true
            }
        }
        return changed
    }
}
