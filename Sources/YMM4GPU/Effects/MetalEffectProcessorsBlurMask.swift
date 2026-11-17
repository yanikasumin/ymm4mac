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

#endif
