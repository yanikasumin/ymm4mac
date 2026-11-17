import XCTest
@testable import YMM4Core

/// MAC-0036: トランジションパラメータの型付き復号と、
/// Before/AfterVideoEffects の定義供給の検証。
/// 期待値は本家の各パラメータクラスのフィールド初期化子と
/// プロパティ構成（逆コンパイル実測）に基づく。
final class TransitionParameterTests: XCTestCase {

    private func preserved(
        _ typeName: String, _ fields: [(String, JSONValue)] = []
    ) -> PreservedObject {
        PreservedObject(.object(
            [(key: "$type", value: .string(typeName))]
                + fields.map { (key: $0.0, value: $0.1) }
        ))
    }

    private func typeName(_ className: String) -> String {
        "YukkuriMovieMaker.Transition.\(className), YukkuriMovieMaker"
    }

    /// パラメータ未指定（nil）は本家のフィールド初期化子どおり Push。
    func testNilParameterDefaultsToPush() {
        let parameter = TransitionParameter.decode(nil)
        XCTAssertEqual(parameter.kind, .push)
        XCTAssertEqual(parameter.easingFamily, .expo)
        XCTAssertEqual(parameter.easingMode, .inOut)
        XCTAssertEqual(parameter.angle.value(atFrame: 0, length: 100, fps: 30), 0)
    }

    /// $type を持たない保持値も Push へ倒れる。
    func testParameterWithoutTypeDefaultsToPush() {
        let parameter = TransitionParameter.decode(PreservedObject(.object([])))
        XCTAssertEqual(parameter.kind, .push)
    }

    /// 全内蔵方式の種別判定。
    func testBuiltInKinds() {
        let cases: [(String, TransitionKind)] = [
            ("NoneTransitionParameter", .none),
            ("SwitchTransitionParameter", .switchKind),
            ("FadeTransitionParameter", .fade),
            ("SlideTransitionParameter", .slide),
            ("PushTransitionParameter", .push),
            ("DoubleOpenDoorTransitionParameter", .doubleOpenDoor),
            ("DoubleSlideDoorTransitionParameter", .doubleSlideDoor),
            ("SliceTransitionParameter", .slice),
            ("RuleImageTransitionParameter", .ruleImage),
        ]
        for (className, kind) in cases {
            let parameter = TransitionParameter.decode(preserved(typeName(className)))
            XCTAssertEqual(parameter.kind, kind, className)
        }
    }

    /// プラグイン方式（コミュニティ等）は unknown として差し替え点になる。
    func testPluginParameterIsUnknown() {
        let parameter = TransitionParameter.decode(preserved(
            "SomePlugin.PageTurnTransitionParameter, SomePlugin"
        ))
        XCTAssertEqual(parameter.kind, .unknown)
    }

    /// Fade の既定は Expo / InOut で、指定があれば上書きされる。
    func testFadeEasingDefaultsAndOverrides() {
        let defaults = TransitionParameter.decode(preserved(typeName("FadeTransitionParameter")))
        XCTAssertEqual(defaults.easingFamily, .expo)
        XCTAssertEqual(defaults.easingMode, .inOut)

        let custom = TransitionParameter.decode(preserved(
            typeName("FadeTransitionParameter"),
            [("EasingType", .string("Linear")), ("EasingMode", .string("Out"))]
        ))
        XCTAssertEqual(custom.easingFamily, .linear)
        XCTAssertEqual(custom.easingMode, .out)
    }

    /// 進行率は本家の Easing.GetValue と同じ（Linear は率そのもの、
    /// Jump の InOut は中点で切り替わる）。
    func testEasedRate() {
        let linear = TransitionParameter.decode(preserved(
            typeName("FadeTransitionParameter"),
            [("EasingType", .string("Linear")), ("EasingMode", .string("In"))]
        ))
        XCTAssertEqual(linear.easedRate(frame: 5, duration: 20), 0.25, accuracy: 1e-9)
        XCTAssertEqual(linear.easedRate(frame: 0, duration: 20), 0, accuracy: 1e-9)
        XCTAssertEqual(linear.easedRate(frame: 20, duration: 20), 1, accuracy: 1e-9)
        XCTAssertEqual(linear.easedRate(frame: 3, duration: 0), 0, accuracy: 1e-9)
    }

