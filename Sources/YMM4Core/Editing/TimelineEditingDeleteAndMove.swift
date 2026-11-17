import Foundation

public extension Timeline {
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
}
