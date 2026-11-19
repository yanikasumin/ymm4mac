import XCTest
@testable import YMM4Core

final class AnimationTests: XCTestCase {
    /// キーフレーム1つ（位置10）を持つ直線移動アニメーション。
    /// 値: 開始 0、キーフレーム位置で 50、終了 100。長さ 20、基準 30fps。
    private func makeLinearAnimation() -> Animation {
        Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(50), AnimationValue(100)],
            keyFrames: KeyFrames(frames: [10]),
            length: 20, videoFPS: 30
        )
    }

    func testConstantValue() {
        let animation = Animation(
            defaultValue: 42, minValue: 0, maxValue: 100,
            animationType: .none, values: [AnimationValue(42)]
        )
        XCTAssertEqual(animation.value(atFrame: 0, length: 100, fps: 30), 42)
        XCTAssertEqual(animation.value(atFrame: 50, length: 100, fps: 30), 42)
        XCTAssertEqual(animation.value(atFrame: 100, length: 100, fps: 30), 42)
    }

    func testFinalClampApplies() {
        let animation = Animation(
            defaultValue: 0, minValue: 0, maxValue: 100,
            animationType: .none, values: [AnimationValue(150)]
        )
        XCTAssertEqual(animation.value(atFrame: 0, length: 10, fps: 30), 100)
    }

    func testLoopRemainder() {
        let animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000, loop: 360,
            animationType: .none, values: [AnimationValue(370)]
        )
        XCTAssertEqual(animation.value(atFrame: 0, length: 10, fps: 30), 10)
    }

    func testMovementAmount() {
        // 開始 10、1フレームあたり 2 ずつ増加。30 フレーム目で 10 + 2×30 = 70
        let animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .movementAmount,
            values: [AnimationValue(10), AnimationValue(2)]
        )
        XCTAssertEqual(animation.value(atFrame: 0, length: 100, fps: 30), 10)
        XCTAssertEqual(animation.value(atFrame: 30, length: 100, fps: 30), 70)
        XCTAssertEqual(animation.value(atFrame: 100, length: 100, fps: 30), 210)
    }

    func testLinearKeyframeInterpolation() {
        let animation = makeLinearAnimation()
        XCTAssertEqual(animation.value(atFrame: 0, length: 20, fps: 30), 0)
        XCTAssertEqual(animation.value(atFrame: 5, length: 20, fps: 30), 25)
        XCTAssertEqual(animation.value(atFrame: 10, length: 20, fps: 30), 50)
        XCTAssertEqual(animation.value(atFrame: 15, length: 20, fps: 30), 75)
        XCTAssertEqual(animation.value(atFrame: 20, length: 20, fps: 30), 100)
    }

    func testInstantKeepsSegmentStartValue() {
        var animation = makeLinearAnimation()
        animation.animationType = .instant
        XCTAssertEqual(animation.value(atFrame: 5, length: 20, fps: 30), 0)
        XCTAssertEqual(animation.value(atFrame: 9, length: 20, fps: 30), 0)
        XCTAssertEqual(animation.value(atFrame: 10, length: 20, fps: 30), 50)
        XCTAssertEqual(animation.value(atFrame: 19, length: 20, fps: 30), 50)
        // 本家では瞬間移動のイージング率は常に 0 のため、最終フレームでも
        // 最後の区間の開始値のままになる（終了値にはならない）
        XCTAssertEqual(animation.value(atFrame: 20, length: 20, fps: 30), 50)
    }

    func testKeyframePositionsAreConvertedByFPS() {
        // 基準 30fps で位置 10 のキーフレームは、60fps 評価では位置 20 になる
        let animation = makeLinearAnimation()
        XCTAssertEqual(animation.value(atFrame: 10, length: 40, fps: 60), 25)
        XCTAssertEqual(animation.value(atFrame: 20, length: 40, fps: 60), 50)
        XCTAssertEqual(animation.value(atFrame: 30, length: 40, fps: 60), 75)
    }

    func testRepetitiveParityWithoutSpan() {
        // 本家は (int)(rate * totalFrame) が奇数のとき開始値、偶数のとき
        // 終了値を返す（直観とは逆の対応。ANIMATION-FORMULAS.md §5）
        let animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .repetitive,
            values: [AnimationValue(10), AnimationValue(20)]
        )
        XCTAssertEqual(animation.value(atFrame: 0, length: 10, fps: 30), 20)
        XCTAssertEqual(animation.value(atFrame: 1, length: 10, fps: 30), 10)
        XCTAssertEqual(animation.value(atFrame: 2, length: 10, fps: 30), 20)
        XCTAssertEqual(animation.value(atFrame: 3, length: 10, fps: 30), 10)
    }

    func testActiveValueCount() {
        let none = Animation(defaultValue: 0, minValue: 0, maxValue: 100, animationType: .none)
        XCTAssertEqual(none.activeValueCount, 1)

        let amount = Animation(defaultValue: 0, minValue: 0, maxValue: 100, animationType: .movementAmount)
        XCTAssertEqual(amount.activeValueCount, 2)

        var keyframed = makeLinearAnimation()
        XCTAssertEqual(keyframed.activeValueCount, 3) // キーフレーム1 + 2
        keyframed.setKeyFrames(KeyFrames(frames: [5, 10]))
        XCTAssertEqual(keyframed.activeValueCount, 4)
    }

    // MARK: - キーフレーム連動

    func testInsertKeyFrameInsertsEvaluatedValue() {
        var animation = makeLinearAnimation()
        let valueBeforeAt7 = animation.value(atFrame: 7, length: 20, fps: 30)

        XCTAssertTrue(animation.insertKeyFrame(at: 5))

        XCTAssertEqual(animation.keyFrames.frames, [5, 10])
        // 位置5での現在値 25 が挿入される
        XCTAssertEqual(animation.values.map(\.value), [0, 25, 50, 100])
        // 挿入前後で曲線は変わらない
        XCTAssertEqual(animation.value(atFrame: 5, length: 20, fps: 30), 25)
        XCTAssertEqual(animation.value(atFrame: 7, length: 20, fps: 30), valueBeforeAt7)
    }

    func testInsertKeyFrameDoesNotDuplicate() {
        var animation = makeLinearAnimation()
        XCTAssertFalse(animation.insertKeyFrame(at: 10))
        XCTAssertEqual(animation.values.map(\.value), [0, 50, 100])
    }

    func testInsertKeyFrameDoesNotTouchValuesOfUnsupportedType() {
        // キーフレーム非対応の型では、位置だけが増えて values は連動しない
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .repetitive,
            values: [AnimationValue(0), AnimationValue(100)],
            length: 20, videoFPS: 30
        )
        XCTAssertTrue(animation.insertKeyFrame(at: 5))
        XCTAssertEqual(animation.keyFrames.frames, [5])
        XCTAssertEqual(animation.values.map(\.value), [0, 100])
    }

    func testRemoveKeyFrameRemovesCorrespondingValue() {
        var animation = makeLinearAnimation()
        XCTAssertTrue(animation.insertKeyFrame(at: 5))
        XCTAssertTrue(animation.removeKeyFrame(at: 5))
        XCTAssertEqual(animation.keyFrames.frames, [10])
        XCTAssertEqual(animation.values.map(\.value), [0, 50, 100])
        XCTAssertFalse(animation.removeKeyFrame(at: 5))
    }

    // MARK: - KeyFrames

    func testKeyFramesDistribute() {
        var keyFrames = KeyFrames(frames: [3, 7])
        keyFrames.distribute(length: 30)
        // i * 30 / (2 + 1): 10, 20
        XCTAssertEqual(keyFrames.frames, [10, 20])
    }

    func testKeyFramesStaySortedAndUnique() {
        let keyFrames = KeyFrames(frames: [10, 5, 10, 1])
        XCTAssertEqual(keyFrames.frames, [1, 5, 10])
    }

    // MARK: - 値インデックス指定の書き換え（FE-R13-003）

    func testSetValueAtIndexWritesMovementAmountSecondValue() {
        // 移動量指定の第2値（移動量）は定義範囲 [0, 100] の外の負値も
        // 対称範囲では書ける（本家は第2値の Min/Max を対称置換する）。
        var animation = Animation(
            defaultValue: 0, minValue: 0, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(10), AnimationValue(5)]
        )
        animation.setValue(-30, atValueIndex: 1, clampRange: -100...100)
        XCTAssertEqual(animation.values.map(\.value), [10, -30])
        XCTAssertEqual(animation.animationType, .movementAmount)
    }

    func testSetValueAtIndexMaterializesShortValueList() {
        // 値列が [50] だけの状態で第2値を書くと、手前は代用規則
        // （末尾の値）で実体化してから対象位置だけが変わる。
        var animation = Animation(
            defaultValue: 100, minValue: 0, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(50)]
        )
        animation.setValue(3, atValueIndex: 1, clampRange: -100...100)
        XCTAssertEqual(animation.values.map(\.value), [50, 3])
    }

    func testSetValueAtIndexClampsToGivenRange() {
        var animation = Animation(
            defaultValue: 0, minValue: 0, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(0), AnimationValue(0)]
        )
        animation.setValue(150, atValueIndex: 1, clampRange: -100...100)
        XCTAssertEqual(animation.values.map(\.value), [0, 100])
        animation.setValue(-150, atValueIndex: 1, clampRange: -100...100)
        XCTAssertEqual(animation.values.map(\.value), [0, -100])
    }

    func testSetValueAtIndexIgnoresNegativeIndex() {
        var animation = Animation(
            defaultValue: 0, minValue: 0, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(0), AnimationValue(0)]
        )
        animation.setValue(9, atValueIndex: -1, clampRange: -100...100)
        XCTAssertEqual(animation.values.map(\.value), [0, 0])
    }
}
