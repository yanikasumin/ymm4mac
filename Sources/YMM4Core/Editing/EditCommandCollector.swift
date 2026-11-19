import Foundation

/// 履歴1エントリ分のコマンド収集（本家 `UndoRedoCommandCollector` 相当）。
///
/// 追加時の規則は本家の意味論を再現する:
/// - 空のコマンド（変更前後が同値）は受け付けない。
/// - 既存コマンドと統合できる後続の変更が来たら、既存を取り除いて
///   統合結果を末尾へ追加する（統合で位置が末尾へ移る）。
/// - 統合結果が空になる（変更が相殺された）場合は追加しない。
///
/// 実行順も本家どおり: Undo は値変更コマンドを逆順に、次に手続き型
/// コマンドを逆順に適用する。Redo はその正順。
final class EditCommandCollector {
    private(set) var commands: [EditCommand] = []

    var isEmpty: Bool { commands.isEmpty }

    var commandCount: Int { commands.count }

    func add(_ command: EditCommand) {
        if command.isEmpty { return }
        if let index = commands.firstIndex(where: { $0.canConnect(with: command) }) {
            let existing = commands.remove(at: index)
            let merged = existing.connect(with: command)
            if !merged.isEmpty {
                commands.append(merged)
            }
        } else {
            commands.append(command)
        }
    }

    /// 収集した変更を全て変更前へ戻す（トランザクションのキャンセルでも使う）。
    func undoAll() {
        for command in commands.reversed() where !command.isAction {
            command.undo()
        }
        for command in commands.reversed() where command.isAction {
            command.undo()
        }
    }

    /// 収集した変更を全て変更後へ再適用する。
    func redoAll() {
        for command in commands where !command.isAction {
            command.redo()
        }
        for command in commands where command.isAction {
            command.redo()
        }
    }
}
