import XCTest

@testable import PreviewCore

/// PreviewZoomInput（FE-ZOOM-INPUT）の契約: ホイールは本家
/// ZoomPreviewArea の 1.2 べき換算、制限は本家
/// ClampPreviewDisplayZoom（下限 1、上限は画面倍率 8 を領域倍率で
/// 割ったもの）。ピンチは Mac 側の設計（倍率 × (1 + 拡大率)）に
/// 同じ制限を適用する。
final class PreviewZoomInputTests: XCTestCase {
    private func assertClose(
        _ actual: Double, _ expected: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual, expected, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: - ホイール（本家 ZoomPreviewArea）

    /// 1 ノッチ（Delta 120）で ×1.2、逆向きで ÷1.2。
    func testWheelOneNotchStepsByFactor() {
        assertClose(
            PreviewZoomInput.zoom(current: 2, wheelDelta: 120, areaZoom: 1),
            2.4
        )
        assertClose(
            PreviewZoomInput.zoom(current: 2, wheelDelta: -120, areaZoom: 1),
            2.0 / 1.2
        )
    }

    /// Delta は指数へ線形に入る（2 ノッチ = ×1.2²、半ノッチ = ×√1.2）。
    func testWheelDeltaScalesExponent() {
        assertClose(
            PreviewZoomInput.zoom(current: 1, wheelDelta: 240, areaZoom: 1),
            1.44
        )
        assertClose(
            PreviewZoomInput.zoom(current: 1, wheelDelta: 60, areaZoom: 1),
            sqrt(1.2)
        )
        assertClose(
            PreviewZoomInput.zoom(current: 3, wheelDelta: 0, areaZoom: 1),
            3
        )
    }

    /// 上限は画面倍率 8: 領域倍率 0.5 では表示倍率 16、領域倍率 2
    /// では表示倍率 4 が上限になる。
    func testWheelClampsAtScreenZoomLimit() {
        assertClose(
            PreviewZoomInput.zoom(current: 15, wheelDelta: 120, areaZoom: 0.5),
            16
        )
        assertClose(
            PreviewZoomInput.zoom(current: 3.9, wheelDelta: 120, areaZoom: 2),
            4
        )
        // 既に上限なら動かない。
        assertClose(
            PreviewZoomInput.zoom(current: 8, wheelDelta: 120, areaZoom: 1),
            8
        )
    }

    /// 下限は 1（フィット）。1 からは縮小しない。
    func testWheelClampsAtFitLowerBound() {
        assertClose(
            PreviewZoomInput.zoom(current: 1.1, wheelDelta: -120, areaZoom: 1),
            1
        )
        assertClose(
            PreviewZoomInput.zoom(current: 1, wheelDelta: -120, areaZoom: 1),
            1
        )
    }

    // MARK: - ピンチ（Mac 側の設計）

    /// 倍率 × (1 + magnification)。制限はホイールと同じ。
    func testPinchScalesDirectlyAndClamps() {
        assertClose(
            PreviewZoomInput.zoom(current: 2, magnification: 0.5, areaZoom: 1),
            3
        )
        assertClose(
            PreviewZoomInput.zoom(current: 4, magnification: -0.5, areaZoom: 1),
            2
        )
        // 縮小し過ぎても下限 1 で止まる。
        assertClose(
            PreviewZoomInput.zoom(current: 4, magnification: -0.9, areaZoom: 1),
            1
        )
        // 上限も同じ（領域倍率 1 では表示倍率 8）。
        assertClose(
            PreviewZoomInput.zoom(current: 6, magnification: 1, areaZoom: 1),
            8
        )
    }

    // MARK: - 制限そのもの（本家 ClampPreviewDisplayZoom）

    func testClampedZoom() {
        assertClose(PreviewZoomInput.clampedZoom(0.5, areaZoom: 1), 1)
        assertClose(PreviewZoomInput.clampedZoom(100, areaZoom: 1), 8)
        assertClose(PreviewZoomInput.clampedZoom(100, areaZoom: 0.25), 32)
        // 領域倍率が 1 より大きい（映像が領域より小さい）場合は
        // 上限が max(1, 8 / 領域倍率) になる。
        assertClose(PreviewZoomInput.clampedZoom(5, areaZoom: 4), 2)
        assertClose(PreviewZoomInput.clampedZoom(3, areaZoom: 1), 3)
    }

    // MARK: - 表示倍率 1 未満の状態（Mac 側の補正）

    /// ピッカー経由でのみ到達する 1 未満では、縮小操作で倍率が
    /// 上がる逆転を起こさず、拡大操作は 1 を上限に近づく。
    func testSubFitStateDoesNotInvert() {
        assertClose(
            PreviewZoomInput.zoom(current: 0.5, wheelDelta: -120, areaZoom: 1),
            0.5
        )
        assertClose(
            PreviewZoomInput.zoom(current: 0.5, wheelDelta: 120, areaZoom: 1),
            0.6
        )
        assertClose(
            PreviewZoomInput.zoom(current: 0.25, magnification: 10, areaZoom: 1),
            1
        )
        // 1 に到達した後は本家の制限どおりに振る舞う。
        assertClose(
            PreviewZoomInput.zoom(current: 1, wheelDelta: 120, areaZoom: 1),
            1.2
        )
    }
}
