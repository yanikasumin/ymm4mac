#if os(macOS)
import Foundation
import Metal
import YMM4Core

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
        let mask = try renderGaussianBlurred(input: input, sigma: sigma, hardBorder: false)
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

/// ハーフトーンのユニフォーム（MetalGraphics の HalfToneUniforms と一致）。
struct HalfTonePassUniforms {
    var inputPlane: SIMD4<Float>
    var color: SIMD4<Float>
    var inputOffset: SIMD2<Float>
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var texelSize: SIMD2<Float>
    var distance: Float
    var size: Float
    var strength: Float
    var mode: Int32
}

/// ハーフトーンシャドウ。本家 `HalfToneShadowEffect`（Issue #45）。
/// 連鎖（HalfToneShadowEffect.cs の実測）: ガウスぼかし σ = Blur →
/// 単色化（色は白 (1,1,1,1)、Strength = 1、KeepBrightness は
/// アイテムのフラグ）→ HalfTone カスタムシェーダ（Distance は
/// そのまま、Size = Size/100、Strength = Strength/100、Color は
/// Premultiplied、Mode = Layout。出力境界は各辺
/// ceil((Distance/2)・√2) 拡大）→ 不透明度 Opacity/100 →
/// 回転（中心は IsRotateAtCenter で入力境界中心、それ以外は原点）
/// ＋平行移動 (X, Y) → 原画の下へ SourceOver。
/// 配置が unknown の場合は素通し。恒等変形のパスは省略する。
public final class MetalHalfToneShadowProcessor: MetalEffectProcessor {
    private let definition: HalfToneShadowEffectDefinition

    public init(context: MetalGraphicsContext, definition: HalfToneShadowEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let mode: Int32
        switch definition.layout {
        case .triangle: mode = 0
        case .rectangle: mode = 1
        case .rhombus: mode = 2
        case .unknown: return input
        }
        let distance = evaluate(definition.distance, description)
        guard distance > 0 else { return input }
        var chain = input
        let blur = evaluate(definition.blur, description)
        if blur > 0 {
            chain = try renderGaussianBlurred(input: chain, sigma: blur, hardBorder: false)
        }
        chain = try renderColorEffect(
            input: chain,
            uniforms: ColorEffectUniforms(
                mode: 1,
                param0: premultipliedVector(.white),
                param1: SIMD4<Float>(1, definition.keepBrightness ? 1 : 0, 1, 0)
            )
        )
        let expand = ceil(distance / 2 * sqrt(2.0))
        let halftoneBounds = RectF(
            left: chain.bounds.left - expand, top: chain.bounds.top - expand,
            right: chain.bounds.right + expand, bottom: chain.bounds.bottom + expand
        )
        var uniforms = HalfTonePassUniforms(
            inputPlane: planeVector(chain),
            color: premultipliedVector(definition.color),
            inputOffset: SIMD2<Float>(
                Float(chain.planeOffset.x), Float(chain.planeOffset.y)),
            outputOrigin: SIMD2<Float>(
                Float(halftoneBounds.left), Float(halftoneBounds.top)),
            outputSize: SIMD2<Float>(
                Float(halftoneBounds.right - halftoneBounds.left),
                Float(halftoneBounds.bottom - halftoneBounds.top)),
            texelSize: SIMD2<Float>(
                1 / Float(chain.texture.width), 1 / Float(chain.texture.height)),
            distance: Float(distance),
            size: Float(evaluate(definition.size, description) / 100),
            strength: Float(evaluate(definition.strength, description) / 100),
            mode: mode
        )
        let halftoneTexture = try makeTexture(
            width: Int(ceil(halftoneBounds.right - halftoneBounds.left)),
            height: Int(ceil(halftoneBounds.bottom - halftoneBounds.top)),
            usage: [.renderTarget, .shaderRead]
        )
        try executeRenderPass(
            output: halftoneTexture, pipeline: context.devices.halftonePipeline
        ) { encoder in
            encoder.setFragmentTexture(chain.texture, index: 0)
            // 入力境界の外は透明（D2D の画像意味論）。clampToEdge では
            // 縁の色が外側へ漏れてドットが画像外へ伸びる。
            encoder.setFragmentSamplerState(context.devices.borderSampler, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<HalfTonePassUniforms>.size, index: 0
            )
        }
        chain = MetalImage(texture: halftoneTexture, bounds: halftoneBounds)
        let opacity = evaluate(definition.opacity, description) / 100
        if opacity != 1 {
            chain = try renderColorEffect(
                input: chain,
                uniforms: ColorEffectUniforms(
                    mode: 7,
                    param0: SIMD4<Float>(
                        Float(opacity), Float(opacity), Float(opacity), Float(opacity)),
                    param1: .zero
                )
            )
        }
        let angle = evaluate(definition.angle, description)
        let x = evaluate(definition.x, description)
        let y = evaluate(definition.y, description)
        if angle != 0 || x != 0 || y != 0 {
            let center = definition.isRotateAtCenter
                ? Vector3(
                    x: (input.bounds.left + input.bounds.right) / 2,
                    y: (input.bounds.top + input.bounds.bottom) / 2, z: 0)
                : Vector3.zero
            let rotation = Matrix4x4.createTranslation(
                    Vector3(x: -center.x, y: -center.y, z: 0))
                * Matrix4x4.createRotationZ(angle * Double.pi / 180)
                * Matrix4x4.createTranslation(center)
            let matrix = rotation * Matrix4x4.createTranslation(x: x, y: y, z: 0)
            let transformedBounds = MetalDrawingEffect.boundingRect(
                of: chain.bounds, transformedBy: matrix
            )
            chain = try renderTransformed(
                input: chain, matrix: matrix, outputBounds: transformedBounds,
                interpolation: .linear
            )
        }
        return try renderComposite(
            top: input, bottom: chain,
            outputBounds: input.bounds.union(chain.bounds), mode: 0
        )
    }
}

#endif