    /// None は OverlayTarget を読み、既定は Before。
    func testNoneOverlayTarget() {
        let defaults = TransitionParameter.decode(preserved(typeName("NoneTransitionParameter")))
        XCTAssertEqual(defaults.target, .before)
        let after = TransitionParameter.decode(preserved(
            typeName("NoneTransitionParameter"),
            [("OverlayTarget", .string("After"))]
        ))
        XCTAssertEqual(after.target, .after)
    }

    /// Slide は Target と Angle（Animation）を読み、既定 Target は Before。
    func testSlideFields() {
        let parameter = TransitionParameter.decode(preserved(
            typeName("SlideTransitionParameter"),
            [
                ("Target", .string("After")),
                ("Angle", .object([
                    (key: "Values", value: .array([
                        .object([(key: "Value", value: .number(90))]),
                    ])),
                ])),
            ]
        ))
        XCTAssertEqual(parameter.target, .after)
        XCTAssertEqual(
            parameter.angle.value(atFrame: 0, length: 100, fps: 30), 90, accuracy: 1e-9
        )
    }

    /// Slice の既定値（Slices 6 / Shift 0 / Start Left / Direction
    /// Alternating / Target Before）。
    func testSliceDefaults() {
        let parameter = TransitionParameter.decode(preserved(typeName("SliceTransitionParameter")))
        XCTAssertEqual(parameter.slices.value(atFrame: 0, length: 100, fps: 30), 6, accuracy: 1e-9)
        XCTAssertEqual(parameter.shift.value(atFrame: 0, length: 100, fps: 30), 0, accuracy: 1e-9)
        XCTAssertEqual(parameter.start, .left)
        XCTAssertEqual(parameter.direction, .alternating)
        XCTAssertEqual(parameter.target, .before)
    }

    /// RuleImage の既定は Easing が Linear、Tolerance 3、KeepAspect true。
    func testRuleImageDefaults() {
        let parameter = TransitionParameter.decode(preserved(
            typeName("RuleImageTransitionParameter"),
            [("File", .string("rule.png"))]
        ))
        XCTAssertEqual(parameter.easingFamily, .linear)
        XCTAssertEqual(parameter.tolerance.value(atFrame: 0, length: 100, fps: 30), 3, accuracy: 1e-9)
        XCTAssertTrue(parameter.keepAspect)
        XCTAssertFalse(parameter.isFixedCoveringScale)
        XCTAssertFalse(parameter.isReversed)
        XCTAssertEqual(parameter.file, "rule.png")
    }

    /// Before/After の定義供給は別々にキャッシュされ、同一性が保たれる
    /// （前後を取り違えず、再呼び出しでも同じ定義インスタンスが返る）。
    func testTransitionEffectPairsAreCachedPerSide() {
        let item = TransitionItem()
        let invert = PreservedObject(.object([
            (key: "$type", value: .string(
                "YukkuriMovieMaker.Project.Effects.InvertEffect, YukkuriMovieMaker"
            )),
            (key: "IsEnabled", value: .bool(true)),
        ]))
        item.beforeVideoEffects = [invert]
        item.afterVideoEffects = []
        let provider = TypedEffectPairProvider()

        let before1 = provider.transitionEffectPairs(for: item, isBefore: true)
        let before2 = provider.transitionEffectPairs(for: item, isBefore: true)
        let after = provider.transitionEffectPairs(for: item, isBefore: false)

        XCTAssertEqual(before1.count, 1)
        XCTAssertEqual(after.count, 0)
        XCTAssertEqual(before2.count, 1)
        XCTAssertTrue(before1[0].definition as AnyObject === before2[0].definition as AnyObject)
        XCTAssertTrue(before1[0].timeSource === item)
    }

    /// TransitionItem のコーデック往復で TransitionParameter の生保持が
    /// そのまま残る（型付き復号は消費側のビューのみで、保存に影響しない）。
    func testTransitionParameterSurvivesCodecRoundTrip() throws {
        let item = TransitionItem()
        item.transitionParameter = preserved(
            typeName("FadeTransitionParameter"),
            [("EasingType", .string("Linear"))]
        )
        let decoded = try XCTUnwrap(item.cloned() as? TransitionItem)
        XCTAssertEqual(decoded.transitionParameter, item.transitionParameter)
    }
}
