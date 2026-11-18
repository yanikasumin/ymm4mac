#if os(macOS)
import Foundation
import YMM4Core

/// グラデーションメッシュのテッセレーション頂点（平面座標＋直色）。
struct GradientMeshVertex: Equatable {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

/// 評価済みスナップショット（論理座標。本家
/// `GradientMeshPointSnapshot`）。ハンドルはカスタムな方向だけが
/// 値を持ち、それ以外は nil（パッチ構築時に接線から導出する）。
struct GradientMeshSnapshot {
    var position: SIMD2<Double>
    var leftHandle: SIMD2<Double>?
    var rightHandle: SIMD2<Double>?
    var upHandle: SIMD2<Double>?
    var downHandle: SIMD2<Double>?
    /// 直色（成分 0..1）。
    var color: SIMD4<Float>
}

/// 本家 `GradientMeshPatch` 相当（4×4 制御点＋四隅の色）。
/// points は [行 (v)][列 (u)]、行 0 が上端、列 0 が左端。
struct GradientMeshPatch {
    var points: [[SIMD2<Double>]]
    var color00: SIMD4<Float>
    var color03: SIMD4<Float>
    var color30: SIMD4<Float>
    var color33: SIMD4<Float>
}

/// グラデーションメッシュの幾何構築（GRADMESH）。
///
/// 仕様の出所は本家デコンパイル済みコード:
/// - 論理配置とスナップショット: `GradientMeshBrushParameter`
///   （配置は呼び出し側 `MetalBrushFillRenderer.spec` が評価する）
/// - ローカル化と変換: `GradientMeshCoordinateHelper`
///   （ToLocal / CreateTransform / GetInverseTransformedBounds）
/// - パッチ構築と拡張: `GradientMeshPatchBuilder`
///   （Build / BuildExtended / GetHandlePosition と接線導出）
/// - 内部点: D2D `D2D1GetGradientMeshInteriorPointsFromCoonsPatch`
///   の閉形式（Coons 曲面との一致を数値検証済み）
///
/// 本家は D2D のグラデーションメッシュとして描くため、テッセレー
/// ション密度と外周エッジのアンチエイリアス（PatchEdgeMode）は
/// D2D 内部依存で再現できない。こちらはパッチを一様に分割して
/// 三角形化する（分割数は実装選択）。色は四隅色の双線形補間
/// （D2D の色モデルは四隅色のみを持ち、テンソル積の色格子は
/// 双線形埋め込みに帰着する）。
enum GradientMeshGeometry {
    /// パッチあたりの分割数（実装選択。本家は D2D が決める）。
    static let subdivisions = 16

    /// 論理スナップショット列からテッセレーション済み頂点を作る。
    /// `bounds` は本家がブラシの Update へ渡す境界、`transform` は
    /// ブラシ行列 × 境界中心への平行移動（合成済み）。
    static func build(
        horizontalCount: Int,
        verticalCount: Int,
        snapshots: [GradientMeshSnapshot],
        coordinateMode: BrushCoordinateMode,
        extendOutside: Bool,
        bounds: RectF,
        transform: BrushAffine
    ) -> (vertices: [GradientMeshVertex], indices: [UInt32]) {
        guard horizontalCount >= 2, verticalCount >= 2,
              horizontalCount <= GradientMeshBrushParameter.maximumPointCount,
              verticalCount <= GradientMeshBrushParameter.maximumPointCount,
              snapshots.count == horizontalCount * verticalCount
        else { return ([], []) }

        // ToLocal（Relative は境界寸法 / 100、Pixel は等倍）。
        let scaleX: Double
        let scaleY: Double
        switch coordinateMode {
        case .relative:
            scaleX = max(0, bounds.right - bounds.left) / 100
            scaleY = max(0, bounds.bottom - bounds.top) / 100
        case .pixel, .unknown:
            scaleX = 1
            scaleY = 1
        }
        func localize(_ point: SIMD2<Double>) -> SIMD2<Double> {
            SIMD2(point.x * scaleX, point.y * scaleY)
        }
        let local = snapshots.map { snapshot in
            GradientMeshSnapshot(
                position: localize(snapshot.position),
                leftHandle: snapshot.leftHandle.map(localize),
                rightHandle: snapshot.rightHandle.map(localize),
                upHandle: snapshot.upHandle.map(localize),
                downHandle: snapshot.downHandle.map(localize),
                color: snapshot.color
            )
        }

        var patches: [GradientMeshPatch]
        if extendOutside {
            let localBounds = inverseTransformedBounds(bounds, transform)
            patches = buildExtended(
                horizontalCount: horizontalCount, verticalCount: verticalCount,
                points: local,
                left: localBounds.left, top: localBounds.top,
                right: localBounds.right, bottom: localBounds.bottom
            )
        } else {
            patches = buildInner(
                horizontalCount: horizontalCount, verticalCount: verticalCount,
                points: local
            )
        }

        // 本家はパッチ構築後に全制御点へ transform を適用する。
        for index in patches.indices {
            for row in 0..<4 {
                for column in 0..<4 {
                    patches[index].points[row][column] =
                        apply(transform, patches[index].points[row][column])
                }
            }
        }
        return tessellate(patches)
    }

