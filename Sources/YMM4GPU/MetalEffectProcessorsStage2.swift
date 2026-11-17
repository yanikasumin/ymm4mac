#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// GPU エフェクト処理器 第2段（MAC-0028）。
///
/// 第1段（色変換系10種）に続き、幾何変換・ぼかし／マスク・影／塗り・
/// ワープ・イン／アウト・ランダム／反復の31種を Metal で実装する。
/// 各処理器のパラメータ意味論は本家の逆コンパイル実コード
/// （Player.Video.Effects 配下の該当クラス）で確認したものだけを
/// 実装し、式の根拠は各処理器のコメントに記す。数式がコンパイル済み
/// カスタムシェーダ（.cso）の中にしか無いもの、D2D 組み込みで計算式が
/// 公開されていないもの、メッシュ描画系、エフェクト内ファイル読み込み
/// が要るものは素通しのまま残す（対象外の一覧と理由は実装記録側）。
///
/// 中間画像が画面サイズへ折り畳まれている点（MAC-0012 レビュー条件
/// G12-01..06）により、本家の無限平面と差が出うる箇所は各処理器の
/// コメントに差分として明記する。

// MARK: - 共通ヘルパ

extension MetalEffectProcessor {
    /// Animation の現在フレーム評価（本家の GetValue(frame, length, fps)）。
    func evaluate(_ animation: Animation, _ description: EffectDescription) -> Double {
        let (frame, length, fps) = evaluationContext(description)
        return animation.value(atFrame: frame, length: length, fps: fps)
    }

    /// イン／アウト系のイージング値。Core の
    /// `InOutEffectProcessorBase.easingValue`（本家 GetEasingValue）と
    /// 同じ式を、Metal 処理器側でも使えるよう再掲する。
    func inOutEasingValue(
        _ definition: InOutEffectDefinitionBase,
        _ description: EffectDescription,
        from: Double,
        to: Double
    ) -> Double {
        let positionSeconds = description.itemDescription.itemPosition.time
        let durationSeconds = description.itemDescription.itemDuration.time
        let time = definition.effectTimeSeconds
        let inRate = (definition.isInEffect && time > 0)
            ? min(max(positionSeconds / time, 0), 1)
            : 1
        let outRate = (definition.isOutEffect && time > 0)
            ? min(max((durationSeconds - positionSeconds) / time, 0), 1)
            : 1
        let rate = min(inRate, outRate)
        let eased = EasingFamily.getValue(
            family: definition.easingFamily, mode: definition.easingMode, rate: rate
        )
        return from + (to - from) * eased
    }

    /// ランダム系の乱数率。Core の `RandomEffectProcessorBase.randomValue`
    /// （本家 GetRandomValue）と同じ式を再掲する。種は定義の randomSeed
    /// （本家 GetHashCode の代替。対応付けは未解決事項として既存台帳に
    /// 記録済み）。
    func randomRate(
        _ definition: RandomEffectDefinitionBase,
        _ description: EffectDescription,
        parameterID: Int64
    ) -> Double {
        let (frame, length, fps) = evaluationContext(description)
        let span = definition.span.value(atFrame: frame, length: length, fps: fps)
        if span != 0 {
            return Animation.randomMoveRate(
                seed: definition.randomSeed,
                id: parameterID,
                frame: frame,
                fps: fps,
                span: span,
                seedOffset: Int64(description.inputIndex)
            )
        }
        return StatelessRandom.getDouble(keys: [
            definition.randomSeed,
            parameterID,
            Int64(frame),
            Int64(description.inputIndex),
        ])
    }

    /// 反復系のイージング値。Core の `RepeatEffectProcessorBase.easingValue`
    /// （本家 GetEasingValue）と同じ式を再掲する。Span = 0 の偶奇は
    /// 処理器側の実測（奇数フレーム = to）に従う。
    func repeatEasingValue(
        _ definition: RepeatEffectDefinitionBase,
        _ description: EffectDescription,
        from: Double,
        to: Double
    ) -> Double {
        let (frame, length, fps) = evaluationContext(description)
        let span = definition.span.value(atFrame: frame, length: length, fps: fps)
        let centerOffset = definition.isCentering ? -(to - from) / 2 : 0
        if span == 0 {
            return centerOffset + (frame % 2 != 0 ? to : from)
        }
        var seconds = description.itemDescription.itemPosition.time
        if definition.isCentering && definition.easingMode == .inOut {
            seconds += span / 4
        }
        let rate = Animation.repeatMoveRate(
            sec: seconds, span: span,
            family: definition.easingFamily, mode: definition.easingMode
        )
        return centerOffset + from + (to - from) * rate
    }

    /// 透視行列（本家の Transform3D チェーン末尾の固定行列。M34 = −0.001）。
    var perspectiveMatrix: Matrix4x4 {
        var matrix = Matrix4x4.identity
        matrix.m34 = -0.001
        return matrix
    }

    /// 行列が恒等かどうか（16要素の直接比較）。
    func isIdentity(_ matrix: Matrix4x4) -> Bool {
        matrix == .identity
    }

    /// 回転系の画像行列。本家 RotateEffect の非3D分岐:
    /// Scale(DrawDescription.Zoom, 原点) · Rz(Z°) · Ry(−Y°) · Rx(−X°) · 透視。
    /// 左端の変換が先に適用される（System.Numerics の行ベクトル規約）。
    func rotationBakeMatrix(zoom: Vector2, angleX: Double, angleY: Double, angleZ: Double) -> Matrix4x4 {
        let scale = Matrix4x4.createScale(x: zoom.x, y: zoom.y, z: 1, center: .zero)
        let rz = Matrix4x4.createRotationZ(angleZ * Double.pi / 180)
        let ry = Matrix4x4.createRotationY(-angleY * Double.pi / 180)
        let rx = Matrix4x4.createRotationX(-angleX * Double.pi / 180)
        return scale * rz * ry * rx * perspectiveMatrix
    }

    /// 回転系の画像焼き込みと戻り DrawDescription の対。
    /// 3D 分岐では画像は無変換で、回転は DrawDescription 側へ積む
    /// （本家 RotateEffect.Update の戻り値どおり）。
    func bakeRotation(
        input: MetalImage,
        description: EffectDescription,
        angleX: Double,
        angleY: Double,
        angleZ: Double,
        is3D: Bool
    ) throws -> MetalImage? {
        guard !is3D else { return input }
        let matrix = rotationBakeMatrix(
            zoom: description.drawDescription.zoom,
            angleX: angleX, angleY: angleY, angleZ: angleZ
        )
        guard !isIdentity(matrix) else { return input }
        let outputBounds = MetalDrawingEffect.boundingRect(of: input.bounds, transformedBy: matrix)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: outputBounds,
            interpolation: description.drawDescription.zoomInterpolationMode
        )
    }

    /// 回転系の戻り DrawDescription（3D: 回転を加算、非3D: Zoom を等倍へ）。
    func rotationDrawDescription(
        _ description: EffectDescription,
        angleX: Double,
        angleY: Double,
        angleZ: Double,
        is3D: Bool
    ) -> DrawDescription {
        var result = description.drawDescription
        if is3D {
            result.rotation = Vector3(
                x: result.rotation.x + angleX,
                y: result.rotation.y + angleY,
                z: result.rotation.z + angleZ
            )
        } else {
            result.zoom = Vector2(x: 1, y: 1)
        }
        return result
    }

    /// 傾斜の中心点。本家 SkewEffect の switch（Center → 原点、
    /// Custom → パラメータ、他は入力境界の辺）どおり。
    func skewCenter(
        mode: SkewCenterPoint, centerX: Double, centerY: Double, bounds: RectF
    ) -> (x: Double, y: Double) {
        switch mode {
        case .center, .unknown:
            // unknown は定義の既定 (.center) として評価する（MAC-0018 の方針）。
            return (0, 0)
        case .custom:
            return (centerX, centerY)
        case .top:
            return (0, bounds.top)
        case .bottom:
            return (0, bounds.bottom)
        case .left:
            return (bounds.left, 0)
        case .right:
            return (bounds.right, 0)
        }
    }

    /// 傾斜行列。本家 Matrix3x2.CreateSkew(angleX, angleY, center) の
    /// 4x4 埋め込み（M12 = tan(angleY), M21 = tan(angleX),
    /// M41 = −cy・tan(angleX), M42 = −cx・tan(angleY)）。
    func skewMatrix(angleX: Double, angleY: Double, center: (x: Double, y: Double)) -> Matrix4x4 {
        let tanX = tan(angleX * Double.pi / 180)
        let tanY = tan(angleY * Double.pi / 180)
        return Matrix4x4(
            m11: 1, m12: tanY, m13: 0, m14: 0,
            m21: tanX, m22: 1, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: 0,
            m41: -center.y * tanX, m42: -center.x * tanY, m43: 0, m44: 1
        )
    }

    /// 傾斜の画像焼き込み（本家 SkewEffect: AffineTransform2D のみ、
    /// DrawDescription は無変更）。
    func bakeSkew(
        input: MetalImage,
        description: EffectDescription,
        angleX: Double,
        angleY: Double,
        center: (x: Double, y: Double)
    ) throws -> MetalImage? {
        let matrix = skewMatrix(angleX: angleX, angleY: angleY, center: center)
        guard !isIdentity(matrix) else { return input }
        let outputBounds = MetalDrawingEffect.boundingRect(of: input.bounds, transformedBy: matrix)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: outputBounds,
            interpolation: description.drawDescription.zoomInterpolationMode
        )
    }
}

