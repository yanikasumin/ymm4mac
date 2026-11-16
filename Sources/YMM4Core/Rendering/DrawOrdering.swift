import Foundation

/// 順序付け・セグメント構築の入力となる、アイテム1件分の描画資源。
/// 本家 TimelineSource が保持する (IVideoItem, EffectedItemSource) の組に
/// 対応する。順序キーと平面分割の入力は、EffectedItemSource 相当（次段）が
/// 評価して埋める前提で、値として切り出してある。
public struct OrderedDrawResource {
    /// 対象アイテム。
    public var item: BaseItem
    /// 「常に最前面」か（順序キー1段目）。
    public var alwaysOnTop: Bool
    /// Z 順序が有効か（順序キー2段目とラン参加条件に使う）。
    public var zOrderEnabled: Bool
    /// レイヤー（順序キー3段目）。
    public var layer: Int
    /// Source が FrameBuffer 系か（ラン参加条件から外れる）。
    public var isFrameBufferSource: Bool
    /// 各出力の描画変換（ZIndex の算出元）。
    public var drawDescriptions: [DrawDescription]
    /// 平面分割用の四隅（計算できない場合は nil）。
    /// `DrawOrdering.planeSplitQuad(outputs:)` で算出する。
    public var planeSplitQuad: [Vector3]?

    public init(
        item: BaseItem,
        alwaysOnTop: Bool,
        zOrderEnabled: Bool,
        layer: Int,
        isFrameBufferSource: Bool,
        drawDescriptions: [DrawDescription],
        planeSplitQuad: [Vector3]?
    ) {
        self.item = item
        self.alwaysOnTop = alwaysOnTop
        self.zOrderEnabled = zOrderEnabled
        self.layer = layer
        self.isFrameBufferSource = isFrameBufferSource
        self.drawDescriptions = drawDescriptions
        self.planeSplitQuad = planeSplitQuad
    }

    /// 映像アイテムから順序キーを取る初期化子。
    public init(
        visualItem: VisualItem,
        isFrameBufferSource: Bool,
        drawDescriptions: [DrawDescription],
        planeSplitQuad: [Vector3]?
    ) {
        self.init(
            item: visualItem,
            alwaysOnTop: visualItem.isAlwaysOnTop,
            zOrderEnabled: visualItem.isZOrderEnabled,
            layer: visualItem.layer,
            isFrameBufferSource: isFrameBufferSource,
            drawDescriptions: drawDescriptions,
            planeSplitQuad: planeSplitQuad
        )
    }

    /// 順序キー2段目の値。ZOrder 無効時は 0（本家 GetOrderedTimelineResources
    /// の条件式どおり）。
    public var zIndex: Double {
        zOrderEnabled ? DrawOrdering.zIndex(of: drawDescriptions) : 0
    }
}

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

/// 描画順序と平面分割の判定規則。本家 TimelineSource.GetOrderedTimeline
/// Resources / EffectedItemSource.GetZIndex / GetPlaneSplitQuad /
/// PlaneSplitBsp.IsValidQuad の規則を、GPU に触れない純粋計算として実装する。
public enum DrawOrdering {

    /// 出力群の ZIndex。本家 EffectedItemSource.GetZIndex と同じく、
    /// 各出力の変換後原点 Z の最大値。出力が無ければ 0。
    public static func zIndex(of descriptions: [DrawDescription]) -> Double {
        descriptions.map { transformedOriginZ($0) }.max() ?? 0
    }

