import Foundation
import YMM4Core

/// アプリ層の Undo 記録の集約点（FE-UNDO-WIRING）。
///
/// Core の `EditCoordinator`（履歴とトランザクションの統括）への
/// 投入経路をここ1か所へ集約する。所有は `WorkspaceState` が持ち、
/// プロジェクト（ウィンドウ）ごとに1つである。各編集経路は:
///
/// - 離散編集（数値確定・トグル・選択など）: 書き込みの前後で
///   `recordValueChange` を呼ぶ。セッションが有効でなければ、その
///   変更だけのトランザクションとして即時に確定する。
/// - 連続編集（スライダ・ドラッグ）: `beginSession` でトランザクション
///   を開き、途中の変更は同じセッションへ蓄積され（同一対象の連鎖は
///   Core の収集規則で統合される）、終了時に `commitSession` /
///   `cancelSession` で閉じる。開始が拒否された場合は無記録で続行
///   する（呼び出し側は戻り値で所有の有無を追跡すること）。
/// - タイムラインの構造変更（追加・削除・ドラッグ）: 変更前後の
///   スナップショット差分をコマンド化する `recordTimelineChange` /
///   `TimelineEditSnapshot` を使う。
///
/// 本家の自動監視（UndoRedoable）は模倣しない。ここを通らない編集は
/// 記録されず、Undo 対応とはみなさない（未移行経路は実装ログに列挙）。
final class EditRecorder {
    /// 履歴とトランザクションの統括（Core）。
    let coordinator = EditCoordinator()

    /// この接続側が開始したセッションのトランザクション。
    /// 同時に有効なセッションは1つだけであり、所有の追跡は監査
    /// Round 10 の接続条件（開始していないセッションの終了通知では
    /// Undo 処理をしない）の実装である。
    private var sessionTransaction: EditTransaction?

    /// セッションが有効か。
    var hasActiveSession: Bool { sessionTransaction != nil }

    /// セッション所有のトランザクション（差分の投入用）。
    var activeSessionTransaction: EditTransaction? { sessionTransaction }

    // MARK: - セッション（連続編集）

    /// 連続編集のセッションを開始する。既にセッションが有効な場合、
    /// および Core 側で開始が拒否された場合は false を返し、呼び出し
    /// 側はその編集を無記録で続行する（開始していないセッションの
    /// 終了通知は `commitSession` / `cancelSession` でも無視される）。
    @discardableResult
    func beginSession() -> Bool {
        guard sessionTransaction == nil,
              let transaction = coordinator.beginTransaction()
        else { return false }
        sessionTransaction = transaction
        return true
    }

    /// セッションを確定し、蓄積した変更を履歴1エントリとして登録する。
    /// 自分が開始したセッションが無い場合は何もしない。
    func commitSession() {
        guard let transaction = sessionTransaction else { return }
        sessionTransaction = nil
        coordinator.commit(transaction)
    }

    /// セッションを破棄する。蓄積した変更は Core 側で開始状態へ
    /// 巻き戻される。タイムラインのドラッグでは、操作層自身が
    /// スナップショットから復元済みのため、こちらに蓄積される
    /// コマンドは通常は無く、巻き戻しは空振りになる。
    func cancelSession() {
        guard let transaction = sessionTransaction else { return }
        sessionTransaction = nil
        coordinator.cancel(transaction)
    }

    /// プロジェクト切り替え時の後片付け。未確定のセッションがあれば
    /// 先に破棄（巻き戻し）してから履歴を消す順序に統一する
    /// （監査 Round 7 の接続条件）。呼び出しは `WorkspaceState` の
    /// プロジェクト差し替え直前に限る。
    func resetForProjectSwitch() {
        cancelSession()
        coordinator.history.clear()
    }

    // MARK: - 値変更の記録

    /// 適用済みの値変更を記録する。セッションが有効ならそこへ蓄積し、
    /// そうでなければその変更だけのトランザクションとして即時に
    /// 確定する。他の経路のトランザクションが有効な間は記録しない
    /// （未確定の変更と履歴が混ざるのを避ける。Core 側でも開始は
    /// 拒否される）。
    func recordValueChange<Value: Equatable>(
        target: EditTargetKey,
        oldValue: Value,
        newValue: Value,
        apply: @escaping (Value) -> Void
    ) {
        guard oldValue != newValue else { return }
        if let sessionTransaction {
            sessionTransaction.addValueChange(
                target: target, oldValue: oldValue, newValue: newValue,
                apply: apply)
            return
        }
        guard coordinator.activeTransaction == nil,
              let transaction = coordinator.beginTransaction()
        else { return }
        transaction.addValueChange(
            target: target, oldValue: oldValue, newValue: newValue,
            apply: apply)
        coordinator.commit(transaction)
    }

    // MARK: - タイムライン構造変更の記録

    /// タイムラインの構造変更（追加・削除・移動など）を、変更前後の
    /// スナップショット差分として1トランザクションに記録する。
    /// トランザクションを開始できない場合は変更だけを実行する
    /// （無記録）。
    func recordTimelineChange(timeline: Timeline, _ body: () -> Void) {
        guard let transaction = coordinator.beginTransaction() else {
            body()
            return
        }
        let snapshot = TimelineEditSnapshot(timeline: timeline)
        body()
        snapshot.recordDiff(into: transaction, timeline: timeline)
        coordinator.commit(transaction)
    }
}

/// タイムラインのアイテム列と各アイテムの配置値の写し。
///
/// ドラッグ操作層（TimelineInteractionView）が持つ復元用スナップ
/// ショットとは責務が別で、こちらは Undo 記録用に「変更前の状態」を
/// 保持し、確定時に現在状態との差分をコマンド化する。対象フィールド
/// はドラッグ・削除して詰める等で変わりうる配置値（開始フレーム・
/// レイヤー・長さ・素材オフセット・キーフレーム位置・ロック）に
/// 限る。グループ番号は対象外（複製時の再発行は追加された要素の
/// 側の状態であり、メンバーシップの差分で往復できる）。
struct TimelineEditSnapshot {
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

    init(timeline: Timeline) {
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
    func recordDiff(into transaction: EditTransaction, timeline: Timeline) {
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
                    oldValue: old, newValue: new, apply: apply)
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