/// 単色ブラシの色を取り出す。ブラシ保持値（PreservedObject）は
/// `{ Type, Parameter: { $type, Color } }` の形（実ファイルで確認済み）。
/// ブラシ自体が無い場合は本家の既定（単色ブラシ・白:
/// SolidColorBrushParameter の初期色 Colors.White）として扱う。
/// 単色ブラシでないパラメータ（グラデーション等）は nil を返し、
/// 呼び出し側は素通しにする（ブラシサブシステムは差し替え点）。
func solidBrushColor(_ brush: PreservedObject?) -> Color? {
    guard let brush else { return .white }
    guard let parameter = brush.value.field("Parameter"),
          let typeName = parameter.field("$type")?.stringValue,
          typeName.contains("SolidColorBrushParameter")
    else { return nil }
    guard let colorText = parameter.field("Color")?.stringValue else {
        // 色キーが無い場合はパラメータの初期色（白）。
        return .white
    }
    return parseARGBColor(colorText)
}

/// "#AARRGGBB" 形式の色文字列を読む（本家の Color 保存形式）。
func parseARGBColor(_ text: String) -> Color? {
    var hex = text
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
    return Color(
        alpha: UInt8((value >> 24) & 0xFF),
        red: UInt8((value >> 16) & 0xFF),
        green: UInt8((value >> 8) & 0xFF),
        blue: UInt8(value & 0xFF)
    )
}

// MARK: - 幾何変換系

/// 回転。本家 `RotateEffect`。
/// 非3D: 画像へ Scale(Zoom) · Rz(Z) · Ry(−Y) · Rx(−X) · 透視 を焼き、
/// 戻り Zoom を (1,1) にする。3D: 画像は無変換で戻り Rotation へ加算。
/// 本家チェーン中間の Crop（SafeTransform3DHelper）は Transform3D の
/// 境界アーティファクト回避用で、こちらは1パスの焼き込みに畳む
/// （内部実装の違い。出力境界は変換後外接矩形で一致させる）。
public final class MetalRotateProcessor: MetalEffectProcessor {
    private let definition: RotateEffectDefinition

