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
public final class EditCoordinator {
    /// 保持する Undo/Redo 履歴。
    public let history: UndoHistory
    /// 現在有効なトランザクション（無ければ nil）。
    public private(set) var activeTransaction: EditTransaction?

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
    /// ある場合は開始を拒否し、nil を返す（前のトランザクションは
    /// 巻き戻されず、そのまま有効であり続ける）。
    @discardableResult
    public func beginTransaction() -> EditTransaction? {
        guard activeTransaction == nil else { return nil }
        let transaction = EditTransaction()
        activeTransaction = transaction
        return transaction
    }

    /// トランザクションを確定し、蓄積した変更を履歴1エントリとして
    /// 登録する。実質的な変更が無い場合はエントリを作らない。
    /// 有効なトランザクション以外（終了済み・別系統）への呼び出しは
    /// 無視する。
    public func commit(_ transaction: EditTransaction) {
        guard activeTransaction === transaction, !transaction.isFinished else { return }
        transaction.finish()
        activeTransaction = nil
        history.record(transaction)
    }

    /// トランザクションをキャンセルし、蓄積した変更を開始状態へ
    /// 巻き戻す。履歴には残らない。有効なトランザクション以外への
    /// 呼び出しは無視する。
    ///
    /// 巻き戻しは、適用クロージャからの再入（同じトランザクションへの
    /// 再キャンセル等）と組み合わさっても再帰的な巻き戻しにならない
    /// よう、コマンドの実行前に終了状態を確定させてから行う
    /// （FE-R5-119-02）。
    public func cancel(_ transaction: EditTransaction) {
        guard activeTransaction === transaction, !transaction.isFinished else { return }
        transaction.finish()
        activeTransaction = nil
        transaction.rollback()
    }

    /// Undo できるか。
    public var canUndo: Bool { history.canUndo }
    /// Redo できるか。
    public var canRedo: Bool { history.canRedo }

    /// 最新の履歴エントリを Undo する。未確定のトランザクションが
    /// ある間は実行せず false を返す（FE-R5-119-01）。対象が無ければ
    /// false。
    @discardableResult
    public func undo() -> Bool {
        guard activeTransaction == nil else { return false }
        return history.undo()
    }

    /// 最新の履歴エントリを Redo する。未確定のトランザクションが
    /// ある間は実行せず false を返す。対象が無ければ false。
    @discardableResult
    public func redo() -> Bool {
        guard activeTransaction == nil else { return false }
        return history.redo()
    }
}
