import XCTest
@testable import YMM4Core

/// FE-R14-001: 種別変更＋値列正規化（`Animation.changeAnimationType`）の
/// 回帰テスト。各テストは本家 `Animation.EndEditAsync`
/// （Animation.cs:605–686）の分岐に対応する。本家は編集終了時に
/// 旧種別→新種別の組合せで値列を組み替える。Mac には編集セッション
/// 境界が無いため、種別変更そのものが正規化を含む単一操作である。
final class AnimationTypeChangeTests: XCTestCase {
    private func values(of animation: Animation) -> [Double] {
        animation.values.map(\.value)
    }

    // MARK: - 旧種別「なし」からの遷移（EndEditAsync: 旧種別 == なし）

    /// 監査 Round 14 の具体症状: 既定値 100 の拡大率を定数 50 にした
    /// 状態でランダム移動へ切り替えると、本家は終端値も 50 に
    /// 正規化する（先頭の値の複製で補う）。未実体化のまま既定値 100 で
    /// 評価される 50→100 の化けが起きないこと。
    func testNoneToRandomFillsEndValueWithFirstValue() {
        var animation = Animation(
            defaultValue: 100, minValue: 0, maxValue: 1000,
            animationType: .none, values: [AnimationValue(50)]
        )
        animation.changeAnimationType(to: .random)
        XCTAssertEqual(animation.animationType, .random)
        XCTAssertEqual(values(of: animation), [50, 50])
        // 評価しても全区間 50（開始値 = 終了値のため乱数に依らない）
        XCTAssertEqual(animation.value(atFrame: 0, length: 100, fps: 30), 50)
        XCTAssertEqual(animation.value(atFrame: 100, length: 100, fps: 30), 50)
    }

    /// 繰り返し移動への遷移も同じ規則（先頭の値の複製）。
    func testNoneToRepetitiveFillsEndValueWithFirstValue() {
        var animation = Animation(
            defaultValue: 100, minValue: 0, maxValue: 1000,
            animationType: .none, values: [AnimationValue(50)]
        )
        animation.changeAnimationType(to: .repetitive)
        XCTAssertEqual(values(of: animation), [50, 50])
    }

    /// 移動量指定へは移動量 0 が補われる（先頭の値の複製ではない）。
    func testNoneToMovementAmountAppendsZeroAmount() {
        var animation = Animation(
            defaultValue: 100, minValue: 0, maxValue: 1000,
            animationType: .none, values: [AnimationValue(50)]
        )
        animation.changeAnimationType(to: .movementAmount)
        XCTAssertEqual(values(of: animation), [50, 0])
    }

    /// キーフレーム対応型へは、有効な値の数（キーフレーム数 + 2）まで
    /// 先頭の値の複製で補われる。
    func testNoneToKeyFrameSupportedFillsAllValuesWithFirstValue() {
        var animation = Animation(
            defaultValue: 100, minValue: 0, maxValue: 1000,
            animationType: .none, values: [AnimationValue(50)],
            keyFrames: KeyFrames(frames: [10]), length: 20, videoFPS: 30
        )
        animation.changeAnimationType(to: .linear)
        XCTAssertEqual(values(of: animation), [50, 50, 50])
    }

    // MARK: - 「なし」への遷移（EndEditAsync: 新種別 == なし）

