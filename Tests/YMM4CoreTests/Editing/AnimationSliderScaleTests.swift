import XCTest
@testable import YMM4Core

/// スライダ表示範囲の計算（FE-R1-042）の検証。
///
/// 期待値は本家 `TextBoxSlider.ChangeMinMax` の式と
/// `AnimationSliderViewModel` の MinScale 伝播・対称置換を手元で
/// 計算したもので、実装の出力と突き合わせる独立検証として置く。
/// 受け入れ条件 R2-A01〜A04 に対応する観点をテスト名に明記する。
final class AnimationSliderScaleTests: XCTestCase {

    private func spec(
        _ defaultMin: Double, _ defaultMax: Double, format: String = "F1"
    ) -> AnimationSliderSpec {
        AnimationSliderSpec(
            defaultMin: defaultMin, defaultMax: defaultMax,
            stringFormat: format, unit: "")
    }

    // MARK: - Scale の式（端点補正を含む）

    func testScaleWithinDefaultRangeIsOne() {
        // 基準範囲 -100..100、絶対制限 -10000..10000。
        let s = spec(-100, 100)
        for value in [0.0, 50, -50, 99.9, -99.9] {
            XCTAssertEqual(
                AnimationSliderScale.scale(
                    value: value, defaultMin: s.defaultMin, defaultMax: s.defaultMax,
                    absoluteMin: -10000, absoluteMax: 10000),
                1, "value=\(value)")
        }
    }

