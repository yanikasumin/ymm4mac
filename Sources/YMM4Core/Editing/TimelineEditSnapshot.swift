import Foundation

/// タイムラインのアイテム列と各アイテムの配置値の写し。
///
/// ドラッグ操作層（TimelineInteractionView）が持つ復元用スナップ
/// ショットとは責務が別で、こちらは Undo 記録用に「変更前の状態」を
/// 保持し、確定時に現在状態との差分をコマンド化する。対象フィールド
/// はドラッグ・削除して詰める等で変わりうる配置値（開始フレーム・
/// レイヤー・長さ・素材オフセット・キーフレーム位置・ロック）に
/// 限る。グループ番号は対象外（複製時の再発行は追加された要素の
/// 側の状態であり、メンバーシップの差分で往復できる）。
///
/// キャッシュの不変条件（FE-R20-126-01）: 差分コマンドの適用は、
/// どの経路（Undo / Redo / キャンセルの巻き戻し）でも、適用後に
/// 対象タイムラインの長さ・最大レイヤーのキャッシュを再計算する。
/// 配置値の適用クロージャは値を書き戻した直後に
/// `refreshTimelineLengthAndMaxLayer()` を呼び、メンバーシップの
/// 書き戻しも同じ再計算を行う。移動・リサイズだけの往復でも
/// `timeline.length == timeline.computeCurrentLength()`（および
/// maxLayer の整合）が保たれることを、この型の契約とする。
public struct TimelineEditSnapshot {
    struct ItemState {
        let item: BaseItem
        let frame: Int
        let layer: Int
        let length: Int
        let contentOffset: TimeSpanValue
        let keyFrames: KeyFrames
        let isLocked: Bool
    }

    let states: [ItemState]

    public init(timeline: Timeline) {
        states = timeline.items.map {
            ItemState(
                item: $0, frame: $0.frame, layer: $0.layer,
                length: $0.length, contentOffset: $0.contentOffset,
                keyFrames: $0.keyFrames, isLocked: $0.isLocked)
        }
    }

    /// 現在のタイムラインとの差分をコマンドとしてトランザクションへ
    /// 登録する。メンバーシップの変化はリスト追加・削除コマンド
    /// （非 Action）1件にまとめ、残った要素の配置値の変化は値変更
    /// コマンドとして登録する。適用クロージャはいずれも対象を強く
    /// 保持する（`EditTargetKey` の接続側契約）。
    public func recordDiff(into transaction: EditTransaction, timeline: Timeline) {
        let current = timeline.items

        var added: [ListAddRemoveCommand<BaseItem>.Entry] = []
        for (index, item) in current.enumerated()
        where !states.contains(where: { $0.item === item }) {
            added.append(.init(index: index, element: item))
        }
        var removed: [ListAddRemoveCommand<BaseItem>.Entry] = []
        for (index, state) in states.enumerated()
        where !current.contains(where: { $0 === state.item }) {
            removed.append(.init(index: index, element: state.item))
        }
        if !added.isEmpty || !removed.isEmpty {
            transaction.add(ListAddRemoveCommand<BaseItem>(
                getItems: { timeline.items },
                setItems: {
                    timeline.items = $0
                    timeline.refreshTimelineLengthAndMaxLayer()
                },
                added: added, removed: removed))
        }

        for state in states
        where current.contains(where: { $0 === state.item }) {
            let item = state.item
            func record<Value: Equatable>(
                _ key: String, old: Value, new: Value,
                apply: @escaping (Value) -> Void
            ) {
                guard old != new else { return }
                transaction.addValueChange(
                    target: EditTargetKey(item, key: key),
                    oldValue: old, newValue: new,
                    apply: { value in
                        apply(value)
                        // 配置値の書き戻しだけでは長さ・最大レイヤーの
                        // キャッシュが追随しない（移動・リサイズの
                        // Undo/Redo で古いまま残る。FE-R20-126-01）。
                        // 適用のたびに再計算して不変条件を保つ。
                        timeline.refreshTimelineLengthAndMaxLayer()
                    })
            }
            record("Frame", old: state.frame, new: item.frame) { item.frame = $0 }
            record("Layer", old: state.layer, new: item.layer) { item.layer = $0 }
            record("Length", old: state.length, new: item.length) { item.length = $0 }
            record(
                "ContentOffset", old: state.contentOffset, new: item.contentOffset
            ) { item.contentOffset = $0 }
            record("KeyFrames", old: state.keyFrames, new: item.keyFrames) {
                item.setKeyFrames($0)
            }
            record("IsLocked", old: state.isLocked, new: item.isLocked) {
                item.isLocked = $0
            }
        }
    }
}
