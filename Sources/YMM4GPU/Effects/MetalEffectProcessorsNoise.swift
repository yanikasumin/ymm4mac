#if os(macOS)
import Foundation
import Metal
import YMM4Core

// MARK: - ノイズ系（Issue #45 第1弾）

/// ノイズ生成器のユニフォーム（MetalGraphics の NoiseUniforms と一致、
/// 本家 NoiseBase の定数ブロック 96 バイト＋描画側の追加分）。
struct NoisePassUniforms {
    var x: Float
    var y: Float
    var z: Float
    var threshold: Float
    var scaleX: Float
    var scaleY: Float
    var scaleZ: Float
    var strength: Float
    var octaves: Int32
    var seed: Int32
    var levels: Int32
    var angle: Float
    var warpStrength: Float
    var warpScale: Float
    var fractalMode: Int32
    var distanceMode: Int32
    var cellOutput: Int32
    var lacunarity: Float
    var gain: Float
    var pad2: Float
    var stripeInterval: Float
    var stripeWarpAmount: Float
    var flowAmount: Float
    var pad3: Float
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var noiseType: Int32
    var padA: Float
    var padB: Float
    var padC: Float
}

/// ノイズ合成のユニフォーム（MetalGraphics の NoiseBlendUniforms と一致）。
struct NoiseBlendPassUniforms {
    var planeIn: SIMD4<Float>
    var planeA: SIMD4<Float>
    var planeR: SIMD4<Float>
    var planeG: SIMD4<Float>
    var planeB: SIMD4<Float>
    var offsetIn: SIMD2<Float>
    var offsetA: SIMD2<Float>
    var offsetR: SIMD2<Float>
    var offsetG: SIMD2<Float>
    var offsetB: SIMD2<Float>
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
}

/// ノイズパラメータ一式。本家 `BasicNoiseParameterBase` の既定値・
/// 範囲で Animation を作り、生保持 JSON から Values / Span /
/// AnimationType だけを読み込む（`CodecSupport.decodeAnimation` の
/// 扱う範囲のうちノイズパラメータが使う分）。
struct NoiseParameterSet {
    var strength: Animation
    var threshold: Animation
    var levels: Animation
    var octaves: Animation
    var lacunarity: Animation
    var gain: Animation
    var warpStrength: Animation
    var warpScale: Animation
    var x: Animation
    var y: Animation
    var z: Animation
    var speedX: Animation
    var speedY: Animation
    var speedZ: Animation
    var size: Animation
    var scaleX: Animation
    var scaleY: Animation
    var scaleZ: Animation
    var angle: Animation
    /// Fractal の整形モード（0 = Normal、1 = Turbulence、2 = Ridged）。
    var fractalMode: Int32

    init(json: JSONValue) {
        func parameter(
            _ key: String, defaultValue: Double, minValue: Double, maxValue: Double
        ) -> Animation {
            var animation = Animation(
                defaultValue: defaultValue, minValue: minValue, maxValue: maxValue
            )
            guard let field = json.field(key) else { return animation }
            if let values = field.field("Values")?.arrayValue {
                animation.values = values.map {
                    AnimationValue($0.field("Value")?.doubleValue ?? $0.doubleValue ?? 0)
                }
            }
            if let span = field.field("Span")?.doubleValue {
                animation.span = span
            }
            if let name = field.field("AnimationType")?.stringValue,
               let type = AnimationType(honkeName: name) {
                animation.animationType = type
            }
            return animation
        }
        let wide = -100000.0
        let wideMax = 100000.0
        strength = parameter("Strength", defaultValue: 100, minValue: 0, maxValue: 200)
        threshold = parameter("Threshold", defaultValue: 0, minValue: 0, maxValue: 100)
        levels = parameter("Levels", defaultValue: 256, minValue: 2, maxValue: 256)
        octaves = parameter("Octaves", defaultValue: 5, minValue: 0, maxValue: 32)
        lacunarity = parameter("Lacunarity", defaultValue: 2, minValue: 1, maxValue: 4)
        gain = parameter("Gain", defaultValue: 0.5, minValue: 0, maxValue: 1)
        warpStrength = parameter(
            "WarpStrength", defaultValue: 0, minValue: wide, maxValue: wideMax)
        warpScale = parameter("WarpScale", defaultValue: 100, minValue: 0, maxValue: wideMax)
        x = parameter("X", defaultValue: 0, minValue: wide, maxValue: wideMax)
        y = parameter("Y", defaultValue: 0, minValue: wide, maxValue: wideMax)
        z = parameter("Z", defaultValue: 0, minValue: wide, maxValue: wideMax)
        speedX = parameter("SpeedX", defaultValue: 0, minValue: wide, maxValue: wideMax)
        speedY = parameter("SpeedY", defaultValue: 0, minValue: wide, maxValue: wideMax)
        speedZ = parameter("SpeedZ", defaultValue: 0, minValue: wide, maxValue: wideMax)
        size = parameter("Size", defaultValue: 100, minValue: 0, maxValue: wideMax)
        scaleX = parameter("ScaleX", defaultValue: 100, minValue: 0, maxValue: wideMax)
        scaleY = parameter("ScaleY", defaultValue: 100, minValue: 0, maxValue: wideMax)
        scaleZ = parameter("ScaleZ", defaultValue: 100, minValue: 0, maxValue: wideMax)
        angle = parameter("Angle", defaultValue: 0, minValue: wide, maxValue: wideMax)
        if let modeName = json.field("FractalMode")?.stringValue {
            fractalMode = modeName.contains("Turbulence") ? 1
                : modeName.contains("Ridged") ? 2 : 0
        } else if let modeValue = json.field("FractalMode")?.intValue {
            fractalMode = Int32(modeValue)
        } else {
            fractalMode = 0
        }
    }
}