    func testScaleDoublesAtDefaultEndpointWhenAbsoluteRangeIsWider() {
        // 値がちょうど基準端点に一致するとスケールは 2 になる
        // （端点補正は絶対制限の端点と一致する場合だけ効く）。
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 100, defaultMin: -100, defaultMax: 100,
                absoluteMin: -10000, absoluteMax: 10000), 2)
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: -100, defaultMin: -100, defaultMax: 100,
                absoluteMin: -10000, absoluteMax: 10000), 2)
    }

    func testScaleEndpointCorrectionWhenValueSitsAtAbsoluteLimit() {
        // 値 == 基準端点 × (スケール-1) == 絶対制限の端点 なら 1 引く。
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 100, defaultMin: -100, defaultMax: 100,
                absoluteMin: -100, absoluteMax: 100), 1)
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: -100, defaultMin: -100, defaultMax: 100,
                absoluteMin: -100, absoluteMax: 100), 1)
        // スケール 4 の局面でも補正は (スケール-1) 倍で判定する:
        // 300 = 100 × 3 かつ絶対上限も 300 なら 4 → 3（2の冪でなくなる）。
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 300, defaultMin: -100, defaultMax: 100,
                absoluteMin: -10000, absoluteMax: 300), 3)
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: -300, defaultMin: -100, defaultMax: 100,
                absoluteMin: -300, absoluteMax: 10000), 3)
        // 絶対制限が広ければ補正は効かず 4 のまま。
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 300, defaultMin: -100, defaultMax: 100,
                absoluteMin: -10000, absoluteMax: 10000), 4)
    }

    func testScaleGrowsByPowersOfTwo() {
        // floor(値/基準端点) + 1 を 2 の冪へ切り上げる。
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 150, defaultMin: -100, defaultMax: 100,
                absoluteMin: -10000, absoluteMax: 10000), 2)
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 200, defaultMin: -100, defaultMax: 100,
                absoluteMin: -10000, absoluteMax: 10000), 4)
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 250, defaultMin: -100, defaultMax: 100,
                absoluteMin: -10000, absoluteMax: 10000), 4)
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: -200, defaultMin: -100, defaultMax: 100,
                absoluteMin: -10000, absoluteMax: 10000), 4)
    }

    func testScaleWithNonNegativeDefaultRange() {
        // DefaultMin >= 0 では下限側の項は 0 固定（本家の条件分岐）。
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 50, defaultMin: 0, defaultMax: 100,
                absoluteMin: 0, absoluteMax: 10000), 1)
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 100, defaultMin: 0, defaultMax: 100,
                absoluteMin: 0, absoluteMax: 10000), 2)
        // 基準範囲 0..1・絶対制限も 0..1 で値 1 は端点補正で 1。
        XCTAssertEqual(
            AnimationSliderScale.scale(
                value: 1, defaultMin: 0, defaultMax: 1,
                absoluteMin: 0, absoluteMax: 1), 1)
    }

    // MARK: - CurrentMin / CurrentMax

    func testCurrentRangeScalesAndClampsToAbsoluteLimits() {
        var r = AnimationSliderScale.currentRange(
            defaultMin: -100, defaultMax: 100,
            absoluteMin: -10000, absoluteMax: 10000, adjustedScale: 1)
        XCTAssertEqual(r.min, -100)
        XCTAssertEqual(r.max, 100)
        r = AnimationSliderScale.currentRange(
            defaultMin: -100, defaultMax: 100,
            absoluteMin: -10000, absoluteMax: 10000, adjustedScale: 2)
        XCTAssertEqual(r.min, -200)
        XCTAssertEqual(r.max, 200)
        // 絶対制限で頭打ち。
        r = AnimationSliderScale.currentRange(
            defaultMin: -100, defaultMax: 100,
            absoluteMin: -250, absoluteMax: 250, adjustedScale: 4)
        XCTAssertEqual(r.min, -250)
        XCTAssertEqual(r.max, 250)
    }

    func testCurrentRangeNeverShrinksBelowDefaultRange() {
        // 基準端点が正の側では、スケール倍しても基準範囲より狭くならない。
        let r = AnimationSliderScale.currentRange(
            defaultMin: 10, defaultMax: 100,
            absoluteMin: 0, absoluteMax: 10000, adjustedScale: 2)
        XCTAssertEqual(r.min, 10)
        XCTAssertEqual(r.max, 200)
    }

    // MARK: - R2-A01: 基準範囲内ではスライダ範囲 = 基準範囲

    func testSliderRangeEqualsDefaultRangeWhenValuesWithin() {
        let r = AnimationSliderScale.sliderRange(
            values: [30], valueIndex: 0, animationType: .none,
            spec: spec(0, 100), absoluteMin: 0, absoluteMax: 10000)
        XCTAssertEqual(r.min, 0)
        XCTAssertEqual(r.max, 100)
    }

    // MARK: - R2-A02: 範囲外の値ではスケールが拡張される

    func testSliderRangeExpandsForOutOfRangeValue() {
        var r = AnimationSliderScale.sliderRange(
            values: [250], valueIndex: 0, animationType: .none,
            spec: spec(0, 100), absoluteMin: 0, absoluteMax: 10000)
        XCTAssertEqual(r.min, 0)
        XCTAssertEqual(r.max, 400)
        r = AnimationSliderScale.sliderRange(
            values: [-250], valueIndex: 0, animationType: .none,
            spec: spec(-100, 0), absoluteMin: -10000, absoluteMax: 0)
        XCTAssertEqual(r.min, -400)
        XCTAssertEqual(r.max, 0)
    }

    // MARK: - R2-A03: セグメント間でスケールを共有する

    func testSharedScaleAcrossKeyFrameSegments() {
        // キーフレーム1個 → 有効値は3個。末尾の値 500 が全体の
        // スケールを 8 へ押し上げ、先頭区間のスライダにも効く。
        let animation = Animation(
            defaultValue: 0, minValue: -10000, maxValue: 10000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(0), AnimationValue(500)],
            keyFrames: KeyFrames(frames: [10]))
        let s = spec(-100, 100)
        XCTAssertEqual(AnimationSliderScale.activeValues(of: animation), [0, 0, 500])
        for index in [0, 1, 2] {
            let r = AnimationSliderScale.sliderRange(
                for: animation, valueIndex: index, spec: s)
            XCTAssertEqual(r.min, -800, "index=\(index)")
            XCTAssertEqual(r.max, 800, "index=\(index)")
        }
    }

    func testActiveValuesReturnsOnlyExistingValues() {
        // 本家 ActiveValues（Values.Take(GetActiveValueCount())）は
        // 存在する値だけを列挙し、不足分を既定値で作らない
        // （FE-R13-002）。
        let animation = Animation(
            defaultValue: 7, minValue: 0, maxValue: 100,
            animationType: .linear, values: [AnimationValue(5)])
        XCTAssertEqual(AnimationSliderScale.activeValues(of: animation), [5])
        // 有効個数を超える分は切り詰める。
        let constant = Animation(
            defaultValue: 7, minValue: 0, maxValue: 100,
            animationType: .none,
            values: [AnimationValue(5), AnimationValue(9)])
        XCTAssertEqual(AnimationSliderScale.activeValues(of: constant), [5])
    }

    func testSharedScaleIsNotInflatedByMissingMovementAmountValue() {
        // FE-R13-002 の回帰: 既定値 100 の拡大率を定数 50 へ変更して
        // 移動量指定へ切り替えると、値列は [50] のまま保持される。
        // 存在しない第2値を既定値 100 で補うと、対称範囲（±100）の
        // 端点として共有スケールが 2 倍へ膨らんでしまう。本家の
        // 列挙では第2値は参加せず、スケールは 1 のままになる。
        let animation = Animation(
            defaultValue: 100, minValue: 0, maxValue: 10000,
            animationType: .movementAmount, values: [AnimationValue(50)])
        XCTAssertEqual(AnimationSliderScale.activeValues(of: animation), [50])
        let r = AnimationSliderScale.sliderRange(
            for: animation, valueIndex: 0, spec: spec(0, 100))
        XCTAssertEqual(r.min, 0)
        XCTAssertEqual(r.max, 100)
    }

    // MARK: - FE-R13-001: 表示値 = 編集対象値（評価値ではない）

    func testEditValueIsAnimationValueNotEvaluatedValue() {
        // 移動量指定（開始値 0、移動量 1）では、相対フレーム 600 の
        // 評価値は 600 になるが、先頭のスライダが表示・編集するのは
        // 開始値 0 そのもの（本家は AnimationValue.Value を直接
        // 編集する）。
        let animation = Animation(
            defaultValue: 0, minValue: -10000, maxValue: 10000,
            animationType: .movementAmount,
            values: [AnimationValue(0), AnimationValue(1)])
        XCTAssertEqual(animation.value(atFrame: 600, length: 1200, fps: 30), 600)
        XCTAssertEqual(AnimationSliderScale.editValue(of: animation, valueIndex: 0), 0)
        XCTAssertEqual(AnimationSliderScale.editValue(of: animation, valueIndex: 1), 1)
    }

    func testEditValueForKeyFrameSegments() {
        // キーフレーム区間では、その区間の開始値がそのまま編集対象。
        let animation = Animation(
            defaultValue: 0, minValue: -10000, maxValue: 10000,
            animationType: .linear,
            values: [AnimationValue(10), AnimationValue(20), AnimationValue(30)],
            keyFrames: KeyFrames(frames: [10]))
        XCTAssertEqual(AnimationSliderScale.editValue(of: animation, valueIndex: 0), 10)
        XCTAssertEqual(AnimationSliderScale.editValue(of: animation, valueIndex: 1), 20)
        XCTAssertEqual(AnimationSliderScale.editValue(of: animation, valueIndex: 2), 30)
    }

    func testEditValueFallsBackWhenValueNotMaterialized() {
        // 値列が短い場合は末尾値、空の場合は既定値へ落とす
        // （書き込み時に記述子側が実体化する）。
        let short = Animation(
            defaultValue: 7, minValue: 0, maxValue: 100,
            animationType: .linear, values: [AnimationValue(5)])
        XCTAssertEqual(AnimationSliderScale.editValue(of: short, valueIndex: 1), 5)
        let empty = Animation(
            defaultValue: 7, minValue: 0, maxValue: 100,
            animationType: .linear, values: [])
        XCTAssertEqual(AnimationSliderScale.editValue(of: empty, valueIndex: 0), 7)
    }

    // MARK: - R2-A04: 移動量指定の第2値は対称範囲へ置き換える

    func testMovementAmountSecondValueUsesSymmetricRanges() {
        let s = spec(-50, 200)
        let r = AnimationSliderScale.ranges(
            forValueAt: 1, animationType: .movementAmount, spec: s,
            absoluteMin: -100, absoluteMax: 1000)
        XCTAssertEqual(r.defaultMin, -200)
        XCTAssertEqual(r.defaultMax, 200)
        XCTAssertEqual(r.absoluteMin, -1000)
        XCTAssertEqual(r.absoluteMax, 1000)
        // 第1値と、移動量指定でない型の第2値は置き換えない。
        let first = AnimationSliderScale.ranges(
            forValueAt: 0, animationType: .movementAmount, spec: s,
            absoluteMin: -100, absoluteMax: 1000)
        XCTAssertEqual(first.defaultMin, -50)
        XCTAssertEqual(first.defaultMax, 200)
        let other = AnimationSliderScale.ranges(
            forValueAt: 1, animationType: .random, spec: s,
            absoluteMin: -100, absoluteMax: 1000)
        XCTAssertEqual(other.defaultMin, -50)
        XCTAssertEqual(other.defaultMax, 200)
    }

    func testMovementAmountSymmetricReplacementAffectsSharedScale() {
        // 第2値 -150: 対称置換後の基準範囲 -200..200 ではスケール 1。
        // 置換しなければ下限 -50 基準で floor(-150/-50)=3 → スケール 4
        // になり、先頭値のスライダ範囲まで広がってしまう。
        let s = spec(-50, 200)
        let movement = AnimationSliderScale.sliderRange(
            values: [0, -150], valueIndex: 0, animationType: .movementAmount,
            spec: s, absoluteMin: -100, absoluteMax: 1000)
        XCTAssertEqual(movement.min, -50)
        XCTAssertEqual(movement.max, 200)
        let movementSecond = AnimationSliderScale.sliderRange(
            values: [0, -150], valueIndex: 1, animationType: .movementAmount,
            spec: s, absoluteMin: -100, absoluteMax: 1000)
        XCTAssertEqual(movementSecond.min, -200)
        XCTAssertEqual(movementSecond.max, 200)
        // 対照: 置換のない型では同じ値列でスケール 4 が共有される。
        let plain = AnimationSliderScale.sliderRange(
            values: [0, -150], valueIndex: 0, animationType: .random,
            spec: s, absoluteMin: -100, absoluteMax: 1000)
        XCTAssertEqual(plain.min, -100)
        XCTAssertEqual(plain.max, 800)
    }

    // MARK: - 確定時の値の確定処理（FE-R13-004、本家 TextBoxSlider.FixValue）

    func testFixedValueDigitsDerivedFromDeltaF1() {
        // F1 → Delta 0.1 → 桁数 (int)(1/0.1/10 + 1) = 2（表示桁 1 ではない）。
        let delta = spec(0, 100, format: "F1").delta
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                1.234, delta: delta, minimum: -10000, maximum: 10000),
            1.23, accuracy: 1e-9)
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                1.236, delta: delta, minimum: -10000, maximum: 10000),
            1.24, accuracy: 1e-9)
        // 0 から離れる方向へ丸める（AwayFromZero）。
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                -1.236, delta: delta, minimum: -10000, maximum: 10000),
            -1.24, accuracy: 1e-9)
    }

    func testFixedValueDigitsDerivedFromDeltaF0() {
        // F0 → Delta 1 → 桁数 (int)(1/1/10 + 1) = 1。
        let delta = spec(0, 100, format: "F0").delta
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                1.25, delta: delta, minimum: -10000, maximum: 10000),
            1.3, accuracy: 1e-9)
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                1.24, delta: delta, minimum: -10000, maximum: 10000),
            1.2, accuracy: 1e-9)
    }

    func testFixedValueDigitsDerivedFromDeltaF2() {
        // F2 → Delta = Pow(0.1, 2) = 0.010000000000000002（0.1 の
        // 二乗に最も近い double）→ 式 (int)(1/Delta/10 + 1) は
        // 10.999… の切り捨てで 10 桁になる。式をそのまま再現した
        // 帰結であり、11 桁へ寄せない（本家も同じ Pow 経路）。
        let delta = spec(0, 100, format: "F2").delta
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                1.234567890123, delta: delta, minimum: -10000, maximum: 10000),
            1.2345678901, accuracy: 1e-12)
    }

    func testFixedValueDigitsClampedAtFifteen() {
        // F3 → Delta 0.001 → 式の値は 101 だが上限 15 桁で頭打ち。
        let delta = spec(0, 100, format: "F3").delta
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                0.1234567890123456, delta: delta, minimum: -10000, maximum: 10000),
            0.123456789012346, accuracy: 1e-15)
    }

    func testFixedValueClampsAfterRounding() {
        // 丸め → クランプの順序: 100.06 は桁数 1 で 100.1 へ丸まって
        // から上限 100 へクランプされる。
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                100.06, delta: 1, minimum: 0, maximum: 100),
            100, accuracy: 1e-9)
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                -0.06, delta: 1, minimum: 0, maximum: 100),
            0, accuracy: 1e-9)
        // 範囲内の値は丸めだけが効く。
        XCTAssertEqual(
            AnimationSliderScale.fixedValue(
                50.06, delta: 1, minimum: 0, maximum: 100),
            50.1, accuracy: 1e-9)
    }
}
