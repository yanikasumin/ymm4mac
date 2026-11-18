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
/// 全体で1つであることに対応）。有効なトランザクションがある状態で
/// 新しく開始すると、前のトランザクションはキャンセル（開始状態へ
/// 巻き戻し）して置き換える。置き換えは、放棄されたドラッグ等の
/// 中断時に半端な変更を残さないための仕様である。
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
    /// あれば、それをキャンセルしてから開始する。
    @discardableResult
    public func beginTransaction() -> EditTransaction {
        if let active = activeTransaction {
            cancel(active)
        }
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
    public func cancel(_ transaction: EditTransaction) {
        guard activeTransaction === transaction, !transaction.isFinished else { return }
        transaction.rollback()
        transaction.finish()
        activeTransaction = nil
    }

    /// Undo できるか。
    public var canUndo: Bool { history.canUndo }
    /// Redo できるか。
    public var canRedo: Bool { history.canRedo }

    /// 最新の履歴エントリを Undo する。対象が無ければ false。
    @discardableResult
    public func undo() -> Bool { history.undo() }

    /// 最新の履歴エントリを Redo する。対象が無ければ false。
    @discardableResult
    public func redo() -> Bool { history.redo() }
}
