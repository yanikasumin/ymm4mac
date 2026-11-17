import XCTest
@testable import YMM4Core

final class EasingTests: XCTestCase {
    private let families: [EasingFamily] = [
        .linear, .sine, .quad, .cubic, .quart, .quint,
        .expo, .circ, .back, .elastic, .bounce, .jump,
    ]

    func testInFunctionsAtHalf() {
        // 各科の素関数 f(0.5)。数式は ANIMATION-FORMULAS.md §2.2
        let expected: [(EasingFamily, Double)] = [
            (.linear, 0.5),
            (.sine, 0.2928932188134524),   // 1 - cos(π/4)
            (.quad, 0.25),
            (.cubic, 0.125),
            (.quart, 0.0625),
            (.quint, 0.03125),
            (.expo, 0.03125),              // 2^-5
            (.circ, 0.1339745962155614),   // 1 - sqrt(0.75)
            (.back, -0.0876975),           // 0.25 * (2.70158*0.5 - 1.70158)
            (.elastic, 0.1875),            // 56/32 - 105/16 + 60/8 - 10/4
            (.bounce, 0.234375),           // 0.25 - 7.5625 * (5/11 - 0.5)^2
            (.jump, 0),
        ]
        for (family, value) in expected {
            XCTAssertEqual(family.inValue(0.5), value, accuracy: 1e-9, "\(family)")
        }
    }

    func testEndpointsAreForced() {
        // 端点ラッパー: 全科で In(0) = 0、In(1) = 1。
        // Expo の素関数は t=0 で 2^-10 だが、ラッパーが 0 に強制する
        for family in families {
            XCTAssertEqual(family.inValue(0), 0, "\(family)")
            XCTAssertEqual(family.inValue(1), 1, "\(family)")
        }
    }

    func testOutComposition() {
        XCTAssertEqual(EasingFamily.quad.value(mode: .out, rate: 0.5), 0.75, accuracy: 1e-9)
        XCTAssertEqual(
            EasingFamily.sine.value(mode: .out, rate: 0.5),
            0.7071067811865476, accuracy: 1e-9 // cos(π/4)
        )
    }

    func testInOutComposition() {
        XCTAssertEqual(EasingFamily.quad.value(mode: .inOut, rate: 0.25), 0.125, accuracy: 1e-9)
        XCTAssertEqual(EasingFamily.quad.value(mode: .inOut, rate: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(EasingFamily.quad.value(mode: .inOut, rate: 0.75), 0.875, accuracy: 1e-9)
    }

    func testOutInComposition() {
        XCTAssertEqual(EasingFamily.quad.value(mode: .outIn, rate: 0.25), 0.375, accuracy: 1e-9)
        XCTAssertEqual(EasingFamily.quad.value(mode: .outIn, rate: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(EasingFamily.quad.value(mode: .outIn, rate: 0.75), 0.625, accuracy: 1e-9)
    }

    func testBounceSegments() {
        // 区間 [7/11, 1]: 1 - 7.5625 (1 - t)^2
        XCTAssertEqual(EasingFamily.bounce.inValue(0.9), 0.924375, accuracy: 1e-9)
        // 区間 [0, 1/11): 1/64 - 7.5625 (1/22 - t)^2
        XCTAssertEqual(EasingFamily.bounce.inValue(0.05), 0.01546875, accuracy: 1e-9)
    }

    func testJumpInOutIsSpecial() {
        // Jump の InOut だけは合成規則の特例（rate < 0.5 ? 0 : 1）
        XCTAssertEqual(EasingFamily.jump.value(mode: .inOut, rate: 0.25), 0)
        XCTAssertEqual(EasingFamily.jump.value(mode: .inOut, rate: 0.75), 1)
        XCTAssertEqual(EasingFamily.jump.inValue(0.5), 0)
    }

    func testGetValueSineInOut() {
        // 反復移動で使う Sine / InOut。(1 - cos(π r)) / 2 と等しい
        XCTAssertEqual(
            EasingFamily.getValue(family: .sine, mode: .inOut, rate: 0.4666666666666667),
            0.4477357683661733, accuracy: 1e-9
        )
    }
}

final class CubicTests: XCTestCase {
    func testWeightKernel() {
        let cubic = Cubic()
        XCTAssertEqual(cubic.a, -0.5)
        XCTAssertEqual(cubic.taps, 2)
        XCTAssertEqual(cubic.weight(distance: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(cubic.weight(distance: 0.5), 0.5625, accuracy: 1e-9)
        XCTAssertEqual(cubic.weight(distance: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(cubic.weight(distance: 1.5), -0.0625, accuracy: 1e-9)
        XCTAssertEqual(cubic.weight(distance: 2), 0, accuracy: 1e-9)
        XCTAssertEqual(cubic.weight(distance: 2.5), 0, accuracy: 1e-9)
    }

    func testWeightDoesNotTakeAbsoluteValue() {
        // GetWeight 自体は絶対値を取らない（符号付きのまま3次式に入る）
        let cubic = Cubic()
        XCTAssertEqual(cubic.weight(distance: -0.5), 0.1875, accuracy: 1e-9)
        XCTAssertEqual(cubic.weight(distance: .nan), 0, accuracy: 1e-9)
    }
}
