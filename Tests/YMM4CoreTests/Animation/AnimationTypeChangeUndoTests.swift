import XCTest
@testable import YMM4Core

/// FE-R23-127-01: 種別変更の Undo/Redo で変更前の値列が完全復元
/// されることの回帰テスト。
///
/// 種別変更（`Animation.changeAnimationType`）は値列を組み替える
/// 不可逆な操作であるため、種別だけの記録では Undo で値列が
/// 復元できない（例: 直線移動 [0, 50, 100] →「なし」[0] → Undo で
/// 種別だけ戻すと [0, 0, 0] になる）。記録は変更前後の状態
/// （種別＋値列、`Animation.RecordedState`）を一体として保持し、
/// 適用時は変換を再実行せず記録した状態をそのまま書き戻す。
/// ここではアプリ層（AnimationTypeMenu）と同じ記録手順を Core の
/// 記述子＋ `EditRecorder` で再現し、往復を固定する。
final class AnimationTypeChangeUndoTests: XCTestCase {

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
            target: EditTargetKey(box, key: "Test#type")
        )
    }

    private func values(of animation: Animation) -> [Double] {
        animation.values.map(\.value)
    }

    /// アプリ層の種別メニューと同じ手順: 入口確認 → 変更前の状態を
    /// 捕捉 → 記述子経由で種別変更 → 変更前後の状態を一体で記録。
    private func changeType(_ fixture: Fixture, to type: AnimationType) {
        XCTAssertTrue(fixture.recorder.canRecordValueChange())
        let oldState = fixture.descriptor.animationValue!.recordedState
        XCTAssertTrue(fixture.descriptor.setAnimationType(type))
        let newState = fixture.descriptor.animationValue!.recordedState
        fixture.recorder.recordValueChange(
            target: fixture.target,
            oldValue: oldState, newValue: newState,
            apply: { fixture.descriptor.restoreAnimationRecordedState($0) })
    }

    /// キーフレーム対応型 [0, 50, 100] → 定数 → Undo/Redo。
    /// Undo で [0, 50, 100] が完全復元されること。復元が変換の
    /// 再実行であれば、定数 [0] から直線移動へ組み替えて
    /// [0, 0, 0] になるため、この完全一致自体が「記録した状態の
    /// 書き戻し」であることの証明になる。
    func testKeyFrameSupportedToNoneUndoRestoresOriginalValues() {
        let fixture = makeFixture(Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(50), AnimationValue(100)],
            keyFrames: KeyFrames(frames: [10]), length: 20, videoFPS: 30
        ))
        changeType(fixture, to: .none)
        XCTAssertEqual(fixture.box.animation.animationType, .none)
        XCTAssertEqual(values(of: fixture.box.animation), [0])

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(fixture.box.animation.animationType, .linear)
        XCTAssertEqual(values(of: fixture.box.animation), [0, 50, 100])

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(fixture.box.animation.animationType, .none)
        XCTAssertEqual(values(of: fixture.box.animation), [0])
    }

    /// 定数 50 → ランダム移動 → Undo/Redo。
    func testNoneToRandomUndoRedoRoundTrip() {
        let fixture = makeFixture(Animation(
            defaultValue: 100, minValue: 0, maxValue: 1000,
            animationType: .none, values: [AnimationValue(50)],
            length: 20, videoFPS: 30
        ))
        changeType(fixture, to: .random)
        XCTAssertEqual(fixture.box.animation.animationType, .random)
        XCTAssertEqual(values(of: fixture.box.animation), [50, 50])

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(fixture.box.animation.animationType, .none)
        XCTAssertEqual(values(of: fixture.box.animation), [50])

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(fixture.box.animation.animationType, .random)
        XCTAssertEqual(values(of: fixture.box.animation), [50, 50])
    }

    /// 移動量指定 → キーフレーム対応型 → Undo/Redo。
    /// 移動量 0.3・長さ 11 は、組み替え後の値列から移動量を
    /// 再導出すると浮動小数の丸めで 0.3 へ戻らない組合せであり
    /// （再導出値は 0.29999999999999993）、Undo 後の完全一致が
    /// 「記録した状態の書き戻し」であることの証明になる。
    func testMovementAmountToKeyFrameSupportedUndoRestoresAmountExactly() {
        let fixture = makeFixture(Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .movementAmount,
            values: [AnimationValue(0), AnimationValue(0.3)],
            keyFrames: KeyFrames(frames: [3, 7]), length: 11, videoFPS: 30
        ))
        changeType(fixture, to: .linear)
        XCTAssertEqual(fixture.box.animation.animationType, .linear)
        XCTAssertEqual(fixture.box.animation.values.count, 4)
        let convertedValues = values(of: fixture.box.animation)

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(fixture.box.animation.animationType, .movementAmount)
        XCTAssertEqual(values(of: fixture.box.animation), [0, 0.3])

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(fixture.box.animation.animationType, .linear)
        XCTAssertEqual(values(of: fixture.box.animation), convertedValues)
    }

    /// 復元経路は記録した状態をそのまま書き込む（正規化しない）。
    /// 有効な値の数と異なる本数の値列もそのまま戻ること。
    func testRestoreRecordedStateWritesStateVerbatim() {
        let fixture = makeFixture(Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .random,
            values: [AnimationValue(10), AnimationValue(90)],
            length: 20, videoFPS: 30
        ))
        let state = Animation.RecordedState(
            animationType: .linear,
            values: [AnimationValue(1), AnimationValue(2), AnimationValue(3)])
        XCTAssertTrue(fixture.descriptor.restoreAnimationRecordedState(state))
        XCTAssertEqual(fixture.box.animation.animationType, .linear)
        XCTAssertEqual(values(of: fixture.box.animation), [1, 2, 3])
    }
}
