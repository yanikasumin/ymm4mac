import CoreGraphics
import XCTest

@testable import PreviewCore

/// PreviewLayout（FE-R1-022）の契約: 映像は均一倍率で描かれ、
/// 表示枠を超える分は中心で切り抜かれる（縦横比が崩れない）。
final class PreviewLayoutTests: XCTestCase {
    private func assertClose(
        _ actual: Double, _ expected: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual, expected, accuracy: 1e-9, file: file, line: line)
    }

    /// フィット表示（倍率1）: 枠 = 映像 × 領域倍率、切り抜きなし。
    func testFitLayoutHasNoCrop() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 1000, height: 800),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 1.0
        )
        assertClose(layout.uniformScale, 1.5625)
        assertClose(layout.boxSize.width, 1000)
        assertClose(layout.boxSize.height, 562.5)
        assertClose(layout.imageSize.width, layout.boxSize.width)
        assertClose(layout.imageSize.height, layout.boxSize.height)
        assertClose(layout.imageOrigin.x, 0)
        assertClose(layout.imageOrigin.y, 0)
        assertClose(layout.visibleVideoRect.minX, 0)
        assertClose(layout.visibleVideoRect.minY, 0)
        assertClose(layout.visibleVideoRect.width, 640)
        assertClose(layout.visibleVideoRect.height, 360)
    }

    /// 拡大時: 描画寸法は映像の縦横比を保ち、枠からはみ出した分は
    /// 中心で切り抜かれる（旧実装は枠へ引き伸ばして縦横比が崩れた）。
    func testZoomedLayoutKeepsAspectAndCropsCenter() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0
        )
        assertClose(layout.uniformScale, 2.5)
        assertClose(layout.boxSize.width, 800)
        assertClose(layout.boxSize.height, 600)
        // 描画寸法は均一倍率どおりで、縦横比が映像と一致する。
        assertClose(layout.imageSize.width, 1600)
        assertClose(layout.imageSize.height, 900)
        assertClose(
            layout.imageSize.width / layout.imageSize.height, 640.0 / 360.0
        )
        // 中心切り抜き: 見える範囲は映像の中央 320×240。
        assertClose(layout.imageOrigin.x, -400)
        assertClose(layout.imageOrigin.y, -150)
        assertClose(layout.visibleVideoRect.minX, 160)
        assertClose(layout.visibleVideoRect.minY, 60)
        assertClose(layout.visibleVideoRect.width, 320)
        assertClose(layout.visibleVideoRect.height, 240)
    }

    /// 縮小時: 枠 = 映像 × 倍率そのもので、切り抜きは起きない。
    func testShrunkLayoutHasNoCrop() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 0.5
        )
        assertClose(layout.uniformScale, 0.625)
        assertClose(layout.boxSize.width, 400)
        assertClose(layout.boxSize.height, 225)
        assertClose(layout.imageOrigin.x, 0)
        assertClose(layout.imageOrigin.y, 0)
    }

    // MARK: - 表示中心（FE-PREVIEW-PAN）

    /// 中心を指定しない場合は従来どおり中心切り抜き（中心 0）。
    func testViewCenterDefaultsToZero() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0
        )
        assertClose(layout.viewCenter.x, 0)
        assertClose(layout.viewCenter.y, 0)
        assertClose(layout.maxViewCenterOffset.width, 160)
        assertClose(layout.maxViewCenterOffset.height, 60)
    }

    /// 中心を動かすと可視範囲と原点がその分だけずれる。
    /// 可視範囲の中心は常に表示枠の中心へ写る。
    func testViewCenterShiftsVisibleRect() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0,
            viewCenter: CGPoint(x: 160, y: 60)
        )
        // 可視範囲は右下の隅（320×240 のうち右下）。
        assertClose(layout.visibleVideoRect.minX, 320)
        assertClose(layout.visibleVideoRect.minY, 120)
        assertClose(layout.visibleVideoRect.width, 320)
        assertClose(layout.visibleVideoRect.height, 240)
        assertClose(layout.imageOrigin.x, -800)
        assertClose(layout.imageOrigin.y, -300)
        // 可視範囲の中心 (480, 240) が表示枠の中心 (400, 300) へ写る。
        let center = layout.viewPoint(fromVideoPoint: CGPoint(x: 480, y: 240))
        assertClose(center.x, 400)
        assertClose(center.y, 300)
    }

    /// 中心は各軸 ±(映像 − 可視) / 2 へ制限される（本家
    /// ClampPreviewViewCenter）。
    func testViewCenterClampsToMaxOffset() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0,
            viewCenter: CGPoint(x: 10000, y: -10000)
        )
        assertClose(layout.viewCenter.x, 160)
        assertClose(layout.viewCenter.y, -60)
    }

    /// 倍率 1 以下では可視寸法 = 映像寸法になるため、中心は式から
    /// 自然に 0 へ固定される。
    func testViewCenterForcedZeroAtFitAndShrink() {
        for zoom in [1.0, 0.5, 0.25] {
            let layout = PreviewLayout(
                areaSize: CGSize(width: 800, height: 600),
                videoSize: CGSize(width: 640, height: 360),
                displayZoom: zoom,
                viewCenter: CGPoint(x: 50, y: 50)
            )
            assertClose(layout.viewCenter.x, 0)
            assertClose(layout.viewCenter.y, 0)
            assertClose(layout.maxViewCenterOffset.width, 0)
            assertClose(layout.maxViewCenterOffset.height, 0)
        }
    }

    /// 片軸だけ切り抜かれる形状では、切り抜かれない軸の中心は 0 に
    /// 固定され、切り抜かれる軸だけが動く。
    func testViewCenterClampsPerAxis() {
        // 領域 800×1200・映像 640×360: 幅が制限軸。倍率 2 では
        // 描画寸法 1600×900 で、枠は 800×900（縦は切り抜きなし）。
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 1200),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0,
            viewCenter: CGPoint(x: 100, y: 100)
        )
        assertClose(layout.viewCenter.x, 100)
        assertClose(layout.viewCenter.y, 0)
        assertClose(layout.maxViewCenterOffset.width, 160)
        assertClose(layout.maxViewCenterOffset.height, 0)
    }

    /// パン: 内容がカーソルへ追従する向きに中心が動き、範囲で止まる。
    func testPannedViewCenterFollowsCursorAndClamps() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0
        )
        // 均一倍率 2.5。表示座標で右へ 250・上へ 125 動かすと、
        // 中心は映像座標で (−100, +50) 動く。
        let panned = layout.pannedViewCenter(
            from: .zero, byViewDelta: CGPoint(x: 250, y: -125)
        )
        assertClose(panned.x, -100)
        assertClose(panned.y, 50)
        // 大きく動かしても可動範囲で止まる。
        let clamped = layout.pannedViewCenter(
            from: .zero, byViewDelta: CGPoint(x: 100000, y: 100000)
        )
        assertClose(clamped.x, -160)
        assertClose(clamped.y, -60)
        // 開始中心は引数側の値が正本（ドラッグ開始時の中心から解く）。
        let fromOffset = layout.pannedViewCenter(
            from: CGPoint(x: 160, y: 60), byViewDelta: CGPoint(x: -250, y: 125)
        )
        // 160 + 250/2.5 = 260 になるはずが、可動範囲で 160 に制限される。
        assertClose(fromOffset.x, 160)
        assertClose(fromOffset.y, 60 - 50)
    }

    /// カーソル固定ズーム: ズーム前後でカーソル下の映像点が同じ
    /// 領域位置に残る（枠寸法が変わらない形状）。
    func testCursorAnchoredZoomKeepsPointUnderCursor() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0
        )
        let cursor = CGPoint(x: 600, y: 450)
        let videoPoint = layout.videoPoint(fromViewPoint: cursor)
        assertClose(videoPoint.x, 400)
        assertClose(videoPoint.y, 240)
        let newCenter = layout.viewCenter(
            zoomingTo: 4.0, anchoredAtAreaPoint: cursor
        )
        assertClose(newCenter.x, 40)
        assertClose(newCenter.y, 30)
        let zoomed = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 4.0, viewCenter: newCenter
        )
        let after = zoomed.viewPoint(fromVideoPoint: videoPoint)
        assertClose(after.x, cursor.x)
        assertClose(after.y, cursor.y)
    }

    /// カーソル固定ズーム: フィットから拡大するとき、領域中心を
    /// 基準にすれば中心は 0 のまま（表示枠の寸法が変わる形状でも
    /// 領域座標で解くため一致する）。
    func testCursorAnchoredZoomFromFitAroundAreaCenter() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 1.0
        )
        let newCenter = layout.viewCenter(
            zoomingTo: 2.0, anchoredAtAreaPoint: CGPoint(x: 400, y: 300)
        )
        assertClose(newCenter.x, 0)
        assertClose(newCenter.y, 0)
    }

    /// カーソル固定ズーム: 範囲を超える場合はカーソル固定より
    /// クランプを優先する。
    func testCursorAnchoredZoomClampsAtBounds() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 4.0,
            viewCenter: CGPoint(x: 240, y: 120)
        )
        // 左上隅を固定して倍率 2 へ縮小すると、必要な中心は
        // (320, 180) で倍率 2 の可動範囲 (160, 60) を超える。
        let newCenter = layout.viewCenter(
            zoomingTo: 2.0, anchoredAtAreaPoint: CGPoint(x: 0, y: 0)
        )
        assertClose(newCenter.x, 160)
        assertClose(newCenter.y, 60)
    }

    // MARK: - スクロールバー幾何（FE-PREVIEW-PAN）

    /// つまみは可視範囲の割合と位置を表す。
    func testScrollBarGeometryReflectsVisibleFraction() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0
        )
        XCTAssertTrue(layout.hasHorizontalScrollBar)
        XCTAssertTrue(layout.hasVerticalScrollBar)
        let horizontal = layout.horizontalScrollBarGeometry(trackLength: 800)
        XCTAssertNotNil(horizontal)
        assertClose(horizontal!.thumbOffset, 200)
        assertClose(horizontal!.thumbLength, 400)
        let vertical = layout.verticalScrollBarGeometry(trackLength: 600)
        XCTAssertNotNil(vertical)
        assertClose(vertical!.thumbOffset, 100)
        assertClose(vertical!.thumbLength, 400)
    }

    /// バーは倍率 1 以下では出ず、切り抜かれていない軸にも出ない。
    func testScrollBarAbsentWhenNotCropped() {
        let fit = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 1.0
        )
        XCTAssertFalse(fit.hasHorizontalScrollBar)
        XCTAssertFalse(fit.hasVerticalScrollBar)
        XCTAssertNil(fit.horizontalScrollBarGeometry(trackLength: 800))
        // 縦が切り抜かれない形状では縦バーだけ出ない。
        let wide = PreviewLayout(
            areaSize: CGSize(width: 800, height: 1200),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0
        )
        XCTAssertTrue(wide.hasHorizontalScrollBar)
        XCTAssertFalse(wide.hasVerticalScrollBar)
        XCTAssertNil(wide.verticalScrollBarGeometry(trackLength: 600))
    }

    /// つまみ位置からの逆算は、幾何との間で往復が一致し、端では
    /// 中心の可動範囲の端に一致する。
    func testScrollBarThumbOffsetRoundTripsToCenter() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0,
            viewCenter: CGPoint(x: 80, y: 30)
        )
        let geometry = layout.horizontalScrollBarGeometry(trackLength: 800)!
        let restored = layout.viewCenter(
            forHorizontalScrollBarThumbOffset: geometry.thumbOffset,
            trackLength: 800
        )
        assertClose(restored.x, 80)
        assertClose(restored.y, 30)
        // トラックの両端 = 中心の可動範囲の両端。
        let atStart = layout.viewCenter(
            forHorizontalScrollBarThumbOffset: 0, trackLength: 800
        )
        assertClose(atStart.x, -160)
        let atEnd = layout.viewCenter(
            forHorizontalScrollBarThumbOffset: 800 - geometry.thumbLength,
            trackLength: 800
        )
        assertClose(atEnd.x, 160)
    }

    /// 座標変換の往復と、枠中心が映像中心に対応すること。
    func testPointConversionRoundTrips() {
        let layout = PreviewLayout(
            areaSize: CGSize(width: 800, height: 600),
            videoSize: CGSize(width: 640, height: 360),
            displayZoom: 2.0
        )
        let center = layout.viewPoint(
            fromVideoPoint: CGPoint(x: 320, y: 180)
        )
        assertClose(center.x, 400)
        assertClose(center.y, 300)
        for point in [
            CGPoint(x: 0, y: 0), CGPoint(x: 160, y: 60),
            CGPoint(x: 479.5, y: 299.25), CGPoint(x: 640, y: 360),
        ] {
            let roundTripped = layout.videoPoint(
                fromViewPoint: layout.viewPoint(fromVideoPoint: point)
            )
            assertClose(roundTripped.x, point.x)
            assertClose(roundTripped.y, point.y)
        }
    }
}