    // MARK: - 座標ヘルパ

    static func apply(_ affine: BrushAffine, _ point: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(
            affine.a * point.x + affine.c * point.y + affine.tx,
            affine.b * point.x + affine.d * point.y + affine.ty
        )
    }

    /// 本家 `GetInverseTransformedBounds`。逆変換できない場合と
    /// 非有限な場合は入力境界をそのまま返す。
    static func inverseTransformedBounds(_ bounds: RectF, _ transform: BrushAffine) -> RectF {
        guard let inverse = transform.inverted() else { return bounds }
        let corners = [
            SIMD2(bounds.left, bounds.top),
            SIMD2(bounds.right, bounds.top),
            SIMD2(bounds.left, bounds.bottom),
            SIMD2(bounds.right, bounds.bottom),
        ].map { apply(inverse, $0) }
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return bounds }
        return RectF(
            left: corners.map(\.x).min() ?? bounds.left,
            top: corners.map(\.y).min() ?? bounds.top,
            right: corners.map(\.x).max() ?? bounds.right,
            bottom: corners.map(\.y).max() ?? bounds.bottom
        )
    }

    // MARK: - パッチ構築

    private static func position(
        _ points: [GradientMeshSnapshot], _ horizontalCount: Int, _ x: Int, _ y: Int
    ) -> SIMD2<Double> {
        points[y * horizontalCount + x].position
    }

    private static func horizontalTangent(
        _ points: [GradientMeshSnapshot], _ horizontalCount: Int, _ x: Int, _ y: Int
    ) -> SIMD2<Double> {
        if x == 0 {
            return position(points, horizontalCount, 1, y)
                - position(points, horizontalCount, 0, y)
        }
        if x == horizontalCount - 1 {
            return position(points, horizontalCount, x, y)
                - position(points, horizontalCount, x - 1, y)
        }
        return (position(points, horizontalCount, x + 1, y)
            - position(points, horizontalCount, x - 1, y)) / 2
    }

    private static func verticalTangent(
        _ points: [GradientMeshSnapshot], _ horizontalCount: Int,
        _ verticalCount: Int, _ x: Int, _ y: Int
    ) -> SIMD2<Double> {
        if y == 0 {
            return position(points, horizontalCount, x, 1)
                - position(points, horizontalCount, x, 0)
        }
        if y == verticalCount - 1 {
            return position(points, horizontalCount, x, y)
                - position(points, horizontalCount, x, y - 1)
        }
        return (position(points, horizontalCount, x, y + 1)
            - position(points, horizontalCount, x, y - 1)) / 2
    }

    /// 本家 `GetHandlePosition`。カスタムハンドルがあればそれを、
    /// なければ接線の 1/3 で導出した位置を返す。
    private static func handlePosition(
        _ points: [GradientMeshSnapshot], _ horizontalCount: Int,
        _ verticalCount: Int, _ x: Int, _ y: Int, _ direction: Int
    ) -> SIMD2<Double> {
        let snapshot = points[y * horizontalCount + x]
        let base = snapshot.position
        switch direction {
        case 0: // Left
            return snapshot.leftHandle
                ?? (base - horizontalTangent(points, horizontalCount, x, y) / 3)
        case 1: // Right
            return snapshot.rightHandle
                ?? (base + horizontalTangent(points, horizontalCount, x, y) / 3)
        case 2: // Up
            return snapshot.upHandle
                ?? (base - verticalTangent(points, horizontalCount, verticalCount, x, y) / 3)
        default: // Down
            return snapshot.downHandle
                ?? (base + verticalTangent(points, horizontalCount, verticalCount, x, y) / 3)
        }
    }

