import XCTest
@testable import YMM4Core

/// FE-UNDO-CORE: UndoHistory の検証。
///
/// 監査 Round 2 の受け入れ条件 R2-U03（容量超過で最古を破棄）・
/// R2-U04（新規確定で Redo を破棄、適用中の記録抑制）に対応する。
final class UndoHistoryTests: XCTestCase {

    /// 検証用の対象オブジェクト（アイテムの代わり）。
    private final class StubItem {
        var frame: Int = 0
    }

    /// トランザクションを開始し、拒否されたらテストを失敗させる
    /// （開始が成功する前提のテスト用）。
    private func beginTransaction(
        _ coordinator: EditCoordinator,
        file: StaticString = #filePath, line: UInt = #line
    ) -> EditTransaction {
        let transaction = coordinator.beginTransaction()
        XCTAssertNotNil(transaction, "トランザクションの開始が拒否された", file: file, line: line)
        return transaction!
    }

    /// 変更を適用して1トランザクションとして確定する。
    private func commitChange(
        _ coordinator: EditCoordinator, _ item: StubItem, to newValue: Int
    ) {
        let oldValue = item.frame
        item.frame = newValue
        let transaction = beginTransaction(coordinator)
        transaction.addValueChange(
            target: EditTargetKey(item, key: "Frame"),
            oldValue: oldValue, newValue: newValue,
            apply: { item.frame = $0 }
        )
        coordinator.commit(transaction)
    }

    // MARK: - R2-U03: 容量