    /// 描画変換を原点へ適用した後の Z。本家の合成行列
    /// （中心まわりの反転スケール × 回転Z × 回転Y（符号反転）× 回転X
    /// （符号反転）× 平行移動 × カメラ × 透視 M34=-0.001）を再現し、
    /// MatrixHelper.Transform と同じく w で割る。
    public static func transformedOriginZ(_ description: DrawDescription) -> Double {
        let scale = Matrix4x4.createScale(
            x: description.invert ? -1 : 1, y: 1, z: 1,
            center: Vector3(x: description.centerPoint.x, y: description.centerPoint.y, z: 0)
        )
        let rotationZ = Matrix4x4.createRotationZ(.pi * description.rotation.z / 180)
        let rotationY = Matrix4x4.createRotationY(.pi * (0 - description.rotation.y) / 180)
        let rotationX = Matrix4x4.createRotationX(.pi * (0 - description.rotation.x) / 180)
        let translation = Matrix4x4.createTranslation(description.draw)
        let perspective = Matrix4x4(
            m11: 1, m12: 0, m13: 0, m14: 0,
            m21: 0, m22: 1, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: -0.001,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
        let matrix = scale * rotationZ * rotationY * rotationX
            * translation * description.camera * perspective
        return matrix.transform(.zero).z
    }

    /// 描画順序。本家 GetOrderedTimelineResources と同じ3段キー昇順
    /// （IsAlwaysOnTop → ZIndex → Layer）。同キーの要素は入力順を保つ
    /// （本家 LINQ OrderBy の安定性に相当）。
    public static func ordered(_ resources: [OrderedDrawResource]) -> [OrderedDrawResource] {
        resources.sorted { a, b in
            let aTop = a.alwaysOnTop ? 1 : 0
            let bTop = b.alwaysOnTop ? 1 : 0
            if aTop != bTop { return aTop < bTop }
            if a.zIndex != b.zIndex { return a.zIndex < b.zIndex }
            return a.layer < b.layer
        }
    }

    /// 平面分割用の四隅。本家 EffectedItemSource.GetPlaneSplitQuad の規則:
    /// 次のいずれかで nil（=平面分割から外れ、区間がそこで切れる）。
    /// - 出力が0件
    /// - ワールド変換を持たない出力がある、または出力間で変換が一致しない
    /// - 入力境界が取れない出力がある
    /// - 統合した境界が空（Right <= Left または Bottom <= Top）
    /// - 変換後の同次座標 w が 0.001 以下または非有限、座標が非有限
    /// - 変換後の Z が 999 を超える頂点がある
    /// - 四隅が平面をなさない（IsValidQuad が偽）
    public static func planeSplitQuad(outputs: [PlaneSplitOutputGeometry]) -> [Vector3]? {
        guard !outputs.isEmpty else { return nil }
        var worldTransform: Matrix4x4?
        var bounds: RectF?
        for output in outputs {
            guard let transform = output.worldTransform else { return nil }
            if let existing = worldTransform, existing != transform { return nil }
            worldTransform = transform
            guard let inputBounds = output.inputBounds else { return nil }
            bounds = bounds?.union(inputBounds) ?? inputBounds
        }
        guard let bounds, let worldTransform,
              bounds.right > bounds.left, bounds.bottom > bounds.top
        else { return nil }

        let corners = [
            Vector3(x: bounds.left, y: bounds.top, z: 0),
            Vector3(x: bounds.right, y: bounds.top, z: 0),
            Vector3(x: bounds.right, y: bounds.bottom, z: 0),
            Vector3(x: bounds.left, y: bounds.bottom, z: 0),
        ]
        var quad: [Vector3] = []
        quad.reserveCapacity(4)
        for corner in corners {
            let v = worldTransform.transform(x: corner.x, y: corner.y, z: corner.z, w: 1)
            guard v.w > 0.001, v.w.isFinite else { return nil }
            let point = Vector3(x: v.x / v.w, y: v.y / v.w, z: v.z / v.w)
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
            if point.z > 999 { return nil }
            quad.append(point)
        }
        guard isValidQuad(quad) else { return nil }
        return quad
    }

    /// 四隅が平面をなすか。本家 PlaneSplitBsp.IsValidQuad（TryGetPlane）:
    /// Newell 法の法線の長さが 0.01 未満なら平面として扱えない。
    public static func isValidQuad(_ quad: [Vector3]) -> Bool {
        guard quad.count >= 3 else { return false }
        var normal = Vector3.zero
        for i in quad.indices {
            normal = normal + quad[i].cross(quad[(i + 1) % quad.count])
        }
        return normal.length >= 0.01
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

/// 描画セグメント。本家 TimelineSource の DrawSegment に対応する。
/// 実行層は single を順次描画し、planeSplit は断片列の順に描く。
public enum DrawSegment {
    /// 単独描画。
    case single(OrderedDrawResource)
    /// 平面分割（BSP 順序の断片列で描く）。
    case planeSplit(resources: [OrderedDrawResource], fragments: [PlaneSplitFragment])
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

/// 順序済み資源列から描画セグメント列を構築する。
/// 本家 TimelineSource.CreateDrawSegments の規則:
/// - ラン参加条件（CanJoinPlaneSplitRun）: ZOrder 有効かつ FrameBuffer でない。
/// - ランは IsAlwaysOnTop が先頭と同一の間だけ伸びる。
/// - ランが2件未満なら単独描画。
/// - ラン内で四隅が計算できない資源は単独描画になり、そこで区間が切れる。
/// - 残った小区間は、2件以上かつ BSP 順序付けが必要な組があり、かつ
///   Sort が断片列を返した場合だけ平面分割セグメントになる。
///   それ以外は全て単独描画（フォールバック）。
public struct DrawSegmentBuilder {
    public var ordering: any PlaneSplitOrdering

    public init(ordering: any PlaneSplitOrdering = NullPlaneSplitOrdering()) {
        self.ordering = ordering
    }

    /// ラン参加条件。本家 CanJoinPlaneSplitRun と同じ。
    public func canJoinPlaneSplitRun(_ resource: OrderedDrawResource) -> Bool {
        resource.zOrderEnabled && !resource.isFrameBufferSource
    }

    public func buildSegments(from orderedResources: [OrderedDrawResource]) -> [DrawSegment] {
        var segments: [DrawSegment] = []
        var i = 0
        while i < orderedResources.count {
            let resource = orderedResources[i]
            guard canJoinPlaneSplitRun(resource) else {
                segments.append(.single(resource))
                i += 1
                continue
            }
            let runStart = i
            while i < orderedResources.count
                && orderedResources[i].alwaysOnTop == resource.alwaysOnTop
                && canJoinPlaneSplitRun(orderedResources[i])
            {
                i += 1
            }
            let run = Array(orderedResources[runStart..<i])
            guard run.count >= 2 else {
                segments.append(.single(run[0]))
                continue
            }
            // 四隅が計算できない資源の位置で小区間に切る。
            var subStart = 0
            for index in 0...run.count {
                if index >= run.count || run[index].planeSplitQuad == nil {
                    appendPlaneSplitOrSingles(
                        run: Array(run[subStart..<index]),
                        into: &segments
                    )
                    if index < run.count {
                        segments.append(.single(run[index]))
                    }
                    subStart = index + 1
                }
            }
        }
        return segments
    }

    /// 小区間を平面分割セグメントにするか、単独描画の列へ落とす。
    /// 本家 AddPlaneSplitOrSingleSegments と同じ分岐。
    private func appendPlaneSplitOrSingles(
        run: [OrderedDrawResource],
        into segments: inout [DrawSegment]
    ) {
        if run.count >= 2 {
            let quads = run.map { $0.planeSplitQuad! }
            var anyPairRequires = false
            for i in quads.indices {
                for j in (i + 1)..<quads.count where ordering.requiresOrdering(quads[i], quads[j]) {
                    anyPairRequires = true
                }
            }
            if anyPairRequires, let fragments = ordering.sort(quads: quads) {
                segments.append(.planeSplit(resources: run, fragments: fragments))
                return
            }
        }
        for resource in run {
            segments.append(.single(resource))
        }
    }
}
