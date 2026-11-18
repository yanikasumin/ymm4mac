import XCTest
@testable import YMM4Core

/// FE-UNDO-CORE: 明示的な編集トランザクションと EditCoordinator の検証。
///
/// 監査 Round 2 の受け入れ条件 R2-U01（1トランザクションの Undo/Redo
/// 往復）・R2-U02（ドラッグ型の逐次変更が履歴1エントリにまとまる）に
/// 対応する。変更の適用は呼び出し側が行い、トランザクションへは
/// 適用済みの変更を登録する、という契約で検証する。
final class EditCoordinatorTests: XCTestCase {

    /// 検証用の対象オブジェクト（アイテムの代わり）。
    private final class StubItem {
        var frame: Int = 0
        var length: Int = 10
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

    /// 変更をモデルへ適用してからトランザクションへ登録する
    /// （呼び出し側の通常の使い方）。
    private func applyAndRegister(
        _ transaction: EditTransaction, _ item: StubItem,
        keyPath: ReferenceWritableKeyPath<StubItem, Int>, key: String, to newValue: Int
    ) {
        let oldValue = item[keyPath: keyPath]
        item[keyPath: keyPath] = newValue
        transaction.addValueChange(
            target: EditTargetKey(item, key: key),
            oldValue: oldValue, newValue: newValue,
            apply: { item[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - R2-U01: 1トランザクションの Undo/Redo 往復

    func testSingleTransactionUndoRedo() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        let transaction = beginTransaction(coordinator)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 30)
        coordinator.commit(transaction)

        XCTAssertEqual(item.frame, 30)
        XCTAssertTrue(coordinator.canUndo)
        XCTAssertFalse(coordinator.canRedo)

        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 0)
        XCTAssertTrue(coordinator.canRedo)

        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(item.frame, 30)
    }

    // MARK: - R2-U02: 逐次変更が履歴1エントリにまとまる

    func testDragStyleChangesCoalesceIntoOneEntry() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        let transaction = beginTransaction(coordinator)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 10)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 25)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 40)

        // 同一対象への連鎖した変更は収集時に1コマンドへ統合される。
        XCTAssertEqual(transaction.commandCount, 1)
        coordinator.commit(transaction)
        XCTAssertEqual(coordinator.history.undoCount, 1)

        // 1回の Undo で開始値へ、1回の Redo で最終値へ戻る。
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 0)
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(item.frame, 40)
    }

    /// 値の連鎖がつながらない変更（変更後値と次の変更前値が不一致）は
    /// 統合されない（本家 CanConnect の連鎖条件）。
    func testDisconnectedChangesDoNotCoalesce() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        let transaction = beginTransaction(coordinator)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 1)
        // 実際の現在値（1）ではなく 5 を変更前値として登録する連鎖の切れた変更。
        item.frame = 6
        transaction.addValueChange(
            target: EditTargetKey(item, key: "Frame"),
            oldValue: 5, newValue: 6,
            apply: { item.frame = $0 }
        )
        XCTAssertEqual(transaction.commandCount, 2)
        coordinator.commit(transaction)
        XCTAssertEqual(coordinator.history.undoCount, 1)
    }

    /// 統合されたコマンドは収集の末尾へ移るため、Undo の適用順は
    /// 「統合された変更 → 先に登録されていた別の変更」になる（本家
    /// Collector の意味論）。
    func testCoalescedCommandMovesToEnd() {
        let coordinator = EditCoordinator()
        let item = StubItem()
        var applied: [String] = []

        func change(
            _ keyPath: ReferenceWritableKeyPath<StubItem, Int>, _ key: String, to newValue: Int,
            in transaction: EditTransaction
        ) {
            let oldValue = item[keyPath: keyPath]
            item[keyPath: keyPath] = newValue
            transaction.addValueChange(
                target: EditTargetKey(item, key: key),
                oldValue: oldValue, newValue: newValue,
                apply: { value in
                    item[keyPath: keyPath] = value
                    applied.append("\(key)=\(value)")
                }
            )
        }

        let transaction = beginTransaction(coordinator)
        change(\.frame, "Frame", to: 1, in: transaction)
        change(\.length, "Length", to: 20, in: transaction)
        change(\.frame, "Frame", to: 2, in: transaction)
        coordinator.commit(transaction)

        applied.removeAll()
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(applied, ["Frame=0", "Length=10"])

        applied.removeAll()
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(applied, ["Length=20", "Frame=2"])
    }

    /// Undo は値変更コマンドを先に、手続き型コマンドを後に適用する
    /// （本家 Collector の実行順）。Redo も同じく値変更が先。
    func testActionCommandsApplyAfterValueCommands() {
        let coordinator = EditCoordinator()
        let item = StubItem()
        var applied: [String] = []

        let transaction = beginTransaction(coordinator)
        transaction.addAction(
            undo: { applied.append("action-undo") },
            redo: { applied.append("action-redo") }
        )
        item.frame = 5
        transaction.addValueChange(
            target: EditTargetKey(item, key: "Frame"),
            oldValue: 0, newValue: 5,
            apply: { value in
                item.frame = value
                applied.append("value-\(value)")
            }
        )
        coordinator.commit(transaction)

        applied.removeAll()
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(applied, ["value-0", "action-undo"])

        applied.removeAll()
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(applied, ["value-5", "action-redo"])
    }

    // MARK: - 相殺・無変更

    /// 開始値へ戻る変更は相殺され、確定しても履歴に残らない。
    func testChangeReturningToStartValueLeavesNoEntry() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        let transaction = beginTransaction(coordinator)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 5)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 0)

        XCTAssertFalse(transaction.hasChanges)
        XCTAssertEqual(transaction.commandCount, 0)
        coordinator.commit(transaction)
        XCTAssertEqual(coordinator.history.undoCount, 0)
        XCTAssertFalse(coordinator.canUndo)
    }

    /// 変更前後が同値のコマンドは登録時点で破棄される。
    func testEmptyValueChangeIsDroppedOnAdd() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        let transaction = beginTransaction(coordinator)
        transaction.addValueChange(
            target: EditTargetKey(item, key: "Frame"),
            oldValue: 5, newValue: 5,
            apply: { item.frame = $0 }
        )
        XCTAssertEqual(transaction.commandCount, 0)
        coordinator.commit(transaction)
        XCTAssertFalse(coordinator.canUndo)
    }

    // MARK: - キャンセル

    /// キャンセルは蓄積した変更を開始状態へ巻き戻し、履歴に残さない。
    func testCancelRollsBackToStartState() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        let transaction = beginTransaction(coordinator)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 10)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 18)
        applyAndRegister(transaction, item, keyPath: \.length, key: "Length", to: 33)
        coordinator.cancel(transaction)

        XCTAssertEqual(item.frame, 0)
        XCTAssertEqual(item.length, 10)
        XCTAssertTrue(transaction.isFinished)
        XCTAssertNil(coordinator.activeTransaction)
        XCTAssertFalse(coordinator.canUndo)
    }

    // MARK: - トランザクションの管理

    /// 有効なトランザクションがある間の新しい開始は拒否され、前の
    /// トランザクションは巻き戻されずに残る（FE-R5-119-04 の契約
    /// 変更。開始時の暗黙キャンセルは廃止）。中断する場合は cancel を
    /// 明示的に呼ぶ。
    func testBeginIsRefusedWhileTransactionIsActive() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        let first = beginTransaction(coordinator)
        applyAndRegister(first, item, keyPath: \.frame, key: "Frame", to: 7)
        XCTAssertEqual(item.frame, 7)

        // 開始は拒否され、前の変更は巻き戻されない。
        XCTAssertNil(coordinator.beginTransaction())
        XCTAssertEqual(item.frame, 7)
        XCTAssertFalse(first.isFinished)
        XCTAssertTrue(coordinator.activeTransaction === first)

        // 明示的にキャンセルすれば開始状態へ戻り、新しく開始できる。
        coordinator.cancel(first)
        XCTAssertEqual(item.frame, 0)
        let second = beginTransaction(coordinator)
        XCTAssertTrue(coordinator.activeTransaction === second)

        coordinator.commit(second)
        XCTAssertFalse(coordinator.canUndo)
    }

    /// 終了済みトランザクションの確定は無視される（二重確定の防止）。
    func testCommitOfFinishedTransactionIsIgnored() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        let transaction = beginTransaction(coordinator)
        applyAndRegister(transaction, item, keyPath: \.frame, key: "Frame", to: 3)
        coordinator.commit(transaction)
        coordinator.commit(transaction)

        XCTAssertEqual(coordinator.history.undoCount, 1)
    }

    // MARK: - FE-R5-119-01: 未確定トランザクション中の Undo/Redo 排他

    /// 未確定のトランザクションがある間は Undo/Redo を実行せず、値も
    /// 履歴も変わらない。確定後に初めて Undo が効く。
    func testUndoRedoAreBlockedDuringActiveTransaction() {
        let coordinator = EditCoordinator()
        let item = StubItem()

        // A を確定する（0→10）。
        let a = beginTransaction(coordinator)
        applyAndRegister(a, item, keyPath: \.frame, key: "Frame", to: 10)
        coordinator.commit(a)
        XCTAssertEqual(coordinator.history.undoCount, 1)

        // B を開始し、変更を適用しただけ（未確定）にする（10→20）。
        let b = beginTransaction(coordinator)
        applyAndRegister(b, item, keyPath: \.frame, key: "Frame", to: 20)

        // 未確定の間は Undo/Redo とも false で、値・履歴は不変。
        XCTAssertFalse(coordinator.undo())
        XCTAssertFalse(coordinator.redo())
        XCTAssertEqual(item.frame, 20)
        XCTAssertEqual(coordinator.history.undoCount, 1)
        XCTAssertEqual(coordinator.history.redoCount, 0)

        // B を確定してから Undo が効く（B、A の順に戻る）。
        coordinator.commit(b)
        XCTAssertEqual(coordinator.history.undoCount, 2)
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 10)
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 0)
    }

    // MARK: - FE-R5-119-02: Undo/Redo とキャンセルの再入防止

    /// コマンドの適用クロージャの中から Undo を呼んでも再入せず、
    /// 外側の操作が完了して履歴が壊れない。
    func testUndoReentryFromApplyClosureIsRejected() {
        let coordinator = EditCoordinator()
        let item = StubItem()
        var nestedResults: [Bool] = []

        // 1件目（0→10）は通常の変更。
        let first = beginTransaction(coordinator)
        applyAndRegister(first, item, keyPath: \.frame, key: "Frame", to: 10)
        coordinator.commit(first)

        // 2件目（10→20）は、適用のたびに Coordinator.undo() を試みる
        // クロージャで登録する。
        item.frame = 20
        let second = beginTransaction(coordinator)
        second.addValueChange(
            target: EditTargetKey(item, key: "Frame"),
            oldValue: 10, newValue: 20,
            apply: { value in
                item.frame = value
                nestedResults.append(coordinator.undo())
            }
        )
        coordinator.commit(second)
        XCTAssertEqual(coordinator.history.undoCount, 2)

        // 外側の Undo で2件目が戻り、内側の試行は拒否される
        // （1件目まで巻き戻らない）。
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 10)
        XCTAssertEqual(nestedResults, [false])
        XCTAssertEqual(coordinator.history.undoCount, 1)
        XCTAssertEqual(coordinator.history.redoCount, 1)

        // 外側の Redo でも内側の試行は拒否され（Redo 中の内側 Undo も
        // 適用中として扱う）、通常どおり再適用される。内側の試行が
        // 外側の適用フラグを解除しないことも、続く Undo が通常どおり
        // 効くことで確認する。
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(item.frame, 20)
        XCTAssertEqual(nestedResults, [false, false])
        XCTAssertEqual(coordinator.history.undoCount, 2)
        XCTAssertEqual(coordinator.history.redoCount, 0)
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(item.frame, 10)
    }

    /// キャンセルの巻き戻し中に同じトランザクションを再キャンセル
    /// しても再帰的な巻き戻しは起きず、新しいトランザクションの
    /// 開始と組み合わさっても履歴・モデルが壊れない。
    func testCancelReentryDoesNotRecurse() {
        let coordinator = EditCoordinator()
        let item = StubItem()
        var rollbackCount = 0

        let transaction = beginTransaction(coordinator)
        item.frame = 10
        transaction.addAction(
            undo: {
                rollbackCount += 1
                item.frame = 0
                // 巻き戻し中: 同じトランザクションの再キャンセルと、
                // 新しいトランザクションの開始を試みる。
                coordinator.cancel(transaction)
                _ = coordinator.beginTransaction()
            },
            redo: { item.frame = 10 }
        )
        coordinator.cancel(transaction)

        XCTAssertEqual(rollbackCount, 1)
        XCTAssertEqual(item.frame, 0)
        XCTAssertTrue(transaction.isFinished)
        XCTAssertFalse(coordinator.canUndo)
    }
}