    /// 12 個の境界制御点から内部 4 点を Coons の閉形式で補った
    /// パッチを作る（D2D の内部点関数の再現）。
    private static func makePatch(
        _ p00: SIMD2<Double>, _ p01: SIMD2<Double>, _ p02: SIMD2<Double>,
        _ p03: SIMD2<Double>, _ p13: SIMD2<Double>, _ p23: SIMD2<Double>,
        _ p33: SIMD2<Double>, _ p32: SIMD2<Double>, _ p31: SIMD2<Double>,
        _ p30: SIMD2<Double>, _ p20: SIMD2<Double>, _ p10: SIMD2<Double>,
        color00: SIMD4<Float>, color03: SIMD4<Float>,
        color30: SIMD4<Float>, color33: SIMD4<Float>
    ) -> GradientMeshPatch {
        func interior(_ row: Int, _ column: Int) -> SIMD2<Double> {
            let a = Double(row) / 3
            let b = Double(column) / 3
            let top = column == 1 ? p01 : p02
            let bottom = column == 1 ? p31 : p32
            let left = row == 1 ? p10 : p20
            let right = row == 1 ? p13 : p23
            let bilinear = (1 - a) * (1 - b) * p00 + (1 - a) * b * p03
                + a * (1 - b) * p30 + a * b * p33
            return (1 - a) * top + a * bottom + (1 - b) * left + b * right - bilinear
        }
        return GradientMeshPatch(
            points: [
                [p00, p01, p02, p03],
                [p10, interior(1, 1), interior(1, 2), p13],
                [p20, interior(2, 1), interior(2, 2), p23],
                [p30, p31, p32, p33],
            ],
            color00: color00, color03: color03, color30: color30, color33: color33
        )
    }

    /// 本家 `Build`（内部パッチのみ）。
    static func buildInner(
        horizontalCount: Int, verticalCount: Int, points: [GradientMeshSnapshot]
    ) -> [GradientMeshPatch] {
        var patches: [GradientMeshPatch] = []
        for y in 0..<(verticalCount - 1) {
            for x in 0..<(horizontalCount - 1) {
                let p00 = position(points, horizontalCount, x, y)
                let p03 = position(points, horizontalCount, x + 1, y)
                let p30 = position(points, horizontalCount, x, y + 1)
                let p33 = position(points, horizontalCount, x + 1, y + 1)
                patches.append(makePatch(
                    p00,
                    handlePosition(points, horizontalCount, verticalCount, x, y, 1),
                    handlePosition(points, horizontalCount, verticalCount, x + 1, y, 0),
                    p03,
                    handlePosition(points, horizontalCount, verticalCount, x + 1, y, 3),
                    handlePosition(points, horizontalCount, verticalCount, x + 1, y + 1, 2),
                    p33,
                    handlePosition(points, horizontalCount, verticalCount, x + 1, y + 1, 0),
                    handlePosition(points, horizontalCount, verticalCount, x, y + 1, 1),
                    p30,
                    handlePosition(points, horizontalCount, verticalCount, x, y + 1, 2),
                    handlePosition(points, horizontalCount, verticalCount, x, y, 3),
                    color00: points[y * horizontalCount + x].color,
                    color03: points[y * horizontalCount + x + 1].color,
                    color30: points[(y + 1) * horizontalCount + x].color,
                    color33: points[(y + 1) * horizontalCount + x + 1].color
                ))
            }
        }
        return patches
    }

