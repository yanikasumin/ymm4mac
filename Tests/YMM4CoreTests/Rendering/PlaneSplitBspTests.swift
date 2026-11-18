import XCTest

@testable import YMM4Core

/// 平面分割（BSP）本体の試験。本家 PlaneSplitBsp の規則（視点
/// (0,0,1000)、許容誤差 0.01、断片上限 256）に対する幾何ケースで、
/// 順序付けの要否・断片列・切断・マスク多角形を検証する。
final class PlaneSplitBspTests: XCTestCase {
    private let ordering = PlaneSplitBspOrdering()

    /// 視点に正対する平面 z=0 の四隅。
    private func flatQuad(z: Double = 0, half: Double = 50) -> [Vector3] {
        [
            Vector3(x: -half, y: -half, z: z),
            Vector3(x: half, y: -half, z: z),
            Vector3(x: half, y: half, z: z),
            Vector3(x: -half, y: half, z: z),
        ]
    }

    /// 平面 z=x（Y 軸まわりに傾き、z=0 の平面と交わる）の四隅。
    private func tiltedQuad() -> [Vector3] {
        [
            Vector3(x: -50, y: -50, z: -50),
            Vector3(x: 50, y: -50, z: 50),
            Vector3(x: 50, y: 50, z: 50),
            Vector3(x: -50, y: 50, z: -50),
        ]
    }

    /// 交わる組は順序付けが必要。
    func testRequiresOrderingForCrossingPair() {
        XCTAssertTrue(ordering.requiresOrdering(flatQuad(), tiltedQuad()))
    }

    /// 同一平面の組は順序付け不要（本家は共面を除外する）。
    func testRequiresOrderingFalseForCoplanar() {
        let shifted = flatQuad().map { Vector3(x: $0.x + 20, y: $0.y, z: 0) }
        XCTAssertFalse(ordering.requiresOrdering(flatQuad(), shifted))
    }

    /// 画面範囲が重ならない組は順序付け不要。
    func testRequiresOrderingFalseForSeparated() {
        let far = tiltedQuad().map { Vector3(x: $0.x + 500, y: $0.y, z: $0.z) }
        XCTAssertFalse(ordering.requiresOrdering(flatQuad(), far))
    }

    /// 交わる2枚: 傾いた方が平面で2断片に割れ、奥→手前の順に並ぶ。
    func testSortSplitsCrossingQuad() throws {
        let fragments = try XCTUnwrap(ordering.sort(quads: [flatQuad(), tiltedQuad()]))
        XCTAssertEqual(fragments.count, 3)
        // 奥（z<0 側の断片）→ 平面の四隅 → 手前（z>0 側の断片）。
        XCTAssertEqual(fragments[0].resourceIndex, 1)
        XCTAssertTrue(fragments[0].hasCuts)
        XCTAssertEqual(fragments[1].resourceIndex, 0)
        XCTAssertFalse(fragments[1].hasCuts)
        XCTAssertEqual(fragments[2].resourceIndex, 1)
        XCTAssertTrue(fragments[2].hasCuts)
        // 割れた断片は切断（x=0 の線分）を持ち、頂点は4つ。
        for fragment in [fragments[0], fragments[2]] {
            XCTAssertEqual(fragment.vertices.count, 4)
            XCTAssertEqual(fragment.cuts.count, 1)
            for cut in fragment.cuts {
                XCTAssertEqual(cut.a.x, 0, accuracy: 1e-4)
                XCTAssertEqual(cut.b.x, 0, accuracy: 1e-4)
            }
        }
        // 奥の断片は z<=0、手前は z>=0 の範囲にある。
        XCTAssertTrue(fragments[0].vertices.allSatisfy { $0.z <= 1e-4 })
        XCTAssertTrue(fragments[2].vertices.allSatisfy { $0.z >= -1e-4 })
    }

    /// 交わらない2枚（手前 z=100 と奥 z=-100）は奥から並ぶ。
    func testSortOrdersBackToFront() throws {
        let fragments = try XCTUnwrap(
            ordering.sort(quads: [flatQuad(z: 100), flatQuad(z: -100)])
        )
        XCTAssertEqual(fragments.map(\.resourceIndex), [1, 0])
        XCTAssertTrue(fragments.allSatisfy { !$0.hasCuts })
    }

    /// 平面をなさない四隅（同一直線状）は順序付けを諦める（nil）。
    func testSortReturnsNilForDegenerateQuad() {
        let degenerate = [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 10, y: 0, z: 0),
            Vector3(x: 20, y: 0, z: 0),
            Vector3(x: 30, y: 0, z: 0),
        ]
        XCTAssertNil(ordering.sort(quads: [degenerate, flatQuad()]))
    }

    /// マスク多角形: x=0 の切断で画面右半分に切り取られる。
    func testScreenMaskPolygonClipsToFragmentSide() throws {
        let fragment = PlaneSplitFragment(
            resourceIndex: 1,
            vertices: [
                Vector3(x: 0, y: -50, z: 0),
                Vector3(x: 50, y: -50, z: 50),
                Vector3(x: 50, y: 50, z: 50),
                Vector3(x: 0, y: 50, z: 0),
            ],
            cuts: [PlaneSplitCut(
                a: Vector3(x: 0, y: -50, z: 0),
                b: Vector3(x: 0, y: 50, z: 0)
            )]
        )
        let polygon = try XCTUnwrap(planeSplitScreenMaskPolygon(
            fragment: fragment, boundsMin: (-100, -100), boundsMax: (100, 100)
        ))
        XCTAssertEqual(polygon.count, 4)
        XCTAssertTrue(polygon.allSatisfy { $0.x >= -1e-4 })
        XCTAssertTrue(polygon.contains { abs($0.x - 100) < 1e-3 && abs($0.y - 100) < 1e-3 })
        XCTAssertTrue(polygon.contains { abs($0.x) < 1e-3 && abs($0.y + 100) < 1e-3 })
    }
}
