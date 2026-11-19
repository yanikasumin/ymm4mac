import XCTest
@testable import YMM4Core

/// FE-UNDO-WIRING の記録集約点 `EditRecorder` の検証。
///
/// 受け入れ観点:
/// - FE-R20-126-02: トランザクション開始が拒否された場合、
///   `recordTimelineChange` は変更本体を実行せず、モデルにも履歴にも
///   変更を残さない。実行できる場合は変更と記録が行われる。
/// - FE-R20-126-03: セッションには所有権トークンが結び付いており、
///   所有者でない経路の値変更はセッションへ取り込まれない。確定・
///   破棄もトークン一致の場合だけ作用する。
/// - FE-R21-126-01: 終了・取消・プロジェクト切り替えで失効した
///   トークンは再び編集を許可しない。復元処理中（巻き戻し中）の
///   再入編集は入口確認で拒否される。
final class EditRecorderTests: XCTestCase {

    /// 値変更の検証用の箱（アイテムの代わり）。
    private final class ValueBox {
        var value = 0
    }

    private func makeItem(frame: Int, length: Int) -> TextItem {
        let item = TextItem()
        item.frame = frame
        item.length = length
        return item
    }

    /// 開始できる場合は本体が実行され、差分が履歴へ記録される。
    func testRecordTimelineChangeExecutesAndRecordsWhenIdle() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 30)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()

        let recorder = EditRecorder()
        var executed = false
        let result = recorder.recordTimelineChange(timeline: timeline) {
            executed = true
            item.frame = 45
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertTrue(result)
        XCTAssertTrue(executed)
        XCTAssertEqual(item.frame, 45)
        XCTAssertTrue(recorder.coordinator.canUndo)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(item.frame, 0)
    }

    /// セッションが有効な間に開始を拒否された場合、本体は実行されず、
    /// モデルにも履歴にも変更が残らない（FE-R20-126-02）。
    func testRecordTimelineChangeRefusedWhileSessionActive() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 30)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()

        let recorder = EditRecorder()
        let token = recorder.beginSession()
        XCTAssertNotNil(token)
        guard let token else { return }

        var executed = false
        let result = recorder.recordTimelineChange(timeline: timeline) {
            executed = true
            item.frame = 45
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertFalse(result)
        XCTAssertFalse(executed)
        XCTAssertEqual(item.frame, 0)
        XCTAssertEqual(timeline.length, 30)

        // セッションを確定しても、拒否された変更は履歴に現れない
        // （セッション自体は空のためエントリ自体が作られない）。
        recorder.commitSession(token: token)
        XCTAssertFalse(recorder.coordinator.canUndo)
    }

    // MARK: - FE-R20-126-03 セッション所有権

    /// セッションが無い間の離散編集は、その場で履歴へ記録される。
    func testDiscreteValueChangeRecordsImmediately() {
        let recorder = EditRecorder()
        let box = ValueBox()
        XCTAssertTrue(recorder.canRecordValueChange())

        box.value = 10
        recorder.recordValueChange(
            target: EditTargetKey(box, key: "value"),
            oldValue: 0, newValue: 10,
            apply: { box.value = $0 })
        XCTAssertTrue(recorder.coordinator.canUndo)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(box.value, 0)
        XCTAssertTrue(recorder.coordinator.redo())
        XCTAssertEqual(box.value, 10)
    }

    /// 所有者の変更はセッションへ蓄積され、確定で1エントリになる。
    /// 所有者でない経路（トークン無し）の変更はセッションへ取り込ま
    /// れず、入口確認も false を返す。終了済みセッションの古い
    /// トークンも、新しいセッションに対しては所有者として扱われない。
    func testSessionOwnershipForValueChanges() {
        let recorder = EditRecorder()
        let ownerBox = ValueBox()
        let foreignBox = ValueBox()

        let token = recorder.beginSession()
        XCTAssertNotNil(token)
        guard let token else { return }

        // 入口確認: 所有者だけが true。
        XCTAssertTrue(recorder.canRecordValueChange(sessionToken: token))
        XCTAssertFalse(recorder.canRecordValueChange())
        // セッション有効中は新しいセッションを開始できない。
        XCTAssertNil(recorder.beginSession())

        ownerBox.value = 10
        recorder.recordValueChange(
            target: EditTargetKey(ownerBox, key: "value"),
            oldValue: 0, newValue: 10,
            apply: { ownerBox.value = $0 },
            sessionToken: token)
        // 所有者でない経路の投入は破棄される（モデル側の変更は入口
        // 確認で防ぐのが契約で、ここでは記録へ混入しないことを固定
        // する: 確定後の Undo で foreignBox が巻き戻されない）。
        foreignBox.value = 5
        recorder.recordValueChange(
            target: EditTargetKey(foreignBox, key: "value"),
            oldValue: 0, newValue: 5,
            apply: { foreignBox.value = $0 })

        recorder.commitSession(token: token)
        XCTAssertTrue(recorder.coordinator.canUndo)
        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(ownerBox.value, 0)
        XCTAssertEqual(foreignBox.value, 5)

        // 終了済みセッションのトークンは、新しいセッションの所有者
        // ではない。
        let nextToken = recorder.beginSession()
        XCTAssertNotNil(nextToken)
        guard let nextToken else { return }
        XCTAssertFalse(recorder.canRecordValueChange(sessionToken: token))
        XCTAssertTrue(recorder.canRecordValueChange(sessionToken: nextToken))
        recorder.cancelSession(token: nextToken)
    }

    /// 確定・破棄はトークンが一致する場合だけ作用する。他人の
    /// トークンではセッションは閉じず、変更も巻き戻されない。
    func testCommitAndCancelRequireOwnershipToken() {
        let recorder = EditRecorder()
        let box = ValueBox()

        // 先に1つセッションを完結させ、その（失効した）トークンを
        // 「他人のトークン」として使う。
        let staleToken = recorder.beginSession()
        XCTAssertNotNil(staleToken)
        guard let staleToken else { return }
        recorder.cancelSession(token: staleToken)

        let token = recorder.beginSession()
        XCTAssertNotNil(token)
        guard let token else { return }
        box.value = 7
        recorder.recordValueChange(
            target: EditTargetKey(box, key: "value"),
            oldValue: 0, newValue: 7,
            apply: { box.value = $0 },
            sessionToken: token)

        recorder.commitSession(token: staleToken)
        XCTAssertTrue(recorder.hasActiveSession)
        XCTAssertFalse(recorder.coordinator.canUndo)
        recorder.cancelSession(token: staleToken)
        XCTAssertTrue(recorder.hasActiveSession)
        XCTAssertEqual(box.value, 7)

        // 所有者の破棄では巻き戻され、履歴には残らない。
        recorder.cancelSession(token: token)
        XCTAssertFalse(recorder.hasActiveSession)
        XCTAssertEqual(box.value, 0)
        XCTAssertFalse(recorder.coordinator.canUndo)
    }

    // MARK: - FE-R21-126-01 失効トークンと復元中の拒否

    /// セッションを確定で閉じた後、その失効トークンを提示した
    /// 書き込みは入口確認でも記録でも受理されない。トークンなしの
    /// 離散編集は従来どおり可能（過剰な拒否になっていないこと）。
    func testStaleTokenRejectedAfterCommit() {
        let recorder = EditRecorder()
        let box = ValueBox()

        let token = recorder.beginSession()
        XCTAssertNotNil(token)
        guard let token else { return }
        box.value = 10
        recorder.recordValueChange(
            target: EditTargetKey(box, key: "value"),
            oldValue: 0, newValue: 10,
            apply: { box.value = $0 },
            sessionToken: token)
        recorder.commitSession(token: token)
        XCTAssertTrue(recorder.coordinator.canUndo)

        // 失効トークンは再び編集を許可しない。
        XCTAssertFalse(recorder.canRecordValueChange(sessionToken: token))
        XCTAssertTrue(recorder.canRecordValueChange())

        // 入口をすり抜けて記録を試みても受理されない（二重の防壁）。
        // 履歴にはセッション分の1エントリだけが残る。
        box.value = 20
        recorder.recordValueChange(
            target: EditTargetKey(box, key: "value"),
            oldValue: 10, newValue: 20,
            apply: { box.value = $0 },
            sessionToken: token)
        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(box.value, 0)
        XCTAssertFalse(recorder.coordinator.canUndo)
    }

    /// セッションを破棄で閉じた場合、およびプロジェクト切り替えで
    /// 破棄された場合も、失効トークンは受理されない（切り替え後に
    /// 旧 UI から届いた遅延イベントが新しい履歴へ紛れ込まない）。
    func testStaleTokenRejectedAfterCancelAndProjectSwitchReset() {
        let recorder = EditRecorder()
        let box = ValueBox()

        let token = recorder.beginSession()
        XCTAssertNotNil(token)
        guard let token else { return }
        recorder.cancelSession(token: token)
        XCTAssertFalse(recorder.canRecordValueChange(sessionToken: token))
        box.value = 5
        recorder.recordValueChange(
            target: EditTargetKey(box, key: "value"),
            oldValue: 0, newValue: 5,
            apply: { box.value = $0 },
            sessionToken: token)
        XCTAssertFalse(recorder.coordinator.canUndo)

        let nextToken = recorder.beginSession()
        XCTAssertNotNil(nextToken)
        guard let nextToken else { return }
        box.value = 7
        recorder.recordValueChange(
            target: EditTargetKey(box, key: "value"),
            oldValue: 5, newValue: 7,
            apply: { box.value = $0 },
            sessionToken: nextToken)
        // 切り替え時の破棄で巻き戻され、履歴は消える。
        recorder.resetForProjectSwitch()
        XCTAssertEqual(box.value, 5)
        XCTAssertFalse(recorder.coordinator.canUndo)
        XCTAssertFalse(recorder.canRecordValueChange(sessionToken: nextToken))
        box.value = 9
        recorder.recordValueChange(
            target: EditTargetKey(box, key: "value"),
            oldValue: 5, newValue: 9,
            apply: { box.value = $0 },
            sessionToken: nextToken)
        XCTAssertFalse(recorder.coordinator.canUndo)
    }

    /// 復元処理中（キャンセルの巻き戻し中）は、適用クロージャから
    /// 再入した編集が入口確認で拒否され、記録も受理されない。
    /// 巻き戻し前は `activeTransaction` が nil でも許可と判定される
    /// 不整合があった（FE-R21-126-01）。
    func testEditRejectedDuringRestoring() {
        let recorder = EditRecorder()
        let box = ValueBox()
        let reentrantBox = ValueBox()
        var gateDuringRestore: Bool?

        let token = recorder.beginSession()
        XCTAssertNotNil(token)
        guard let token else { return }
        box.value = 10
        recorder.recordValueChange(
            target: EditTargetKey(box, key: "value"),
            oldValue: 0, newValue: 10,
            apply: { value in
                box.value = value
                guard value == 0 else { return }
                // 巻き戻し中の再入。入口確認の結果を捕捉し、記録も
                // 試みる（どちらも拒否されることが契約）。
                gateDuringRestore = recorder.canRecordValueChange()
                reentrantBox.value = 99
                recorder.recordValueChange(
                    target: EditTargetKey(reentrantBox, key: "value"),
                    oldValue: 0, newValue: 99,
                    apply: { reentrantBox.value = $0 })
            },
            sessionToken: token)

        recorder.cancelSession(token: token)
        XCTAssertEqual(gateDuringRestore, false)
        XCTAssertEqual(box.value, 0)
        // 再入した変更は履歴に残らない（Undo で巻き戻せない）。
        XCTAssertFalse(recorder.coordinator.canUndo)
        XCTAssertEqual(reentrantBox.value, 99)
        // 復元が終われば通常の離散編集は再び可能。
        XCTAssertTrue(recorder.canRecordValueChange())
    }
}
