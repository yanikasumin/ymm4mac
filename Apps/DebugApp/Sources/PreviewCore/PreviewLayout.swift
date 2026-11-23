import CoreGraphics

/// プレビューの表示寸法と座標変換（FE-R1-022、FE-PREVIEW-PAN）。
///
/// 本家の規則（PreviewViewModel + TimelineVideoPlayer）:
/// - 領域倍率 AreaZoom = min(領域幅/映像幅, 領域高/映像高)。
/// - 表示枠は min(領域, 映像 × AreaZoom × 表示倍率) を幅・高さ
///   独立に取る（本家 PreviewWidth / PreviewHeight の式そのまま）。
/// - 映像そのものは均一倍率（AreaZoom × 表示倍率）で描き、枠より
///   大きい分は切り抜く（本家 GetVisibleVideoSize /
///   CreatePreviewViewTransform）。枠へ引き伸ばして合わせると
///   縦横比が崩れるため、描画寸法と座標変換はこの均一倍率を正本に
///   する。
/// - 表示中心のオフセット（viewCenter）は映像中心からのずれ
///   （映像座標）で、本家 ClampPreviewViewCenter どおり各軸
///   ±(映像寸法 − 可視寸法) / 2 へ制限する。可視寸法は
///   表示枠 / 均一倍率であり、本家 GetVisibleVideoSize と一致する。
///   倍率が 1 以下では表示枠 = 描画寸法になって可視寸法 = 映像寸法
///   になるため、中心は式から自然に 0 へ固定される。
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
    /// プレビュー領域の寸法（入力値）。
    public var areaSize: CGSize
    /// 表示倍率（入力値。フィット倍率への乗数）。
    public var displayZoom: Double
    /// 表示中心のオフセット（映像座標、映像中心からのずれ）。
    /// init でクランプ済みの値が入る。
    public var viewCenter: CGPoint

    public init(
        areaSize: CGSize, videoSize: CGSize, displayZoom: Double,
        viewCenter: CGPoint = .zero
    ) {
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
        self.videoSize = CGSize(width: videoWidth, height: videoHeight)
        self.areaSize = areaSize
        self.displayZoom = displayZoom
        let clampedCenter = Self.clampViewCenter(
            viewCenter,
            videoSize: self.videoSize,
            visibleVideoSize: CGSize(
                width: boxWidth / scale, height: boxHeight / scale
            )
        )
        self.viewCenter = clampedCenter
        self.imageOrigin = CGPoint(
            x: (boxWidth - videoWidth * scale) / 2 - clampedCenter.x * scale,
            y: (boxHeight - videoHeight * scale) / 2 - clampedCenter.y * scale
        )
    }

    /// 本家 ClampPreviewViewCenter: 各軸 ±(映像 − 可視) / 2 へ制限する。
    private static func clampViewCenter(
        _ center: CGPoint, videoSize: CGSize, visibleVideoSize: CGSize
    ) -> CGPoint {
        let maxX = max(0, (videoSize.width - visibleVideoSize.width) / 2)
        let maxY = max(0, (videoSize.height - visibleVideoSize.height) / 2)
        return CGPoint(
            x: min(max(center.x, -maxX), maxX),
            y: min(max(center.y, -maxY), maxY)
        )
    }

    /// このレイアウトの形状での中心オフセットの可動範囲（各軸の上限。
    /// 下限はその符号反転）。
    public var maxViewCenterOffset: CGSize {
        let visible = visibleVideoRect
        return CGSize(
            width: max(0, (videoSize.width - visible.width) / 2),
            height: max(0, (videoSize.height - visible.height) / 2)
        )
    }

    /// 候補となる中心を、このレイアウトの形状の範囲へ制限する。
    public func clampedViewCenter(_ proposed: CGPoint) -> CGPoint {
        Self.clampViewCenter(
            proposed, videoSize: videoSize, visibleVideoSize: visibleVideoRect.size
        )
    }

    /// パン（表示内容を掴んで動かす）後の中心。内容がカーソルへ
    /// 追従するよう、中心は表示座標の移動量を均一倍率で割った分だけ
    /// 逆向きに動く（本家の中ボタンドラッグの式
    /// 「中心 = 開始中心 − Δfit / 表示倍率」と等価。Δfit は
    /// 領域倍率で割った移動量のため、均一倍率で割る形になる）。
    public func pannedViewCenter(
        from base: CGPoint, byViewDelta delta: CGPoint
    ) -> CGPoint {
        clampedViewCenter(CGPoint(
            x: base.x - delta.x / uniformScale,
            y: base.y - delta.y / uniformScale
        ))
    }

    /// カーソル位置を固定するズームでの新しい中心（純粋計算。
    /// 入力の接続は FE-ZOOM-INPUT で PreviewZoomControls が担い、
    /// 倍率への換算は PreviewZoomInput が担う）。
    ///
    /// 基準点はプレビュー領域座標で受ける。ズーム前後で表示枠の
    /// 寸法が変わっても（フィット境界を跨ぐ場合）、領域内での
    /// 表示枠の位置（中央寄せ）から双方の枠座標へ直して解くため、
    /// 「ズーム前にカーソルの下にあった映像上の点が、ズーム後も
    /// 同じ領域位置に来る」中心が得られる。クランプ範囲を超える
    /// 場合は、カーソル固定より範囲内に収めることを優先する
    /// （本家 ZoomPreviewArea も中心の設定時にクランプされる）。
    public func viewCenter(
        zoomingTo newZoom: Double, anchoredAtAreaPoint areaPoint: CGPoint
    ) -> CGPoint {
        let videoPoint = videoPoint(
            fromViewPoint: CGPoint(
                x: areaPoint.x - boxOriginInArea.x,
                y: areaPoint.y - boxOriginInArea.y
            )
        )
        let base = PreviewLayout(
            areaSize: areaSize, videoSize: videoSize, displayZoom: newZoom
        )
        let newScale = base.uniformScale
        let localPoint = CGPoint(
            x: areaPoint.x - base.boxOriginInArea.x,
            y: areaPoint.y - base.boxOriginInArea.y
        )
        // 新レイアウトで viewPoint(fromVideoPoint: videoPoint) が
        // localPoint に一致する中心を解く:
        // localPoint = base.imageOrigin − center × newScale
        //              + videoPoint × newScale
        let candidate = CGPoint(
            x: videoPoint.x + (base.imageOrigin.x - localPoint.x) / newScale,
            y: videoPoint.y + (base.imageOrigin.y - localPoint.y) / newScale
        )
        return PreviewLayout(
            areaSize: areaSize, videoSize: videoSize,
            displayZoom: newZoom, viewCenter: candidate
        ).viewCenter
    }

    /// プレビュー領域内での表示枠の原点（表示枠は領域の中央に置かれる）。
    private var boxOriginInArea: CGPoint {
        CGPoint(
            x: (areaSize.width - boxSize.width) / 2,
            y: (areaSize.height - boxSize.height) / 2
        )
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

    // MARK: - スクロールバー幾何

    /// スクロールバーのつまみの形状（トラック座標。単位はポイント）。
    public struct ScrollBarGeometry: Equatable, Sendable {
        /// トラック先頭からつまみ開始位置までの距離。
        public var thumbOffset: Double
        /// つまみの長さ。
        public var thumbLength: Double

        public init(thumbOffset: Double, thumbLength: Double) {
            self.thumbOffset = thumbOffset
            self.thumbLength = thumbLength
        }
    }

    /// 横スクロールバーを出すか。本家 DrawPreviewScrollBars の条件
    /// どおり、表示倍率が 1 より大きく、その軸が切り抜かれている
    /// （可視寸法 < 映像寸法）場合だけ出す。
    public var hasHorizontalScrollBar: Bool {
        displayZoom > 1 && visibleVideoRect.width < videoSize.width
    }

    /// 縦スクロールバーを出すか（条件は横と対称）。
    public var hasVerticalScrollBar: Bool {
        displayZoom > 1 && visibleVideoRect.height < videoSize.height
    }

    /// 横スクロールバーのつまみ形状。トラック長（ポイント）に対して、
    /// つまみは可視範囲の映像全体に対する割合と位置を表す
    /// （本家 GetPreviewScrollBarThumbRectX の意味論を表示枠座標へ
    /// 写したもの）。
    public func horizontalScrollBarGeometry(
        trackLength: Double
    ) -> ScrollBarGeometry? {
        guard hasHorizontalScrollBar, trackLength > 0 else { return nil }
        let visible = visibleVideoRect
        return ScrollBarGeometry(
            thumbOffset: visible.minX / videoSize.width * trackLength,
            thumbLength: visible.width / videoSize.width * trackLength
        )
    }

    /// 縦スクロールバーのつまみ形状（横と対称）。
    public func verticalScrollBarGeometry(
        trackLength: Double
    ) -> ScrollBarGeometry? {
        guard hasVerticalScrollBar, trackLength > 0 else { return nil }
        let visible = visibleVideoRect
        return ScrollBarGeometry(
            thumbOffset: visible.minY / videoSize.height * trackLength,
            thumbLength: visible.height / videoSize.height * trackLength
        )
    }

    /// 横スクロールバーのつまみ位置から逆算した中心（つまみの
    /// ドラッグと、トラッククリックでのジャンプの共通の受け口。
    /// ジャンプは呼び出し側が「つまみ中心 = クリック位置」になる
    /// オフセットを渡す。本家 GetPreviewScrollBarJumpViewCenter が
    /// クリック位置へつまみを中心寄せする挙動と一致する）。
    public func viewCenter(
        forHorizontalScrollBarThumbOffset offset: Double, trackLength: Double
    ) -> CGPoint {
        guard trackLength > 0 else { return viewCenter }
        let visible = visibleVideoRect
        let newMinX = offset / trackLength * videoSize.width
        return clampedViewCenter(CGPoint(
            x: newMinX + visible.width / 2 - videoSize.width / 2,
            y: viewCenter.y
        ))
    }

    /// 縦スクロールバーのつまみ位置から逆算した中心（横と対称）。
    public func viewCenter(
        forVerticalScrollBarThumbOffset offset: Double, trackLength: Double
    ) -> CGPoint {
        guard trackLength > 0 else { return viewCenter }
        let visible = visibleVideoRect
        let newMinY = offset / trackLength * videoSize.height
        return clampedViewCenter(CGPoint(
            x: viewCenter.x,
            y: newMinY + visible.height / 2 - videoSize.height / 2
        ))
    }
}
