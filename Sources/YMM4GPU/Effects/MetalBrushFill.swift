#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core

/// ブラシ塗りの GPU 実装（BRUSH46）。
///
/// 本家のブラシは `IBrushParameter.CreateBrush` が D2D ブラシを生成し、
/// 各エフェクトが効果ごとの境界（Bounds）を渡して `FillRectangle` 等で
/// 塗る。こちらでは同じ幾何をシェーダ（`ymm4BrushFragment`）で解析的に
/// 評価する。パターン系（市松・ドット・格子線）は本家がタイル
/// ビットマップ＋ BitmapBrush（Wrap・MultiSampleLinear 補間）で描くの
/// に対し、こちらは逆変換後の座標で解析的に判定するため、パターン
/// 境界の約1px の縁の柔らかさだけが異なる（既知の差分として記録）。
///
/// 幾何の根拠（いずれも本家デコンパイル済みコードで確認）:
/// - 線形: `LinearGradientBrushSource` + `LinearGradientBrushHelper.
///   CalculatePoints`。Pixel モードは原点基準の絶対座標で
///   始点 = v・(−Size/2 + Offset)、終点 = v・(Size/2 + Offset)
///   （v = (cos θ, sin θ)、Size は max(0.001, Size)）。
///   Relative モードは境界の射影長 L = W・|vx| + H・|vy| に対し
///   長さ = max(0.001, L・Size/100)、ずれ = L・Offset/100 を
///   境界中心へ適用する。
/// - 放射: `RadiulGradientBrushSource`。旧 `IBrushSource.Update`
///   しか実装しておらず Bounds は使われない（絶対 px 幾何）。
///   zoom = Zoom/100、aspect 係数 ax = 1 − max(0, Aspect/100)、
///   ay = 1 + min(0, Aspect/100) として、中心 = (CenterX, CenterY)、
///   焦点 = 中心 + (OriginX・zoom・ax, OriginY・zoom・ay)、
///   半径 = (RadiusX・zoom・ax, RadiusY・zoom・ay)。
///   ブラシ変換は 回転（Angle）→ 左右反転拡縮 の順（行ベクトル規約）。
///   D2D の放射グラデーションは楕円族 center(t) = F + t・(C − F)、
///   radii(t) = t・(rx, ry) で定義されるため、t は二次方程式で解く。
/// - 市松: `CheckeredBrushSource`。タイルは 2s×2s（s = (int)max(1, Size)）
///   の四象限塗り分けであり、セルパリティと等価。
/// - ドット: `DotBrushSource`。間隔 = (int)max(1, Span・zoom)、
///   半径 = Radius・zoom の円をタイル中心へ描く（zoom = Zoom/100）。
/// - ストライプ: `StripeBrushSource`。幅とオフセットへ zoom を掛けた
///   線形グラデーション（分岐点 [(0, c1), (p, c1), (p, c2), (1, c2)]、
///   p = w1/(w1+w2)、Wrap 固定、始終点は Angle で回転）。
/// - 格子線: `GridLineBrushSource`。タイル (int)max(Width・zoom, 1) ×
///   (int)max(Height・zoom, 1) の矩形輪郭を太さ Thickness・zoom で
///   描く（ストロークは境界中心。タイル内では内側半分＋隣接タイルの
///   外側半分で幅が完成する）。本家は Zoom の評価で
///   GetValue(frame, length, frame) と fps 位置へ frame を渡す
///   不整合があるが、こちらは通常評価とし、差分として記録する。
/// - ビットマップ: `BitmapBrushSource`。画像ファイルのみ対応
///   （動画ファイルは未対応で素通し）。変換は
///   平行移動（−幅/2, −高さ/2。整数除算）→ 拡縮（Zoom/100）→
///   描画変換（DrawingBrushParameterBase.CreateBrushMatrix）。
///   補間は D2D ビットマップブラシの既定（線形）とする。
/// - パターン共通の描画変換: `DrawingBrushParameterBase.
///   CreateBrushMatrix` = アスペクト拡縮 → 左右反転拡縮 → 回転 →
///   平行移動（行ベクトル規約で左から適用）。Scalable 系は先頭へ
///   拡縮（Zoom/100）を追加する。
/// - グラデーションメッシュ: `GradientMeshBrushSource` +
///   `GradientMeshPatchBuilder`。格子点の Coons パッチを CPU 側で
///   テッセレーションして頂点色で描く（`GradientMeshGeometry`）。
///   本家は D2D のグラデーションメッシュで描くため、テッセレー
///   ション密度と外周エッジのアンチエイリアスは再現できない
///   （既知の差分）。拡張（ExtendOutside）の対象境界は本家では
///   MaximumBitmapSize の矩形だが、こちらは塗り境界を使う
///   （描画範囲外は結果に影響しない）。
///
/// グラデーションの分岐点補間は本家どおり成分線形
/// （D2D `Gamma.StandardRgb` は格納値の成分線形補間に相当）で、
/// 補間後に Premultiplied 化する（#45 の Gradient 実装で検証済みの
/// 規約と同じ）。

