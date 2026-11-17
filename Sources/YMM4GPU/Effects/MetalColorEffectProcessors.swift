#if os(macOS)
import Foundation
import Metal
import YMM4Core

// MARK: - 色変換系の処理器

/// 色反転。本家 `InvertEffect`（D2D 組み込み Invert）。
public final class MetalInvertProcessor: MetalEffectProcessor {
    public init(context: MetalGraphicsContext, definition: InvertEffectDefinition) {
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        try renderColorEffect(input: input, uniforms: ColorEffectUniforms(mode: 0))
    }
}

/// 単色化。本家 `MonocolorizationEffect`（カスタムシェーダ効果）。
/// パラメータの渡し方は本家処理器の実測どおり（Strength は /100、
/// Color は Premultiplied の Vector4）。
public final class MetalMonocolorizationProcessor: MetalEffectProcessor {
    private let definition: MonocolorizationEffectDefinition

    public init(context: MetalGraphicsContext, definition: MonocolorizationEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        let strength = definition.strength.value(atFrame: frame, length: length, fps: fps) / 100
        let color = definition.color
        // 基準色の輝度（直色。輝度を保持する場合の正規化に使う）。
        let luma = 0.299 * Double(color.red) / 255
            + 0.587 * Double(color.green) / 255
            + 0.114 * Double(color.blue) / 255
        return try renderColorEffect(
            input: input,
            uniforms: ColorEffectUniforms(
                mode: 1,
                param0: premultipliedVector(color),
                param1: SIMD4<Float>(
                    Float(strength),
                    definition.keepBrightness ? 1 : 0,
                    Float(luma),
                    0
                )
            )
        )
    }
}

/// セピア。本家 `SepiaEffect`（D2D 組み込み Sepia の出力を、原画との
/// CrossFade で Strength だけ混ぜる構成）。
/// Intensity = SepiaIntensity / 100、Weight = Strength / 100（実測）。
public final class MetalSepiaProcessor: MetalEffectProcessor {
    private let definition: SepiaEffectDefinition

    public init(context: MetalGraphicsContext, definition: SepiaEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        let intensity = definition.sepiaIntensity.value(atFrame: frame, length: length, fps: fps) / 100
        let weight = definition.strength.value(atFrame: frame, length: length, fps: fps) / 100
        return try renderColorEffect(
            input: input,
            uniforms: ColorEffectUniforms(
                mode: 2,
                param0: SIMD4<Float>(Float(intensity), Float(weight), 0, 0)
            )
        )
    }
}

/// 色調補正（単色）。本家 `TintEffect`（D2D 組み込み Tint）。
/// Color は Premultiplied の Vector4 として渡される（実測）。
public final class MetalTintProcessor: MetalEffectProcessor {
    private let definition: TintEffectDefinition

    public init(context: MetalGraphicsContext, definition: TintEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        try renderColorEffect(
            input: input,
            uniforms: ColorEffectUniforms(mode: 3, param0: premultipliedVector(definition.color))
        )
    }
}

/// 露出。本家 `ExposureEffect`（D2D 組み込み Exposure）。
/// Value = パラメータ / 100（EV、実測）。
public final class MetalExposureProcessor: MetalEffectProcessor {
    private let definition: ExposureEffectDefinition

    public init(context: MetalGraphicsContext, definition: ExposureEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        let exposureValue = definition.value.value(atFrame: frame, length: length, fps: fps) / 100
        return try renderColorEffect(
            input: input,
            uniforms: ColorEffectUniforms(
                mode: 4,
                param0: SIMD4<Float>(Float(pow(2.0, exposureValue)), 0, 0, 0)
            )
        )
    }
}

/// ガンマ補正。本家 `GammaCorrectionEffect`（D2D 組み込み GammaTransfer）。
/// 指数は Red = 1/(Red×Gamma) 等、Alpha = 1/Gamma（実測）。
public final class MetalGammaCorrectionProcessor: MetalEffectProcessor {
    private let definition: GammaCorrectionEffectDefinition

    public init(context: MetalGraphicsContext, definition: GammaCorrectionEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        let gamma = definition.gamma.value(atFrame: frame, length: length, fps: fps)
        let red = definition.red.value(atFrame: frame, length: length, fps: fps) * gamma
        let green = definition.green.value(atFrame: frame, length: length, fps: fps) * gamma
        let blue = definition.blue.value(atFrame: frame, length: length, fps: fps) * gamma
        return try renderColorEffect(
            input: input,
            uniforms: ColorEffectUniforms(
                mode: 5,
                param0: SIMD4<Float>(
                    Float(1 / red), Float(1 / green), Float(1 / blue), Float(1 / gamma)
                )
            )
        )
    }
}

/// ポスタリゼーション。本家 `PosterizeEffect`（D2D 組み込み Posterize）。
/// 階調数は GetValue の int 化（切り捨て、実測）。
public final class MetalPosterizeProcessor: MetalEffectProcessor {
    private let definition: PosterizeEffectDefinition

    public init(context: MetalGraphicsContext, definition: PosterizeEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        let redCount = max(2, Int(definition.r.value(atFrame: frame, length: length, fps: fps)))
        let greenCount = max(2, Int(definition.g.value(atFrame: frame, length: length, fps: fps)))
        let blueCount = max(2, Int(definition.b.value(atFrame: frame, length: length, fps: fps)))
        return try renderColorEffect(
            input: input,
            uniforms: ColorEffectUniforms(
                mode: 6,
                param0: SIMD4<Float>(Float(redCount), Float(greenCount), Float(blueCount), 0)
            )
        )
    }
}

/// 線形変換。本家 `LinearTransferEffect`（D2D 組み込み LinearTransfer）。
/// 傾き・切片はいずれも /100（実測）。
public final class MetalLinearTransferProcessor: MetalEffectProcessor {
    private let definition: LinearTransferEffectDefinition

    public init(context: MetalGraphicsContext, definition: LinearTransferEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        func evaluate(_ animation: Animation) -> Float {
            Float(animation.value(atFrame: frame, length: length, fps: fps) / 100)
        }
        return try renderColorEffect(
            input: input,
            uniforms: ColorEffectUniforms(
                mode: 7,
                param0: SIMD4<Float>(
                    evaluate(definition.redSlope),
                    evaluate(definition.greenSlope),
                    evaluate(definition.blueSlope),
                    evaluate(definition.alphaSlope)
                ),
                param1: SIMD4<Float>(
                    evaluate(definition.redYIntercept),
                    evaluate(definition.greenYIntercept),
                    evaluate(definition.blueYIntercept),
                    evaluate(definition.alphaYIntercept)
                )
            )
        )
    }
}

#endif
