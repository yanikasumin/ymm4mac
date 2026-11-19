import Foundation

/// 明示的な編集トランザクション（開始・変更の蓄積・確定・キャンセル）。
///
/// 本家は `UndoRedoable` の自動監視で変更を捕捉するが、Mac 版 Core は
/// 全変更が共通通知を通らないため、捕捉はこの明示方式にする
/// （フロントエンド監査 Round 2 の設計判断）。
///
/// 契約:
/// - 変更の適用は呼び出し側が行う。`add` は適用済みの変更を「変更前後の
///   値＋適用方法」のコマンドとして登録するだけで、モデルは触らない。
/// - 確定（`EditCoordinator.commit`）すると、蓄積したコマンド全体が
///   履歴の1エントリになる。ドラッグのような逐次変更は、同一対象への
///   変更が収集時に統合されるため、開始値と最終値を持つ1エントリに
///   まとまる。
/// - キャンセル（`EditCoordinator.cancel`）すると、登録済みコマンドの
///   Undo で開始状態へ巻き戻し、履歴には残さない。
/// - 無変更（登録が無い、または変更が相殺された）トランザクションを
///   確定しても履歴エントリは作られない。
public final class EditTransaction {
    /// 蓄積中のコマンド収集。確定時に履歴へ渡る。
    let collector = EditCommandCollector()
    /// 確定またはキャンセル済みか。終了後の `add` は無視される。
    public private(set) var isFinished = false

    init() {}

    /// 蓄積済みコマンドの件数（統合・相殺の反映後）。
    public var commandCount: Int { collector.commandCount }

    /// 実質的な変更が蓄積されているか。
    public var hasChanges: Bool { !collector.isEmpty }

    /// 適用済みの変更をコマンドとして登録する。
    public func add(_ command: EditCommand) {
        guard !isFinished else { return }
        collector.add(command)
    }

    /// 値変更を登録する（`ValueChangeCommand` の簡易登録）。
    public func addValueChange<Value: Equatable>(
        target: EditTargetKey,
        oldValue: Value,
        newValue: Value,
        apply: @escaping (Value) -> Void
    ) {
        add(ValueChangeCommand(
            target: target, oldValue: oldValue, newValue: newValue, apply: apply
        ))
    }

    /// 手続き型の変更を登録する（`ActionEditCommand` の簡易登録）。
    public func addAction(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        add(ActionEditCommand(undo: undo, redo: redo))
    }

    /// キャンセル時の巻き戻し。登録済みコマンドを Undo 順で適用する。
    func rollback() {
        collector.undoAll()
    }

    /// 確定・キャンセルによる終了を記録する。
    func finish() {
        isFinished = true
    }
}
