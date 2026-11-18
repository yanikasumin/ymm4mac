import Foundation

/// 平面分割（BSP）の本体。本家 PlaneSplitBsp の規則をそのまま写した
/// 実装で、`PlaneSplitOrdering` の差し替え点へ差す。
///
/// 本家は内部の算術を全て単精度（float）で行うため、こちらも内部は
/// Float で計算し、境界（`Vector3` は Double）でのみ変換する。
/// 視点は (0, 0, 1000)、透視距離 1000、許容誤差 0.01、断片の上限 256
/// （上限を超えたら順序付けを諦めて nil = 逐次描画フォールバック）。
///
/// 既定の順序付けとしてはまだ差していない: 切断のある断片の画像生成
/// （マスク多角形でのクリップ描画）が実行層に未実装で、現行の
/// TimelineSource は切断のある断片を描画から落とす。その生成が入る
/// までは `DrawSegmentBuilder` の既定は Null のままにし、本実装は
/// 明示的に差した利用側とテストで使う（台帳 BSP 節）。
public struct PlaneSplitBspOrdering: PlaneSplitOrdering {
    public init() {}

    public func requiresOrdering(_ a: [Vector3], _ b: [Vector3]) -> Bool {
        PlaneSplitBsp.requiresOrdering(a.map(FVec3.init), b.map(FVec3.init))
    }

    public func sort(quads: [[Vector3]]) -> [PlaneSplitFragment]? {
        guard let fragments = PlaneSplitBsp.sort(quads.map { $0.map(FVec3.init) })
        else { return nil }
        return fragments.map { fragment in
            PlaneSplitFragment(
                resourceIndex: fragment.index,
                vertices: fragment.vertices.map { $0.vector3 },
                cuts: fragment.cuts.map {
                    PlaneSplitCut(a: $0.a.vector3, b: $0.b.vector3)
                }
            )
        }
    }
}

/// 画面マスク多角形の算出（本家 PlaneSplitBsp.CreateScreenMaskPolygon）。
/// 断片の切断列で画面境界の矩形を切り取り、断片が実際に描くべき
/// 画面領域の多角形を返す。作れない場合は nil。
public func planeSplitScreenMaskPolygon(
    fragment: PlaneSplitFragment,
    boundsMin: (x: Double, y: Double),
    boundsMax: (x: Double, y: Double)
) -> [(x: Double, y: Double)]? {
    let fFragment = PlaneSplitBsp.Fragment(
        index: fragment.resourceIndex,
        vertices: fragment.vertices.map(FVec3.init),
        cuts: fragment.cuts.map {
            PlaneSplitBsp.Cut(a: FVec3($0.a), b: FVec3($0.b))
        }
    )
    guard let polygon = PlaneSplitBsp.createScreenMaskPolygon(
        fragment: fFragment,
        boundsMin: FVec2(Float(boundsMin.x), Float(boundsMin.y)),
        boundsMax: FVec2(Float(boundsMax.x), Float(boundsMax.y))
    ) else { return nil }
    return polygon.map { (x: Double($0.x), y: Double($0.y)) }
}

// MARK: - 単精度の内部型

/// 本家の System.Numerics.Vector3 に対応する単精度ベクトル。
struct FVec3: Equatable {
    var x: Float
    var y: Float
    var z: Float

