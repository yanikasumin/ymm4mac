import CoreGraphics
import XCTest

@testable import PreviewCore

/// PreviewItemRect.frontmostIndex（FE-R1-023-A）: 重なりの選択は
/// 実際の描画順（drawOrder）に従い、除外されたアイテムは候補に
/// 入らない。監査の検証条件（背面と前面が重なる場合に描画順で
/// 選択すること）に対応する。
final class PreviewItemRectTests: XCTestCase {
    private func rect(
        _ itemIndex: Int, _ bounds: CGRect, _ drawOrder: Int
    ) -> PreviewItemRect {
        PreviewItemRect(itemIndex: itemIndex, bounds: bounds, drawOrder: drawOrder)
    }

    /// 重なりでは前面（drawOrder が大きい方）が選ばれる。
    func testFrontmostWinsOnOverlap() {
        let rects = [
            rect(0, CGRect(x: 0, y: 0, width: 200, height: 200), 0),
            rect(1, CGRect(x: 100, y: 100, width: 200, height: 200), 1),
        ]
        XCTAssertEqual(
            PreviewItemRect.frontmostIndex(in: rects, at: CGPoint(x: 150, y: 150)), 1
        )
        // 重ならない部分では背面側が選ばれる。
        XCTAssertEqual(
            PreviewItemRect.frontmostIndex(in: rects, at: CGPoint(x: 50, y: 50)), 0
        )
    }

    /// 除外されたアイテム（ロック中など）は、前面でも選ばれず、
    /// 背面側へ落ちる。
    func testExcludedItemIsSkipped() {
        let rects = [
            rect(0, CGRect(x: 0, y: 0, width: 200, height: 200), 0),
            rect(1, CGRect(x: 100, y: 100, width: 200, height: 200), 1),
        ]
        XCTAssertEqual(
            PreviewItemRect.frontmostIndex(
                in: rects, at: CGPoint(x: 150, y: 150), isExcluded: { $0 == 1 }
            ),
            0
        )
    }

    /// 描画順が同点の場合は、インデックスが大きい方を前面とする。
    func testDrawOrderTieBreaksByLargerIndex() {
        let rects = [
            rect(3, CGRect(x: 0, y: 0, width: 100, height: 100), 0),
            rect(5, CGRect(x: 0, y: 0, width: 100, height: 100), 0),
        ]
        XCTAssertEqual(
            PreviewItemRect.frontmostIndex(in: rects, at: CGPoint(x: 50, y: 50)), 5
        )
    }

    /// どの矩形にも含まれない点・空の列では nil。
    func testNoHitReturnsNil() {
        let rects = [
            rect(0, CGRect(x: 0, y: 0, width: 100, height: 100), 0),
        ]
        XCTAssertNil(
            PreviewItemRect.frontmostIndex(in: rects, at: CGPoint(x: 500, y: 500))
        )
        XCTAssertNil(
            PreviewItemRect.frontmostIndex(in: [], at: CGPoint(x: 0, y: 0))
        )
    }

    // MARK: - 四角形による当たり判定（FE-R1-023-B）

    private func quadRect(
        _ itemIndex: Int, _ bounds: CGRect, _ drawOrder: Int, _ quad: [CGPoint]
    ) -> PreviewItemRect {
        PreviewItemRect(
            itemIndex: itemIndex, bounds: bounds, drawOrder: drawOrder, quad: quad
        )
    }

    /// 回転したアイテム（ダイヤ型の四角形）では、外接矩形の四隅
    /// 付近（絵の無い余白）は当たらず、背面のアイテムが選ばれる。
    /// 中心は前面のダイヤが選ばれる。
    func testFrontmostUsesQuadNotBounds() {
        let diamond = [
            CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 100),
            CGPoint(x: 100, y: 200), CGPoint(x: 0, y: 100),
        ]
        let rects = [
            rect(0, CGRect(x: 0, y: 0, width: 200, height: 200), 0),
            quadRect(1, CGRect(x: 0, y: 0, width: 200, height: 200), 1, diamond),
        ]
        // ダイヤの中心は前面（drawOrder 1）。
        XCTAssertEqual(
            PreviewItemRect.frontmostIndex(in: rects, at: CGPoint(x: 100, y: 100)), 1
        )
        // 外接矩形の隅（ダイヤの外）は背面（drawOrder 0）へ落ちる。
        XCTAssertEqual(
            PreviewItemRect.frontmostIndex(in: rects, at: CGPoint(x: 10, y: 10)), 0
        )
    }

    /// 境界上の点は内側として扱う（本家 IsPointInQuad は外積 0 の
    /// 辺を符号判定から外すため、境界は含まれる）。
    func testPointOnQuadEdgeIsInside() {
        let diamond = [
            CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 100),
            CGPoint(x: 100, y: 200), CGPoint(x: 0, y: 100),
        ]
        let item = quadRect(0, CGRect(x: 0, y: 0, width: 200, height: 200), 0, diamond)
        // 辺 (0,100)-(100,0) の中点。
        XCTAssertTrue(item.contains(CGPoint(x: 50, y: 50)))
        // 頂点そのもの。
        XCTAssertTrue(item.contains(CGPoint(x: 100, y: 0)))
    }

    /// 透視で歪んだ台形: 上辺が短く下辺が長い四角形では、上辺
    /// 付近の左右は外側、下部中央は内側。
    func testPerspectiveTrapezoid() {
        let trapezoid = [
            CGPoint(x: 40, y: 0), CGPoint(x: 160, y: 0),
            CGPoint(x: 200, y: 200), CGPoint(x: 0, y: 200),
        ]
        let item = quadRect(
            0, CGRect(x: 0, y: 0, width: 200, height: 200), 0, trapezoid
        )
        XCTAssertTrue(item.contains(CGPoint(x: 100, y: 100)))
        XCTAssertFalse(item.contains(CGPoint(x: 10, y: 10)))
        // 上辺の上（y < 0）は外側。
        XCTAssertFalse(item.contains(CGPoint(x: 100, y: -1)))
    }

    /// 四角形が1点に潰れている場合は、四隅の外接矩形（その点
    /// 自身）で判定するフォールバックになる（本家の規則）。
    func testDegenerateQuadFallsBackToBoundingBox() {
        let point = CGPoint(x: 50, y: 50)
        let item = quadRect(
            0, CGRect(x: 0, y: 0, width: 100, height: 100), 0,
            [point, point, point, point]
        )
        XCTAssertTrue(item.contains(point))
        XCTAssertFalse(item.contains(CGPoint(x: 51, y: 50)))
    }

    /// 四隅が与えられない場合は矩形の四隅で代替され、右辺・下辺を
    /// 含めて判定する（本家の矩形フォールバックは両端を含む。
    /// CGRect.contains の最大辺排他とは異なる）。
    func testDefaultQuadIncludesMaxEdges() {
        let item = rect(0, CGRect(x: 0, y: 0, width: 100, height: 100), 0)
        XCTAssertTrue(item.contains(CGPoint(x: 100, y: 50)))
        XCTAssertTrue(item.contains(CGPoint(x: 50, y: 100)))
        XCTAssertFalse(item.contains(CGPoint(x: 101, y: 50)))
    }
}