    /// 本家 `BuildExtended`。内部パッチに、拡張境界までの帯パッチと
    /// 四隅の双線形パッチを加える。エッジのアンチエイリアス指定
    /// （AliasOuterEdges / PatchEdgeMode）は D2D 描画依存のため
    /// 再現しない。
    static func buildExtended(
        horizontalCount: Int, verticalCount: Int, points: [GradientMeshSnapshot],
        left: Double, top: Double, right: Double, bottom: Double
    ) -> [GradientMeshPatch] {
        let inner = buildInner(
            horizontalCount: horizontalCount, verticalCount: verticalCount,
            points: points
        )
        guard !inner.isEmpty else { return [] }

        // 拡張境界は全点位置と「使われるカスタムハンドル」を
        // 含むよう広げる（本家字面どおり）。
        var left = left
        var top = top
        var right = right
        var bottom = bottom
        for y in 0..<verticalCount {
            for x in 0..<horizontalCount {
                let snapshot = points[y * horizontalCount + x]
                left = min(left, snapshot.position.x)
                top = min(top, snapshot.position.y)
                right = max(right, snapshot.position.x)
                bottom = max(bottom, snapshot.position.y)
                let handles: [SIMD2<Double>?] = [
                    x > 0 ? snapshot.leftHandle : nil,
                    x < horizontalCount - 1 ? snapshot.rightHandle : nil,
                    y > 0 ? snapshot.upHandle : nil,
                    y < verticalCount - 1 ? snapshot.downHandle : nil,
                ]
                for handle in handles {
                    guard let handle else { continue }
                    left = min(left, handle.x)
                    top = min(top, handle.y)
                    right = max(right, handle.x)
                    bottom = max(bottom, handle.y)
                }
            }
        }

        func lerp(_ from: SIMD2<Double>, _ to: SIMD2<Double>, _ amount: Double)
            -> SIMD2<Double>
        {
            from + (to - from) * amount
        }

        var patches = inner
        let columns = horizontalCount - 1
        // 上帯・下帯（本家 AddTopAndBottomPatches）
        for i in 0..<columns {
            let topPatch = inner[i]
            let t00 = SIMD2(topPatch.points[0][0].x, top)
            let t03 = SIMD2(topPatch.points[0][3].x, top)
            patches.append(makePatch(
                t00,
                SIMD2(topPatch.points[0][1].x, top),
                SIMD2(topPatch.points[0][2].x, top),
                t03,
                lerp(t03, topPatch.points[0][3], 1.0 / 3),
                lerp(t03, topPatch.points[0][3], 2.0 / 3),
                topPatch.points[0][3],
                topPatch.points[0][2],
                topPatch.points[0][1],
                topPatch.points[0][0],
                lerp(t00, topPatch.points[0][0], 2.0 / 3),
                lerp(t00, topPatch.points[0][0], 1.0 / 3),
                color00: topPatch.color00, color03: topPatch.color03,
                color30: topPatch.color00, color33: topPatch.color03
            ))
            let bottomPatch = inner[(verticalCount - 2) * columns + i]
            let b30 = SIMD2(bottomPatch.points[3][0].x, bottom)
            let b33 = SIMD2(bottomPatch.points[3][3].x, bottom)
            patches.append(makePatch(
                bottomPatch.points[3][0],
                bottomPatch.points[3][1],
                bottomPatch.points[3][2],
                bottomPatch.points[3][3],
                lerp(bottomPatch.points[3][3], b33, 1.0 / 3),
                lerp(bottomPatch.points[3][3], b33, 2.0 / 3),
                b33,
                SIMD2(bottomPatch.points[3][2].x, bottom),
                SIMD2(bottomPatch.points[3][1].x, bottom),
                b30,
                lerp(bottomPatch.points[3][0], b30, 2.0 / 3),
                lerp(bottomPatch.points[3][0], b30, 1.0 / 3),
                color00: bottomPatch.color30, color03: bottomPatch.color33,
                color30: bottomPatch.color30, color33: bottomPatch.color33
            ))
        }
        // 左帯・右帯（本家 AddLeftAndRightPatches）
        for i in 0..<(verticalCount - 1) {
            let leftPatch = inner[i * columns]
            let l00 = SIMD2(left, leftPatch.points[0][0].y)
            let l30 = SIMD2(left, leftPatch.points[3][0].y)
            patches.append(makePatch(
                l00,
                lerp(l00, leftPatch.points[0][0], 1.0 / 3),
                lerp(l00, leftPatch.points[0][0], 2.0 / 3),
                leftPatch.points[0][0],
                leftPatch.points[1][0],
                leftPatch.points[2][0],
                leftPatch.points[3][0],
                lerp(l30, leftPatch.points[3][0], 2.0 / 3),
                lerp(l30, leftPatch.points[3][0], 1.0 / 3),
                l30,
                SIMD2(left, leftPatch.points[2][0].y),
                SIMD2(left, leftPatch.points[1][0].y),
                color00: leftPatch.color00, color03: leftPatch.color00,
                color30: leftPatch.color30, color33: leftPatch.color30
            ))
            let rightPatch = inner[i * columns + columns - 1]
            let r03 = SIMD2(right, rightPatch.points[0][3].y)
            let r33 = SIMD2(right, rightPatch.points[3][3].y)
            patches.append(makePatch(
                rightPatch.points[0][3],
                lerp(rightPatch.points[0][3], r03, 1.0 / 3),
                lerp(rightPatch.points[0][3], r03, 2.0 / 3),
                r03,
                SIMD2(right, rightPatch.points[1][3].y),
                SIMD2(right, rightPatch.points[2][3].y),
                r33,
                lerp(rightPatch.points[3][3], r33, 2.0 / 3),
                lerp(rightPatch.points[3][3], r33, 1.0 / 3),
                rightPatch.points[3][3],
                rightPatch.points[2][3],
                rightPatch.points[1][3],
                color00: rightPatch.color03, color03: rightPatch.color03,
                color30: rightPatch.color33, color33: rightPatch.color33
            ))
        }
        // 四隅（本家 CreateBilinearPatch、単色）
        func bilinearPatch(
            _ p00: SIMD2<Double>, _ p03: SIMD2<Double>,
            _ p30: SIMD2<Double>, _ p33: SIMD2<Double>, color: SIMD4<Float>
        ) -> GradientMeshPatch {
            makePatch(
                p00,
                lerp(p00, p03, 1.0 / 3),
                lerp(p00, p03, 2.0 / 3),
                p03,
                lerp(p03, p33, 1.0 / 3),
                lerp(p03, p33, 2.0 / 3),
                p33,
                lerp(p30, p33, 2.0 / 3),
                lerp(p30, p33, 1.0 / 3),
                p30,
                lerp(p00, p30, 2.0 / 3),
                lerp(p00, p30, 1.0 / 3),
                color00: color, color03: color, color30: color, color33: color
            )
        }
        let topLeft = points[0]
        let topRight = points[horizontalCount - 1]
        let bottomLeft = points[(verticalCount - 1) * horizontalCount]
        let bottomRight = points[points.count - 1]
        patches.append(bilinearPatch(
            SIMD2(left, top), SIMD2(topLeft.position.x, top),
            SIMD2(left, topLeft.position.y), topLeft.position,
            color: topLeft.color
        ))
        patches.append(bilinearPatch(
            SIMD2(topRight.position.x, top), SIMD2(right, top),
            topRight.position, SIMD2(right, topRight.position.y),
            color: topRight.color
        ))
        patches.append(bilinearPatch(
            SIMD2(left, bottomLeft.position.y), bottomLeft.position,
            SIMD2(left, bottom), SIMD2(bottomLeft.position.x, bottom),
            color: bottomLeft.color
        ))
        patches.append(bilinearPatch(
            bottomRight.position, SIMD2(right, bottomRight.position.y),
            SIMD2(bottomRight.position.x, bottom), SIMD2(right, bottom),
            color: bottomRight.color
        ))
        return patches
    }

