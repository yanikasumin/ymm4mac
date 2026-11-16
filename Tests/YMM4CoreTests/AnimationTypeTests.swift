import XCTest
@testable import YMM4Core

final class AnimationTypeTests: XCTestCase {
    func testBasicRawValues() {
        XCTAssertEqual(AnimationType.none.rawValue, 0)
        XCTAssertEqual(AnimationType.linear.rawValue, 1)
        XCTAssertEqual(AnimationType.instant.rawValue, 3)
        XCTAssertEqual(AnimationType.movementAmount.rawValue, 5)
        XCTAssertEqual(AnimationType.random.rawValue, 6)
        XCTAssertEqual(AnimationType.repetitive.rawValue, 8)
        XCTAssertEqual(AnimationType.interpolation.rawValue, 15)
        XCTAssertEqual(AnimationType.accelerationDeceleration.rawValue, 103)
    }

    func testEasingRawValues() {
        // 科ごとの帯: 末尾 1=In、2=Out、3=InOut、4=OutIn、5〜8 は同順の _Int 版
        XCTAssertEqual(AnimationType.quadIn.rawValue, 10001)
        XCTAssertEqual(AnimationType.quadOut.rawValue, 10002)
        XCTAssertEqual(AnimationType.quadInOut.rawValue, 10003)
        XCTAssertEqual(AnimationType.quadOutIn.rawValue, 10004)
        XCTAssertEqual(AnimationType.quadInInt.rawValue, 10005)
        XCTAssertEqual(AnimationType.quadOutInInt.rawValue, 10008)
        XCTAssertEqual(AnimationType.cubicIn.rawValue, 10101)
        XCTAssertEqual(AnimationType.quartIn.rawValue, 10201)
        XCTAssertEqual(AnimationType.quintIn.rawValue, 10301)
        XCTAssertEqual(AnimationType.sineIn.rawValue, 10401)
        XCTAssertEqual(AnimationType.circIn.rawValue, 10501)
        XCTAssertEqual(AnimationType.expoIn.rawValue, 10601)
        XCTAssertEqual(AnimationType.backIn.rawValue, 10701)
        XCTAssertEqual(AnimationType.elasticIn.rawValue, 10801)
        XCTAssertEqual(AnimationType.bounceIn.rawValue, 10901)
        XCTAssertEqual(AnimationType.bounceOutInInt.rawValue, 10908)
    }

    func testBezierRawValues() {
        XCTAssertEqual(AnimationType.linearBezier.rawValue, 100_000)
        XCTAssertEqual(AnimationType.interpolationBezier.rawValue, 100_001)
    }

    func testKeyFrameSupport() {
        // 対応しないのは なし・移動量指定・反復移動・ランダム移動 のみ
        XCTAssertFalse(AnimationType.none.isKeyFrameSupported)
        XCTAssertFalse(AnimationType.movementAmount.isKeyFrameSupported)
        XCTAssertFalse(AnimationType.repetitive.isKeyFrameSupported)
        XCTAssertFalse(AnimationType.random.isKeyFrameSupported)
        XCTAssertTrue(AnimationType.linear.isKeyFrameSupported)
        XCTAssertTrue(AnimationType.instant.isKeyFrameSupported)
        XCTAssertTrue(AnimationType.interpolation.isKeyFrameSupported)
        XCTAssertTrue(AnimationType.accelerationDeceleration.isKeyFrameSupported)
        XCTAssertTrue(AnimationType.quadIn.isKeyFrameSupported)
        XCTAssertTrue(AnimationType.linearBezier.isKeyFrameSupported)
    }

    func testClassification() {
        XCTAssertTrue(AnimationType.quadIn.isEasing)
        XCTAssertFalse(AnimationType.linear.isEasing)
        XCTAssertFalse(AnimationType.accelerationDeceleration.isEasing)

        // IsInterpolationEasing は 値 % 10 > 4
        XCTAssertTrue(AnimationType.quadInInt.isInterpolationEasing)
        XCTAssertFalse(AnimationType.quadIn.isInterpolationEasing)
        XCTAssertFalse(AnimationType.interpolationBezier.isInterpolationEasing)

        // 補間系は 補間移動 と 加減速移動 のみ
        XCTAssertTrue(AnimationType.interpolation.isInterpolation)
        XCTAssertTrue(AnimationType.accelerationDeceleration.isInterpolation)
        XCTAssertFalse(AnimationType.linear.isInterpolation)
    }
}
