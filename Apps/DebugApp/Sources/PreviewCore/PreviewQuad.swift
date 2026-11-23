import CoreGraphics

/// 四角形の当たり判定（FE-R1-023-B）。本家 TimelineVideoPlayer.
/// IsPointInQuad の規則を移植した純粋関数:
/// - 各辺について、辺ベクトルと頂点→点ベクトルの外積の符号が
///   全てそろっていれば内側（境界上の点は外積 0 となり、符号を
///   壊さないため内側に含まれる）。凸四角形に対する判定であり、
///   回転・透視で歪んだ四角形でも、頂点の同次座標 w が正である
///   限り四角形は凸のまま保たれる（供給側の妥当性規則が保証する）。
/// - 全ての外積が 0（四角形が潰れている）場合は、四隅の外接矩形
///   （最小・最大）で判定する（本家のフォールバック）。
public enum PreviewQuad {
    /// 点が四角形の内側（境界を含む）にあるか。quad は頂点の並び
    /// （左上・右上・右下・左下の順）を前提とするが、判定自体は
    /// 並びの向き（時計回り・反時計回り）を問わない。
    public static func contains(_ point: CGPoint, in quad: [CGPoint]) -> Bool {
        guard !quad.isEmpty else { return false }
        var sign = 0
        for i in quad.indices {
            let a = quad[i]
            let b = quad[(i + 1) % quad.count]
            let edgeX = b.x - a.x
            let edgeY = b.y - a.y
            let toPointX = point.x - a.x
            let toPointY = point.y - a.y
            let cross = edgeX * toPointY - edgeY * toPointX
            if cross != 0 {
                let s = cross > 0 ? 1 : -1
                if sign == 0 {
                    sign = s
                } else if s != sign {
                    return false
                }
            }
        }
        if sign != 0 { return true }
        // 全ての外積が 0（潰れた四角形）: 四隅の外接矩形で判定する。
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for corner in quad {
            minX = min(minX, corner.x)
            maxX = max(maxX, corner.x)
            minY = min(minY, corner.y)
            maxY = max(maxY, corner.y)
        }
        return minX <= point.x && point.x <= maxX
            && minY <= point.y && point.y <= maxY
    }
}