/// ノイズ。本家 `NoiseEffect`（Issue #45）。
/// 配線（NoiseEffect.cs の実測）: 生成器の出力（グレースケール）を
/// NoiseBlend で入力へ乗算する。IsColor のとき R / G / B は別々の
/// 生成器（シードオフセット +100 / +200 / +300)、IsAlpha のとき
/// A は生成器（+0)。どちらでもないときは1つの生成器が R / G / B を
/// 兼ねる（シードオフセットは +0 とする。実プロジェクトでは
/// 未使用の経路）。使わないチャンネルは白（係数 1)。
/// パラメータから定数への変換は BasicNoiseParameterBase.
/// SetParameterTo の実測どおり（X / Y / Z は速度×フレームを加えて
/// 剰余、Scale は 100 / max(0.001, 値 × Size/100)、Seed は
/// オフセット % 1234、Angle は符号反転してラジアン化）。
/// IsUniqueSeed のシード基礎値はパラメータの .NET GetHashCode で
/// 対応付け未確定のため 0 として扱う（差分として記録。
/// 実プロジェクトの全実例は IsUniqueSeed = false)。
/// 対応する生成器は Fractal / Random / Curl の3種。それ以外の
/// NoiseType と、パラメータが無い場合は素通し（本家は生成器が
/// 作れない場合に全チャンネル白 = 入力そのままになる）。
public final class MetalNoiseProcessor: MetalEffectProcessor {
    private let definition: NoiseEffectDefinition

    public init(context: MetalGraphicsContext, definition: NoiseEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let noiseType: Int32
        switch definition.noiseType {
        case .fractal: noiseType = 0
        case .random: noiseType = 1
        case .curl: noiseType = 2
        default: return input
        }
        guard let parameter = definition.noiseParameter else { return input }
        let parameters = NoiseParameterSet(json: parameter.value)
        let white = try makeWhiteImage(input: input)
        func generator(_ seedOffset: Int) throws -> MetalImage {
            try renderGenerator(
                input: input, parameters: parameters,
                description: description, noiseType: noiseType, seedOffset: seedOffset
            )
        }
        let texA: MetalImage
        let texR: MetalImage
        let texG: MetalImage
        let texB: MetalImage
        if definition.isColor {
            texR = try generator(100)
            texG = try generator(200)
            texB = try generator(300)
        } else if !definition.isAlpha {
            let shared = try generator(0)
            texR = shared
            texG = shared
            texB = shared
        } else {
            texR = white
            texG = white
            texB = white
        }
        texA = definition.isAlpha ? try generator(0) : white
        var uniforms = NoiseBlendPassUniforms(
            planeIn: planeVector(input),
            planeA: planeVector(texA),
            planeR: planeVector(texR),
            planeG: planeVector(texG),
            planeB: planeVector(texB),
            offsetIn: SIMD2<Float>(Float(input.planeOffset.x), Float(input.planeOffset.y)),
            offsetA: SIMD2<Float>(Float(texA.planeOffset.x), Float(texA.planeOffset.y)),
            offsetR: SIMD2<Float>(Float(texR.planeOffset.x), Float(texR.planeOffset.y)),
            offsetG: SIMD2<Float>(Float(texG.planeOffset.x), Float(texG.planeOffset.y)),
            offsetB: SIMD2<Float>(Float(texB.planeOffset.x), Float(texB.planeOffset.y)),
            outputOrigin: SIMD2<Float>(Float(input.bounds.left), Float(input.bounds.top)),
            outputSize: SIMD2<Float>(
                Float(input.bounds.right - input.bounds.left),
                Float(input.bounds.bottom - input.bounds.top))
        )
        let outputTexture = try makeTexture(
            width: Int(ceil(input.bounds.right - input.bounds.left)),
            height: Int(ceil(input.bounds.bottom - input.bounds.top)),
            usage: [.renderTarget, .shaderRead]
        )
        try executeRenderPass(
            output: outputTexture, pipeline: context.devices.noiseBlendPipeline
        ) { encoder in
            encoder.setFragmentTexture(input.texture, index: 0)
            encoder.setFragmentTexture(texA.texture, index: 1)
            encoder.setFragmentTexture(texR.texture, index: 2)
            encoder.setFragmentTexture(texG.texture, index: 3)
            encoder.setFragmentTexture(texB.texture, index: 4)
            encoder.setFragmentSamplerState(context.devices.borderSampler, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<NoiseBlendPassUniforms>.size, index: 0
            )
        }
        return MetalImage(texture: outputTexture, bounds: input.bounds)
    }

