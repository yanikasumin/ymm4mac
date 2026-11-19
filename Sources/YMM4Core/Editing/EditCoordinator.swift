import Foundation

/// 編集トランザクションと Undo 履歴の確定入口（薄い統括層）。
///
/// 編集操作の実体は Core の各編集操作（`TimelineEditing` 等）の責務の
/// ままで、この型は「トランザクションの開始・確定・キャンセル」「履歴
/// への登録」「Undo/Redo の実行」「履歴変更の通知」だけを統括する
/// （フロントエンド監査 Round 2 の設計判断: 編集の確定責務を1か所へ
/// 集約する）。
///
/// 同時に有効なトランザクションは1つだけとする（本家のコレクタが
/// 全体で1つであることに対応）。有効なトランザクションがある間は
/// 新しいトランザクションを開始できない（`beginTransaction` は nil
/// を返す）。前の編集を中断する場合は `cancel`、確定して次へ進む
/// 場合は `commit` を、呼び出し側が明示的に呼ぶ契約とする
/// （FE-R5-119-04。「新しい編集が始まった」ことだけを根拠に前の
/// 編集を Core 側が黙って巻き戻すと、終了イベント未処理のドラッグ
/// 結果などが黙って失われるため）。
///
/// 履歴の Undo/Redo もこの Coordinator 経由でのみ実行できる
/// （`UndoHistory` 側の操作はモジュール内に閉じた）。未確定の
/// トランザクションがある間の Undo/Redo は実行しない。確定前の
/// 変更と履歴エントリが混ざった状態で履歴を動かすと、その後の
/// 確定・巻き戻しが履歴とモデルを乖離させるためである
/// （FE-R5-119-01）。
///
/// キャンセルの巻き戻し中も同様で、巻き戻しの適用クロージャから
/// 過去の履歴の Undo や新しいトランザクションの開始が交錯すると
/// 履歴とモデルが乖離する。そのため Coordinator は「編集中」と
/// 「復元処理中（巻き戻し中）」を操作状態として区別して一元管理し、
/// 巻き戻しが完了するまでは他の操作（開始・確定・キャンセル・
/// Undo/Redo）を全て拒否する（FE-R6-119-01）。R5 処分では巻き戻し
/// 開始前に有効なトランザクションを解除していたため、巻き戻し中は
/// Undo の排他条件（有効なトランザクションの存在）が消えていた。
public final class EditCoordinator {
    /// 保持する Undo/Redo 履歴。
    public let history: UndoHistory

    /// Coordinator の操作状態。状態遷移と操作の可否はこの1か所で
    /// 管理する（FE-R6-119-01）。
    private enum OperationState {
        /// 有効なトランザクションは無く、巻き戻しもしていない。
        case idle
        /// トランザクションが有効（編集中）。
        case editing(EditTransaction)
        /// キャンセルの巻き戻しを実行中（復元処理中）。完了するまで
        /// 他の操作は全て拒否する。
        case restoring
    }

    private var operationState: OperationState = .idle

    /// 現在有効なトランザクション（編集中でなければ nil。巻き戻し中
    /// も nil だが、その間は `beginTransaction` も受け付けない）。
    public var activeTransaction: EditTransaction? {
        guard case .editing(let transaction) = operationState else { return nil }
        return transaction
    }

    public init(capacity: Int = UndoHistory.defaultCapacity) {
        self.history = UndoHistory(capacity: capacity)
    }

    /// 履歴の状態が変わったときの通知（`UndoHistory.onHistoryChanged`
    /// への転送）。
    public var onHistoryChanged: (() -> Void)? {
        get { history.onHistoryChanged }
        set { history.onHistoryChanged = newValue }
    }

    /// 編集トランザクションを開始する。既に有効なトランザクションが
    /// ある場合、および巻き戻し中の場合は開始を拒否し、nil を返す
    /// （前のトランザクションは巻き戻されず、そのまま有効であり
    /// 続ける）。
    @discardableResult
    public func beginTransaction() -> EditTransaction? {
        guard case .idle = operationState else { return nil }
        let transaction = EditTransaction()
        operationState = .editing(transaction)
        return transaction
    }

    /// トランザクションを確定し、蓄積した変更を履歴1エントリとして
    /// 登録する。実質的な変更が無い場合はエントリを作らない。
    /// 有効なトランザクション以外（終了済み・別系統）への呼び出しは
    /// 無視する。
    public func commit(_ transaction: EditTransaction) {
        guard case .editing(let active) = operationState,
              active === transaction, !transaction.isFinished else { return }
        transaction.finish()
        operationState = .idle
        history.record(transaction)
    }

    /// トランザクションをキャンセルし、蓄積した変更を開始状態へ
    /// 巻き戻す。履歴には残らない。有効なトランザクション以外への
    /// 呼び出しは無視する。
    ///
    /// 巻き戻しは、適用クロージャからの再入（同じトランザクションへの
    /// 再キャンセル等）と組み合わさっても再帰的な巻き戻しにならない
    /// よう、コマンドの実行前に終了状態を確定させてから行う
    /// （FE-R5-119-02）。さらに巻き戻しの実行中は操作状態を復元処理中
    /// として保持し、巻き戻しが完了するまで開始・Undo/Redo など他の
    /// 操作を全て拒否する（FE-R6-119-01）。
    public func cancel(_ transaction: EditTransaction) {
        guard case .editing(let active) = operationState,
              active === transaction, !transaction.isFinished else { return }
        transaction.finish()
        operationState = .restoring
        defer { operationState = .idle }
        transaction.rollback()
    }

    /// Undo できるか。
    public var canUndo: Bool { history.canUndo }
    /// Redo できるか。
    public var canRedo: Bool { history.canRedo }

    /// 最新の履歴エントリを Undo する。未確定のトランザクションが
    /// ある間、および巻き戻し中は実行せず false を返す
    /// （FE-R5-119-01、FE-R6-119-01）。対象が無ければ false。
    @discardableResult
    public func undo() -> Bool {
        guard case .idle = operationState else { return false }
        return history.undo()
    }

    /// 最新の履歴エントリを Redo する。未確定のトランザクションが
    /// ある間、および巻き戻し中は実行せず false を返す。対象が
    /// 無ければ false。
    @discardableResult
    public func redo() -> Bool {
        guard case .idle = operationState else { return false }
        return history.redo()
    }
}
