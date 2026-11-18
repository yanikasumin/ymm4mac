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
///   破棄される（本家の `isUndoRedoing` による記録抑制）。ただし抑制が
///   有効なのはコマンドの適用中だけで、履歴変更の通知は本家と同様に
///   抑制を解除してから発火させる。通知の時点でも抑制が残っていると、
///   通知から生じた新しい編集の確定が記録だけ黙って破棄され、Undo
///   できない変更が生まれるためである（FE-R6-119-02）。
///
/// 本家との意図的な差異:
/// - 本家の Undo/Redo は非同期（非同期コマンドを含むため）。Mac 版の
///   コマンドは全て同期のため、履歴も同期 API とする。
/// - 本家は履歴が空の Undo/Redo を想定しない（呼び出し側が可否を
///   見る）。こちらは `false` を返して安全に倒す。
/// - 本家はモデルの自動監視でコマンドを集めるが、こちらへの投入は
///   `EditCoordinator` 経由の明示トランザクションに限る（投入経路を
///   1つに保つため、`record` はモジュール内に閉じる）。
/// - 履歴の操作（確定・Undo・Redo）の入口も `EditCoordinator` へ
///   一本化する。未確定トランザクションとの排他や再入防止は
///   Coordinator 側の責務であり、こちら側の `undo` / `redo` も
///   モジュール内に閉じて、アプリ層からは Coordinator 経由でのみ
///   実行できる形にする（FE-R5-119-01）。
public final class UndoHistory {
    /// 履歴容量の既定値（本家の上限既定値と同じ100）。
    public static let defaultCapacity = 100

    /// 容量の実値。0未満にはならない（不変条件は代入の全経路で保証
    /// する。FE-R5-119-03）。
    private var capacityStorage: Int

    /// 保持する履歴エントリの上限。変更すると直ちに最古から切り詰める。
    /// 負の値を代入した場合は 0 として扱う。
    public var capacity: Int {
        get { capacityStorage }
        set {
            capacityStorage = max(0, newValue)
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
        self.capacityStorage = max(0, capacity)
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
    /// 適用中（コマンドの適用クロージャからの再入）は実行せず false
    /// を返す（FE-R5-119-02）。入口は `EditCoordinator` 経由に一本化
    /// するためモジュール内に閉じる。
    ///
    /// 記録抑制はコマンドの適用中だけに限定し、スタックの更新を終えて
    /// 抑制を解除してから履歴変更の通知を発火させる（FE-R6-119-02）。
    @discardableResult
    func undo() -> Bool {
        guard !isApplying else { return false }
        guard let entry = undoStack.popLast() else { return false }
        applySuppressingRecording { entry.undoAll() }
        redoStack.append(entry)
        onHistoryChanged?()
        return true
    }

    /// 最新の Redo エントリを再適用し、Undo 側へ戻す。対象が無ければ false。
    /// 再入と通知の扱いは `undo` と同じ。
    @discardableResult
    func redo() -> Bool {
        guard !isApplying else { return false }
        guard let entry = redoStack.popLast() else { return false }
        applySuppressingRecording { entry.redoAll() }
        undoStack.append(entry)
        onHistoryChanged?()
        return true
    }

    /// コマンドの適用だけを記録抑制の範囲内で実行する。適用が終われば
    /// 抑制は解除されるため、この後に発火する履歴変更通知の中から
    /// 新しい編集を確定させても、その確定は記録される
    /// （FE-R6-119-02）。
    private func applySuppressingRecording(_ apply: () -> Void) {
        isApplying = true
        defer { isApplying = false }
        apply()
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