    /// 生成器1チャンネル分のテクスチャ（入力境界と同じ寸法）。
    private func renderGenerator(
        input: MetalImage,
        parameters: NoiseParameterSet,
        description: EffectDescription,
        noiseType: Int32,
        seedOffset: Int
    ) throws -> MetalImage {
        let (frame, _, _) = evaluationContext(description)
        func value(_ animation: Animation) -> Double {
            evaluate(animation, description)
        }
        let size = value(parameters.size)
        var uniforms = NoisePassUniforms(
            x: Float((value(parameters.x) + value(parameters.speedX) * Double(frame))
                .truncatingRemainder(dividingBy: 123456.789)),
            y: Float((value(parameters.y) + value(parameters.speedY) * Double(frame))
                .truncatingRemainder(dividingBy: 154321.0987)),
            z: Float((value(parameters.z) + value(parameters.speedZ) * Double(frame))
                .truncatingRemainder(dividingBy: 160213.8549)),
            threshold: Float(value(parameters.threshold) / 100),
            scaleX: Float(100 / max(0.001, value(parameters.scaleX) * (size / 100))),
            scaleY: Float(100 / max(0.001, value(parameters.scaleY) * (size / 100))),
            scaleZ: Float(100 / max(0.001, value(parameters.scaleZ) * (size / 100))),
            strength: Float(value(parameters.strength) / 100),
            octaves: Int32(value(parameters.octaves)),
            seed: Int32(seedOffset % 1234),
            levels: Int32(value(parameters.levels)),
            angle: Float(-(value(parameters.angle) * Double.pi / 180)),
            warpStrength: Float(value(parameters.warpStrength)),
            warpScale: Float(max(0.01, value(parameters.warpScale) / 100)),
            fractalMode: parameters.fractalMode,
            distanceMode: 0,
            cellOutput: 0,
            lacunarity: Float(value(parameters.lacunarity)),
            gain: Float(value(parameters.gain)),
            pad2: 0,
            stripeInterval: 0,
            stripeWarpAmount: 0,
            flowAmount: 0,
            pad3: 0,
            outputOrigin: SIMD2<Float>(Float(input.bounds.left), Float(input.bounds.top)),
            outputSize: SIMD2<Float>(
                Float(input.bounds.right - input.bounds.left),
                Float(input.bounds.bottom - input.bounds.top)),
            noiseType: noiseType,
            padA: 0, padB: 0, padC: 0
        )
        let texture = try makeTexture(
            width: Int(ceil(input.bounds.right - input.bounds.left)),
            height: Int(ceil(input.bounds.bottom - input.bounds.top)),
            usage: [.renderTarget, .shaderRead]
        )
        try executeRenderPass(
            output: texture, pipeline: context.devices.noisePipeline
        ) { encoder in
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<NoisePassUniforms>.size, index: 0
            )
        }
        return MetalImage(texture: texture, bounds: input.bounds)
    }

    /// 白チャンネル（係数 1）用の白テクスチャ。入力と同じ寸法で
    /// 作る: 1×1 テクスチャだと線形サンプラの足跡がテクセル中心
    /// 以外で境界色（透明）と混ざり、係数が 1 にならないため。
    private func makeWhiteImage(input: MetalImage) throws -> MetalImage {
        let width = input.texture.width
        let height = input.texture.height
        let texture = try makeTexture(width: width, height: height, usage: [.shaderRead])
        let bytes = [UInt8](repeating: 255, count: width * height * 4)
        bytes.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: raw.baseAddress!, bytesPerRow: width * 4
            )
        }
        return MetalImage(texture: texture, bounds: input.bounds)
    }
}

#endif