    public init(context: MetalGraphicsContext, definition: RotateEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func angles(_ description: EffectDescription) -> (x: Double, y: Double, z: Double) {
        (
            x: evaluate(definition.x, description),
            y: evaluate(definition.y, description),
            z: evaluate(definition.z, description)
        )
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let angle = angles(description)
        return try bakeRotation(
            input: input, description: description,
            angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let angle = angles(description)
        return rotationDrawDescription(
            description, angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }
}

/// 傾斜。本家 `SkewEffect`（AffineTransform2D + CreateSkew、
/// DrawDescription は無変更）。
public final class MetalSkewProcessor: MetalEffectProcessor {
    private let definition: SkewEffectDefinition

    public init(context: MetalGraphicsContext, definition: SkewEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let center = skewCenter(
            mode: definition.centerPoint,
            centerX: evaluate(definition.centerX, description),
            centerY: evaluate(definition.centerY, description),
            bounds: input.bounds
        )
        return try bakeSkew(
            input: input, description: description,
            angleX: evaluate(definition.angleX, description),
            angleY: evaluate(definition.angleY, description),
            center: center
        )
    }
}

/// 中心点。本家 `CenterPointEffect`。
/// 画像を (−cx, −cy) だけ平行移動する（AffineTransform2D）。こちらでは
/// テクスチャを作り直さず、境界と平面オフセットの付け替えで表す
/// （画素は不変）。IsKeepPosition の場合は戻り Draw へ (+cx, +cy) を加え、
/// 見かけの位置を保つ。
public final class MetalCenterPointProcessor: MetalEffectProcessor {
    private let definition: CenterPointEffectDefinition

    public init(context: MetalGraphicsContext, definition: CenterPointEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func center(_ description: EffectDescription, bounds: RectF) -> (x: Double, y: Double) {
        let cx: Double
        switch definition.horizontal {
        case .custom: cx = evaluate(definition.x, description)
        case .center: cx = (bounds.left + bounds.right) / 2
        case .left: cx = bounds.left
        case .right: cx = bounds.right
        case .origin, .unknown: cx = 0
        }
        let cy: Double
        switch definition.vertical {
        case .custom: cy = evaluate(definition.y, description)
        case .center: cy = (bounds.top + bounds.bottom) / 2
        case .top: cy = bounds.top
        case .bottom: cy = bounds.bottom
        case .origin, .unknown: cy = 0
        }
        return (cx, cy)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let c = center(description, bounds: input.bounds)
        guard c.x != 0 || c.y != 0 else { return input }
        return MetalImage(
            texture: input.texture,
            bounds: RectF(
                left: input.bounds.left - c.x, top: input.bounds.top - c.y,
                right: input.bounds.right - c.x, bottom: input.bounds.bottom - c.y
            ),
            texturePlaneRect: input.texturePlaneRect,
            planeOffset: Vector2(x: input.planeOffset.x + c.x, y: input.planeOffset.y + c.y),
            interpolation: input.interpolation
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        guard definition.isKeepPosition, let input else {
            return description.drawDescription
        }
        let c = center(description, bounds: input.bounds)
        var result = description.drawDescription
        result.draw = Vector3(
            x: result.draw.x + c.x, y: result.draw.y + c.y, z: result.draw.z
        )
        return result
    }
}

/// 切り抜き。本家 `CropEffect`。
/// 切り抜き矩形 = 入力境界から上下左右を差し引いた範囲。合計が寸法を
/// 超える場合は本家どおり Top = 高さ / Bottom = 0（左右も同様）に
/// クランプしてから矩形を作る。IsCentering の場合は矩形の中心が
/// 元の中心へ来るよう平行移動を加える。DrawDescription は無変更。
/// 焼き込みで確定させるため、後段のサンプリング系が切り抜き範囲外を
/// 読むことはない（本家の Crop 実体化と同じ）。
public final class MetalCropProcessor: MetalEffectProcessor {
    private let definition: CropEffectDefinition

    public init(context: MetalGraphicsContext, definition: CropEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        var top = evaluate(definition.top, description)
        var bottom = evaluate(definition.bottom, description)
        var left = evaluate(definition.left, description)
        var right = evaluate(definition.right, description)
        let width = input.bounds.right - input.bounds.left
        let height = input.bounds.bottom - input.bounds.top
        if top + bottom > height {
            top = height
            bottom = 0
        }
        if left + right > width {
            left = width
            right = 0
        }
        var rect = RectF(
            left: input.bounds.left + left, top: input.bounds.top + top,
            right: input.bounds.right - right, bottom: input.bounds.bottom - bottom
        )
        var translation = Vector2.zero
        if definition.isCentering {
            translation = Vector2(x: (right - left) / 2, y: (bottom - top) / 2)
            rect = RectF(
                left: rect.left + translation.x, top: rect.top + translation.y,
                right: rect.right + translation.x, bottom: rect.bottom + translation.y
            )
        }
        let isUnchanged = rect.left == input.bounds.left && rect.top == input.bounds.top
            && rect.right == input.bounds.right && rect.bottom == input.bounds.bottom
        guard !isUnchanged else { return input }
        let matrix = Matrix4x4.createTranslation(x: translation.x, y: translation.y, z: 0)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: rect,
            interpolation: input.interpolation
        )
    }
}

/// 余白。本家 `MarginEffect`。
/// 出力境界 = 入力境界と「上下左右へ広げた矩形」の和集合（負の余白では
/// 入力境界が残る）。内容の平面位置は不変。DrawDescription は無変更。
public final class MetalMarginProcessor: MetalEffectProcessor {
    private let definition: MarginEffectDefinition

    public init(context: MetalGraphicsContext, definition: MarginEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let expanded = RectF(
            left: input.bounds.left - evaluate(definition.left, description),
            top: input.bounds.top - evaluate(definition.top, description),
            right: input.bounds.right + evaluate(definition.right, description),
            bottom: input.bounds.bottom + evaluate(definition.bottom, description)
        )
        let union = input.bounds.union(expanded)
        let isUnchanged = union.left == input.bounds.left && union.top == input.bounds.top
            && union.right == input.bounds.right && union.bottom == input.bounds.bottom
        guard !isUnchanged else { return input }
        return try renderTransformed(
            input: input, matrix: .identity, outputBounds: union,
            interpolation: input.interpolation
        )
    }
}

/// 複写反転。本家 `CopyAndReverseEffect`。
/// 原本と、境界中心で反転（任意）＋平行移動した複写を、隙間の中央で
/// 半平面に切り分けて SourceOver 合成する。中心化の平行移動
/// (−dx/2, −dy/2) は常に行われ、IsCentering でない場合は戻り Draw へ
/// (+dx/2, +dy/2) を加えて相殺する。こちらでは半平面の切り分けを
/// ワープシェーダ（mode 4）で1パスに畳む。分割座標は本家どおり
/// ceil を含む式で求める。
public final class MetalCopyAndReverseProcessor: MetalEffectProcessor {
    private let definition: CopyAndReverseEffectDefinition

    public init(context: MetalGraphicsContext, definition: CopyAndReverseEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func layout(
        _ description: EffectDescription, bounds: RectF
    ) -> (dx: Double, dy: Double, split: Double, axisIsX: Bool, originalIsGreater: Bool) {
        let width = bounds.right - bounds.left
        let height = bounds.bottom - bounds.top
        let distance = evaluate(definition.distance, description)
        switch definition.position {
        case .left:
            return (-width - distance, 0, bounds.left - ceil(distance / 2), true, true)
        case .right:
            return (width + distance, 0, ceil(bounds.right + distance / 2), true, false)
        case .top:
            return (0, -height - distance, bounds.top - ceil(distance / 2), false, true)
        case .bottom, .unknown:
            // unknown は定義の既定 (.bottom) として評価する。
            return (0, height + distance, ceil(bounds.bottom + distance / 2), false, false)
        }
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let layout = layout(description, bounds: input.bounds)
        let centerX = (input.bounds.left + input.bounds.right) / 2
        let centerY = (input.bounds.top + input.bounds.bottom) / 2
        let cloneBounds = RectF(
            left: input.bounds.left + layout.dx, top: input.bounds.top + layout.dy,
            right: input.bounds.right + layout.dx, bottom: input.bounds.bottom + layout.dy
        )
        let union = input.bounds.union(cloneBounds)
        let outputBounds = RectF(
            left: union.left - layout.dx / 2, top: union.top - layout.dy / 2,
            right: union.right - layout.dx / 2, bottom: union.bottom - layout.dy / 2
        )
        return try renderWarp(
            input: input, mask: nil, outputBounds: outputBounds, mode: 4,
            param0: SIMD4<Float>(
                Float(layout.split), Float(centerX), Float(centerY), layout.axisIsX ? 0 : 1
            ),
            param1: SIMD4<Float>(
                Float(layout.dx), Float(layout.dy),
                definition.isLeftRightReversed ? -1 : 1,
                definition.isTopBottomReversed ? -1 : 1
            ),
            maskPlane: SIMD4<Float>(
                Float(layout.dx / 2), Float(layout.dy / 2),
                layout.originalIsGreater ? 0 : 1, 0
            )
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        guard !definition.isCentering, let input else {
            return description.drawDescription
        }
        let layout = layout(description, bounds: input.bounds)
        var result = description.drawDescription
        result.draw = Vector3(
            x: result.draw.x + layout.dx / 2,
            y: result.draw.y + layout.dy / 2,
            z: result.draw.z
        )
        return result
    }
}

/// タイリング。本家 `TilingEffect`。
/// 入力境界を int 化（切り捨て）した矩形をタイルとして nx × ny に並べ、
/// (L(nx−1), T(ny−1)) の平行移動で全体を中心寄せする（本家の
/// Tile → Crop → AffineTransform2D の構成）。こちらではワープ
/// シェーダ（mode 2）の剰余サンプリングで表す。タイル境界での線形
/// 補間の滲みは本家（D2D Tile のラップ）とは出方が違いうる（差分）。
public final class MetalTilingProcessor: MetalEffectProcessor {
    private let definition: TilingEffectDefinition

    public init(context: MetalGraphicsContext, definition: TilingEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let left = Double(Int(input.bounds.left))
        let top = Double(Int(input.bounds.top))
        let tileWidth = Double(Int(input.bounds.right)) - left
        let tileHeight = Double(Int(input.bounds.bottom)) - top
        let countX = Int(evaluate(definition.x, description))
        let countY = Int(evaluate(definition.y, description))
        // 最終平行移動 (L(nx−1), T(ny−1)) を含めた出力境界。
        let translationX = left * Double(countX - 1)
        let translationY = top * Double(countY - 1)
        let outputBounds = RectF(
            left: left + translationX, top: top + translationY,
            right: left + tileWidth * Double(countX) + translationX,
            bottom: top + tileHeight * Double(countY) + translationY
        )
        guard tileWidth > 0, tileHeight > 0, countX > 0, countY > 0 else {
            return MetalImage(texture: context.devices.transparentTexture, bounds: outputBounds)
        }
        if countX == 1 && countY == 1 {
            return input
        }
        return try renderWarp(
            input: input, mask: nil, outputBounds: outputBounds, mode: 2,
            param0: SIMD4<Float>(Float(left), Float(top), Float(tileWidth), Float(tileHeight)),
            param1: SIMD4<Float>(Float(translationX), Float(translationY), 0, 0)
        )
    }
}

/// 自動ズーム。本家 `AutomaticZoomEffect`（DrawDescription のみの変更、
/// 画像は無変換）。画面矩形（画面サイズから上下 = MarginTop、
/// 左右 = MarginLeft を差し引いた範囲）の外に Draw 点がある場合は
/// Zoom を (0,0) にし、内側の場合は入力境界の変換後外接範囲が画面
/// 矩形へ収まる倍率を UpOnly / DownOnly の区分どおりに求めて Zoom へ
/// 乗算する。倍率の初期値は UpOnly のとき最大値（＝制約なし）から
/// 始める本家の式どおり。
public final class MetalAutomaticZoomProcessor: MetalEffectProcessor {
    private let definition: AutomaticZoomEffectDefinition

    public init(context: MetalGraphicsContext, definition: AutomaticZoomEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        guard let input else { return description.drawDescription }
        var result = description.drawDescription
        let screen = description.itemDescription.screenSize
        let marginTop = evaluate(definition.automaticZoomMarginTop, description)
        let marginLeft = evaluate(definition.automaticZoomMarginLeft, description)
        let halfWidth = Double(screen.width) / 2
        let halfHeight = Double(screen.height) / 2
        let top = -halfHeight + marginTop
        let bottom = halfHeight - marginTop
        let left = -halfWidth + marginLeft
        let right = halfWidth - marginLeft
        let draw = result.draw
        guard draw.x >= left, draw.x <= right, draw.y >= top, draw.y <= bottom else {
            result.zoom = Vector2(x: 0, y: 0)
            return result
        }
        // 入力境界の四隅を Zoom（反転込み）＋回転で写した外接範囲。
        let scaleX = result.zoom.x * (result.invert ? -1 : 1)
        let scaleY = result.zoom.y
        var matrix = Matrix4x4.createScale(
            x: scaleX, y: scaleY, z: 1,
            center: Vector3(x: result.centerPoint.x, y: result.centerPoint.y, z: 0)
        )
        if !definition.ignoreRotation {
            matrix = matrix * Matrix4x4.createRotationZ(-result.rotation.z * Double.pi / 180)
        }
        let corners: [(Double, Double)] = [
            (input.bounds.left, input.bounds.top), (input.bounds.right, input.bounds.top),
            (input.bounds.left, input.bounds.bottom), (input.bounds.right, input.bounds.bottom),
        ]
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for corner in corners {
            let v = matrix.transform(x: corner.0, y: corner.1, z: 0, w: 1)
            let w = v.w == 0 ? 1 : v.w
            minX = min(minX, v.x / w)
            maxX = max(maxX, v.x / w)
            minY = min(minY, v.y / w)
            maxY = max(maxY, v.y / w)
        }
        let mode: AutomaticZoomMode = switch definition.automaticZoomMode {
        case .unknown: .downOnly
        default: definition.automaticZoomMode
        }
        let target: AutomaticZoomTarget = switch definition.automaticZoomTarget {
        case .unknown: .widthHeight
        default: definition.automaticZoomTarget
        }
        let upOnly = mode == .upOnly
        let downOnly = mode == .downOnly
        var factor = upOnly ? Double.greatestFiniteMagnitude : 1.0
        if target == .widthOnly || target == .widthHeight {
            var f = factor
            if maxX > 0 { f = min((right - draw.x) / maxX, f) }
            if minX < 0 { f = min((left - draw.x) / minX, f) }
            if !downOnly { f = max(f, 1.0) }
            factor = min(f, factor)
        }
        if target == .heightOnly || target == .widthHeight {
            var f = factor
            if maxY > 0 { f = min((bottom - draw.y) / maxY, f) }
            if minY < 0 { f = min((top - draw.y) / minY, f) }
            if !downOnly { f = max(f, 1.0) }
            factor = min(f, factor)
        }
        if factor == Double.greatestFiniteMagnitude { factor = 0 }
        result.zoom = Vector2(x: result.zoom.x * factor, y: result.zoom.y * factor)
        return result
    }
}

/// 角丸。本家 `RoundCornerEffect`（Primitive のマスク構成）。
/// マスクα = 入力αを σ = min(Radius, 最小寸法) × 2/3 でぼかし、
/// clamp(2α − 1) → clamp(α × 255/(254・Blur/100 + 1)) と2段の
/// LinearTransfer を通したもの。出力 = 入力 × マスクα（AlphaMask）。
/// ぼかしの境界は Soft（マスクが画像端で落ちることが角丸の前提。
/// 本家の同系プリミティブの既定とも一致）。
public final class MetalRoundCornerProcessor: MetalEffectProcessor {
    private let definition: RoundCornerEffectDefinition

    public init(context: MetalGraphicsContext, definition: RoundCornerEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let width = input.bounds.right - input.bounds.left
        let height = input.bounds.bottom - input.bounds.top
        let radius = evaluate(definition.radius, description)
        let sigma = min(radius, min(width, height)) * 2 / 3
        let blurred = try renderGaussianBlurred(input: input, sigma: sigma, hardBorder: false)
        guard let mask = blurred else { return nil }
        let blurRate = evaluate(definition.blur, description) / 100
        let secondSlope = 255 / (254 * blurRate + 1)
        return try renderWarp(
            input: input, mask: mask, outputBounds: input.bounds, mode: 0,
            param0: SIMD4<Float>(Float(secondSlope), 0, 0, 0)
        )
    }
}

// MARK: - ぼかし・マスク系

/// 縁ぼかし。本家 `BorderBlurEffect`（Primitive.BorderBlur）。
/// マスクα = 入力αを σ = min(Blur, 最小寸法) でぼかして
/// clamp(2α − 1) を通したもの。出力 = 入力 × マスクα。
/// σ のクランプは処理器側にある（プリミティブ側ではない）ことを
/// 実コードで確認済み。ぼかしの境界は Soft（角丸と同じ理由）。
public final class MetalBorderBlurProcessor: MetalEffectProcessor {
    private let definition: BorderBlurEffectDefinition

    public init(context: MetalGraphicsContext, definition: BorderBlurEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let width = input.bounds.right - input.bounds.left
        let height = input.bounds.bottom - input.bounds.top
        let sigma = min(evaluate(definition.blur, description), min(width, height))
        let blurred = try renderGaussianBlurred(input: input, sigma: sigma, hardBorder: false)
        guard let mask = blurred else { return nil }
        return try renderWarp(
            input: input, mask: mask, outputBounds: input.bounds, mode: 0,
            param0: SIMD4<Float>(1, 0, 0, 0)
        )
    }
}

/// 方向ぼかし。本家 `DirectionalBlurEffect`（D2D 組み込み DirectionalBlur）。
/// StandardDeviation = 値そのもの、Angle = −パラメータ + 90（度）、
/// BorderMode = IsHardBorderMode ? Hard : Soft、Optimization = Quality
/// （いずれも実測）。D2D の内部サンプリング方式は非公開のため、
/// 指定方向の1次元ガウスで近似する（差分として記録）。
public final class MetalDirectionalBlurProcessor: MetalEffectProcessor {
    private let definition: DirectionalBlurEffectDefinition

    public init(context: MetalGraphicsContext, definition: DirectionalBlurEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let sigma = evaluate(definition.standardDeviation, description)
        let d2dAngle = -evaluate(definition.angle, description) + 90
        return try renderDirectionalBlurred(
            input: input, sigma: sigma, angleDegrees: d2dAngle,
            hardBorder: definition.isHardBorderMode
        )
    }
}

/// 色収差。本家 `ChromaticAberration`（CustomEffects。D2D プリミティブの
/// 合成が C# 側で全て読める）。
/// R 成分だけを取り (1 + s) 倍、G はそのまま、B は (1 − s) 倍して
/// Composite(Plus) し、[0,1] へクランプする（s = Strength / 100）。
/// Plus 合成はαも加算するため、半透明画素は本家でも不透明寄りに
/// なる（そのまま再現する）。こちらでは3点サンプリングの1パスに畳む。
/// Strength = 100（s = 1）では B の拡縮が 0 になり本家でも像が
/// 潰れるため、拡縮率の下限を設けてサンプル不能だけを避ける（差分）。
public final class MetalChromaticAberrationProcessor: MetalEffectProcessor {
    private let definition: ChromaticAberrationEffectDefinition

    public init(context: MetalGraphicsContext, definition: ChromaticAberrationEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let strength = evaluate(definition.strength, description) / 100
        let scaleR = 1 + strength
        let scaleB = max(1 - strength, 0.000001)
        func scaled(_ rect: RectF, _ scale: Double) -> RectF {
            RectF(
                left: rect.left * scale, top: rect.top * scale,
                right: rect.right * scale, bottom: rect.bottom * scale
            )
        }
        let outputBounds = input.bounds
            .union(scaled(input.bounds, scaleR))
            .union(scaled(input.bounds, scaleB))
        return try renderWarp(
            input: input, mask: nil, outputBounds: outputBounds, mode: 1,
            param0: SIMD4<Float>(Float(scaleR), Float(scaleB), 0, 0)
        )
    }
}

// MARK: - 影・塗り・枠線系（単色ブラシのみ）

/// 角丸矩形の塗りをテクスチャへ描く（FillBackground の下地用）。
/// 図形シェーダ（SDF）の全面塗りを使い、`outputBounds` を張る
/// テクスチャのうち `rect` の範囲だけを単色で塗る。
func renderRoundedRectFill(
    context: MetalGraphicsContext,
    rect: RectF,
    radius: Double,
    color: Color,
    outputBounds: RectF
) throws -> MetalImage? {
    let outWidth = outputBounds.right - outputBounds.left
    let outHeight = outputBounds.bottom - outputBounds.top
    guard outWidth > 0, outHeight > 0 else { return nil }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: max(1, Int(ceil(outWidth))), height: max(1, Int(ceil(outHeight))),
        mipmapped: false
    )
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .shared
    guard let texture = context.devices.device.makeTexture(descriptor: descriptor),
          let commandBuffer = context.commandQueue.makeCommandBuffer()
    else { return nil }
    let passDescriptor = MTLRenderPassDescriptor()
    let attachment = passDescriptor.colorAttachments[0]
    attachment?.texture = texture
    attachment?.loadAction = .clear
    attachment?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    attachment?.storeAction = .store
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
    else { return nil }
    let centerX = (rect.left + rect.right) / 2
    let centerY = (rect.top + rect.bottom) / 2
    let corners: [(Double, Double)] = [
        (rect.left, rect.top), (rect.right, rect.top),
        (rect.left, rect.bottom), (rect.right, rect.bottom),
    ]
    let vertices: [QuadVertex] = corners.map { corner in
        QuadVertex(
            position: SIMD4<Float>(
                Float(2 * (corner.0 - outputBounds.left) / outWidth - 1),
                Float(-(2 * (corner.1 - outputBounds.top) / outHeight - 1)),
                0, 1
            ),
            uv: SIMD2<Float>(Float(corner.0 - centerX), Float(corner.1 - centerY))
        )
    }
    struct ShapeUniforms {
        var halfSize: SIMD2<Float>
        var radius: Float
        var bandWidth: Float
        var aaScale: Float
        var color: SIMD4<Float>
    }
    let rectWidth = rect.right - rect.left
    let rectHeight = rect.bottom - rect.top
    var uniforms = ShapeUniforms(
        halfSize: SIMD2<Float>(Float(rectWidth / 2), Float(rectHeight / 2)),
        radius: Float(min(radius, min(rectWidth, rectHeight) / 2)),
        bandWidth: -1,
        aaScale: 1,
        color: premultipliedVector(color)
    )
    encoder.setRenderPipelineState(context.devices.shapePipeline)
    encoder.setVertexBytes(
        vertices, length: MemoryLayout<QuadVertex>.stride * vertices.count, index: 0
    )
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.size, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    if commandBuffer.status == .error {
        throw MetalRenderError.commandBufferFailed(underlying: commandBuffer.error)
    }
    return MetalImage(texture: texture, bounds: outputBounds)
}

/// 影。本家 `ShadowEffect`。
/// 連鎖: シルエット（白 × 入力α）をブラシでマスク（単色ブラシでは
/// ブラシ色 × 入力α と等しい）→ ガウスぼかし σ = Blur（BorderMode は
/// 未設定のため Soft とする。記録）→ 回転（中心は IsRotateAtCenter で
/// 境界中心、それ以外は原点）・拡縮 Zoom/100 ・平行移動 (X, Y) →
/// 不透明度 Opacity/100 → 原画の下へ SourceOver。
/// 単色ブラシ以外（グラデーション等）は素通し（ブラシサブシステムが
/// 差し替え点）。
public final class MetalShadowProcessor: MetalEffectProcessor {
    private let definition: ShadowEffectDefinition

    public init(context: MetalGraphicsContext, definition: ShadowEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.brush) else {
            return input
        }
        // シルエット（ブラシ色 × 入力α）。
        guard let silhouette = try renderWarp(
            input: input, mask: nil, outputBounds: input.bounds, mode: 5,
            param0: premultipliedVector(brushColor)
        ) else { return nil }
        let blur = evaluate(definition.blur, description)
        guard let blurred = try renderGaussianBlurred(
            input: silhouette, sigma: blur, hardBorder: false
        ) else { return nil }
        // 変形: 回転・拡縮（中心は境界中心か原点）→ 平行移動。
        let center = definition.isRotateAtCenter
            ? Vector3(
                x: (input.bounds.left + input.bounds.right) / 2,
                y: (input.bounds.top + input.bounds.bottom) / 2, z: 0)
            : Vector3.zero
        let zoom = evaluate(definition.zoom, description) / 100
        let angle = evaluate(definition.angle, description)
        // 中心 c まわりの回転 = T(−c) · Rz · T(c)（左端から適用される）。
        let rotation = Matrix4x4.createTranslation(Vector3(x: -center.x, y: -center.y, z: 0))
            * Matrix4x4.createRotationZ(angle * Double.pi / 180)
            * Matrix4x4.createTranslation(center)
        let scale = Matrix4x4.createScale(x: zoom, y: zoom, z: 1, center: center)
        let translation = Matrix4x4.createTranslation(
            x: evaluate(definition.x, description),
            y: evaluate(definition.y, description), z: 0
        )
        let matrix = rotation * scale * translation
        let shadowBounds = MetalDrawingEffect.boundingRect(of: blurred.bounds, transformedBy: matrix)
        guard let shadow = try renderTransformed(
            input: blurred, matrix: matrix, outputBounds: shadowBounds,
            interpolation: .linear
        ) else { return nil }
        let outputBounds = input.bounds.union(shadow.bounds)
        let opacity = evaluate(definition.opacity, description) / 100
        return try renderComposite(
            top: input, bottom: shadow, outputBounds: outputBounds, mode: 0,
            opacityBottom: opacity
        )
    }
}

/// 背景塗りつぶし。本家 `FillBackgroundEffect`。
/// 入力境界を上下左右へ広げた矩形 E を角丸（Round）付きでブラシ色に
/// 塗り（不透明度 = Opacity/100)、その上へ入力を描く。
/// IsBackgroundOnly の場合は DestinationOut（塗り × (1 − 入力α)）。
/// 混合モードが通常以外の場合は通常合成へ落とす（MAC-0012 台帳の
/// 既存方針）。入力境界の幅・高さが 1 以下のときは本家どおり無効。
/// 塗り矩形の寸法は本家が (int) 化してジオメトリを作るため、画素
/// 単位では最大1pxのずれがありうる（差分として記録）。
public final class MetalFillBackgroundProcessor: MetalEffectProcessor {
    private let definition: FillBackgroundEffectDefinition

    public init(context: MetalGraphicsContext, definition: FillBackgroundEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.brush) else {
            return input
        }
        let width = input.bounds.right - input.bounds.left
        let height = input.bounds.bottom - input.bounds.top
        guard width > 1, height > 1 else { return input }
        let expanded = RectF(
            left: input.bounds.left - evaluate(definition.left, description),
            top: input.bounds.top - evaluate(definition.top, description),
            right: input.bounds.right + evaluate(definition.right, description),
            bottom: input.bounds.bottom + evaluate(definition.bottom, description)
        )
        let fillRect = RectF(
            left: min(expanded.left, expanded.right), top: min(expanded.top, expanded.bottom),
            right: max(expanded.left, expanded.right), bottom: max(expanded.top, expanded.bottom)
        )
        let outputBounds = input.bounds.union(fillRect)
        guard let fill = try renderRoundedRectFill(
            context: context, rect: fillRect,
            radius: evaluate(definition.round, description),
            color: brushColor, outputBounds: outputBounds
        ) else { return nil }
        let opacity = evaluate(definition.opacity, description) / 100
        if definition.isBackgroundOnly {
            return try renderComposite(
                top: input, bottom: fill, outputBounds: outputBounds, mode: 1,
                opacityBottom: opacity
            )
        }
        return try renderComposite(
            top: input, bottom: fill, outputBounds: outputBounds, mode: 0,
            opacityBottom: opacity
        )
    }
}

/// 前景塗りつぶし。本家 `FillForegroundEffect`。
/// ブラシ色を入力境界で塗り、入力αでマスク（AlphaMask）し、
/// 不透明度 Opacity/100 を掛ける。IsBrushOnly でなければ入力の上へ
/// 通常合成する（混合モード通常以外は通常合成へ落とす。既存方針）。
public final class MetalFillForegroundProcessor: MetalEffectProcessor {
    private let definition: FillForegroundEffectDefinition

    public init(context: MetalGraphicsContext, definition: FillForegroundEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.brush) else {
            return input
        }
        guard let fill = try renderRoundedRectFill(
            context: context, rect: input.bounds, radius: 0,
            color: brushColor, outputBounds: input.bounds
        ) else { return nil }
        guard let masked = try renderWarp(
            input: fill, mask: input, outputBounds: input.bounds, mode: 3
        ) else { return nil }
        let opacity = evaluate(definition.opacity, description) / 100
        if definition.isBrushOnly {
            return try renderColorEffect(
                input: masked,
                uniforms: ColorEffectUniforms(
                    mode: 7,
                    param0: SIMD4<Float>(Float(opacity), Float(opacity), Float(opacity), Float(opacity)),
                    param1: .zero
                )
            )
        }
        return try renderComposite(
            top: masked, bottom: input, outputBounds: input.bounds, mode: 0,
            opacityTop: opacity
        )
    }
}

/// 枠線。本家 `FrameLineEffect`。
/// 上下左右の余白（(int) 化）の外側へ太さ Thickness の帯（＋全方向の
/// ときは四隅の正方形）をブラシ色で描き、不透明度 Opacity/100 を
/// 掛けて、RenderPlacement に従い入力の前／後へ SourceOver する。
/// 本家どおり、帯が出るのは入力境界の幅が 1 より大きいときだけ。
/// 帯の描画は単色四角形の複数回描画で1テクスチャへ集める。
public final class MetalFrameLineProcessor: MetalEffectProcessor {
    private let definition: FrameLineEffectDefinition

    public init(context: MetalGraphicsContext, definition: FrameLineEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.brush) else {
            return input
        }
        let bounds = input.bounds
        guard bounds.right - bounds.left > 1 else { return input }
        let left = Double(Int(evaluate(definition.left, description)))
        let top = Double(Int(evaluate(definition.top, description)))
        let right = Double(Int(evaluate(definition.right, description)))
        let bottom = Double(Int(evaluate(definition.bottom, description)))
        let thickness = evaluate(definition.thickness, description)
        // unknown は定義の既定 (.all) として評価する（MAC-0018 の方針）。
        let type: FrameLineType = if case .unknown = definition.type {
            .all
        } else {
            definition.type
        }
        var rects: [RectF] = []
        if type == .all || type == .top {
            rects.append(RectF(
                left: bounds.left - left, top: bounds.top - top - thickness,
                right: bounds.right + right, bottom: bounds.top - top
            ))
        }
        if type == .all || type == .bottom {
            rects.append(RectF(
                left: bounds.left - left, top: bounds.bottom + bottom,
                right: bounds.right + right, bottom: bounds.bottom + bottom + thickness
            ))
        }
        if type == .all || type == .left {
            rects.append(RectF(
                left: bounds.left - left - thickness, top: bounds.top - top,
                right: bounds.left - left, bottom: bounds.bottom + bottom
            ))
        }
        if type == .all || type == .right {
            rects.append(RectF(
                left: bounds.right + right, top: bounds.top - top,
                right: bounds.right + right + thickness, bottom: bounds.bottom + bottom
            ))
        }
        if type == .all {
            let corners: [(Double, Double)] = [
                (bounds.left - left - thickness, bounds.top - top - thickness),
                (bounds.right + right, bounds.top - top - thickness),
                (bounds.left - left - thickness, bounds.bottom + bottom),
                (bounds.right + right, bounds.bottom + bottom),
            ]
            for corner in corners {
                rects.append(RectF(
                    left: corner.0, top: corner.1,
                    right: corner.0 + thickness, bottom: corner.1 + thickness
                ))
            }
        }
        guard !rects.isEmpty, thickness > 0 else { return input }
        var outputBounds = bounds
        for rect in rects { outputBounds = outputBounds.union(rect) }
        guard let lineImage = try renderSolidRects(
            rects: rects, color: brushColor, outputBounds: outputBounds
        ) else { return nil }
        let opacity = evaluate(definition.opacity, description) / 100
        if definition.renderPlacement == .front {
            return try renderComposite(
                top: lineImage, bottom: input, outputBounds: outputBounds, mode: 0,
                opacityTop: opacity
            )
        }
        // .back（定義の既定）および unknown は後ろとして扱う。
        return try renderComposite(
            top: input, bottom: lineImage, outputBounds: outputBounds, mode: 0,
            opacityBottom: opacity
        )
    }

    /// 単色四角形の列を1つのテクスチャへ描く（全面四角形×単色シェーダ）。
    private func renderSolidRects(
        rects: [RectF], color: Color, outputBounds: RectF
    ) throws -> MetalImage? {
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        guard outWidth > 0, outHeight > 0,
              let texture = makeTexture(
                width: Int(ceil(outWidth)), height: Int(ceil(outHeight)),
                usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = context.commandQueue.makeCommandBuffer()
        else { return nil }
        let passDescriptor = MTLRenderPassDescriptor()
        let attachment = passDescriptor.colorAttachments[0]
        attachment?.texture = texture
        attachment?.loadAction = .clear
        attachment?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        attachment?.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return nil }
        encoder.setRenderPipelineState(context.devices.solidPipeline)
        var fillColor = premultipliedVector(color)
        encoder.setFragmentBytes(
            &fillColor, length: MemoryLayout<SIMD4<Float>>.size, index: 0
        )
        for rect in rects {
            let corners: [(Double, Double)] = [
                (rect.left, rect.top), (rect.right, rect.top),
                (rect.left, rect.bottom), (rect.right, rect.bottom),
            ]
            let vertices: [QuadVertex] = corners.map { corner in
                QuadVertex(
                    position: SIMD4<Float>(
                        Float(2 * (corner.0 - outputBounds.left) / outWidth - 1),
                        Float(-(2 * (corner.1 - outputBounds.top) / outHeight - 1)),
                        0, 1
                    ),
                    uv: SIMD2<Float>(0, 0)
                )
            }
            encoder.setVertexBytes(
                vertices, length: MemoryLayout<QuadVertex>.stride * vertices.count, index: 0
            )
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw MetalRenderError.commandBufferFailed(underlying: commandBuffer.error)
        }
        return MetalImage(texture: texture, bounds: outputBounds)
    }
}

// MARK: - ワープ系

/// 形態学フィルタ。本家 `MorphologyEffect`（D2D 組み込み Morphology）。
/// Width × Height の矩形近傍のチャンネル最大（Dilate）／最小（Erode）。
/// 寸法は (int) 化して渡す（実測）。分離可能な矩形フィルタとして
/// 横・縦の2パスで計算する（結果は等しい）。偶数寸法の中心位置は
/// 本家未計測のため −(n−1)/2 始まりと仮定する（未解決として記録）。
/// 入力境界の外は透明として扱う（無限平面モデル）。
public final class MetalMorphologyProcessor: MetalEffectProcessor {
    private let definition: MorphologyEffectDefinition

