import Foundation

/// 平面分割の四隅算出に必要な、出力1件分の幾何情報。
/// 本家では EffectedItemSource が各出力の DrawingEffect から
/// WorldTransform3D と入力境界を取り出して判定する。その供給は次段の
/// 責務とし、ここでは判定規則だけを実装する。
public struct PlaneSplitOutputGeometry {
    /// 出力の描画エフェクトのワールド変換（DrawingEffect でない場合は nil）。
    public var worldTransform: Matrix4x4?
    /// 変換前の入力境界（取得できない場合は nil）。
    public var inputBounds: RectF?

    public init(worldTransform: Matrix4x4?, inputBounds: RectF?) {
        self.worldTransform = worldTransform
        self.inputBounds = inputBounds
    }
}

/// BSP の断片1件。本家 PlaneSplitBsp.Fragment のうち、この層で必要な
/// 「どの資源の断片か」と「切断があるか」だけを表す。断片画像の生成は
/// GPU 実行層の責務。
public struct PlaneSplitFragment: Equatable, Sendable {
    /// ラン内での資源の位置。
    public var resourceIndex: Int
    /// 切断があるか（true なら実行層が断片画像を個別生成する）。
    public var hasCuts: Bool

    public init(resourceIndex: Int, hasCuts: Bool) {
        self.resourceIndex = resourceIndex
        self.hasCuts = hasCuts
    }
}

/// 平面分割の順序付け（BSP）。本家 PlaneSplitBsp に対応する差し替え点。
/// BSP 本体の実装は次段の仕事であり、この層では未実装の実装
/// （NullPlaneSplitOrdering）を既定として逐次描画へフォールバックする。
/// 本家でも Sort が nil を返せば逐次描画になるため、フォールバック先の
/// 意味論は一致する。
public protocol PlaneSplitOrdering {
    /// 2つの四隅の組について BSP 順序付けが必要か
    /// （本家 PlaneSplitBsp.RequiresBspOrdering）。
    func requiresOrdering(_ a: [Vector3], _ b: [Vector3]) -> Bool
    /// 四隅の列を BSP 順序の断片列へ並べ替える。並べ替えできない場合は
    /// nil（本家 PlaneSplitBsp.Sort の nil 返却に対応）。
    func sort(quads: [[Vector3]]) -> [PlaneSplitFragment]?
}

/// BSP 未実装時の順序付け。順序付けが必要な組は無いものとし、Sort は
/// 常に nil を返す。結果として全てのランは逐次描画へフォールバックする。
public struct NullPlaneSplitOrdering: PlaneSplitOrdering {
    public init() {}

    public func requiresOrdering(_ a: [Vector3], _ b: [Vector3]) -> Bool {
        false
    }

    public func sort(quads: [[Vector3]]) -> [PlaneSplitFragment]? {
        nil
    }
}
