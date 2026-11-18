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

/// 断片の切断1件（切断線分の両端）。本家 PlaneSplitBsp の Cuts に対応。
public struct PlaneSplitCut: Equatable, Sendable {
    public var a: Vector3
    public var b: Vector3

    public init(a: Vector3, b: Vector3) {
        self.a = a
        self.b = b
    }
}

/// BSP の断片1件。本家 PlaneSplitBsp.Fragment に対応し、資源の位置・
/// 断片の頂点列・切断列を持つ。断片画像の生成（切断で切り取った
/// 画像の描画）は実行層の責務。
public struct PlaneSplitFragment: Equatable, Sendable {
    /// ラン内での資源の位置。
    public var resourceIndex: Int
    /// 断片の頂点列（ワールド空間の四隅。切断で増えることがある）。
    public var vertices: [Vector3]
    /// この断片を生んだ切断列。
    public var cuts: [PlaneSplitCut]

    /// 切断があるか（true なら実行層が断片画像を個別生成する）。
    public var hasCuts: Bool { !cuts.isEmpty }

    public init(resourceIndex: Int, vertices: [Vector3], cuts: [PlaneSplitCut]) {
        self.resourceIndex = resourceIndex
        self.vertices = vertices
        self.cuts = cuts
    }
}

/// 平面分割の順序付け（BSP）。本家 PlaneSplitBsp に対応する差し替え点。
/// 本体は `PlaneSplitBspOrdering`（PlaneSplitBsp.swift）に実装済み。
/// 既定は未実装の実装（NullPlaneSplitOrdering）で逐次描画へ
/// フォールバックする。本家でも Sort が nil を返せば逐次描画になる
/// ため、フォールバック先の意味論は一致する。既定を本体へ差し替える
/// 前提は、切断のある断片の画像生成が実行層に入ること（台帳 BSP 節）。
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
