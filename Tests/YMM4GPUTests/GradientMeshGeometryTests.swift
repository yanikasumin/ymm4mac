#if os(macOS)
import Foundation
import XCTest
@testable import YMM4GPU
import YMM4Core

/// グラデーションメッシュ幾何（GRADMESH）の検証。
/// 期待値は本家 `GradientMeshPatchBuilder` の式を独立に評価して
/// 得た値（既定格子では双線形と一致し、カスタムハンドル時は
/// テンソル積ベジェ評価と一致する）。
final class GradientMeshGeometryTests: XCTestCase {

    private let red = SIMD4<Float>(1, 0, 0, 1)
    private let gold = SIMD4<Float>(1, Float(215) / 255, 0, 1)
    private let royalBlue = SIMD4<Float>(
        Float(65) / 255, Float(105) / 255, Float(225) / 255, 1
    )
    private let cyan = SIMD4<Float>(0, 1, 1, 1)

    /// 2×2 既定格子の論理スナップショット（W=H=100、オフセットなし）。
    private func defaultSnapshots(
        rightHandleOfTopLeft: SIMD2<Double>? = nil
    ) -> [GradientMeshSnapshot] {
        [
            GradientMeshSnapshot(
                position: SIMD2(-50, -50), leftHandle: nil,
                rightHandle: rightHandleOfTopLeft, upHandle: nil,
                downHandle: nil, color: red
            ),
            GradientMeshSnapshot(
                position: SIMD2(50, -50), leftHandle: nil, rightHandle: nil,
                upHandle: nil, downHandle: nil, color: gold
            ),
            GradientMeshSnapshot(
                position: SIMD2(-50, 50), leftHandle: nil, rightHandle: nil,
                upHandle: nil, downHandle: nil, color: royalBlue
            ),
            GradientMeshSnapshot(
                position: SIMD2(50, 50), leftHandle: nil, rightHandle: nil,
                upHandle: nil, downHandle: nil, color: cyan
            ),
        ]
    }

    private func vertex(
        _ vertices: [GradientMeshVertex], row: Int, column: Int
    ) -> GradientMeshVertex {
        let n = GradientMeshGeometry.subdivisions
        return vertices[row * (n + 1) + column]
    }

    func testDefaultGridIsBilinear() {
        let bounds = RectF(left: -16, top: -16, right: 16, bottom: 16)
        let result = GradientMeshGeometry.build(
            horizontalCount: 2, verticalCount: 2,
            snapshots: defaultSnapshots(),
            coordinateMode: .relative, extendOutside: false,
            bounds: bounds, transform: .identity
        )
        let n = GradientMeshGeometry.subdivisions
        XCTAssertEqual(result.vertices.count, (n + 1) * (n + 1))
        XCTAssertEqual(result.indices.count, n * n * 6)

        let corner = vertex(result.vertices, row: 0, column: 0)
        XCTAssertEqual(corner.position.x, -16, accuracy: 1e-4)
        XCTAssertEqual(corner.position.y, -16, accuracy: 1e-4)
        XCTAssertEqual(corner.color, red)

        // 中心は四隅の重心・色平均と一致する。
        let center = vertex(result.vertices, row: n / 2, column: n / 2)
        XCTAssertEqual(center.position.x, 0, accuracy: 1e-4)
        XCTAssertEqual(center.position.y, 0, accuracy: 1e-4)
        XCTAssertEqual(center.color.x, Float(0.5637255), accuracy: 1e-5)
        XCTAssertEqual(center.color.y, Float(0.5637255), accuracy: 1e-5)
        XCTAssertEqual(center.color.z, Float(0.4705882), accuracy: 1e-5)
        XCTAssertEqual(center.color.w, 1)

        // (u, v) = (0.25, 0.5) は双線形で (-8, 0)。
        let quarter = vertex(result.vertices, row: n / 2, column: n / 4)
        XCTAssertEqual(quarter.position.x, -8, accuracy: 1e-4)
        XCTAssertEqual(quarter.position.y, 0, accuracy: 1e-4)
    }