    // MARK: - テッセレーション

    private static func cubicBasis(_ t: Double) -> [Double] {
        let s = 1 - t
        return [s * s * s, 3 * t * s * s, 3 * t * t * s, t * t * t]
    }

    static func tessellate(
        _ patches: [GradientMeshPatch]
    ) -> (vertices: [GradientMeshVertex], indices: [UInt32]) {
        let n = subdivisions
        var vertices: [GradientMeshVertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity(patches.count * (n + 1) * (n + 1))
        indices.reserveCapacity(patches.count * n * n * 6)
        for patch in patches {
            let base = UInt32(vertices.count)
            for row in 0...n {
                let v = Double(row) / Double(n)
                let bv = cubicBasis(v)
                for column in 0...n {
                    let u = Double(column) / Double(n)
                    let bu = cubicBasis(u)
                    var point = SIMD2<Double>(0, 0)
                    for i in 0..<4 {
                        for j in 0..<4 {
                            point += bv[i] * bu[j] * patch.points[i][j]
                        }
                    }
                    let color = (1 - Float(u)) * (1 - Float(v)) * patch.color00
                        + Float(u) * (1 - Float(v)) * patch.color03
                        + (1 - Float(u)) * Float(v) * patch.color30
                        + Float(u) * Float(v) * patch.color33
                    vertices.append(GradientMeshVertex(
                        position: SIMD2(Float(point.x), Float(point.y)),
                        color: color
                    ))
                }
            }
            for row in 0..<n {
                for column in 0..<n {
                    let a = base + UInt32(row * (n + 1) + column)
                    let b = a + 1
                    let c = a + UInt32(n + 1)
                    let d = c + 1
                    indices.append(contentsOf: [a, b, c, b, d, c])
                }
            }
        }
        return (vertices, indices)
    }
}
#endif
