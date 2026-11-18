import XCTest
@testable import YMM4Core

/// 数式抽出（ANIMATION-FORMULAS.md）に基づく評価経路のテスト。
/// 期待値は本家の数式を独立に計算したもの。
final class AnimationEvaluationTests: XCTestCase {
    private func makeAnimation(
        type: AnimationType,
        values: [Double],
        keyFrames: [Int] = [],
        span: Double = 0,
        randomSeed: Int64 = 0
    ) -> Animation {
        Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: type,
            values: values.map(AnimationValue.init),
            span: span,
            keyFrames: KeyFrames(frames: keyFrames),
            length: 20, videoFPS: 30,
            randomSeed: randomSeed
        )
    }

    /// キーフレーム追加は、追加位置の現在値を挿入する（本家
    /// Animation の KeyFramesChanging ハンドラと同じ規則）。非線形
    /// イージングでは区間ごとの再評価で曲線が変わるが、これは
    /// 本家でも同じ挙動である（K19-02 の本家確認に基づく固定）。
    func testInsertKeyFrameOnQuadInMatchesHonkeSemantics() {
        var animation = makeAnimation(type: .quadIn, values: [0, 100])
        XCTAssertEqual(
            animation.value(atFrame: 15, length: 20, fps: 30), 56.25,
            accuracy: 1e-9
        )
        XCTAssertTrue(animation.insertKeyFrame(at: 10))
        // 追加位置の値 25 が挿入され、区間 [10, 20] の二次イージングで
        // フレーム15 は 25 + 75 * 0.25 = 43.75 になる（本家も同じ）。
        XCTAssertEqual(animation.values.map(\.value), [0, 25, 100])
        XCTAssertEqual(
            animation.value(atFrame: 15, length: 20, fps: 30), 43.75,
            accuracy: 1e-9
        )
    }

    /// 値列が短い保存データへの区間値編集では、まず評価上の有効値
    /// 列（キーフレーム数 + 2 個。本家の GetActiveValueCount と同じ
    /// 数）へ展開してから対象位置だけを書き換える。展開しないと、
    /// 代用規則で読まれていた最終端点まで変わってしまう
    /// （K19-03／R20-114-02）。範囲外の区間は受け付けない。
    func testSetValuePadsWithLastEffectiveValue() {
        var animation = makeAnimation(
            type: .linear, values: [10], keyFrames: [10, 20]
        )
        animation.setValue(50, atSegment: 2)
        XCTAssertEqual(animation.values.map(\.value), [10, 10, 50, 10])
        animation.setValue(99, atSegment: 3)
        XCTAssertEqual(animation.values.map(\.value), [10, 10, 50, 10])
    }

    /// 不完全な値列で先頭区間を編集しても、最終端点の評価値は
    /// 編集前と変わらない（R20-114-02 の QA04）。
    func testSetValueOnShortValuesPreservesEndpointEvaluation() {
        var animation = makeAnimation(
            type: .linear, values: [10], keyFrames: [10]
        )
        let endpointBefore = animation.value(atFrame: 20, length: 20, fps: 30)
        animation.setValue(30, atSegment: 0)
        XCTAssertEqual(animation.values.map(\.value), [30, 10, 10])
        XCTAssertEqual(
            animation.value(atFrame: 20, length: 20, fps: 30), endpointBefore,
            accuracy: 1e-9
        )
    }

    // MARK: - 経路4: 区間ごとイージング＋線形補間（非 _Int 版）

    func testQuadInAppliesEasingPerSegment() {
        let animation = makeAnimation(type: .quadIn, values: [0, 50, 100], keyFrames: [10])
        // 区間内率 0.5 → Quad In = 0.25
        XCTAssertEqual(animation.value(atFrame: 5, length: 20, fps: 30), 12.5, accuracy: 1e-9)
        XCTAssertEqual(animation.value(atFrame: 10, length: 20, fps: 30), 50, accuracy: 1e-9)
        XCTAssertEqual(animation.value(atFrame: 15, length: 20, fps: 30), 62.5, accuracy: 1e-9)
        XCTAssertEqual(animation.value(atFrame: 20, length: 20, fps: 30), 100, accuracy: 1e-9)
    }

    func testNonIntWithoutKeyFramesEasesWholeRateAndLerps() {
        // キーフレームが無ければ区間は全体であり、結果は単純な率イージングになる
        let animation = makeAnimation(type: .quadIn, values: [0, 100])
        XCTAssertEqual(animation.value(atFrame: 10, length: 20, fps: 30), 25, accuracy: 1e-9)
    }

    // MARK: - 経路2: 全体率イージング＋スプライン加重平均（_Int 版）

    func testIntEasingUsesWholeRateSpline() {
        // 全体率 0.5 → Quad In = 0.25 → 位置 0.25 でのスプライン加重平均。
        // 単純な線形補間（25）とは異なる値になる
        let animation = makeAnimation(type: .quadInInt, values: [0, 100])
        XCTAssertEqual(animation.value(atFrame: 0, length: 20, fps: 30), 0, accuracy: 1e-9)
        XCTAssertEqual(animation.value(atFrame: 10, length: 20, fps: 30), 20.3125, accuracy: 1e-9)
        XCTAssertEqual(animation.value(atFrame: 20, length: 20, fps: 30), 100, accuracy: 1e-9)
    }

    func testIntAndNonIntTakeDifferentPaths() {
        let nonInt = makeAnimation(type: .sineIn, values: [0, 100])
        let int = makeAnimation(type: .sineInInt, values: [0, 100])
        // 非 _Int: Sine In(0.5) をそのまま線形補間に使う
        XCTAssertEqual(
            nonInt.value(atFrame: 10, length: 20, fps: 30),
            29.28932188134524, accuracy: 1e-9
        )
        // _Int: 同じ率をスプラインの位置として使うため結果が異なる
        XCTAssertNotEqual(
            int.value(atFrame: 10, length: 20, fps: 30),
            nonInt.value(atFrame: 10, length: 20, fps: 30)
        )
    }

    // MARK: - 経路1: 補間移動・加減速移動（スプライン加重平均）

    func testInterpolationSplineMidpoint() {
        // 本家 Animation.cs のループ条件は値の範囲を1つ超えた位置まで含み、
        // その位置は末尾フォールバックで最後の値になるため、中点は 50 にならない
        let animation = makeAnimation(type: .interpolation, values: [0, 100])
        XCTAssertEqual(animation.value(atFrame: 0, length: 20, fps: 30), 0, accuracy: 1e-9)
        XCTAssertEqual(
            animation.value(atFrame: 10, length: 20, fps: 30),
            47.05882352941177, accuracy: 1e-9
        )
        XCTAssertEqual(animation.value(atFrame: 20, length: 20, fps: 30), 100, accuracy: 1e-9)
    }

    func testInterpolationSplineWithKeyFrame() {
        let animation = makeAnimation(type: .interpolation, values: [0, 50, 100], keyFrames: [10])
        XCTAssertEqual(
            animation.value(atFrame: 5, length: 20, fps: 30),
            20.58823529411765, accuracy: 1e-9
        )
        XCTAssertEqual(
            animation.value(atFrame: 15, length: 20, fps: 30),
            78.125, accuracy: 1e-9
        )
    }

    func testAccelerationDecelerationSpline() {
        // 率 0.25 → 加減速の率変換 (1 - cos(π/4)) / 2 ≈ 0.1464 を連続座標として加重平均
        let animation = makeAnimation(type: .accelerationDeceleration, values: [0, 100])
        XCTAssertEqual(
            animation.value(atFrame: 5, length: 20, fps: 30),
            9.707382956013424, accuracy: 1e-6
        )
    }

    // MARK: - 経路3: Linear_Bezier / Interpolation_Bezier

    func testLinearBezierWithDefaultPoints() {
        let animation = makeAnimation(type: .linearBezier, values: [0, 100])
        XCTAssertEqual(animation.value(atFrame: 5, length: 20, fps: 30), 25, accuracy: 1e-4)
        XCTAssertEqual(animation.value(atFrame: 10, length: 20, fps: 30), 50, accuracy: 1e-6)
    }

    func testInterpolationBezierUsesSpline() {
        // 既定ベジェは率 0.5 を 0.5 に写すため、位置 0.5 のスプライン加重平均になる
        let animation = makeAnimation(type: .interpolationBezier, values: [0, 100])
        XCTAssertEqual(animation.value(atFrame: 10, length: 20, fps: 30), 50, accuracy: 1e-6)
    }

    // MARK: - キーフレーム系経路は最終処理を通らない

    func testKeyframedPathsSkipFinalClamp() {
        // 本家 GetValue のキーフレーム系経路は早期 return であり、
        // Loop 剰余と [min, max] クランプを適用しない
        let animation = Animation(
            defaultValue: 0, minValue: 0, maxValue: 60,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(50), AnimationValue(100)],
            keyFrames: KeyFrames(frames: [10]),
            length: 20, videoFPS: 30
        )
        XCTAssertEqual(animation.value(atFrame: 20, length: 20, fps: 30), 100)
    }

    // MARK: - 反復移動 Span > 0

    func testRepetitiveWithSpan() {
        // Span = 1 秒、30fps、長さ 60 フレーム（2秒）。半周期 0.5 秒の
        // 三角波に Sine InOut を適用する
        let animation = makeAnimation(type: .repetitive, values: [0, 100], span: 1.0)
        XCTAssertEqual(animation.value(atFrame: 0, length: 60, fps: 30), 0, accuracy: 1e-9)
        XCTAssertEqual(
            animation.value(atFrame: 7, length: 60, fps: 30),
            44.77357683661733, accuracy: 1e-6
        )
        XCTAssertEqual(animation.value(atFrame: 15, length: 60, fps: 30), 100, accuracy: 1e-9)
        XCTAssertEqual(animation.value(atFrame: 30, length: 60, fps: 30), 0, accuracy: 1e-9)
        XCTAssertEqual(animation.value(atFrame: 45, length: 60, fps: 30), 100, accuracy: 1e-9)
    }

    // MARK: - ランダム移動

    func testRandomWithoutSpanMatchesStatelessRandom() {
        // シード 0、フレーム 30: GetDouble([0, 30]) = 0.6724544805420507
        let animation = makeAnimation(type: .random, values: [10, 20])
        XCTAssertEqual(
            animation.value(atFrame: 30, length: 100, fps: 30),
            16.724544805420507, accuracy: 1e-9
        )
    }

    func testRandomIsDeterministic() {
        // GetHashCode の具体値との対応付けは未確定のため、決定的性質
        // （同一入力で同一結果）と値域だけを主張する
        let animation = makeAnimation(type: .random, values: [10, 20], randomSeed: 42)
        for frame in [0, 1, 2, 3, 50, 99] {
            let first = animation.value(atFrame: frame, length: 100, fps: 30)
            XCTAssertEqual(first, animation.value(atFrame: frame, length: 100, fps: 30))
            XCTAssertGreaterThanOrEqual(first, 10)
            XCTAssertLessThanOrEqual(first, 20)
        }
    }

    func testRandomWithSpanIsDeterministicAndSmoothed() {
        let animation = makeAnimation(type: .random, values: [0, 100], span: 1.0)
        // シード 0、フレーム 30（周期位置 t = 1.0）での加重和
        XCTAssertEqual(
            animation.value(atFrame: 30, length: 60, fps: 30),
            35.53953806690252, accuracy: 1e-6
        )
        XCTAssertEqual(
            animation.value(atFrame: 15, length: 60, fps: 30),
            35.884428076620184, accuracy: 1e-6
        )
        for frame in [0, 10, 20, 40, 59] {
            let first = animation.value(atFrame: frame, length: 60, fps: 30)
            XCTAssertEqual(first, animation.value(atFrame: frame, length: 60, fps: 30))
            XCTAssertGreaterThanOrEqual(first, -1)
            XCTAssertLessThanOrEqual(first, 101)
        }
    }
}
