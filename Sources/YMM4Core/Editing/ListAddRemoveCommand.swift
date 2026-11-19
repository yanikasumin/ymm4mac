import Foundation

/// リストへの要素の追加・削除（本家 `UndoRedoAddRemoveListItemsCommand`
/// 相当）。
///
/// 本家ではこのコマンドは `IsAction = false` で、値変更コマンドと
/// 同じ実行順グループに入る。そのためこちらでも `isAction` は false
/// とし、`ActionEditCommand`（手続き型）へ寄せない（値変更との混在
/// 時に Undo の適用順が本家と逆転するため。フロントエンド監査
/// Round 5 の接続条件）。
///
/// コマンドは「変更がリストへ適用された後」に、追加・削除された
/// 要素とその位置を持って生成される。Undo は追加分を取り除いて
/// 削除分を元の位置へ戻し、Redo はその逆を行う。要素の照合は参照
/// 同一性で行う（本家のリスト操作が要素の同一性で効くことに対応）。
///
/// 接続側の契約（`EditTargetKey` の契約と同じ）: リストへの読み書き
/// クロージャと保持する要素が、対象リストの所有者を強く保持する
/// こと。コマンドが履歴に残る間、対象と要素は解放されない。
public final class ListAddRemoveCommand<Element: AnyObject>: EditCommand {
    /// 位置つきの要素1件。`index` は変更適用時点のリスト内位置
    /// （追加分は追加後の位置、削除分は削除前の位置）。
    public struct Entry {
        public let index: Int
        public let element: Element

        public init(index: Int, element: Element) {
            self.index = index
            self.element = element
        }
    }

    private let getItems: () -> [Element]
    private let setItems: ([Element]) -> Void
    /// この変更で追加された要素。
    public let added: [Entry]
    /// この変更で削除された要素。
    public let removed: [Entry]

    public init(
        getItems: @escaping () -> [Element],
        setItems: @escaping ([Element]) -> Void,
        added: [Entry],
        removed: [Entry]
    ) {
        self.getItems = getItems
        self.setItems = setItems
        self.added = added
        self.removed = removed
    }

    /// 本家 `UndoRedoAddRemoveListItemsCommand` が IsAction=false で
    /// あることに対応し、値変更コマンドと同じ実行順グループに入る。
    public var isAction: Bool { false }

    /// 追加も削除も無いコマンドは空であり、収集時に破棄される。
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    /// リスト変更は統合しない（本家でも追加・削除の連結は行わない）。
    public func canConnect(with other: EditCommand) -> Bool { false }

    public func connect(with other: EditCommand) -> EditCommand {
        preconditionFailure("ListAddRemoveCommand は統合できない（canConnect は常に false）")
    }

    /// 追加分を取り除き、削除分を元の位置へ戻す。
    public func undo() {
        var items = getItems()
        items.removeAll { element in added.contains { $0.element === element } }
        insert(entries: removed, into: &items)
        setItems(items)
    }

    /// 削除分を取り除き、追加分を元の位置へ戻す。
    public func redo() {
        var items = getItems()
        items.removeAll { element in removed.contains { $0.element === element } }
        insert(entries: added, into: &items)
        setItems(items)
    }

    /// 記録位置の昇順に挿入する。記録位置は変更適用時点のもので、
    /// Undo/Redo の時点ではリストの長さが変わっている可能性がある
    /// ため、範囲内へ丸めてから挿入する。
    private func insert(entries: [Entry], into items: inout [Element]) {
        for entry in entries.sorted(by: { $0.index < $1.index }) {
            let index = min(max(entry.index, 0), items.count)
            items.insert(entry.element, at: index)
        }
    }
}