    public init(context: MetalGraphicsContext, definition: MorphologyEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let width = max(1, Int(evaluate(definition.width, description)))
        let height = max(1, Int(evaluate(definition.height, description)))
        let dilate: Bool
        switch definition.mode {
        case .dilate: dilate = true
        case .erode, .unknown: dilate = false
        }
        return try renderMorphology(input: input, width: width, height: height, dilate: dilate)
    }
}

/// 描画遅延。本家 `DrawLazyEffectEffect`。
/// 現在の DrawDescription のうち有効な成分（位置・不透明度・拡縮・
/// 回転・反転・カメラ）を画像側へ先に焼き込み、戻り DrawDescription
/// からその成分を消す。画像行列は本家どおり
/// Scale(Zoom) · 反転 · Rz · Ry(−Y) · Rx(−X) · 平行移動 · カメラ · 透視。
/// 不透明度はαだけを拡縮する ColorMatrix（Premultiplied の整合は
/// 本家でも崩れる。そのまま再現）。カメラの最終化
/// （CameraFinalizer）は Core 側の差し替え点のため、保持済みの
/// カメラ行列をそのまま使う。
public final class MetalDrawLazyProcessor: MetalEffectProcessor {
    private let definition: DrawLazyEffectEffectDefinition

    public init(context: MetalGraphicsContext, definition: DrawLazyEffectEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let dd = description.drawDescription
        let draw = definition.isXYZ ? dd.draw : Vector3.zero
        let zoom = definition.isZoom ? dd.zoom : Vector2(x: 1, y: 1)
        let rotation = definition.isRotation ? dd.rotation : Vector3.zero
        let camera = definition.isCamera ? dd.camera : Matrix4x4.identity
        var matrix = Matrix4x4.createScale(x: zoom.x, y: zoom.y, z: 1, center: .zero)
        if definition.isInvert && dd.invert {
            matrix = matrix * Matrix4x4.createScale(
                x: -1, y: 1, z: 1,
                center: Vector3(x: dd.centerPoint.x, y: dd.centerPoint.y, z: 0)
            )
        }
        matrix = matrix
            * Matrix4x4.createRotationZ(rotation.z * Double.pi / 180)
            * Matrix4x4.createRotationY(-rotation.y * Double.pi / 180)
            * Matrix4x4.createRotationX(-rotation.x * Double.pi / 180)
            * Matrix4x4.createTranslation(draw)
            * camera
            * perspectiveMatrix
        var image = input
        if !isIdentity(matrix) {
            let outputBounds = MetalDrawingEffect.boundingRect(of: input.bounds, transformedBy: matrix)
            guard let transformed = try renderTransformed(
                input: input, matrix: matrix, outputBounds: outputBounds,
                interpolation: dd.zoomInterpolationMode
            ) else { return nil }
            image = transformed
        }
        if definition.isOpacity && dd.opacity != 1 {
            return try renderColorEffect(
                input: image,
                uniforms: ColorEffectUniforms(
                    mode: 7,
                    param0: SIMD4<Float>(1, 1, 1, Float(dd.opacity)),
                    param1: .zero
                )
            )
        }
        return image
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        var result = description.drawDescription
        if definition.isXYZ { result.draw = .zero }
        if definition.isZoom { result.zoom = Vector2(x: 1, y: 1) }
        if definition.isRotation { result.rotation = .zero }
        if definition.isCamera { result.camera = .identity }
        if definition.isOpacity { result.opacity = 1 }
        if definition.isInvert { result.invert = false }
        return result
    }
}

/// ジャンプ。本家 `JumpEffect`（DrawDescription のみの変更）。
/// 静的関数 Jump の式を実コードどおりに写す。入力境界の高さは
/// GetImageLocalBounds の高さ（こちらでは入力実体の境界）。
public final class MetalJumpProcessor: MetalEffectProcessor {
    private let definition: JumpEffectDefinition

