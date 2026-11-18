import Foundation

/// Undo/Redo 履歴（本家 `UndoRedoManager` の履歴保持部分に相当）。
///
/// 本家との対応:
/// - 確定済みトランザクションが1エントリとして積まれ、上限（既定100、
///   本家の `UndoRedoLimit`）を超えたら最古を破棄する。
/// - 新しいエントリの確定で Redo 側は破棄される。ただし実質的な変更が
///   無いトランザクションの確定はエントリを作らず、Redo も破棄しない
///   （本家の空の `Record()` が何もしないことに対応）。
/// - Undo/Redo の適用中は記録が抑制され、適用の副作用で生じた確定は
///   破棄される（本家の `isUndoRedoing` による記録抑制）。
///
/// 本家との意図的な差異:
/// - 本家の Undo/Redo は非同期（非同期コマンドを含むため）。Mac 版の
///   コマンドは全て同期のため、履歴も同期 API とする。
/// - 本家は履歴が空の Undo/Redo を想定しない（呼び出し側が可否を
///   見る）。こちらは `false` を返して安全に倒す。
/// - 本家はモデルの自動監視でコマンドを集めるが、こちらへの投入は
///   `EditCoordinator` 経由の明示トランザクションに限る（投入経路を
///   1つに保つため、`record` はモジュール内に閉じる）。
public final class UndoHistory {
    /// 履歴容量の既定値（本家の上限既定値と同じ100）。
    public static let defaultCapacity = 100

    /// 保持する履歴エントリの上限。変更すると直ちに最古から切り詰める。
    public var capacity: Int {
        didSet {
            if trimExcess() {
                onHistoryChanged?()
            }
        }
    }

    private var undoStack: [EditCommandCollector] = []
    private var redoStack: [EditCommandCollector] = []
    /// Undo/Redo の適用中か。この間の確定は記録しない。
    private(set) var isApplying = false

    /// 履歴の状態が変わったときの通知（確定・Undo・Redo・全消去・
    /// 容量変更による切り詰め）。Core には一元的な変更通知の仕組みが
    /// 無い（モデルの伝播は `didSet` フックが担う）ため、利用側が
    /// UI の再描画等に使えるようクロージャで受ける形にする
    /// （`UserDictionaryStore.onSaveResult` の前例と同じ方式）。
    public var onHistoryChanged: (() -> Void)?

    public init(capacity: Int = UndoHistory.defaultCapacity) {
        self.capacity = max(0, capacity)
    }

    /// Undo できるエントリがあるか。
    public var canUndo: Bool { !undoStack.isEmpty }
    /// Redo できるエントリがあるか。
    public var canRedo: Bool { !redoStack.isEmpty }
    /// Undo 側のエントリ数。
    public var undoCount: Int { undoStack.count }
    /// Redo 側のエントリ数。
    public var redoCount: Int { redoStack.count }

    /// トランザクションを履歴1エントリとして確定する。
    /// 適用中、または実質的な変更が無い場合は何もしない。
    func record(_ transaction: EditTransaction) {
        guard !isApplying else { return }
        guard !transaction.collector.isEmpty else { return }
        undoStack.append(transaction.collector)
        redoStack.removeAll()
        trimExcess()
        onHistoryChanged?()
    }

    /// 最新のエントリを Undo し、Redo 側へ移す。対象が無ければ false。
    @discardableResult
    public func undo() -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        isApplying = true
        entry.undoAll()
        isApplying = false
        redoStack.append(entry)
        onHistoryChanged?()
        return true
    }

    /// 最新の Redo エントリを再適用し、Undo 側へ戻す。対象が無ければ false。
    @discardableResult
    public func redo() -> Bool {
        guard let entry = redoStack.popLast() else { return false }
        isApplying = true
        entry.redoAll()
        isApplying = false
        undoStack.append(entry)
        onHistoryChanged?()
        return true
    }

    /// 履歴を全て破棄する（プロジェクトの読み込み・新規作成時用）。
    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        onHistoryChanged?()
    }

    /// 容量を超えた分を最古から破棄する。破棄したら true。
    @discardableResult
    private func trimExcess() -> Bool {
        let excess = undoStack.count - capacity
        guard excess > 0 else { return false }
        undoStack.removeFirst(excess)
        return true
    }
}
