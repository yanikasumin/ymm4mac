import XCTest
@testable import YMM4Core

/// FE-R25-128-01: 移動量指定の第2値（移動量）の編集が Undo へ
/// 接続されていることの回帰テスト。
///
/// 第2値の書き込み（`PropertyDescriptor.setAnimationValue(_:
/// atValueIndex:clampRange:)`）は、値列が対象位置まで実体化して
/// いない場合に読み取り側の代用規則で実体化してから書き換える
/// ため、編集には「値の変更」と「値列の個数の変化」が混ざり
/// うる。第2値だけの記録では Undo で実体化前の個数へ戻せない
/// ため、記録は種別変更（FE-R23-127-01）と同じく変更前後の状態
/// （種別＋値列、`Animation.RecordedState`）を一体で保持し、
/// 適用時はそのまま書き戻す。ここではアプリ層
/// （`AnimationRowView` の第2値行）と同じ記録手順を Core の
/// 記述子＋ `EditRecorder` で再現し、往復を固定する。
final class AnimationMovementValueUndoTests: XCTestCase {

    /// 記述子の読み書き先（アイテム内プロパティの代わり）。
    private final class AnimationBox {
        var animation: Animation

        init(_ animation: Animation) {
            self.animation = animation
        }
    }

    private struct Fixture {
        let box: AnimationBox
        let descriptor: PropertyDescriptor
        let recorder: EditRecorder
        let target: EditTargetKey
    }

    private func makeFixture(_ animation: Animation) -> Fixture {
        let box = AnimationBox(animation)
        let descriptor = PropertyDescriptor.animation(
            id: "Test", displayName: "Test", group: "Test",
            get: { box.animation }, set: { box.animation = $0 }
        )
        return Fixture(
            box: box,
            descriptor: descriptor,
            recorder: EditRecorder(),
            target: EditTargetKey(box, key: "Test#movement")
        )
    }

    private func values(of animation: Animation) -> [Double] {
        animation.values.map(\.value)
    }

    /// アプリ層の第2値の書き込みと同じ手順: 入口確認 → 変更前の
    /// 状態を捕捉 → 記述子経由で第2値を書き換え（クランプ範囲は
    /// アプリ層と同じく絶対制限の対称範囲）→ 変更前後の状態を
    /// 一体で記録する。`sessionToken` はスライダのドラッグ
    /// セッションを再現する場合にだけ渡す。
    private func writeMovementValue(
        _ fixture: Fixture, _ value: Double,
        sessionToken: EditSessionToken? = nil
    ) {
        XCTAssertTrue(
            fixture.recorder.canRecordValueChange(sessionToken: sessionToken))
        let animation = fixture.descriptor.animationValue!
        let oldState = animation.recordedState
        let radius = max(abs(animation.minValue), abs(animation.maxValue))
        XCTAssertTrue(fixture.descriptor.setAnimationValue(
            value, atValueIndex: 1, clampRange: (-radius)...radius))
        let newState = fixture.descriptor.animationValue!.recordedState
        fixture.recorder.recordValueChange(
            target: fixture.target,
            oldValue: oldState, newValue: newState,
            apply: { fixture.descriptor.restoreAnimationRecordedState($0) },
            sessionToken: sessionToken)
    }

    /// [10, 5] → 第2値を -30 へ → Undo → Redo の往復。
    func testMovementValueUndoRedoRoundTrip() {
        let fixture = makeFixture(Animation(
            defaultValue: 0, minValue: -100, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(10), AnimationValue(5)],
            length: 20, videoFPS: 30
        ))
        writeMovementValue(fixture, -30)
        XCTAssertEqual(values(of: fixture.box.animation), [10, -30])

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(fixture.box.animation.animationType, .movementAmount)
        XCTAssertEqual(values(of: fixture.box.animation), [10, 5])

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(values(of: fixture.box.animation), [10, -30])
    }

    /// 短い値列 [50] から第2値を実体化して書いた場合、Undo で
    /// 値列の個数まで含めて実体化前の形（[50] の1個）へ戻ること。
    func testShortValueListMaterializationRestoredByUndo() {
        let fixture = makeFixture(Animation(
            defaultValue: 0, minValue: -100, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(50)],
            length: 20, videoFPS: 30
        ))
        writeMovementValue(fixture, 3)
        // 実体化: 第2値の代用値（末尾値 50）が実値として入り、
        // 対象位置が 3 になる。
        XCTAssertEqual(values(of: fixture.box.animation), [50, 3])

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(values(of: fixture.box.animation), [50])

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(values(of: fixture.box.animation), [50, 3])
    }

    /// スライダのドラッグ（セッション中の逐次書き込み）は履歴
    /// 1エントリへまとまり、Undo でドラッグ開始前の状態へ戻る
    /// こと（第1値のセッションとは独立した第2値専用のセッション
    /// を使う想定の再現）。
    func testMovementSliderSessionCoalescesIntoOneHistoryEntry() {
        let fixture = makeFixture(Animation(
            defaultValue: 0, minValue: -100, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(10), AnimationValue(5)],
            length: 20, videoFPS: 30
        ))
        let token = fixture.recorder.beginSession()
        XCTAssertNotNil(token)
        writeMovementValue(fixture, 8, sessionToken: token)
        writeMovementValue(fixture, -12, sessionToken: token)
        writeMovementValue(fixture, -30, sessionToken: token)
        fixture.recorder.commitSession(token: token!)
        XCTAssertEqual(values(of: fixture.box.animation), [10, -30])
        XCTAssertEqual(fixture.recorder.coordinator.history.undoCount, 1)

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(values(of: fixture.box.animation), [10, 5])

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(values(of: fixture.box.animation), [10, -30])
    }

    /// 他人のセッションが有効な間は、第2値の離散編集（テキスト
    /// 確定）の入口確認が拒否されること（アプリ層はこの判定で
    /// モデル変更自体を行わない）。
    func testMovementDiscreteWriteBlockedWhileForeignSessionActive() {
        let fixture = makeFixture(Animation(
            defaultValue: 0, minValue: -100, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(10), AnimationValue(5)],
            length: 20, videoFPS: 30
        ))
        let foreignToken = fixture.recorder.beginSession()
        XCTAssertNotNil(foreignToken)
        XCTAssertFalse(fixture.recorder.canRecordValueChange())
        fixture.recorder.cancelSession(token: foreignToken!)
        XCTAssertTrue(fixture.recorder.canRecordValueChange())
        // 拒否の間は書き込み手順へ進まないため、値も履歴も
        // 変わっていない。
        XCTAssertEqual(values(of: fixture.box.animation), [10, 5])
        XCTAssertFalse(fixture.recorder.coordinator.canUndo)
    }
}
