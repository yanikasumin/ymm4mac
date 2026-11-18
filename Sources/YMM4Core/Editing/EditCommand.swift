import Foundation

/// 編集コマンドが指す対象（対象オブジェクトの同一性＋プロパティ識別子）。
///
/// 本家 `UndoRedoPropertyChangedCommand` は「対象インスタンス＋プロパティ名」
/// で変更先を識別し、Undo/Redo 時にリフレクションで値を戻す。Mac 版 Core
/// にはリフレクション相当の仕組みが無く、既存の `PropertyAccess` も
/// get/set クロージャで読み書きを抽象化しているため、こちらでは同一性を
/// このキーで表し、値の適用はコマンド側のクロージャが担う。
///
/// 接続側の契約: このキーは対象オブジェクトを保持しない
/// （`ObjectIdentifier` は同一性を表す値でしかない）。コマンドが履歴に
/// 残る間に対象が解放されない保証は、適用クロージャ側が対象を強参照
/// することに依存する。接続側はコマンドの適用クロージャで対象を強く
/// 捕捉すること。弱参照だけで捕捉すると、履歴に残ったコマンドの
/// Undo/Redo の時点で対象が消えている可能性がある。
public struct EditTargetKey: Hashable, Sendable {
    /// 対象オブジェクトの同一性。
    public let object: ObjectIdentifier
    /// プロパティ識別子（記述子の `id` 等、対象内で一意な名前）。
    public let key: String

    public init(object: ObjectIdentifier, key: String) {
        self.object = object
        self.key = key
    }

    public init(_ target: AnyObject, key: String) {
        self.init(object: ObjectIdentifier(target), key: key)
    }
}

/// 履歴に記録できる編集コマンド1件の契約（本家 `IUndoRedoCommandBase` 相当）。
///
/// コマンドは「変更がモデルへ適用された後」に、変更前後の状態を持って
/// 生成される。Undo/Redo は保持した状態を再適用する操作であり、変更その
/// ものの実行はコマンドの責務ではない。
public protocol EditCommand: AnyObject {
    /// 手続き型コマンドか。本家同様、値変更コマンド（非 Action）は
    /// 手続き型コマンド（Action）より先に Undo/Redo される。
    var isAction: Bool { get }
    /// 実質的な変更が無いか（変更前後が同値）。空のコマンドは収集時に
    /// 破棄され、履歴に残らない。
    var isEmpty: Bool { get }
    /// 後続の変更 `other` と1件へ統合できるか。
    func canConnect(with other: EditCommand) -> Bool
    /// `other` と統合した新しいコマンドを返す。`canConnect(with:)` が
    /// true の場合にだけ呼ばれる。
    func connect(with other: EditCommand) -> EditCommand
    /// 変更前の状態へ戻す。
    func undo()
    /// 変更後の状態を再適用する。
    func redo()
}

/// 1つのプロパティの値変更（本家 `UndoRedoPropertyChangedCommand` 相当）。
///
/// 対象は `EditTargetKey` で識別し、値の書き戻しは `apply` クロージャが
/// 行う（本家はリフレクションでプロパティへ代入する。Mac 版は既存の
/// `PropertyAccess` と同じクロージャ方式に揃えた）。クロージャは対象を
/// 保持するため、コマンドが履歴に残る間は対象も残る（本家も対象
/// インスタンスを保持する）。
public final class ValueChangeCommand<Value: Equatable>: EditCommand {
    /// 変更対象。
    public let target: EditTargetKey
    /// 変更前の値。
    public let oldValue: Value
    /// 変更後の値。
    public let newValue: Value
    private let apply: (Value) -> Void

    public init(
        target: EditTargetKey,
        oldValue: Value,
        newValue: Value,
        apply: @escaping (Value) -> Void
    ) {
        self.target = target
        self.oldValue = oldValue
        self.newValue = newValue
        self.apply = apply
    }

    public var isAction: Bool { false }

    public var isEmpty: Bool { oldValue == newValue }

    /// 統合できるのは、同じ対象への変更で、自分の変更後値が相手の
    /// 変更前値と一致する（値の連鎖がつながる）場合だけ（本家
    /// `CanConnect` の意味論）。
    public func canConnect(with other: EditCommand) -> Bool {
        guard let other = other as? ValueChangeCommand<Value> else { return false }
        return target == other.target && newValue == other.oldValue
    }

    /// 統合結果は「自分の変更前値 → 相手の変更後値」の1件になる。
    /// 適用クロージャは同一対象・同一プロパティ由来で等価なため、
    /// 自分のものを引き継ぐ（本家は対象＋プロパティ名を引き継ぐ）。
    public func connect(with other: EditCommand) -> EditCommand {
        guard let other = other as? ValueChangeCommand<Value> else {
            preconditionFailure("canConnect(with:) が true の場合にだけ呼ばれる")
        }
        return ValueChangeCommand(
            target: target, oldValue: oldValue, newValue: other.newValue, apply: apply
        )
    }

    public func undo() { apply(oldValue) }

    public func redo() { apply(newValue) }
}

/// 手続き型の変更（本家 `UndoRedoActionCommand` 相当）。
///
/// 値の対では表せない変更（アイテムの追加・削除など）を、Undo/Redo の
/// クロージャ対で表す。統合は行わず、空にもならない。
public final class ActionEditCommand: EditCommand {
    private let undoBody: () -> Void
    private let redoBody: () -> Void

    public init(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        self.undoBody = undo
        self.redoBody = redo
    }

    public var isAction: Bool { true }

    public var isEmpty: Bool { false }

    public func canConnect(with other: EditCommand) -> Bool { false }

    public func connect(with other: EditCommand) -> EditCommand {
        preconditionFailure("ActionEditCommand は統合できない（canConnect は常に false）")
    }

    public func undo() { undoBody() }

    public func redo() { redoBody() }
}
