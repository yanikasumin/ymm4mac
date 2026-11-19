import Foundation

/// Undo 記録の集約点（FE-UNDO-WIRING）。
///
/// Core の `EditCoordinator`（履歴とトランザクションの統括）への
/// 投入経路をここ1か所へ集約する。所有はアプリ層の `WorkspaceState`
/// が持ち、プロジェクト（ウィンドウ）ごとに1つである。各編集経路は:
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
///
/// 配置は Core（FE-R20-126-01）: アプリ層にはテスト対象が無く、
/// 記録の振る舞い（差分の適用でタイムラインのキャッシュが壊れない
/// こと等）を回帰テストで固定するため、集約点と差分捕捉を Core の
/// テスト対象へ移した。所有と接続の形はアプリ層時代と変えていない。
public final class EditRecorder {
    /// 履歴とトランザクションの統括（Core）。
    public let coordinator = EditCoordinator()

    /// この接続側が開始したセッションのトランザクション。
    /// 同時に有効なセッションは1つだけであり、所有の追跡は監査
    /// Round 10 の接続条件（開始していないセッションの終了通知では
    /// Undo 処理をしない）の実装である。
    private var sessionTransaction: EditTransaction?

    /// セッションが有効か。
    public var hasActiveSession: Bool { sessionTransaction != nil }

    /// セッション所有のトランザクション（差分の投入用）。
    public var activeSessionTransaction: EditTransaction? { sessionTransaction }

    public init() {}

    // MARK: - セッション（連続編集）

    /// 連続編集のセッションを開始する。既にセッションが有効な場合、
    /// および Core 側で開始が拒否された場合は false を返し、呼び出し
    /// 側はその編集を無記録で続行する（開始していないセッションの
    /// 終了通知は `commitSession` / `cancelSession` でも無視される）。
    @discardableResult
    public func beginSession() -> Bool {
        guard sessionTransaction == nil,
              let transaction = coordinator.beginTransaction()
        else { return false }
        sessionTransaction = transaction
        return true
    }

    /// セッションを確定し、蓄積した変更を履歴1エントリとして登録する。
    /// 自分が開始したセッションが無い場合は何もしない。
    public func commitSession() {
        guard let transaction = sessionTransaction else { return }
        sessionTransaction = nil
        coordinator.commit(transaction)
    }

    /// セッションを破棄する。蓄積した変更は Core 側で開始状態へ
    /// 巻き戻される。タイムラインのドラッグでは、操作層自身が
    /// スナップショットから復元済みのため、こちらに蓄積される
    /// コマンドは通常は無く、巻き戻しは空振りになる。
    public func cancelSession() {
        guard let transaction = sessionTransaction else { return }
        sessionTransaction = nil
        coordinator.cancel(transaction)
    }

    /// プロジェクト切り替え時の後片付け。未確定のセッションがあれば
    /// 先に破棄（巻き戻し）してから履歴を消す順序に統一する
    /// （監査 Round 7 の接続条件）。呼び出しは `WorkspaceState` の
    /// プロジェクト差し替え直前に限る。
    public func resetForProjectSwitch() {
        cancelSession()
        coordinator.history.clear()
    }

    // MARK: - 値変更の記録

    /// 適用済みの値変更を記録する。セッションが有効ならそこへ蓄積し、
    /// そうでなければその変更だけのトランザクションとして即時に
    /// 確定する。他の経路のトランザクションが有効な間は記録しない
    /// （未確定の変更と履歴が混ざるのを避ける。Core 側でも開始は
    /// 拒否される）。
    public func recordValueChange<Value: Equatable>(
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
    public func recordTimelineChange(timeline: Timeline, _ body: () -> Void) {
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
