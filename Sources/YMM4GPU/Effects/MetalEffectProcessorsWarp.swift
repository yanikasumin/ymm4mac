#if os(macOS)
import Foundation
import Metal
import YMM4Core

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
            let transformed = try renderTransformed(
                input: input, matrix: matrix, outputBounds: outputBounds,
                interpolation: dd.zoomInterpolationMode
            )
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

#endif
