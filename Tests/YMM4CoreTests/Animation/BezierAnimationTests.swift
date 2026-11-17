import XCTest
@testable import YMM4Core

final class BezierAnimationTests: XCTestCase {
    private func point(
        _ x: Float, _ y: Float,
        cp1: (Float, Float) = (0, 0), cp2: (Float, Float) = (0, 0)
    ) -> BezierAnimationPoint {
        BezierAnimationPoint(
            point: BezierVector(x: x, y: y),
            controlPoint1: BezierVector(x: cp1.0, y: cp1.1),
            controlPoint2: BezierVector(x: cp2.0, y: cp2.1)
        )
    }

    func testDefaultPointsAreIdentity() {
        // 既定の2点（制御点オフセット ±0.3）は対称で、ほぼ恒等になる
        let bezier = BezierAnimation()
        XCTAssertEqual(bezier.points, BezierAnimationPoint.createDefaultPoints())
        XCTAssertEqual(bezier.value(atRate: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(bezier.value(atRate: 0.25), 0.25, accuracy: 1e-6)
        XCTAssertEqual(bezier.value(atRate: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(bezier.value(atRate: 0.75), 0.75, accuracy: 1e-6)
        XCTAssertEqual(bezier.value(atRate: 1), 1, accuracy: 1e-9)
    }

    func testEaseCurve() {
        // CSS の ease 相当（始点 CP2 = (0.42, 0)、終点 CP1 = (-0.58, 0)）
        let bezier = BezierAnimation(points: [
            point(0, 0, cp2: (0.42, 0)),
            point(1, 1, cp1: (-0.58, 0)),
        ])
        XCTAssertEqual(bezier.value(atRate: 0.25), 0.15368131732987678, accuracy: 1e-5)
        XCTAssertEqual(bezier.value(atRate: 0.5), 0.6152608828266148, accuracy: 1e-5)
        XCTAssertEqual(bezier.value(atRate: 0.75), 0.923418351007945, accuracy: 1e-5)
    }

    func testStraightLinePoints() {
        // 制御点オフセットが両方とも (0, 0) なら直線になる
        let bezier = BezierAnimation(points: [point(0, 0), point(1, 1)])
        XCTAssertEqual(bezier.value(atRate: 0.3), 0.3, accuracy: 1e-6)
        XCTAssertEqual(bezier.value(atRate: 0.7), 0.7, accuracy: 1e-6)
    }

    func testFewerThanTwoPointsReturnsRate() {
        XCTAssertEqual(BezierAnimation(points: []).value(atRate: 0.3), 0.3)
        XCTAssertEqual(BezierAnimation(points: [point(0.5, 0.5)]).value(atRate: 0.3), 0.3)
    }

    func testOutOfRangeReturnsEndY() {
        let bezier = BezierAnimation(points: [point(0, 0.2), point(1, 0.8)])
        XCTAssertEqual(bezier.value(atRate: 0), 0.2, accuracy: 1e-6)
        XCTAssertEqual(bezier.value(atRate: -0.5), 0.2, accuracy: 1e-6)
        XCTAssertEqual(bezier.value(atRate: 1), 0.8, accuracy: 1e-6)
        XCTAssertEqual(bezier.value(atRate: 1.5), 0.8, accuracy: 1e-6)
    }

    func testQuadraticWithTwoPointsIgnoresControlPoints() {
        // 2点の2次モードでは制御点が両方とも (0, 0) に置き換わり直線になる
        let bezier = BezierAnimation(
            points: [point(0, 0, cp1: (0.9, 0.9), cp2: (0.9, 0.9)), point(1, 1, cp1: (-0.9, -0.9), cp2: (-0.9, -0.9))],
            isQuadratic: true
        )
        XCTAssertEqual(bezier.value(atRate: 0.3), 0.3, accuracy: 1e-6)
    }

    func testQuadraticWithThreePoints() {
        // (0,0), (0.5,1), (1,0) の2次モード。対称な山形になる
        let bezier = BezierAnimation(
            points: [point(0, 0), point(0.5, 1), point(1, 0)],
            isQuadratic: true
        )
        XCTAssertEqual(bezier.value(atRate: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(bezier.value(atRate: 0.25), 0.375, accuracy: 1e-5)
        XCTAssertEqual(bezier.value(atRate: 0.5), 0.5, accuracy: 1e-5)
        XCTAssertEqual(bezier.value(atRate: 0.75), 0.375, accuracy: 1e-5)
        XCTAssertEqual(bezier.value(atRate: 1), 0, accuracy: 1e-9)
    }
}