    /// 容量を超えたら最古のエントリから破棄され、Undo 可能な範囲がずれる。
    func testCapacityTrimsOldestEntries() {
        let coordinator = EditCoordinator(capacity: 3)
        let item = StubItem()

        commitChange(coordinator, item, to: 1)
        commitChange(coordinator, item, to: 2)
        commitChange(coordinator, item, to: 3)
        commitChange(coordinator, item, to: 4)

        XCTAssertEqual(coordinator.history.undoCount, 3)

        // 破棄された最古の変更（0→1）までは戻れない。
        XCTAssertTrue(coordinator.undo())
        XCTAssertTrue(coordinator.undo())
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 1)
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertFalse(coordinator.undo())
    }

    /// 既定容量は本家と同じ100。
    func testDefaultCapacityIsOneHundred() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        for value in 1...101 {
            commitChange(coordinator, item, to: value)
        }
        XCTAssertEqual(coordinator.history.undoCount, 100)
    }

    // MARK: - R2-U04: Redo の破棄と記録抑制

    /// Undo 後の新規確定で Redo は破棄される。
    func testNewCommitClearsRedo() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        commitChange(coordinator, item, to: 10)
        commitChange(coordinator, item, to: 20)
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 10)
        XCTAssertTrue(coordinator.canRedo)

        commitChange(coordinator, item, to: 15)
        XCTAssertFalse(coordinator.canRedo)
        XCTAssertEqual(coordinator.history.redoCount, 0)

        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 10)
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 0)
    }

    /// 実質的な変更が無いトランザクションの確定は、履歴エントリを
    /// 作らないだけでなく Redo も破棄しない（本家の空の Record() の
    /// 意味論）。
    func testEmptyCommitPreservesRedo() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        commitChange(coordinator, item, to: 10)
        XCTAssertTrue(coordinator.undo())
        XCTAssertTrue(coordinator.canRedo)

        let empty = beginTransaction(coordinator)
        coordinator.commit(empty)

        XCTAssertTrue(coordinator.canRedo)
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(item.frame, 10)
    }

    /// Undo/Redo の適用中に生じた確定は記録されない。適用の副作用で
    /// モデルが変わっても、履歴には新しいエントリが増えず、Redo の
    /// 往復も壊れない。
    func testRecordingIsSuppressedDuringApplication() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        // 適用の副作用として、別の変更を確定しようとする手続き型コマンド。
        func sideEffectAttempt(to newValue: Int) {
            let oldValue = item.frame
            item.frame = newValue
            let transaction = beginTransaction(coordinator)
            transaction.addValueChange(
                target: EditTargetKey(item, key: "Frame"),
                oldValue: oldValue, newValue: newValue,
                apply: { item.frame = $0 }
            )
            coordinator.commit(transaction)
        }

        item.frame = 30
        let transaction = beginTransaction(coordinator)
        transaction.addAction(
            undo: {
                item.frame = 0
                sideEffectAttempt(to: 999)
            },
            redo: {
                item.frame = 30
                sideEffectAttempt(to: 555)
            }
        )
        coordinator.commit(transaction)
        XCTAssertEqual(coordinator.history.undoCount, 1)

        // Undo 適用中の確定試行は破棄され、エントリは Redo 側へ移るだけ。
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 999)
        XCTAssertEqual(coordinator.history.undoCount, 0)
        XCTAssertEqual(coordinator.history.redoCount, 1)

        // Redo 適用中の確定試行も破棄される。
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(item.frame, 555)
        XCTAssertEqual(coordinator.history.undoCount, 1)
        XCTAssertEqual(coordinator.history.redoCount, 0)
    }

    // MARK: - その他

    /// 履歴が空の Undo/Redo は false を返して何もしない。
    func testUndoRedoOnEmptyHistoryReturnsFalse() {
        let coordinator = EditCoordinator()
        XCTAssertFalse(coordinator.undo())
        XCTAssertFalse(coordinator.redo())
    }

    /// 全消去で Undo/Redo 両側が空になる。
    func testClearEmptiesHistory() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        commitChange(coordinator, item, to: 10)
        commitChange(coordinator, item, to: 20)
        XCTAssertTrue(coordinator.undo())
        coordinator.history.clear()

        XCTAssertFalse(coordinator.canUndo)
        XCTAssertFalse(coordinator.canRedo)
        XCTAssertEqual(coordinator.history.undoCount, 0)
        XCTAssertEqual(coordinator.history.redoCount, 0)
    }

    /// 履歴変更の通知は確定・Undo・Redo・全消去で発火し、無変更の
    /// 確定では発火しない。
    func testHistoryChangedNotification() {
        let coordinator = EditCoordinator()
        let item = StubItem()
        var notifications = 0
        coordinator.onHistoryChanged = { notifications += 1 }

        commitChange(coordinator, item, to: 10)
        XCTAssertEqual(notifications, 1)

        let empty = beginTransaction(coordinator)
        coordinator.commit(empty)
        XCTAssertEqual(notifications, 1)

        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(notifications, 2)
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(notifications, 3)

        coordinator.history.clear()
        XCTAssertEqual(notifications, 4)
    }

    // MARK: - FE-R5-119-03: 容量の不変条件

    /// 空の履歴へ負の容量を指定しても異常終了せず、容量0として扱う
    /// （容量0では確定しても何も保持されない）。
    func testNegativeCapacityOnEmptyHistoryBehavesAsZero() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        coordinator.history.capacity = -1
        XCTAssertEqual(coordinator.history.capacity, 0)

        commitChange(coordinator, item, to: 10)
        XCTAssertEqual(item.frame, 10)
        XCTAssertEqual(coordinator.history.undoCount, 0)
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertFalse(coordinator.undo())
    }

    /// 非空の履歴へ負の容量を指定すると、容量0として全エントリが
    /// 切り詰められる（異常終了しない）。
    func testNegativeCapacityOnNonEmptyHistoryTrimsAll() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        commitChange(coordinator, item, to: 10)
        commitChange(coordinator, item, to: 20)
        XCTAssertEqual(coordinator.history.undoCount, 2)

        coordinator.history.capacity = -5
        XCTAssertEqual(coordinator.history.capacity, 0)
        XCTAssertEqual(coordinator.history.undoCount, 0)
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertFalse(coordinator.undo())
    }
}