    func testCustomHandleBendsPatch() {
        let bounds = RectF(left: -16, top: -16, right: 16, bottom: 16)
        let result = GradientMeshGeometry.build(
            horizontalCount: 2, verticalCount: 2,
            snapshots: defaultSnapshots(rightHandleOfTopLeft: SIMD2(50, -50)),
            coordinateMode: .relative, extendOutside: false,
            bounds: bounds, transform: .identity
        )
        let n = GradientMeshGeometry.subdivisions
        // 左上点の右ハンドルを右上点の位置まで引くと、中心は
        // テンソル積評価どおり (4, 0) へ寄る（双線形なら (0, 0)）。
        let center = vertex(result.vertices, row: n / 2, column: n / 2)
        XCTAssertEqual(center.position.x, 4, accuracy: 1e-4)
        XCTAssertEqual(center.position.y, 0, accuracy: 1e-4)
        // (u, v) = (0.5, 0.25) は (6, -8)。
        let point = vertex(result.vertices, row: n / 4, column: n / 2)
        XCTAssertEqual(point.position.x, 6, accuracy: 1e-4)
        XCTAssertEqual(point.position.y, -8, accuracy: 1e-4)
        // 色は (u, v) の双線形のままで、幾何の曲がりに影響されない。
        XCTAssertEqual(center.color.x, Float(0.5637255), accuracy: 1e-5)
    }

    func testExtendOutsideCoversBounds() {
        // Pixel モードで格子 (±5) が境界 (±16) より小さい場合。
        let snapshots = [
            GradientMeshSnapshot(
                position: SIMD2(-5, -5), leftHandle: nil, rightHandle: nil,
                upHandle: nil, downHandle: nil, color: red
            ),
            GradientMeshSnapshot(
                position: SIMD2(5, -5), leftHandle: nil, rightHandle: nil,
                upHandle: nil, downHandle: nil, color: gold
            ),
            GradientMeshSnapshot(
                position: SIMD2(-5, 5), leftHandle: nil, rightHandle: nil,
                upHandle: nil, downHandle: nil, color: royalBlue
            ),
            GradientMeshSnapshot(
                position: SIMD2(5, 5), leftHandle: nil, rightHandle: nil,
                upHandle: nil, downHandle: nil, color: cyan
            ),
        ]
        let bounds = RectF(left: -16, top: -16, right: 16, bottom: 16)
        let extended = GradientMeshGeometry.build(
            horizontalCount: 2, verticalCount: 2, snapshots: snapshots,
            coordinateMode: .pixel, extendOutside: true,
            bounds: bounds, transform: .identity
        )
        let n = GradientMeshGeometry.subdivisions
        // 内部 1 + 帯 4 + 隅 4 = 9 パッチ。
        XCTAssertEqual(extended.vertices.count, 9 * (n + 1) * (n + 1))
        // 隅まで届き、隅の色は最も近い格子点の色で一定。
        let cornerVertex = extended.vertices.first {
            $0.position.x == -16 && $0.position.y == -16
        }
        XCTAssertNotNil(cornerVertex)
        XCTAssertEqual(cornerVertex?.color, red)
        XCTAssertTrue(extended.vertices.allSatisfy {
            abs($0.position.x) <= 16.001 && abs($0.position.y) <= 16.001
        })

        let plain = GradientMeshGeometry.build(
            horizontalCount: 2, verticalCount: 2, snapshots: snapshots,
            coordinateMode: .pixel, extendOutside: false,
            bounds: bounds, transform: .identity
        )
        XCTAssertEqual(plain.vertices.count, (n + 1) * (n + 1))
        XCTAssertTrue(plain.vertices.allSatisfy {
            abs($0.position.x) <= 5.001 && abs($0.position.y) <= 5.001
        })
    }

    func testTransformAppliesToAllPoints() {
        let bounds = RectF(left: -16, top: -16, right: 16, bottom: 16)
        let result = GradientMeshGeometry.build(
            horizontalCount: 2, verticalCount: 2,
            snapshots: defaultSnapshots(),
            coordinateMode: .relative, extendOutside: false,
            bounds: bounds, transform: .translation(100, 50)
        )
        let corner = vertex(result.vertices, row: 0, column: 0)
        XCTAssertEqual(corner.position.x, 84, accuracy: 1e-4)
        XCTAssertEqual(corner.position.y, 34, accuracy: 1e-4)
    }

    func testInvalidCountsProduceNoGeometry() {
        let bounds = RectF(left: -16, top: -16, right: 16, bottom: 16)
        let result = GradientMeshGeometry.build(
            horizontalCount: 2, verticalCount: 2,
            snapshots: defaultSnapshots().dropLast().map { $0 },
            coordinateMode: .relative, extendOutside: false,
            bounds: bounds, transform: .identity
        )
        XCTAssertTrue(result.vertices.isEmpty)
        XCTAssertTrue(result.indices.isEmpty)
    }
}
#endif