    public init(context: MetalGraphicsContext, definition: JumpEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let dd = description.drawDescription
        let height = input.map { $0.bounds.bottom - $0.bounds.top } ?? 0
        let zoomY = dd.zoom.y
        let jumpHeight = zoomY <= 0
            ? 0
            : evaluate(definition.jumpHeight, description) / zoomY
        let stretch = height * evaluate(definition.stretch, description) / 100
        let period = evaluate(definition.period, description)
        let distortion = height / 2 * evaluate(definition.distortion, description) / 100
        let interval = evaluate(definition.interval, description)
        let toX = evaluate(definition.x, description)
        let toY = evaluate(definition.y, description)
        let time = description.itemDescription.itemPosition.time
        let totalTime = description.itemDescription.itemDuration.time
        return Self.jump(
            dd, height: height, jumpHeight: jumpHeight, stretch: stretch,
            period: period, distortion: distortion, interval: interval,
            toX: toX, toY: toY, time: time, totalTime: totalTime
        )
    }

    /// 本家 JumpEffect.Jump の式（実コードの写し。変数の意味は本家と
    /// 同じ: num = 総周期数、num2 = 現在の周期番号、num3 = 周期内時刻、
    /// num4 = 跳躍位相、num7 = 現在の跳躍量）。
    static func jump(
        _ dd: DrawDescription,
        height: Double,
        jumpHeight: Double,
        stretch: Double,
        period: Double,
        distortion: Double,
        interval: Double,
        toX: Double,
        toY: Double,
        time: Double,
        totalTime: Double
    ) -> DrawDescription {
        let zoomY = dd.zoom.y
        let num = (period + interval == 0) ? 0 : totalTime / (period + interval)
        let num2 = (period + interval != 0) ? Int(time / (period + interval)) : 0
        let num3 = time - (period + interval) * Double(num2)
        let num4 = (period == 0) ? 0 : min(1, num3 / period)
        let num5 = num3 - period
        let num6 = (interval == 0) ? 0 : num5 / interval
        let num7 = (num3 < period)
            ? jumpHeight * sin(num4 * Double.pi)
            : -distortion * sin(num6 * Double.pi)
        let num8 = (height == 0) ? 1 : (height + min(num7 * 2, stretch)) / height
        let num9 = (num8 == 0) ? 1 : 1 / num8
        let num10 = (num == 0) ? 0 : toX / num
        let num11 = (num == 0) ? 0 : toY / num
        let num12 = num10 * (Double(num2) + num4)
        let num13 = num11 * (Double(num2) + num4)
        var result = dd
        result.draw = Vector3(
            x: dd.draw.x + num12,
            y: dd.draw.y + num13 - num7 * zoomY,
            z: dd.draw.z
        )
        result.zoom = Vector2(x: dd.zoom.x * num9, y: dd.zoom.y * num8)
        return result
    }
}

// MARK: - イン／アウト系

/// イン／アウト縁ぼかし。本家 `InOutBorderBlurEffect`。
/// BorderBlur プリミティブを σ = GetEasingValue(Value → 0) で使う。
/// この経路では σ の最小寸法クランプは無い（実コードで確認。
/// 通常の縁ぼかしとの違い）。
public final class MetalInOutBorderBlurProcessor: MetalEffectProcessor {
    private let definition: InOutBorderBlurEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutBorderBlurEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let sigma = inOutEasingValue(definition, description, from: definition.value, to: 0)
        let blurred = try renderGaussianBlurred(input: input, sigma: sigma, hardBorder: false)
        guard let mask = blurred else { return nil }
        return try renderWarp(
            input: input, mask: mask, outputBounds: input.bounds, mode: 0,
            param0: SIMD4<Float>(1, 0, 0, 0)
        )
    }
}

