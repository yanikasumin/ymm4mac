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