    init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ v: Vector3) {
        self.init(Float(v.x), Float(v.y), Float(v.z))
    }

    var vector3: Vector3 {
        Vector3(x: Double(x), y: Double(y), z: Double(z))
    }

    static let zero = FVec3(0, 0, 0)

    static func + (a: FVec3, b: FVec3) -> FVec3 {
        FVec3(a.x + b.x, a.y + b.y, a.z + b.z)
    }

    static func - (a: FVec3, b: FVec3) -> FVec3 {
        FVec3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    static func / (a: FVec3, s: Float) -> FVec3 {
        FVec3(a.x / s, a.y / s, a.z / s)
    }

    func dot(_ other: FVec3) -> Float {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: FVec3) -> FVec3 {
        FVec3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    var length: Float {
        dot(self).squareRoot()
    }

    var lengthSquared: Float {
        dot(self)
    }

    static func lerp(_ a: FVec3, _ b: FVec3, _ amount: Float) -> FVec3 {
        FVec3(
            a.x + (b.x - a.x) * amount,
            a.y + (b.y - a.y) * amount,
            a.z + (b.z - a.z) * amount
        )
    }
}

/// 本家の System.Numerics.Vector2 に対応する単精度ベクトル。
struct FVec2: Equatable {
    var x: Float
    var y: Float

    init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    static func - (a: FVec2, b: FVec2) -> FVec2 {
        FVec2(a.x - b.x, a.y - b.y)
    }

    static func + (a: FVec2, b: FVec2) -> FVec2 {
        FVec2(a.x + b.x, a.y + b.y)
    }

    static func / (a: FVec2, s: Float) -> FVec2 {
        FVec2(a.x / s, a.y / s)
    }

    var lengthSquared: Float {
        x * x + y * y
    }

    static func lerp(_ a: FVec2, _ b: FVec2, _ amount: Float) -> FVec2 {
        FVec2(a.x + (b.x - a.x) * amount, a.y + (b.y - a.y) * amount)
    }
}

// MARK: - 本家 PlaneSplitBsp の写し

enum PlaneSplitBsp {
    struct Cut: Equatable {
        var a: FVec3
        var b: FVec3
    }

    struct Fragment {
        var index: Int
        var vertices: [FVec3]
        var cuts: [Cut]
    }

    private final class Node {
        let normal: FVec3
        let d: Float
        var polys: [Poly] = []
        var front: Node?
        var back: Node?

        init(normal: FVec3, d: Float) {
            self.normal = normal
            self.d = d
        }
    }

    private struct Poly {
        var index: Int
        var vertices: [FVec3]
        var cuts: [Cut]
    }

    static let perspectiveDistance: Float = 1000
    static let eye = FVec3(0, 0, 1000)
    static let epsilon: Float = 0.01
    private static let maxFragments = 256

    static func project(_ v: FVec3) -> FVec2 {
        let scale = 1 - v.z / perspectiveDistance
        return FVec2(v.x / scale, v.y / scale)
    }

    static func requiresOrdering(_ a: [FVec3], _ b: [FVec3]) -> Bool {
        guard let (normal, d) = tryGetPlane(a),
              tryGetPlane(b) != nil else { return false }
        if isCoplanar(b, normal: normal, d: d) { return false }
        return screenBoundsOverlap(a, b)
    }

    static func sort(_ quads: [[FVec3]]) -> [Fragment]? {
        var root: Node?
        var fragmentCount = quads.count
        for (index, quad) in quads.enumerated() {
            let poly = Poly(index: index, vertices: quad, cuts: [])
            if root == nil {
                guard let (normal, d) = tryGetPlane(poly.vertices) else {
                    return nil
                }
                let node = Node(normal: normal, d: d)
                node.polys.append(poly)
                root = node
            } else if !insert(root!, poly, fragmentCount: &fragmentCount) {
                return nil
            }
        }
        guard let root else { return [] }
        var output: [Fragment] = []
        output.reserveCapacity(fragmentCount)
        traverse(root, into: &output)
        return output
    }

    static func createScreenMaskPolygon(
        fragment: Fragment,
        boundsMin: FVec2, boundsMax: FVec2
    ) -> [FVec2]? {
        var center = FVec2(0, 0)
        for v in fragment.vertices {
            let p = project(v)
            center = FVec2(center.x + p.x, center.y + p.y)
        }
        center = center / Float(fragment.vertices.count)
        var list: [FVec2] = [
            FVec2(boundsMin.x, boundsMin.y),
            FVec2(boundsMax.x, boundsMin.y),
            FVec2(boundsMax.x, boundsMax.y),
            FVec2(boundsMin.x, boundsMax.y),
        ]
        for cut in fragment.cuts {
            let a = project(cut.a)
            let direction = project(cut.b) - a
            if direction.lengthSquared < 1e-12 { return nil }
            let side = cross(direction, center - a)
            if abs(side) < 1e-6 { return nil }
            list = clipByHalfPlane(
                list, a: a, direction: direction, sign: side < 0 ? -1 : 1
            )
            if list.count < 3 { return nil }
        }
        return list
    }

    // MARK: 木の構築

    private static func insert(
        _ node: Node, _ poly: Poly, fragmentCount: inout Int
    ) -> Bool {
        var node = node
        while true {
            var distances = [Float](repeating: 0, count: poly.vertices.count)
            var hasFront = false
            var hasBack = false
            for i in poly.vertices.indices {
                let value = node.normal.dot(poly.vertices[i]) + node.d
                distances[i] = value
                hasFront = hasFront || value > epsilon
                hasBack = hasBack || value < -epsilon
            }
            if !hasFront && !hasBack {
                node.polys.append(poly)
                return true
            }
            if hasFront && hasBack {
                if let (front, back) = trySplit(poly, distances: distances) {
                    fragmentCount += 1
                    if fragmentCount > maxFragments { return false }
                    if !insertOrAttach(node, front, isFront: true, fragmentCount: &fragmentCount) {
                        return false
                    }
                    return insertOrAttach(node, back, isFront: false, fragmentCount: &fragmentCount)
                }
                // 分割できない場合は本家どおり多数決で片側へ寄せ、
                // 分割せずにその側へ降りる。
                let frontCount = distances.count { $0 > epsilon }
                let backCount = distances.count { $0 < -epsilon }
                if frontCount >= backCount {
                    hasBack = false
                } else {
                    hasFront = false
                }
            }
            if hasFront {
                if node.front == nil {
                    return attachAsChild(node, poly, isFront: true)
                }
                node = node.front!
            } else {
                if node.back == nil {
                    return attachAsChild(node, poly, isFront: false)
                }
                node = node.back!
            }
        }
    }

    private static func insertOrAttach(
        _ node: Node, _ poly: Poly, isFront: Bool, fragmentCount: inout Int
    ) -> Bool {
        if let child = isFront ? node.front : node.back {
            return insert(child, poly, fragmentCount: &fragmentCount)
        }
        return attachAsChild(node, poly, isFront: isFront)
    }

    private static func attachAsChild(_ node: Node, _ poly: Poly, isFront: Bool) -> Bool {
        guard let (normal, d) = tryGetPlane(poly.vertices) else {
            node.polys.append(poly)
            return true
        }
        let child = Node(normal: normal, d: d)
        child.polys.append(poly)
        if isFront {
            node.front = child
        } else {
            node.back = child
        }
        return true
    }

    private static func trySplit(
        _ poly: Poly, distances: [Float]
    ) -> (front: Poly, back: Poly)? {
        let count = poly.vertices.count
        var frontVertices: [FVec3] = []
        var backVertices: [FVec3] = []
        var onPlane: [FVec3] = []
        frontVertices.reserveCapacity(count + 1)
        backVertices.reserveCapacity(count + 1)
        for i in 0..<count {
            let vertex = poly.vertices[i]
            let distance = distances[i]
            let next = poly.vertices[(i + 1) % count]
            let nextDistance = distances[(i + 1) % count]
            if distance >= -epsilon { frontVertices.append(vertex) }
            if distance <= epsilon { backVertices.append(vertex) }
            if abs(distance) <= epsilon { onPlane.append(vertex) }
            if (distance > epsilon && nextDistance < -epsilon)
                || (distance < -epsilon && nextDistance > epsilon) {
                let amount = distance / (distance - nextDistance)
                let intersection = FVec3.lerp(vertex, next, amount)
                frontVertices.append(intersection)
                backVertices.append(intersection)
                onPlane.append(intersection)
            }
        }
        guard let pair = tryGetFarthestPair(onPlane) else { return nil }
        let cut = Cut(a: pair.0, b: pair.1)
        return (
            front: Poly(index: poly.index, vertices: frontVertices, cuts: poly.cuts + [cut]),
            back: Poly(index: poly.index, vertices: backVertices, cuts: poly.cuts + [cut])
        )
    }

    private static func tryGetFarthestPair(_ points: [FVec3]) -> (FVec3, FVec3)? {
        var best: (FVec3, FVec3)?
        var bestLength: Float = 0
        for i in points.indices {
            for j in (i + 1)..<points.count {
                let length = (points[i] - points[j]).lengthSquared
                if length > bestLength {
                    bestLength = length
                    best = (points[i], points[j])
                }
            }
        }
        return bestLength > 0.0001 ? best : nil
    }

    private static func traverse(_ node: Node?, into output: inout [Fragment]) {
        guard let node else { return }
        // 視点が平面の表側にあるかで巡回順が入れ替わる（本家 Traverse）。
        let eyeSide = node.normal.dot(eye) + node.d >= 0
        let first = eyeSide ? node.back : node.front
        let last = eyeSide ? node.front : node.back
        traverse(first, into: &output)
        for poly in node.polys.sorted(by: { $0.index < $1.index }) {
            output.append(Fragment(index: poly.index, vertices: poly.vertices, cuts: poly.cuts))
        }
        traverse(last, into: &output)
    }

    // MARK: 平面と画面範囲

    /// Newell 法で平面を求める。法線の長さが許容誤差未満なら平面として
    /// 扱えない（本家 TryGetPlane）。
    static func tryGetPlane(_ vertices: [FVec3]) -> (normal: FVec3, d: Float)? {
        guard vertices.count >= 3 else { return nil }
        var sum = FVec3.zero
        var center = FVec3.zero
        for i in vertices.indices {
            let current = vertices[i]
            let next = vertices[(i + 1) % vertices.count]
            sum = sum + current.cross(next)
            center = center + current
        }
        center = center / Float(vertices.count)
        let length = sum.length
        if length < epsilon { return nil }
        let normal = sum / length
        return (normal, -normal.dot(center))
    }

    private static func isCoplanar(_ vertices: [FVec3], normal: FVec3, d: Float) -> Bool {
        for v in vertices {
            if abs(normal.dot(v) + d) > epsilon { return false }
        }
        return true
    }

    private static func screenBoundsOverlap(_ a: [FVec3], _ b: [FVec3]) -> Bool {
        let (aMin, aMax) = screenBounds(a)
        let (bMin, bMax) = screenBounds(b)
        return aMin.x <= bMax.x && bMin.x <= aMax.x
            && aMin.y <= bMax.y && bMin.y <= aMax.y
    }

    static func screenBounds(_ vertices: [FVec3]) -> (min: FVec2, max: FVec2) {
        var min = FVec2(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var max = FVec2(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        for v in vertices {
            let p = project(v)
            min = FVec2(Swift.min(min.x, p.x), Swift.min(min.y, p.y))
            max = FVec2(Swift.max(max.x, p.x), Swift.max(max.y, p.y))
        }
        return (min, max)
    }

    private static func cross(_ a: FVec2, _ b: FVec2) -> Float {
        a.x * b.y - a.y * b.x
    }

    private static func clipByHalfPlane(
        _ polygon: [FVec2], a: FVec2, direction: FVec2, sign: Float
    ) -> [FVec2] {
        var list: [FVec2] = []
        list.reserveCapacity(polygon.count + 1)
        for i in polygon.indices {
            let current = polygon[i]
            let next = polygon[(i + 1) % polygon.count]
            let currentSide = cross(direction, current - a) * sign
            let nextSide = cross(direction, next - a) * sign
            if currentSide >= 0 { list.append(current) }
            if (currentSide > 0 && nextSide < 0) || (currentSide < 0 && nextSide > 0) {
                list.append(FVec2.lerp(current, next, currentSide / (currentSide - nextSide)))
            }
        }
        return list
    }
}