/// イン／アウトぼかし。本家 `InOutGaussianBlurEffect`（D2D 組み込み
/// GaussianBlur、σ = GetEasingValue(Value → 0)）。BorderMode は
/// 未設定のため Soft とする（本家の GaussianBlurEffect の既定
/// IsHardBorderMode = false と同じ扱い。記録）。
public final class MetalInOutGaussianBlurProcessor: MetalEffectProcessor {
    private let definition: InOutGaussianBlurEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutGaussianBlurEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let sigma = inOutEasingValue(definition, description, from: definition.value, to: 0)
        return try renderGaussianBlurred(input: input, sigma: sigma, hardBorder: false)
    }
}

/// イン／アウトモザイク。本家 `InOutMosaicEffect`。
/// セル寸法 = max(1, GetEasingValue(Value → 1))、形状はカスタム効果の
/// 既定（矩形）。第1段の矩形モザイク本体を共有する。
public final class MetalInOutMosaicProcessor: MetalEffectProcessor {
    private let definition: InOutMosaicEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutMosaicEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let size = max(1, inOutEasingValue(definition, description, from: definition.value, to: 1))
        return try renderRectangleMosaic(input: input, cellSize: size)
    }
}

/// イン／アウト画像外から移動。本家 `InOutMoveFromOutsideImageEffect`。
/// Flood（透明）へ平行移動した入力を重ね、元の境界で Crop する構成。
/// ずらし量は方向（左 = (−幅, 0) 等）を GetEasingValue(→ 0) で
/// 補間したもの。こちらでは元の境界を出力境界とする平行移動の
/// 焼き込みに畳む（結果は等しい）。
public final class MetalInOutMoveFromOutsideImageProcessor: MetalEffectProcessor {
    private let definition: InOutMoveFromOutsideImageEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutMoveFromOutsideImageEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let width = input.bounds.right - input.bounds.left
        let height = input.bounds.bottom - input.bounds.top
        let offset: (x: Double, y: Double)
        switch definition.value {
        case .left: offset = (-width, 0)
        case .right: offset = (width, 0)
        case .top: offset = (0, -height)
        case .bottom: offset = (0, height)
        case .unknown: offset = (-width, 0)
        }
        let appliedX = inOutEasingValue(definition, description, from: offset.x, to: 0)
        let appliedY = inOutEasingValue(definition, description, from: offset.y, to: 0)
        guard appliedX != 0 || appliedY != 0 else { return input }
        let matrix = Matrix4x4.createTranslation(x: appliedX, y: appliedY, z: 0)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: input.bounds,
            interpolation: input.interpolation
        )
    }
}