    /// 先頭の値だけが残る。
    func testKeyFrameSupportedToNoneKeepsOnlyFirstValue() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(50), AnimationValue(100)],
            keyFrames: KeyFrames(frames: [10]), length: 20, videoFPS: 30
        )
        animation.changeAnimationType(to: .none)
        XCTAssertEqual(values(of: animation), [0])
    }

    // MARK: - 旧種別「移動量指定」からの遷移

    /// 非対応型へ: 終端値 = 開始値 + 移動量 × 長さ。
    func testMovementAmountToRandomConvertsEndValue() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .movementAmount,
            values: [AnimationValue(10), AnimationValue(2)],
            length: 30, videoFPS: 30
        )
        animation.changeAnimationType(to: .random)
        XCTAssertEqual(values(of: animation), [10, 70])
    }

    /// キーフレーム対応型へ: 開始値→終端値の間を等分位置へ割り付ける。
    func testMovementAmountToKeyFrameSupportedDistributesLinearly() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .movementAmount,
            values: [AnimationValue(10), AnimationValue(2)],
            keyFrames: KeyFrames(frames: [15]), length: 30, videoFPS: 30
        )
        animation.changeAnimationType(to: .linear)
        XCTAssertEqual(values(of: animation), [10, 40, 70])
    }

    // MARK: - 旧種別がキーフレーム非対応（ランダム移動・反復移動）からの遷移

    /// 移動量指定へ: 移動量 =（終了値 − 開始値）/ 長さ。
    func testRandomToMovementAmountConvertsAmount() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .random,
            values: [AnimationValue(0), AnimationValue(100)],
            length: 50, videoFPS: 30
        )
        animation.changeAnimationType(to: .movementAmount)
        XCTAssertEqual(values(of: animation), [0, 2])
    }

    /// キーフレーム対応型へ（繰り返し移動から）: 開始値→終了値を
    /// 等分位置へ線形に割り付ける。
    func testRepetitiveToKeyFrameSupportedDistributesLinearly() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .repetitive,
            values: [AnimationValue(0), AnimationValue(100)],
            keyFrames: KeyFrames(frames: [10]), length: 20, videoFPS: 30
        )
        animation.changeAnimationType(to: .linear)
        XCTAssertEqual(values(of: animation), [0, 50, 100])
    }

    /// 非対応同士（ランダム ⇔ 反復）は本家でも値列を変えない。
    func testRandomToRepetitiveKeepsValues() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .random,
            values: [AnimationValue(10), AnimationValue(90)],
            length: 20, videoFPS: 30
        )
        animation.changeAnimationType(to: .repetitive)
        XCTAssertEqual(values(of: animation), [10, 90])
    }

    // MARK: - 旧種別がキーフレーム対応型からの遷移

    /// 移動量指定へ: 移動量 =（末尾の値 − 先頭の値）/ 長さ。
    /// 末尾は値列全体の最後（キーフレーム位置の値ではない）。
    func testKeyFrameSupportedToMovementAmountUsesLastValue() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(50), AnimationValue(100)],
            keyFrames: KeyFrames(frames: [10]), length: 20, videoFPS: 30
        )
        animation.changeAnimationType(to: .movementAmount)
        XCTAssertEqual(values(of: animation), [0, 5])
    }

    /// 非対応型へ: 終端値 = 末尾の値。
    func testKeyFrameSupportedToRandomUsesLastValueAsEndValue() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(50), AnimationValue(100)],
            keyFrames: KeyFrames(frames: [10]), length: 20, videoFPS: 30
        )
        animation.changeAnimationType(to: .random)
        XCTAssertEqual(values(of: animation), [0, 100])
    }

    /// 対応同士は本家でも値列を変えない（キーフレーム数が同じため
    /// 有効な値の数も変わらない）。
    func testKeyFrameSupportedToKeyFrameSupportedKeepsValues() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(50), AnimationValue(100)],
            keyFrames: KeyFrames(frames: [10]), length: 20, videoFPS: 30
        )
        animation.changeAnimationType(to: .instant)
        XCTAssertEqual(values(of: animation), [0, 50, 100])
    }

    // MARK: - その他

    /// 同一種別への変更は値列に触らない。
    func testSameTypeChangeIsNoOp() {
        var animation = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .random,
            values: [AnimationValue(10), AnimationValue(90)],
            length: 20, videoFPS: 30
        )
        animation.changeAnimationType(to: .random)
        XCTAssertEqual(values(of: animation), [10, 90])
    }

    // MARK: - 空の値列への種付け（FE-R23-127-02）

    /// 値列が空の異常データでも、「なし」への遷移（先頭だけ残す
    /// 分岐）で既定値が実体化される。入口の種付けが無いと空の
    /// まま残った。
    func testEmptyValuesSeededWithDefaultValueOnChangeToNone() {
        var animation = Animation(
            defaultValue: 100, minValue: 0, maxValue: 1000,
            animationType: .linear, values: []
        )
        animation.changeAnimationType(to: .none)
        XCTAssertEqual(values(of: animation), [100])
    }

    /// 値列を変えない分岐（ランダム ⇔ 反復）でも、入口の種付けに
    /// より空のままにはならない。
    func testEmptyValuesSeededWithDefaultValueOnRandomToRepetitive() {
        var animation = Animation(
            defaultValue: 42, minValue: 0, maxValue: 1000,
            animationType: .random, values: []
        )
        animation.changeAnimationType(to: .repetitive)
        XCTAssertEqual(values(of: animation), [42])
    }

    /// 旧種別「なし」からの遷移でも種付けが効く（既定値＋移動量 0）。
    func testEmptyValuesSeededWithDefaultValueOnNoneToMovementAmount() {
        var animation = Animation(
            defaultValue: 42, minValue: 0, maxValue: 1000,
            animationType: .none, values: []
        )
        animation.changeAnimationType(to: .movementAmount)
        XCTAssertEqual(values(of: animation), [42, 0])
    }

    /// 記述子の種別セッターは必ずこの操作を通る（アプリ層の経路が
    /// 迂回しないことの固定）。定数 50 → ランダム移動で終端値も 50。
    func testDescriptorSetTypeNormalizesValues() {
        var stored = Animation(
            defaultValue: 100, minValue: 0, maxValue: 1000,
            animationType: .none, values: [AnimationValue(50)],
            length: 20, videoFPS: 30
        )
        let descriptor = PropertyDescriptor.animation(
            id: "Test", displayName: "Test", group: "Test",
            get: { stored }, set: { stored = $0 }
        )
        XCTAssertTrue(descriptor.setAnimationType(.random))
        XCTAssertEqual(stored.animationType, .random)
        XCTAssertEqual(values(of: stored), [50, 50])
    }
}
