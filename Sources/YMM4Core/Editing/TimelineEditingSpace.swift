import Foundation

public extension Timeline {
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