/// イン／アウト回転。本家 `InOutRotateEffect`。Rotate と同じ構造で、
/// 角度は GetEasingValue(ValueX/Y/Z → 0)（double 値）。
public final class MetalInOutRotateProcessor: MetalEffectProcessor {
    private let definition: InOutRotateEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutRotateEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func angles(_ description: EffectDescription) -> (x: Double, y: Double, z: Double) {
        (
            x: inOutEasingValue(definition, description, from: definition.valueX, to: 0),
            y: inOutEasingValue(definition, description, from: definition.valueY, to: 0),
            z: inOutEasingValue(definition, description, from: definition.valueZ, to: 0)
        )
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let angle = angles(description)
        return try bakeRotation(
            input: input, description: description,
            angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let angle = angles(description)
        return rotationDrawDescription(
            description, angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }
}

/// イン／アウト傾斜。本家 `InOutSkewEffect`。Skew と同じ構造で、
/// 角度・中心は GetEasingValue(→ 0) の double 値。
public final class MetalInOutSkewProcessor: MetalEffectProcessor {
    private let definition: InOutSkewEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutSkewEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let center = skewCenter(
            mode: definition.centerPoint,
            centerX: definition.centerX, centerY: definition.centerY,
            bounds: input.bounds
        )
        return try bakeSkew(
            input: input, description: description,
            angleX: inOutEasingValue(definition, description, from: definition.angleX, to: 0),
            angleY: inOutEasingValue(definition, description, from: definition.angleY, to: 0),
            center: center
        )
    }
}

/// イン／アウト起き上がり。本家 `InOutGetUpEffect`（実コードで検証）。
/// 角度 = GetEasingValue(90 → 0)。基線点 v は入力のワールド境界
/// （こちらではプレーンな入力の境界と同一視する。解釈として記録）
/// から Base で決まり、3D の場合は境界を Zoom で拡縮してから求める。
/// 回転ベクトル r は Base で決まり、Direction = Front で符号反転する。
/// 画像行列は両分岐とも Scale(Zoom) が先頭に付く:
/// - 3D: Scale(Zoom) · 平行移動(−v)。戻りは Draw += v、Rotation −= r、
///   Zoom = (1,1)。
/// - 非3D: Scale(Zoom) · [平行移動(−v・Zoom) · Rz(r.z) · Ry(r.y) ·
///   Rx(r.x) · 透視 · 平行移動(+v・Zoom)]。戻りは Zoom = (1,1) のみ。
/// 本家の回転は Rotate と違い Y / X とも符号反転しない（実コード）。
/// チェーン中間の Crop（SafeTransform3DHelper）は1パスの焼き込みに
/// 畳む（内部実装の違い）。
public final class MetalInOutGetUpProcessor: MetalEffectProcessor {
    private let definition: InOutGetUpEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutGetUpEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    /// 基線点と回転ベクトル（本家 Update の switch の写し）。
    private func baseline(
        _ description: EffectDescription, bounds: RectF
    ) -> (point: Vector2, rotation: Vector3) {
        let angle = inOutEasingValue(definition, description, from: 90, to: 0)
        let centerX = (bounds.left + bounds.right) / 2
        let centerY = (bounds.top + bounds.bottom) / 2
        let point: Vector2
        let rotation: Vector3
        switch definition.base {
        case .top:
            point = Vector2(x: 0, y: bounds.top)
            rotation = Vector3(x: -angle, y: 0, z: 0)
        case .bottom, .unknown:
            point = Vector2(x: 0, y: bounds.bottom)
            rotation = Vector3(x: angle, y: 0, z: 0)
        case .left:
            point = Vector2(x: bounds.left, y: 0)
            rotation = Vector3(x: 0, y: angle, z: 0)
        case .right:
            point = Vector2(x: bounds.right, y: 0)
            rotation = Vector3(x: 0, y: -angle, z: 0)
        case .centerX:
            point = .zero
            rotation = Vector3(x: angle, y: 0, z: 0)
        case .centerY:
            point = .zero
            rotation = Vector3(x: 0, y: angle, z: 0)
        case .trueCenterX:
            point = Vector2(x: centerX, y: centerY)
            rotation = Vector3(x: angle, y: 0, z: 0)
        case .trueCenterY:
            point = Vector2(x: centerX, y: centerY)
            rotation = Vector3(x: 0, y: angle, z: 0)
        }
        if definition.direction == .front {
            return (point, Vector3(x: -rotation.x, y: -rotation.y, z: -rotation.z))
        }
        return (point, rotation)
    }

