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
}
