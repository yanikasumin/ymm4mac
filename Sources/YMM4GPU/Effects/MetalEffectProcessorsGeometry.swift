#if os(macOS)
import Foundation
import Metal
import YMM4Core

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
        let mask = try renderGaussianBlurred(input: input, sigma: sigma, hardBorder: false)
        let blurRate = evaluate(definition.blur, description) / 100
        let secondSlope = 255 / (254 * blurRate + 1)
        return try renderWarp(
            input: input, mask: mask, outputBounds: input.bounds, mode: 0,
            param0: SIMD4<Float>(Float(secondSlope), 0, 0, 0)
        )
    }
}

#endif
