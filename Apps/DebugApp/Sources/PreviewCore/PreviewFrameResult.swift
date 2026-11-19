import CoreGraphics

/// プレビュー1フレーム分の、アイテム1件の実描画矩形（FE-R1-023-A）。
///
/// GPU 層が記録した内容境界（登録済み画像の bounds に変換を適用した
/// 外接矩形）を、映像左上原点の座標系へ変換した値だけを運ぶ
/// （GPU の MetalImage 自体はメインスレッドへ渡さない）。回転・透視
/// 変換後の外接矩形（AABB）であり、画素単位の精密な囲みではない:
/// クリッピングされた透明部分や回転の余白も含まれる。この限界は
/// 台帳（IMPLEMENTATION_LOG の FE-R1-023-A 節）に明示する。
public struct PreviewItemRect: Equatable, Sendable {
    /// スナップショット内タイムラインのアイテムインデックス。
    /// 識別情報（セッションキー・版数・フレーム）を伴う結果の中でのみ
    /// 有効であり、異なるモデル版数間で再利用してはならない。
    public var itemIndex: Int
    /// 映像左上原点を原点とする実描画矩形（映像座標、y 下向き）。
    public var bounds: CGRect
    /// 描画順（0 が最も背面。大きいほど前面）。
    public var drawOrder: Int

    public init(itemIndex: Int, bounds: CGRect, drawOrder: Int) {
        self.itemIndex = itemIndex
        self.bounds = bounds
        self.drawOrder = drawOrder
    }
}

/// 描画結果の契約（FE-R1-023-A）: 画像と、それに対応するアイテム別
/// 実描画矩形を一体の結果として運ぶ。完成条件は「矩形を取得できる
/// こと」ではなく「現在表示されている画像に対応する正しい矩形で
/// 操作できること」であり、画像と矩形は同じ結果から取ること
/// （別々に最新化される状態を混ぜない）。
public struct PreviewFrameResult: Sendable {
    /// 合成結果の画像。
    public var image: CGImage
    /// アイテム別の実描画矩形（描画順に昇順）。描画出力の無い
    /// アイテムは含まれない。
    public var itemRects: [PreviewItemRect]

    public init(image: CGImage, itemRects: [PreviewItemRect]) {
        self.image = image
        self.itemRects = itemRects
    }
}

extension PreviewItemRect {
    /// 点を含む矩形のうち、実際の描画順で最も前面のアイテムの
    /// インデックスを返す。描画順が同点の場合はタイムラインの
    /// インデックスが大きい方を前面とする（描画順は合成器が
    /// 安定ソートで決めるため、同点は通常起きないが、規則を
    /// 決めておく）。isExcluded が真のアイテムは候補から外れる
    /// （ロック中アイテムなど、消費側の事情による除外）。
    public static func frontmostIndex(
        in rects: [PreviewItemRect],
        at point: CGPoint,
        isExcluded: (Int) -> Bool = { _ in false }
    ) -> Int? {
        var best: PreviewItemRect?
        for rect in rects where rect.bounds.contains(point) && !isExcluded(rect.itemIndex) {
            if let current = best,
               rect.drawOrder < current.drawOrder
                || (rect.drawOrder == current.drawOrder
                    && rect.itemIndex < current.itemIndex) {
                continue
            }
            best = rect
        }
        return best?.itemIndex
    }
}