// MARK: - 2次元アフィン変換（System.Numerics Matrix3x2 の行ベクトル規約）

/// 本家 Matrix3x2 と同じ規約の 2D アフィン変換。
/// 点 (x, y) は (a・x + c・y + tx, b・x + d・y + ty) へ写る。
struct BrushAffine: Equatable {
    var a: Double
    var b: Double
    var c: Double
    var d: Double
    var tx: Double
    var ty: Double

    static var identity: BrushAffine {
        BrushAffine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    }

    static func scale(_ sx: Double, _ sy: Double) -> BrushAffine {
        BrushAffine(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    /// 本家 CreateRotation（反時計回り。y 下向き座標では時計回りに見える）。
    static func rotation(_ radians: Double) -> BrushAffine {
        let cosine = cos(radians)
        let sine = sin(radians)
        return BrushAffine(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    static func translation(_ x: Double, _ y: Double) -> BrushAffine {
        BrushAffine(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    init(values: [Float]) {
        self.init(
            a: Double(values[0]), b: Double(values[1]),
            c: Double(values[2]), d: Double(values[3]),
            tx: Double(values[4]), ty: Double(values[5])
        )
    }

    var values: [Float] {
        [Float(a), Float(b), Float(c), Float(d), Float(tx), Float(ty)]
    }

    /// self を先に適用し、次に next を適用する合成（本家の行列積
    /// `self * next` と同じ）。
    func then(_ next: BrushAffine) -> BrushAffine {
        BrushAffine(
            a: a * next.a + b * next.c,
            b: a * next.b + b * next.d,
            c: c * next.a + d * next.c,
            d: c * next.b + d * next.d,
            tx: tx * next.a + ty * next.c + next.tx,
            ty: tx * next.b + ty * next.d + next.ty
        )
    }

    /// 逆変換。行列式が 0 の場合は nil。
    func inverted() -> BrushAffine? {
        let determinant = a * d - b * c
        guard determinant != 0 else { return nil }
        let ia = d / determinant
        let ib = -b / determinant
        let ic = -c / determinant
        let id = a / determinant
        return BrushAffine(
            a: ia, b: ib, c: ic, d: id,
            tx: -(tx * ia + ty * ic),
            ty: -(tx * ib + ty * id)
        )
    }
}

/// 本家 `Color` を直色（非 Premultiplied）の Vector4 へ変換する
/// （グラデーション分岐点用）。
func straightVector(_ color: Color) -> SIMD4<Float> {
    SIMD4<Float>(
        Float(color.red) / 255,
        Float(color.green) / 255,
        Float(color.blue) / 255,
        Float(color.alpha) / 255
    )
}

// MARK: - 評価済みブラシ仕様

/// フレーム評価済みのブラシ塗り仕様。シェーダのユニフォームと
/// ビットマップ参照をそのまま保持し、図形 Source の再描画キーにも
/// 使えるよう Equatable とする。単色・未対応ブラシは仕様を作らず
/// nil で表す（呼び出し側が既存経路／素通しへ倒す）。
struct BrushFillSpec: Equatable {
    /// シェーダの mode（0=線形, 1=放射, 2=市松, 3=ドット, 4=格子線,
    /// 5=ビットマップ, 6=グラデーションメッシュ）。
    var mode: UInt32
    /// 線形 = 始点、放射 = 中心。
    var pointA: SIMD2<Float> = .zero
    /// 線形 = 終点、放射 = 焦点。
    var pointB: SIMD2<Float> = .zero
    /// 放射の半径 (rx, ry)。
    var radii: SIMD2<Float> = .zero
    /// パターン座標への逆変換（放射・パターン系）。
    var invA: SIMD2<Float> = SIMD2(1, 0)
    var invC: SIMD2<Float> = SIMD2(0, 1)
    var invT: SIMD2<Float> = .zero
    /// グラデーションの延長方式（0=Clamp, 1=Wrap, 2=Mirror）。
    var extendMode: UInt32 = 0
    /// 分岐点の色（直色、Offset 昇順）。
    var stopColors: [SIMD4<Float>] = []
    var stopOffsets: [Float] = []
    /// パターン色（Premultiplied）。
    var color1: SIMD4<Float> = .zero
    var color2: SIMD4<Float> = .zero
    /// パターン寸法（mode ごとの意味はシェーダ側コメント参照）。
    var pattern: SIMD4<Float> = .zero
    /// ビットマップの解決済みファイルパス。
    var bitmapPath: String = ""
    var bitmapExtendX: UInt32 = 1
    var bitmapExtendY: UInt32 = 1
    /// ビットマップの前方変換のうち拡縮・描画変換の部分（6要素）。
    /// 中心化の平行移動はテクスチャ寸法が要るため描画時に前置する。
    var bitmapAffine: [Float] = []
    /// グラデーションメッシュのテッセレーション済み頂点（mode 6）。
    /// 空の場合は本家どおり透明な塗りになる。
    var meshVertices: [GradientMeshVertex] = []
    var meshIndices: [UInt32] = []
}

// MARK: - レンダラ

/// ブラシ塗りをテクスチャへ描く。ビットマップのデコード結果と
/// サンプラはインスタンス内にキャッシュする（処理器・図形 Source が
/// 所有する）。
final class MetalBrushFillRenderer {
    private let context: MetalGraphicsContext
    private var bitmapCache: [String: MTLTexture] = [:]
    private var samplerCache: [UInt32: MTLSamplerState] = [:]

    init(context: MetalGraphicsContext) {
        self.context = context
    }

    // MARK: 仕様の構築

    /// ブラシをフレーム評価して仕様を作る。単色ブラシ（呼び出し側の
    /// 既存経路が担当）と、GPU で描けないブラシ（ノイズ・
    /// コミュニティ等の生保持）は nil。
    /// `patternBounds` は本家がブラシの Update へ渡す境界であり、
    /// 線形グラデーションの Relative モードだけが参照する。
    static func spec(
        brush: Brush, patternBounds: RectF, frame: Int, length: Int, fps: Int
    ) -> BrushFillSpec? {
        guard brush.nonObjectRawValue == nil else { return nil }
        func eval(_ animation: Animation) -> Double {
            animation.value(atFrame: frame, length: length, fps: fps)
        }
        func drawingAffine(_ transform: BrushDrawingTransform) -> BrushAffine {
            let aspect = eval(transform.aspect) / 100
            return BrushAffine.scale(1 - max(0, aspect), 1 + min(0, aspect))
                .then(.scale(transform.isInverted ? -1 : 1, 1))
                .then(.rotation(eval(transform.angle) * Double.pi / 180))
                .then(.translation(eval(transform.x), eval(transform.y)))
        }
        func setInverse(_ spec: inout BrushFillSpec, _ affine: BrushAffine) -> Bool {
            guard let inverse = affine.inverted() else { return false }
            spec.invA = SIMD2(Float(inverse.a), Float(inverse.b))
            spec.invC = SIMD2(Float(inverse.c), Float(inverse.d))
            spec.invT = SIMD2(Float(inverse.tx), Float(inverse.ty))
            return true
        }

        switch brush.parameter {
        case .solidColor, .preserved, .noise:
            return nil

        case .linearGradient(let parameter):
            guard let stops = gradientStops(parameter.stops) else { return nil }
            var spec = BrushFillSpec(mode: 0)
            spec.extendMode = extendValue(parameter.extendMode)
            spec.stopColors = stops.colors
            spec.stopOffsets = stops.offsets
            let size = max(0.001, eval(parameter.size))
            let offset = eval(parameter.offset)
            let radians = eval(parameter.angle) * Double.pi / 180
            let vx = cos(radians)
            let vy = sin(radians)
            switch parameter.coordinateMode {
            case .relative:
                let width = patternBounds.right - patternBounds.left
                let height = patternBounds.bottom - patternBounds.top
                let projection = width * abs(vx) + height * abs(vy)
                let length = max(0.001, projection * size / 100)
                let shift = projection * offset / 100
                let centerX = (patternBounds.left + patternBounds.right) / 2
                let centerY = (patternBounds.top + patternBounds.bottom) / 2
                spec.pointA = SIMD2(
                    Float(centerX + vx * (-length / 2 + shift)),
                    Float(centerY + vy * (-length / 2 + shift))
                )
                spec.pointB = SIMD2(
                    Float(centerX + vx * (length / 2 + shift)),
                    Float(centerY + vy * (length / 2 + shift))
                )
            case .pixel, .unknown:
                // unknown は本家では到達しない前提で Pixel として扱う。
                spec.pointA = SIMD2(
                    Float(vx * (-size / 2 + offset)),
                    Float(vy * (-size / 2 + offset))
                )
                spec.pointB = SIMD2(
                    Float(vx * (size / 2 + offset)),
                    Float(vy * (size / 2 + offset))
                )
            }
            return spec

        case .radialGradient(let parameter):
            guard let stops = gradientStops(parameter.stops) else { return nil }
            var spec = BrushFillSpec(mode: 1)
            spec.extendMode = extendValue(parameter.extendMode)
            spec.stopColors = stops.colors
            spec.stopOffsets = stops.offsets
            let zoom = eval(parameter.zoom) / 100
            let aspect = eval(parameter.aspect) / 100
            let factorX = 1 - max(0, aspect)
            let factorY = 1 + min(0, aspect)
            let centerX = eval(parameter.centerX)
            let centerY = eval(parameter.centerY)
            spec.pointA = SIMD2(Float(centerX), Float(centerY))
            spec.pointB = SIMD2(
                Float(centerX + eval(parameter.originX) * zoom * factorX),
                Float(centerY + eval(parameter.originY) * zoom * factorY)
            )
            spec.radii = SIMD2(
                Float(eval(parameter.radiusX) * zoom * factorX),
                Float(eval(parameter.radiusY) * zoom * factorY)
            )
            let transform = BrushAffine.rotation(eval(parameter.angle) * Double.pi / 180)
                .then(.scale(parameter.isInverted ? -1 : 1, 1))
            guard setInverse(&spec, transform) else { return nil }
            return spec

        case .checkered(let parameter):
            var spec = BrushFillSpec(mode: 2)
            let size = Int(max(1.0, eval(parameter.size)))
            spec.pattern = SIMD4(Float(size), 0, 0, 0)
            spec.color1 = premultipliedVector(parameter.color1)
            spec.color2 = premultipliedVector(parameter.color2)
            guard setInverse(&spec, drawingAffine(parameter.drawing)) else { return nil }
            return spec

        case .dot(let parameter):
            var spec = BrushFillSpec(mode: 3)
            let zoom = eval(parameter.zoom) / 100
            let span = Int(max(1.0, eval(parameter.span) * zoom))
            spec.pattern = SIMD4(
                Float(span), Float(eval(parameter.radius) * zoom), 0, 0
            )
            spec.color1 = premultipliedVector(parameter.foreground)
            spec.color2 = premultipliedVector(parameter.background)
            guard setInverse(&spec, drawingAffine(parameter.drawing)) else { return nil }
            return spec

        case .stripe(let parameter):
            var spec = BrushFillSpec(mode: 0)
            let zoom = eval(parameter.zoom) / 100
            let width1 = eval(parameter.width1) * zoom
            let width2 = eval(parameter.width2) * zoom
            let offset = eval(parameter.offset) * zoom
            let radians = eval(parameter.angle) * Double.pi / 180
            let cosine = cos(radians)
            let sine = sin(radians)
            func rotated(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
                (x * cosine - y * sine, x * sine + y * cosine)
            }
            let start = rotated(offset - width1 / 2, 0)
            let endBase = rotated(width1 + width2 - width1 / 2, 0)
            let endShift = rotated(offset, 0)
            spec.pointA = SIMD2(Float(start.x), Float(start.y))
            spec.pointB = SIMD2(
                Float(endBase.x + endShift.x), Float(endBase.y + endShift.y)
            )
            let position = (width1 + width2 == 0)
                ? 0.5
                : width1 / (width1 + width2)
            spec.stopColors = [
                straightVector(parameter.color1), straightVector(parameter.color1),
                straightVector(parameter.color2), straightVector(parameter.color2),
            ]
            spec.stopOffsets = [0, Float(position), Float(position), 1]
            spec.extendMode = 1
            return spec

        case .gridLine(let parameter):
            var spec = BrushFillSpec(mode: 4)
            let zoom = eval(parameter.zoom) / 100
            let tileWidth = Int(max(eval(parameter.width) * zoom, 1.0))
            let tileHeight = Int(max(eval(parameter.height) * zoom, 1.0))
            spec.pattern = SIMD4(
                Float(tileWidth), Float(tileHeight),
                Float(eval(parameter.thickness) * zoom), 0
            )
            spec.color1 = premultipliedVector(parameter.strokeColor)
            spec.color2 = premultipliedVector(parameter.backgroundColor)
            guard setInverse(&spec, drawingAffine(parameter.drawing)) else { return nil }
            return spec

        case .bitmap(let parameter):
            guard let path = parameter.filePath, !path.isEmpty,
                  let url = resolveMediaURL(path: path, baseDirectory: nil)
            else { return nil }
            var spec = BrushFillSpec(mode: 5)
            spec.bitmapPath = url.path
            spec.bitmapExtendX = extendValue(parameter.extendModeX)
            spec.bitmapExtendY = extendValue(parameter.extendModeY)
            let zoom = eval(parameter.zoom) / 100
            let forward = BrushAffine.scale(zoom, zoom)
                .then(drawingAffine(parameter.drawing))
            spec.bitmapAffine = forward.values
            return spec

        case .gradientMesh(let parameter):
            var spec = BrushFillSpec(mode: 6)
            let horizontalCount = parameter.horizontalCount
            let verticalCount = parameter.verticalCount
            var snapshots: [GradientMeshSnapshot] = []
            if horizontalCount >= 2, verticalCount >= 2,
               parameter.points.count == horizontalCount * verticalCount {
                // 本家 GetLogicalPointSnapshots: 論理配置は
                // -W/2 + W・列/(横点数-1) + 点オフセット・(W/100)。
                // ハンドルは内向きかつカスタムの方向だけが値を持つ。
                let meshWidth = eval(parameter.width)
                let meshHeight = eval(parameter.height)
                let offsetScaleX = meshWidth / 100
                let offsetScaleY = meshHeight / 100
                for row in 0..<verticalCount {
                    for column in 0..<horizontalCount {
                        let point = parameter.points[row * horizontalCount + column]
                        let position = SIMD2<Double>(
                            -meshWidth / 2
                                + meshWidth * Double(column) / Double(horizontalCount - 1)
                                + eval(point.x) * offsetScaleX,
                            -meshHeight / 2
                                + meshHeight * Double(row) / Double(verticalCount - 1)
                                + eval(point.y) * offsetScaleY
                        )
                        func customHandle(
                            _ isCustom: Bool, _ animationX: Animation,
                            _ animationY: Animation
                        ) -> SIMD2<Double>? {
                            guard isCustom else { return nil }
                            return position + SIMD2(
                                eval(animationX) * offsetScaleX,
                                eval(animationY) * offsetScaleY
                            )
                        }
                        snapshots.append(GradientMeshSnapshot(
                            position: position,
                            leftHandle: column > 0
                                ? customHandle(
                                    point.isLeftHandleCustom,
                                    point.leftHandleX, point.leftHandleY)
                                : nil,
                            rightHandle: column < horizontalCount - 1
                                ? customHandle(
                                    point.isRightHandleCustom,
                                    point.rightHandleX, point.rightHandleY)
                                : nil,
                            upHandle: row > 0
                                ? customHandle(
                                    point.isUpHandleCustom,
                                    point.upHandleX, point.upHandleY)
                                : nil,
                            downHandle: row < verticalCount - 1
                                ? customHandle(
                                    point.isDownHandleCustom,
                                    point.downHandleX, point.downHandleY)
                                : nil,
                            color: straightVector(point.color)
                        ))
                    }
                }
            }
            // 本家 CreateTransform: ブラシ行列 × 境界中心への平行移動。
            let zoom = eval(parameter.zoom) / 100
            let brushMatrix = BrushAffine.scale(zoom, zoom)
                .then(drawingAffine(parameter.drawing))
            let transform = brushMatrix.then(.translation(
                (patternBounds.left + patternBounds.right) / 2,
                (patternBounds.top + patternBounds.bottom) / 2
            ))
            let geometry = GradientMeshGeometry.build(
                horizontalCount: horizontalCount,
                verticalCount: verticalCount,
                snapshots: snapshots,
                coordinateMode: parameter.coordinateMode,
                extendOutside: parameter.extendOutside,
                bounds: patternBounds,
                transform: transform
            )
            spec.meshVertices = geometry.vertices
            spec.meshIndices = geometry.indices
            return spec
        }
    }

    /// 分岐点列を Offset 昇順へ並べ替えてシェーダ用に変換する。
    /// 空の列と過大な列（シェーダのバイトバッファ上限）は未対応。
    private static func gradientStops(
        _ stops: [GradientStopValue]
    ) -> (colors: [SIMD4<Float>], offsets: [Float])? {
        guard !stops.isEmpty, stops.count <= 128 else { return nil }
        let sorted = stops.sorted { $0.offset < $1.offset }
        return (
            colors: sorted.map { straightVector($0.color) },
            offsets: sorted.map { Float($0.offset) }
        )
    }

    /// 本家 ExtendMode をシェーダの数値へ写す。unknown は Clamp。
    private static func extendValue(_ mode: ExtendMode) -> UInt32 {
        switch mode {
        case .wrap: return 1
        case .mirror: return 2
        case .clamp, .unknown: return 0
        }
    }

    // MARK: 描画

    /// 仕様の塗りを `outputBounds` 全体へ描く。出力境界が空の場合と
    /// ビットマップの読み込みに失敗した場合は nil。
    func render(spec: BrushFillSpec, outputBounds: RectF) throws -> MetalImage? {
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        guard outWidth > 0, outHeight > 0 else { return nil }

        if spec.mode == 6 {
            return try renderMesh(spec: spec, outputBounds: outputBounds)
        }

        var uniforms = BrushPassUniforms(
            outputOrigin: SIMD2(Float(outputBounds.left), Float(outputBounds.top)),
            outputSize: SIMD2(Float(outWidth), Float(outHeight)),
            pointA: spec.pointA,
            pointB: spec.pointB,
            radii: spec.radii,
            invA: spec.invA,
            invC: spec.invC,
            invT: spec.invT,
            color1: spec.color1,
            color2: spec.color2,
            pattern: spec.pattern,
            mode: spec.mode,
            extendMode: spec.extendMode,
            stopCount: UInt32(spec.stopColors.count),
            pad0: 0
        )
        var tile: MTLTexture = context.devices.transparentTexture
        var sampler: MTLSamplerState = context.devices.linearSampler
        if spec.mode == 5 {
            guard spec.bitmapAffine.count == 6,
                  let loaded = bitmapTexture(path: spec.bitmapPath)
            else { return nil }
            tile = loaded
            // 中心化（整数除算は本家の C# と同じ 0 方向への切り捨て。
            // 寸法は正のため床と一致する）。
            let forward = BrushAffine.translation(
                -Double(loaded.width / 2), -Double(loaded.height / 2)
            ).then(BrushAffine(values: spec.bitmapAffine))
            guard let inverse = forward.inverted() else { return nil }
            uniforms.invA = SIMD2(Float(inverse.a), Float(inverse.b))
            uniforms.invC = SIMD2(Float(inverse.c), Float(inverse.d))
            uniforms.invT = SIMD2(Float(inverse.tx), Float(inverse.ty))
            sampler = bitmapSampler(
                extendX: spec.bitmapExtendX, extendY: spec.bitmapExtendY
            )
        }

        let output = try makeOutputTexture(width: outWidth, height: outHeight)
        var stopColors = spec.stopColors.isEmpty ? [.zero] : spec.stopColors
        var stopOffsets = spec.stopOffsets.isEmpty ? [0] : spec.stopOffsets
        try executePass(output: output, pipeline: context.devices.brushPipeline) { encoder in
            encoder.setFragmentTexture(tile, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<BrushPassUniforms>.size, index: 0
            )
            encoder.setFragmentBytes(
                &stopColors, length: MemoryLayout<SIMD4<Float>>.size * stopColors.count,
                index: 1
            )
            encoder.setFragmentBytes(
                &stopOffsets, length: MemoryLayout<Float>.size * stopOffsets.count,
                index: 2
            )
        }
        return MetalImage(texture: output, bounds: outputBounds)
    }

    /// グラデーションメッシュの描画。頂点が空の場合は本家どおり
    /// 透明な塗り（クリアのみ）を返す。
    private func renderMesh(
        spec: BrushFillSpec, outputBounds: RectF
    ) throws -> MetalImage? {
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        let output = try makeOutputTexture(width: outWidth, height: outHeight)
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        let passDescriptor = MTLRenderPassDescriptor()
        let attachment = passDescriptor.colorAttachments[0]
        attachment?.texture = output
        attachment?.loadAction = .clear
        attachment?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        attachment?.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        encoder.setRenderPipelineState(context.devices.meshPipeline)
        if !spec.meshVertices.isEmpty, !spec.meshIndices.isEmpty {
            var uniforms = MeshPassUniforms(
                outputOrigin: SIMD2(
                    Float(outputBounds.left), Float(outputBounds.top)),
                outputSize: SIMD2(Float(outWidth), Float(outHeight))
            )
            var vertices = spec.meshVertices
            var indices = spec.meshIndices
            guard let vertexBuffer = context.devices.device.makeBuffer(
                bytes: &vertices,
                length: MemoryLayout<GradientMeshVertex>.stride * vertices.count,
                options: [.storageModeShared]
            ) else {
                throw MetalRenderError.commandBufferFailed(underlying: nil)
            }
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(
                &uniforms, length: MemoryLayout<MeshPassUniforms>.size, index: 1
            )
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indices.count,
                indexType: .uint32,
                indexBuffer: try makeIndexBuffer(indices: &indices),
                indexBufferOffset: 0
            )
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw MetalRenderError.commandBufferFailed(underlying: commandBuffer.error)
        }
        return MetalImage(texture: output, bounds: outputBounds)
    }

    private func makeIndexBuffer(indices: inout [UInt32]) throws -> MTLBuffer {
        guard let buffer = context.devices.device.makeBuffer(
            bytes: &indices, length: MemoryLayout<UInt32>.size * indices.count,
            options: [.storageModeShared]
        ) else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        return buffer
    }

    /// 塗り画像をマスク画像のアルファで切り取る（本家 AlphaMask）。
    /// 図形 Source のブラシ塗りで使う（処理器側は renderWarp を使う）。
    func maskedByAlpha(fill: MetalImage, mask: MetalImage) throws -> MetalImage {
        let outputBounds = fill.bounds
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        guard outWidth > 0, outHeight > 0 else { return fill }
        let output = try makeOutputTexture(width: outWidth, height: outHeight)
        var uniforms = WarpPassUniforms(
            inputPlane: planeVector(fill),
            maskPlane: planeVector(mask),
            param0: .zero,
            param1: .zero,
            inputOffset: SIMD2(Float(fill.planeOffset.x), Float(fill.planeOffset.y)),
            maskOffset: SIMD2(Float(mask.planeOffset.x), Float(mask.planeOffset.y)),
            outputOrigin: SIMD2(Float(outputBounds.left), Float(outputBounds.top)),
            outputSize: SIMD2(Float(outWidth), Float(outHeight)),
            mode: 3,
            pad0: 0, pad1: 0, pad2: 0
        )
        try executePass(output: output, pipeline: context.devices.warpPipeline) { encoder in
            encoder.setFragmentTexture(fill.texture, index: 0)
            encoder.setFragmentTexture(mask.texture, index: 1)
            encoder.setFragmentSamplerState(context.devices.borderSampler, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<WarpPassUniforms>.size, index: 0
            )
        }
        return MetalImage(texture: output, bounds: outputBounds)
    }

    // MARK: 内部

    private func planeVector(_ image: MetalImage) -> SIMD4<Float> {
        SIMD4<Float>(
            Float(image.texturePlaneRect.left), Float(image.texturePlaneRect.top),
            Float(image.texturePlaneRect.right - image.texturePlaneRect.left),
            Float(image.texturePlaneRect.bottom - image.texturePlaneRect.top)
        )
    }

    private func makeOutputTexture(width: Double, height: Double) throws -> MTLTexture {
        let pixelWidth = max(1, Int(ceil(width)))
        let pixelHeight = max(1, Int(ceil(height)))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: pixelWidth, height: pixelHeight,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = context.devices.device.makeTexture(descriptor: descriptor)
        else {
            throw MetalRenderError.textureCreationFailed(
                width: pixelWidth, height: pixelHeight
            )
        }
        return texture
    }

    private func executePass(
        output: MTLTexture,
        pipeline: MTLRenderPipelineState,
        configure: (MTLRenderCommandEncoder) -> Void
    ) throws {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        let passDescriptor = MTLRenderPassDescriptor()
        let attachment = passDescriptor.colorAttachments[0]
        attachment?.texture = output
        attachment?.loadAction = .clear
        attachment?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        attachment?.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        encoder.setRenderPipelineState(pipeline)
        let quad: [QuadVertex] = [
            QuadVertex(position: SIMD4(-1, 1, 0, 1), uv: SIMD2(0, 0)),
            QuadVertex(position: SIMD4(1, 1, 0, 1), uv: SIMD2(1, 0)),
            QuadVertex(position: SIMD4(-1, -1, 0, 1), uv: SIMD2(0, 1)),
            QuadVertex(position: SIMD4(1, -1, 0, 1), uv: SIMD2(1, 1)),
        ]
        encoder.setVertexBytes(
            quad, length: MemoryLayout<QuadVertex>.stride * quad.count, index: 0
        )
        configure(encoder)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw MetalRenderError.commandBufferFailed(underlying: commandBuffer.error)
        }
    }

    /// ビットマップブラシの画像を読み込む（パス単位でキャッシュ）。
    /// 動画ファイルは ImageIO で開けないため nil（未対応）。
    private func bitmapTexture(path: String) -> MTLTexture? {
        if let cached = bitmapCache[path] { return cached }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let decoded = makePremultipliedTexture(
                device: context.devices.device, cgImage: cgImage
              )
        else { return nil }
        bitmapCache[path] = decoded.texture
        return decoded.texture
    }

    /// ビットマップブラシ用のサンプラ（軸ごとに延長方式が異なる）。
    private func bitmapSampler(extendX: UInt32, extendY: UInt32) -> MTLSamplerState {
        let key = extendX * 8 + extendY
        if let cached = samplerCache[key] { return cached }
        func address(_ value: UInt32) -> MTLSamplerAddressMode {
            switch value {
            case 1: return .repeat
            case 2: return .mirrorRepeat
            default: return .clampToEdge
            }
        }
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = address(extendX)
        descriptor.tAddressMode = address(extendY)
        guard let sampler = context.devices.device.makeSamplerState(descriptor: descriptor)
        else { return context.devices.linearSampler }
        samplerCache[key] = sampler
        return sampler
    }
}

/// グラデーションメッシュシェーダのユニフォーム
/// （MetalGraphics のシェーダ定義と一致）。
struct MeshPassUniforms {
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
}

/// ブラシ塗りシェーダのユニフォーム（MetalGraphics のシェーダ定義と一致）。
struct BrushPassUniforms {
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var pointA: SIMD2<Float>
    var pointB: SIMD2<Float>
    var radii: SIMD2<Float>
    var invA: SIMD2<Float>
    var invC: SIMD2<Float>
    var invT: SIMD2<Float>
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var pattern: SIMD4<Float>
    var mode: UInt32
    var extendMode: UInt32
    var stopCount: UInt32
    var pad0: Float
}

#endif
