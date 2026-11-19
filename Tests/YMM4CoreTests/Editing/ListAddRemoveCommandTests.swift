import XCTest
@testable import YMM4Core

/// FE-UNDO-WIRING: リスト追加・削除コマンド（本家
/// `UndoRedoAddRemoveListItemsCommand` 相当、IsAction=false）の検証。
///
/// 受け入れ観点: 追加のみ／削除のみ／混在の Undo・Redo 往復、削除分の
/// 元位置への復元、値変更コマンドと同一トランザクションに混在した
/// 場合の実行順（非 Action グループとして登録の逆順／正順）、
/// 実 Timeline のアイテム列への適用（長さキャッシュの追随を含む）。
final class ListAddRemoveCommandTests: XCTestCase {

    /// 検証用の要素（アイテムの代わり）。
    private final class StubElement {
        let name: String
        var frame: Int = 0
        init(_ name: String) { self.name = name }
    }

    /// 配列の所有者。コマンドの読み書きクロージャはこちらを保持する。
    private final class StubList {
        var items: [StubElement] = []
    }

    private func makeCommand(
        list: StubList,
        added: [ListAddRemoveCommand<StubElement>.Entry] = [],
        removed: [ListAddRemoveCommand<StubElement>.Entry] = []
    ) -> ListAddRemoveCommand<StubElement> {
        ListAddRemoveCommand(
            getItems: { list.items },
            setItems: { list.items = $0 },
            added: added, removed: removed
        )
    }

    private func names(_ list: StubList) -> [String] {
        list.items.map(\.name)
    }

    // MARK: - 追加のみ

    func testAddOnlyUndoRedo() {
        let list = StubList()
        let a = StubElement("a")
        let b = StubElement("b")
        list.items = [a]

        // b を末尾（位置1）へ追加した変更を記録する。
        list.items = [a, b]
        let command = makeCommand(
            list: list, added: [.init(index: 1, element: b)])

        XCTAssertFalse(command.isAction)
        XCTAssertFalse(command.isEmpty)

        command.undo()
        XCTAssertEqual(names(list), ["a"])
        command.redo()
        XCTAssertEqual(names(list), ["a", "b"])
    }

    /// 追加分は記録位置へ戻る（末尾への単純追加ではない）。
    func testAddRestoresRecordedIndex() {
        let list = StubList()
        let a = StubElement("a")
        let b = StubElement("b")
        let c = StubElement("c")
        list.items = [a, c]

        list.items = [a, b, c]
        let command = makeCommand(
            list: list, added: [.init(index: 1, element: b)])

        command.undo()
        XCTAssertEqual(names(list), ["a", "c"])
        command.redo()
        XCTAssertEqual(names(list), ["a", "b", "c"])
    }

    // MARK: - 削除のみ

    /// 複数要素の削除は、Undo で元の位置と並びのまま戻る。
    func testRemoveOnlyUndoRestoresOriginalIndices() {
        let list = StubList()
        let a = StubElement("a")
        let b = StubElement("b")
        let c = StubElement("c")
        let d = StubElement("d")
        list.items = [a, b, c, d]

        // b（位置1）と d（位置3）を削除した変更を記録する。
        list.items = [a, c]
        let command = makeCommand(
            list: list,
            removed: [.init(index: 1, element: b), .init(index: 3, element: d)])

        command.undo()
        XCTAssertEqual(names(list), ["a", "b", "c", "d"])
        command.redo()
        XCTAssertEqual(names(list), ["a", "c"])
    }

    // MARK: - 追加と削除の混在

    func testMixedAddAndRemoveUndoRedo() {
        let list = StubList()
        let a = StubElement("a")
        let b = StubElement("b")
        let c = StubElement("c")
        list.items = [a, b]

        // b を削除し、c を末尾へ追加した変更を記録する。
        list.items = [a, c]
        let command = makeCommand(
            list: list,
            added: [.init(index: 1, element: c)],
            removed: [.init(index: 1, element: b)])

        command.undo()
        XCTAssertEqual(names(list), ["a", "b"])
        command.redo()
        XCTAssertEqual(names(list), ["a", "c"])
    }

    // MARK: - コマンドの性質

    /// 追加も削除も無いコマンドは空であり、履歴へ残らない。
    func testEmptyCommandIsDropped() {
        let coordinator = EditCoordinator()
        let list = StubList()
        let transaction = coordinator.beginTransaction()
        XCTAssertNotNil(transaction)
        transaction?.add(makeCommand(list: list))
        XCTAssertEqual(transaction?.commandCount, 0)
        coordinator.commit(transaction!)
        XCTAssertFalse(coordinator.canUndo)
    }

    /// リスト変更は値変更と統合されない（canConnect は常に false）。
    func testListCommandDoesNotConnect() {
        let list = StubList()
        let element = StubElement("a")
        let command = makeCommand(
            list: list, added: [.init(index: 0, element: element)])
        XCTAssertFalse(command.canConnect(with: command))
    }

