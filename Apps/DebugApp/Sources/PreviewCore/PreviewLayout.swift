import CoreGraphics

/// プレビューの表示寸法と座標変換（FE-R1-022）。
///
/// 本家の規則（PreviewViewModel + TimelineVideoPlayer）:
/// - 領域倍率 AreaZoom = min(領域幅/映像幅, 領域高/映像高)。
/// - 表示枠は min(領域, 映像 × AreaZoom × 表示倍率) を幅・高さ
///   独立に取る（本家 PreviewWidth / PreviewHeight の式そのまま）。
/// - 映像そのものは均一倍率（AreaZoom × 表示倍率）で描き、枠より
///   大きい分は中心で切り抜く（本家 GetVisibleVideoSize /
///   CreatePreviewViewTransform）。枠へ引き伸ばして合わせると
///   縦横比が崩れるため、描画寸法と座標変換はこの均一倍率を正本に
///   する。
public struct PreviewLayout: Equatable, Sendable {
    /// 表示枠の寸法（プレビュー領域内に収まる大きさ）。
    public var boxSize: CGSize
    /// 映像の描画寸法（均一倍率を掛けた実寸。枠より大きいことがある）。
    public var imageSize: CGSize
    /// 均一倍率（映像座標 → 表示座標）。
    public var uniformScale: Double
    /// 表示枠内での映像原点（映像座標 (0,0)）の位置。
    /// 切り抜きが発生する場合は負になる。
    public var imageOrigin: CGPoint
    /// 映像の寸法。
    public var videoSize: CGSize

    public init(areaSize: CGSize, videoSize: CGSize, displayZoom: Double) {
        let videoWidth = max(videoSize.width, 1)
        let videoHeight = max(videoSize.height, 1)
        let areaScale = min(
            areaSize.width / videoWidth, areaSize.height / videoHeight
        )
        let scale = areaScale * displayZoom
        let boxWidth = min(areaSize.width, videoWidth * scale)
        let boxHeight = min(areaSize.height, videoHeight * scale)
        self.boxSize = CGSize(width: boxWidth, height: boxHeight)
        self.imageSize = CGSize(width: videoWidth * scale, height: videoHeight * scale)
        self.uniformScale = scale
        self.imageOrigin = CGPoint(
            x: (boxWidth - videoWidth * scale) / 2,
            y: (boxHeight - videoHeight * scale) / 2
        )
        self.videoSize = CGSize(width: videoWidth, height: videoHeight)
    }

    /// 映像座標 → 表示枠内の座標。
    public func viewPoint(fromVideoPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageOrigin.x + point.x * uniformScale,
            y: imageOrigin.y + point.y * uniformScale
        )
    }

    /// 表示枠内の座標 → 映像座標。
    public func videoPoint(fromViewPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - imageOrigin.x) / uniformScale,
            y: (point.y - imageOrigin.y) / uniformScale
        )
    }

    /// 表示枠内で見えている映像範囲（映像座標）。
    public var visibleVideoRect: CGRect {
        CGRect(
            x: -imageOrigin.x / uniformScale,
            y: -imageOrigin.y / uniformScale,
            width: boxSize.width / uniformScale,
            height: boxSize.height / uniformScale
        )
    }
}