    /// 3D 分岐では境界を Zoom で拡縮してから基線を求める（本家どおり）。
    private func effectiveBounds(
        _ description: EffectDescription, input: MetalImage
    ) -> RectF {
        guard definition.is3D else { return input.bounds }
        let zoom = description.drawDescription.zoom
        return RectF(
            left: input.bounds.left * zoom.x, top: input.bounds.top * zoom.y,
            right: input.bounds.right * zoom.x, bottom: input.bounds.bottom * zoom.y
        )
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let zoom = description.drawDescription.zoom
        let bounds = effectiveBounds(description, input: input)
        let (point, rotation) = baseline(description, bounds: bounds)
        let scale = Matrix4x4.createScale(x: zoom.x, y: zoom.y, z: 1, center: .zero)
        let matrix: Matrix4x4
        if definition.is3D {
            matrix = scale * Matrix4x4.createTranslation(
                x: -point.x, y: -point.y, z: 0
            )
        } else {
            let inner = Matrix4x4.createTranslation(x: -point.x * zoom.x, y: -point.y * zoom.y, z: 0)
                * Matrix4x4.createRotationZ(rotation.z * Double.pi / 180)
                * Matrix4x4.createRotationY(rotation.y * Double.pi / 180)
                * Matrix4x4.createRotationX(rotation.x * Double.pi / 180)
                * perspectiveMatrix
                * Matrix4x4.createTranslation(x: point.x * zoom.x, y: point.y * zoom.y, z: 0)
            matrix = scale * inner
        }
        guard !isIdentity(matrix) else { return input }
        let outputBounds = MetalDrawingEffect.boundingRect(of: input.bounds, transformedBy: matrix)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: outputBounds,
            interpolation: description.drawDescription.zoomInterpolationMode
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        var result = description.drawDescription
        result.zoom = Vector2(x: 1, y: 1)
        guard definition.is3D, let input else { return result }
        let bounds = effectiveBounds(description, input: input)
        let (point, rotation) = baseline(description, bounds: bounds)
        result.draw = Vector3(
            x: result.draw.x + point.x, y: result.draw.y + point.y, z: result.draw.z
        )
        result.rotation = Vector3(
            x: result.rotation.x - rotation.x,
            y: result.rotation.y - rotation.y,
            z: result.rotation.z - rotation.z
        )
        return result
    }
}

/// イン／アウトジャンプ。本家 `InOutJumpEffect`（DrawDescription のみの
/// 変更。実コードで検証）。イン／アウトの進行率から逆算した時刻を
/// 専用の Jump 変形（インターバル位相が先行する形）へ渡す。
public final class MetalInOutJumpProcessor: MetalEffectProcessor {
    private let definition: InOutJumpEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutJumpEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let dd = description.drawDescription
        let durationSeconds = description.itemDescription.itemDuration.time
        let positionSeconds = description.itemDescription.itemPosition.time
        let effectTime = definition.effectTimeSeconds
        let inRate = (definition.isInEffect && effectTime > 0)
            ? min(max(positionSeconds / effectTime, 0), 1)
            : 1
        let outRate = (definition.isOutEffect && effectTime > 0)
            ? min(max((durationSeconds - positionSeconds) / effectTime, 0), 1)
            : 1
        let num3 = 1 - min(inRate, outRate)
        let height = input.map { $0.bounds.bottom - $0.bounds.top } ?? 0
        let zoomY = dd.zoom.y
        var isReversed = false
        if positionSeconds < effectTime && inRate < outRate {
            isReversed = definition.isInReverse
        } else if durationSeconds - effectTime < positionSeconds && outRate < inRate {
            isReversed = definition.isOutReverse
        }
        return Self.jump(
            dd,
            height: height,
            jumpHeight: zoomY <= 0 ? 0 : definition.jumpHeight / zoomY,
            stretch: height * definition.stretch / 100,
            period: definition.period,
            distortion: height / 2 * definition.distortion / 100,
            interval: definition.interval,
            toX: definition.x,
            toY: definition.y,
            isReversed: isReversed,
            time: effectTime * num3,
            totalTime: effectTime
        )
    }

    /// 本家 InOutJumpEffect.Jump の式（実コードの写し。通常の Jump と
    /// 位相の組み立てが異なる: num4 = clamp(num3 − interval, 0, period)、
    /// num8 はインターバル内では歪み、それ以外では跳躍）。
    static func jump(
        _ dd: DrawDescription,
        height: Double,
        jumpHeight: Double,
        stretch: Double,
        period: Double,
        distortion: Double,
        interval: Double,
        toX: Double,
        toY: Double,
        isReversed: Bool,
        time: Double,
        totalTime: Double
    ) -> DrawDescription {
        let zoomY = dd.zoom.y
        let num = (period + interval == 0) ? 0 : totalTime / (period + interval)
        let num2 = (period + interval != 0) ? Int(time / (period + interval)) : 0
        let num3 = time - (period + interval) * Double(num2)
        let num4 = min(max(num3 - interval, 0), period)
        let num5 = (period == 0) ? 0 : num4 / period
        let num7 = (interval == 0) ? 0 : num3 / interval
        let num8 = (num3 < interval)
            ? -distortion * sin(num7 * Double.pi)
            : jumpHeight * sin(num5 * Double.pi)
        let num9 = (height == 0) ? 1 : (height + min(num8 * 2, stretch)) / height
        let num10 = (num9 == 0) ? 1 : 1 / num9
        let num11 = (num == 0) ? 0 : toX / num
        let num12 = (num == 0) ? 0 : toY / num
        let num13 = num11 * (Double(num2) + num5)
        let num14 = num12 * (Double(num2) + num5)
        var result = dd
        result.draw = Vector3(
            x: dd.draw.x + num13,
            y: dd.draw.y + num14 - num8 * zoomY,
            z: dd.draw.z
        )
        result.zoom = Vector2(
            x: dd.zoom.x * num10 * (isReversed ? -1 : 1),
            y: dd.zoom.y * num9
        )
        return result
    }
}

// MARK: - ランダム／反復系

/// ランダム回転。本家 `RandomRotateEffect`。
/// 角度 = パラメータ値 × 乱数率 − パラメータ値 / 2（パラメータ ID は
/// X = 0, Y = 1, Z = 2）。以降は Rotate と同じ構造。
public final class MetalRandomRotateProcessor: MetalEffectProcessor {
    private let definition: RandomRotateEffectDefinition

    public init(context: MetalGraphicsContext, definition: RandomRotateEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func angles(_ description: EffectDescription) -> (x: Double, y: Double, z: Double) {
        func angle(_ animation: Animation, id: Int64) -> Double {
            let value = evaluate(animation, description)
            return value * randomRate(definition, description, parameterID: id) - value / 2
        }
        return (
            x: angle(definition.x, id: 0),
            y: angle(definition.y, id: 1),
            z: angle(definition.z, id: 2)
        )
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let angle = angles(description)
        return try bakeRotation(
            input: input, description: description,
            angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let angle = angles(description)
        return rotationDrawDescription(
            description, angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }
}

/// ランダム傾斜。本家 `RandomSkewEffect`。
/// 角度 = パラメータ値 × 乱数率 − パラメータ値 / 2（ID は X = 0,
/// Y = 1）。中心は Skew と同じ。
public final class MetalRandomSkewProcessor: MetalEffectProcessor {
    private let definition: RandomSkewEffectDefinition

    public init(context: MetalGraphicsContext, definition: RandomSkewEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let valueX = evaluate(definition.angleX, description)
        let valueY = evaluate(definition.angleY, description)
        let center = skewCenter(
            mode: definition.centerPoint,
            centerX: evaluate(definition.centerX, description),
            centerY: evaluate(definition.centerY, description),
            bounds: input.bounds
        )
        return try bakeSkew(
            input: input, description: description,
            angleX: valueX * randomRate(definition, description, parameterID: 0) - valueX / 2,
            angleY: valueY * randomRate(definition, description, parameterID: 1) - valueY / 2,
            center: center
        )
    }
}

/// 反復回転。本家 `RepeatRotateEffect`。
/// 角度 = 反復イージング値 (0 → パラメータ値)。以降は Rotate と同じ。
public final class MetalRepeatRotateProcessor: MetalEffectProcessor {
    private let definition: RepeatRotateEffectDefinition

    public init(context: MetalGraphicsContext, definition: RepeatRotateEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func angles(_ description: EffectDescription) -> (x: Double, y: Double, z: Double) {
        (
            x: repeatEasingValue(definition, description, from: 0, to: evaluate(definition.x, description)),
            y: repeatEasingValue(definition, description, from: 0, to: evaluate(definition.y, description)),
            z: repeatEasingValue(definition, description, from: 0, to: evaluate(definition.z, description))
        )
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let angle = angles(description)
        return try bakeRotation(
            input: input, description: description,
            angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let angle = angles(description)
        return rotationDrawDescription(
            description, angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }
}

/// 反復傾斜。本家 `RepeatSkewEffect`。
/// 角度 = 反復イージング値 (0 → パラメータ値)。中心は Skew と同じ。
public final class MetalRepeatSkewProcessor: MetalEffectProcessor {
    private let definition: RepeatSkewEffectDefinition

    public init(context: MetalGraphicsContext, definition: RepeatSkewEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let center = skewCenter(
            mode: definition.centerPoint,
            centerX: evaluate(definition.centerX, description),
            centerY: evaluate(definition.centerY, description),
            bounds: input.bounds
        )
        return try bakeSkew(
            input: input, description: description,
            angleX: repeatEasingValue(
                definition, description, from: 0, to: evaluate(definition.angleX, description)
            ),
            angleY: repeatEasingValue(
                definition, description, from: 0, to: evaluate(definition.angleY, description)
            ),
            center: center
        )
    }
}
#endif