    // MARK: - 値変更との混在順序

    /// 値変更とリスト変更は同じ非 Action グループとして扱われ、
    /// Undo は登録の逆順、Redo は登録の正順に適用される（本家
    /// Collector の意味論。リスト変更を Action へ寄せると値変更より
    /// 後回しになり、この順序が逆転する）。
    func testMixedWithValueChangeAppliesInCollectorOrder() {
        let coordinator = EditCoordinator()
        let list = StubList()
        let item = StubElement("item")
        var log: [String] = []

        let command = ListAddRemoveCommand<StubElement>(
            getItems: { list.items },
            setItems: { list.items = $0; log.append("list") },
            added: [.init(index: 0, element: item)],
            removed: [])

        let transaction = coordinator.beginTransaction()
        XCTAssertNotNil(transaction)
        // 値変更を先に、リスト変更を後に登録する。適用は呼び出し側が
        // 先に行う（コマンドは適用済み変更の記録である）。
        item.frame = 10
        transaction?.addValueChange(
            target: EditTargetKey(item, key: "Frame"),
            oldValue: 0, newValue: 10,
            apply: { value in item.frame = value; log.append("value") })
        list.items = [item]
        transaction?.add(command)
        coordinator.commit(transaction!)

        log.removeAll()
        XCTAssertTrue(coordinator.undo())
        // 逆順: リスト変更（追加の取消し）→ 値変更（旧値へ）。
        XCTAssertEqual(log, ["list", "value"])
        XCTAssertTrue(list.items.isEmpty)
        XCTAssertEqual(item.frame, 0)

        log.removeAll()
        XCTAssertTrue(coordinator.redo())
        // 正順: 値変更（新値へ）→ リスト変更（追加の再適用）。
        XCTAssertEqual(log, ["value", "list"])
        XCTAssertEqual(list.items.map(\.name), ["item"])
        XCTAssertEqual(item.frame, 10)
    }

    /// 同一トランザクションで「アイテムの値変更＋そのアイテムの削除」
    /// を行った場合、Undo で要素が戻り値も旧値へ戻る。
    func testValueChangeAndRemovalOfSameElement() {
        let coordinator = EditCoordinator()
        let list = StubList()
        let item = StubElement("item")
        list.items = [item]

        let transaction = coordinator.beginTransaction()
        XCTAssertNotNil(transaction)
        item.frame = 25
        transaction?.addValueChange(
            target: EditTargetKey(item, key: "Frame"),
            oldValue: 0, newValue: 25,
            apply: { item.frame = $0 })
        list.items = []
        transaction?.add(makeCommand(
            list: list, removed: [.init(index: 0, element: item)]))
        coordinator.commit(transaction!)

        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(list.items.map(\.name), ["item"])
        XCTAssertEqual(item.frame, 0)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(list.items.isEmpty)
        XCTAssertEqual(item.frame, 25)
    }

    // MARK: - 実 Timeline への適用

    /// タイムラインのアイテム列に対する追加・削除の往復。
    /// setItems 側で長さキャッシュを再計算する接続（アプリ層の
    /// 接続形）で、キャッシュも往復に追随することを確認する。
    func testTimelineItemsAddRemoveRoundTrip() {
        let timeline = Timeline()
        let first = TextItem()
        first.frame = 0
        first.length = 30
        let second = TextItem()
        second.frame = 30
        second.length = 30
        timeline.addItems([first])
        XCTAssertEqual(timeline.length, 30)

        let coordinator = EditCoordinator()
        func timelineCommand(
            added: [ListAddRemoveCommand<BaseItem>.Entry] = [],
            removed: [ListAddRemoveCommand<BaseItem>.Entry] = []
        ) -> ListAddRemoveCommand<BaseItem> {
            ListAddRemoveCommand<BaseItem>(
                getItems: { timeline.items },
                setItems: {
                    timeline.items = $0
                    timeline.refreshTimelineLengthAndMaxLayer()
                },
                added: added, removed: removed)
        }

        // 追加の往復。
        let addTransaction = coordinator.beginTransaction()
        XCTAssertNotNil(addTransaction)
        timeline.addItems([second])
        addTransaction?.add(timelineCommand(
            added: [.init(index: 1, element: second)]))
        coordinator.commit(addTransaction!)
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertEqual(timeline.length, 60)

        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(timeline.items.count, 1)
        XCTAssertTrue(timeline.items.first === first)
        XCTAssertEqual(timeline.length, 30)
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertEqual(timeline.length, 60)

        // 削除の往復。
        let removeTransaction = coordinator.beginTransaction()
        XCTAssertNotNil(removeTransaction)
        timeline.deleteItems([first])
        removeTransaction?.add(timelineCommand(
            removed: [.init(index: 0, element: first)]))
        coordinator.commit(removeTransaction!)
        XCTAssertEqual(timeline.items.count, 1)

        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertTrue(timeline.items.first === first)
        XCTAssertEqual(timeline.length, 60)
    }
}
