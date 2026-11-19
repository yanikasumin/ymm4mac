import Foundation

/// プレビューの連続ズーム入力（ホイール／ピンチ）から表示倍率への
/// 換算（FE-ZOOM-INPUT）。幾何（カーソル固定の中心計算）は
/// PreviewLayout.viewCenter(zoomingTo:anchoredAtAreaPoint:) が正本で、
/// 本型は「入力の量 → 新しい表示倍率」だけを担う純粋計算である。
///
/// 本家の規則（TimelineVideoPlayer.cs の ZoomPreviewArea /
/// ClampPreviewDisplayZoom / ShouldZoomPreviewArea で確認）:
/// - ホイール: 新倍率 = 現在倍率 × 1.2^(Delta / 120)。Delta 120 が
///   1 ノッチで、コマンドの拡大／縮小（PreviewViewModel の
///   ZoomInPreview / ZoomOutPreview）も同じ ×1.2 / ÷1.2 を使う。
/// - 制限: 表示倍率は [1, max(1, 8 / 領域倍率)]。上限 8 は
///   画面倍率（領域倍率 × 表示倍率）の上限 MaxPreviewScreenZoom。
///   下限 1 は「フィットより縮小しない」であり、設定時にも同じ
///   制限が掛かる（PreviewDisplayZoom のセッタ）。
/// - ズームする入力の判定（Ctrl + タッチパッドでないホイール）自体は
///   入力の受け口（アプリ層）の責務で、本型は扱わない。
///
/// ピンチは本家に無い（TimelineVideoPlayer にタッチ操作の処理は
/// 無い）ため、Mac の標準的な振る舞いとして「倍率 × (1 + 拡大率)」
/// で換算し、制限はホイールと同じものを適用する。
public enum PreviewZoomInput {
    /// 画面倍率（領域倍率 × 表示倍率）の上限（本家
    /// MaxPreviewScreenZoom）。
    public static let maximumScreenZoom = 8.0
    /// ホイール 1 ノッチあたりの倍率変化（本家 ZoomPreviewArea の
    /// 1.2 べき）。
    public static let wheelStepFactor = 1.2
    /// ホイール Delta の 1 ノッチ分（Windows のホイール単位）。
    /// Mac のマウスホイールは 1 ノッチ = deltaY 1 行のため、受け口は
    /// 行数 × 本値を本家単位の Delta として渡す。
    public static let wheelDeltaPerNotch = 120.0

    /// 本家 ClampPreviewDisplayZoom: 表示倍率を
    /// [1, max(1, 画面上限 / 領域倍率)] へ制限する。領域倍率が
    /// 正でない場合は上限を 1 とみなす（実レイアウトでは領域倍率は
    /// 常に正）。
    public static func clampedZoom(_ zoom: Double, areaZoom: Double) -> Double {
        let upper = areaZoom > 0
            ? max(1.0, maximumScreenZoom / areaZoom)
            : 1.0
        return min(max(zoom, 1.0), upper)
    }

    /// ホイールによる新しい表示倍率（本家 ZoomPreviewArea の倍率計算
    /// そのもの: 現在倍率 × 1.2^(Delta / 120) を制限内に収める）。
    public static func zoom(
        current: Double, wheelDelta: Double, areaZoom: Double
    ) -> Double {
        let candidate = current
            * pow(wheelStepFactor, wheelDelta / wheelDeltaPerNotch)
        return resolvedZoom(
            current: current, candidate: candidate, areaZoom: areaZoom
        )
    }

    /// ピンチによる新しい表示倍率（Mac 側の設計: 倍率 ×
    /// (1 + magnification)。magnification は NSEvent の拡大率で、
    /// ピンチアウトが正）。
    public static func zoom(
        current: Double, magnification: Double, areaZoom: Double
    ) -> Double {
        let candidate = current * (1 + magnification)
        return resolvedZoom(
            current: current, candidate: candidate, areaZoom: areaZoom
        )
    }

    /// 候補倍率へ制限を適用する。本家の表示倍率の定義域は 1 以上
    /// だが、Mac には倍率ピッカー経由でのみ到達する 1 未満の状態
    /// （25% / 50%）がある。その状態からの操作だけは本家の制限を
    /// そのまま適用すると「縮小操作で倍率が上がる」逆転が起きる
    /// ため、Mac 側の補正として次を置く: 縮小方向では現在倍率を
    /// 維持し、拡大方向では 1 を上限として近づける（1 に到達した
    /// 以後の操作は本家の制限どおり）。現在倍率が 1 以上の場合は
    /// 本家の制限そのものである。
    private static func resolvedZoom(
        current: Double, candidate: Double, areaZoom: Double
    ) -> Double {
        if current < 1 {
            if candidate <= current { return current }
            return min(candidate, 1)
        }
        return clampedZoom(candidate, areaZoom: areaZoom)
    }
}
