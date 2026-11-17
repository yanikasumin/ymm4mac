#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// GPU 処理系エフェクトの Metal 処理器を供給する `EffectPairProvider`。
///
/// Core の `TypedEffectPairProvider` を内包し、DrawDescription 変換群や
/// 未対応の GPU 系はそちらが返す定義（と処理器）をそのまま使い、第1段の
/// 対象（色変換系＋ガウスぼかし＋矩形モザイク）だけを Metal 処理器を返す
/// ラッパ定義へ差し替える。ラッパは基底定義の同一性でキャッシュし、
/// 連鎖の再利用判定（定義インスタンスの同一性）が安定するよう保つ。
/// 描画はこの供給元が所有する文脈で同期実行する（合成全体が同期実行の
/// ため、段ごとに完了を待っても順序は変わらない）。
public final class MetalEffectPairProvider: EffectPairProvider {
    private let inner: TypedEffectPairProvider
    private let context: MetalGraphicsContext
    private var wrappers: [ObjectIdentifier: MetalEffectDefinition] = [:]

    public init(devices: MetalGraphicsDevices) {
        self.inner = TypedEffectPairProvider()
        self.context = devices.makeContext()
    }

    public func ownEffectPairs(for item: BaseItem & VideoItemProperties) -> [EffectPair] {
        wrap(inner.ownEffectPairs(for: item))
    }

    public func groupEffectPairs(
        for group: GroupItem, childIndex: Int, childCount: Int
    ) -> [EffectPair] {
        wrap(inner.groupEffectPairs(for: group, childIndex: childIndex, childCount: childCount))
    }

    public func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair] {
        wrap(inner.faceEffectPairs(for: faceItem))
    }

    /// 内包供給元のキャッシュを破棄する（プロジェクト再読み込み時など）。
    public func invalidateCache() {
        inner.invalidateCache()
        wrappers = [:]
    }

    private func wrap(_ pairs: [EffectPair]) -> [EffectPair] {
        pairs.map { pair in
            guard let base = pair.definition as? VideoEffectDefinitionBase,
                  MetalEffectDefinition.supportsMetalProcessing(base)
            else {
                return pair
            }
            let key = ObjectIdentifier(base)
            let wrapper: MetalEffectDefinition
            if let cached = wrappers[key] {
                wrapper = cached
            } else {
                wrapper = MetalEffectDefinition(base: base, context: context)
                wrappers[key] = wrapper
            }
            return EffectPair(
                timeSource: pair.timeSource,
                definition: wrapper,
                groupIndex: pair.groupIndex,
                groupCount: pair.groupCount
            )
        }
    }
}

/// 型付き定義を Metal 処理器へ結び付けるラッパ定義。
///
/// 有効状態と診断表現は基底定義へ委譲し、`createProcessor()` だけを
/// Metal 処理器へ差し替える。連鎖側からは通常の定義として見える。
final class MetalEffectDefinition: VideoEffectDefinition {
    let base: VideoEffectDefinitionBase
    let context: MetalGraphicsContext

    init(base: VideoEffectDefinitionBase, context: MetalGraphicsContext) {
        self.base = base
        self.context = context
    }

    var isEnabled: Bool { base.isEnabled }

    var diagnosticText: String? { base.diagnosticText }

    /// Metal 処理器が用意できる定義か（第1段の対象）。
    static func supportsMetalProcessing(_ definition: VideoEffectDefinitionBase) -> Bool {
        switch definition {
        case is InvertEffectDefinition,
             is MonocolorizationEffectDefinition,
             is SepiaEffectDefinition,
             is TintEffectDefinition,
             is ExposureEffectDefinition,
             is GammaCorrectionEffectDefinition,
             is PosterizeEffectDefinition,
             is LinearTransferEffectDefinition,
             is GaussianBlurEffectDefinition,
             is MosaicEffectDefinition:
            return true
        default:
            return false
        }
    }

    func createProcessor() -> any VideoEffectProcessor {
        switch base {
        case let definition as InvertEffectDefinition:
            return MetalInvertProcessor(context: context, definition: definition)
        case let definition as MonocolorizationEffectDefinition:
            return MetalMonocolorizationProcessor(context: context, definition: definition)
        case let definition as SepiaEffectDefinition:
            return MetalSepiaProcessor(context: context, definition: definition)
        case let definition as TintEffectDefinition:
            return MetalTintProcessor(context: context, definition: definition)
        case let definition as ExposureEffectDefinition:
            return MetalExposureProcessor(context: context, definition: definition)
        case let definition as GammaCorrectionEffectDefinition:
            return MetalGammaCorrectionProcessor(context: context, definition: definition)
        case let definition as PosterizeEffectDefinition:
            return MetalPosterizeProcessor(context: context, definition: definition)
        case let definition as LinearTransferEffectDefinition:
            return MetalLinearTransferProcessor(context: context, definition: definition)
        case let definition as GaussianBlurEffectDefinition:
            return MetalGaussianBlurProcessor(context: context, definition: definition)
        case let definition as MosaicEffectDefinition:
            return MetalMosaicProcessor(context: context, definition: definition)
        default:
            return base.createProcessor()
        }
    }
}

/// Metal エフェクト処理器の基盤。
///
/// 入力は登録表（デバイス共有）で実体へ解決し、効果を適用した新しい
/// テクスチャを出力参照へ登録する。出力の境界は入力と同じ（ガウス
/// ぼかしの Soft 境界だけが境界を広げる。本家の D2D でも出力境界が
/// 広がるのはその場合のみ）。
///
/// 第1段の制約: 入力の実体が「変換なし・不透明度 1」のプレーンな画像
/// であることを前提とする。現在の Source 実装（画像・図形・テキスト・
/// 字幕）と処理器自身の出力はすべてこの形であり、連鎖の入力は常に
/// プレーンになる。プレーンでない入力が来た場合は効果を適用せず入力を
/// そのまま出す（差し替え点。台帳に記録）。
public class MetalEffectProcessor: VideoEffectProcessor {
    /// 描画に使う文脈（供給元が所有し、処理器間で共有する）。
    let context: MetalGraphicsContext
    private var inputReference: ImageReference?
    private let outputReference = ImageReference(label: "metal-effect")
    private var hasOutput = false

    public init(context: MetalGraphicsContext) {
        self.context = context
    }

    public var output: ImageReference? {
        hasOutput ? outputReference : nil
    }

    public func setInput(_ image: ImageReference?) {
        inputReference = image
    }

    public func clearInput() {
        inputReference = nil
    }

    @discardableResult
    public func update(_ description: EffectDescription) throws -> DrawDescription {
        guard let inputReference,
              let input = context.devices.image(for: inputReference)
        else {
            // 入力が無い場合は 1×1 透明を出す（本家の空出力に相当）。
            register(MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            ))
            return description.drawDescription
        }
        guard input.transform == .identity, input.opacity == 1 else {
            register(input)
            return description.drawDescription
        }
        if let rendered = try render(input: input, description: description) {
            register(rendered)
        } else {
            register(input)
        }
        // 本家の対象処理器はいずれも DrawDescription を無変換で返す。
        return description.drawDescription
    }

    /// 効果の適用。具象処理器が差し替える。返した実体が出力として
    /// 登録される。入力自身を返せば素通しになる。
    func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        input
    }

    public func dispose() {
        context.devices.unregister(outputReference)
        inputReference = nil
        hasOutput = false
    }

    private func register(_ image: MetalImage) {
        context.devices.register(outputReference, image: image)
        hasOutput = true
    }

    // MARK: - 評価文脈

    /// パラメータ評価の文脈（本家の各処理器が読む ItemPosition /
    /// ItemDuration / FPS）。
    func evaluationContext(_ description: EffectDescription) -> (frame: Int, length: Int, fps: Int) {
        (
            frame: description.itemDescription.itemPosition.frame,
            length: description.itemDescription.itemDuration.frame,
            fps: description.itemDescription.fps
        )
    }

    // MARK: - 描画ヘルパ

    /// エフェクト用テクスチャを生成する（読み戻し可能な共有ストレージ）。
    func makeTexture(width: Int, height: Int, usage: MTLTextureUsage) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(1, width), height: max(1, height), mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .shared
        return context.devices.device.makeTexture(descriptor: descriptor)
    }

    /// 全面四角形の頂点（クリップ空間。uv はテクスチャ全体）。
    var fullscreenQuad: [QuadVertex] {
        [
            QuadVertex(position: SIMD4(-1, 1, 0, 1), uv: SIMD2(0, 0)),
            QuadVertex(position: SIMD4(1, 1, 0, 1), uv: SIMD2(1, 0)),
            QuadVertex(position: SIMD4(-1, -1, 0, 1), uv: SIMD2(0, 1)),
            QuadVertex(position: SIMD4(1, -1, 0, 1), uv: SIMD2(1, 1)),
        ]
    }

    /// 1パスの描画を実行し、完了まで待つ。GPU 実行の失敗は
    /// `MetalRenderError` として投げる（MAC-0021 の契約に合わせる）。
    func executeRenderPass(
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
        let vertices = fullscreenQuad
        encoder.setVertexBytes(
            vertices, length: MemoryLayout<QuadVertex>.stride * vertices.count, index: 0
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

    /// 色変換系の共通パス。入力と同寸法のテクスチャへ書き出す。
    func renderColorEffect(
        input: MetalImage,
        uniforms: ColorEffectUniforms
    ) throws -> MetalImage? {
        guard let outputTexture = makeTexture(
            width: input.texture.width, height: input.texture.height,
            usage: [.renderTarget, .shaderRead]
        ) else { return nil }
        var uniforms = uniforms
        try executeRenderPass(
            output: outputTexture, pipeline: context.devices.effectPipeline
        ) { encoder in
            encoder.setFragmentTexture(input.texture, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<ColorEffectUniforms>.size, index: 0
            )
        }
        return MetalImage(
            texture: outputTexture, bounds: input.bounds,
            texturePlaneRect: input.texturePlaneRect,
            planeOffset: input.planeOffset,
            interpolation: input.interpolation
        )
    }
}

/// 色変換シェーダのユニフォーム（MetalGraphics のシェーダ定義と一致）。
struct ColorEffectUniforms {
    var mode: UInt32
    var param0: SIMD4<Float>
    var param1: SIMD4<Float>

    init(mode: UInt32, param0: SIMD4<Float> = .zero, param1: SIMD4<Float> = .zero) {
        self.mode = mode
        self.param0 = param0
        self.param1 = param1
    }
}

/// 本家 `Color`（ARGB のバイト値）を Premultiplied の Vector4 へ変換する。
/// 本家の各処理器が使う式どおり（成分 = バイト値/255 × アルファ/255、
/// アルファ成分 = アルファ/255）。
func premultipliedVector(_ color: Color) -> SIMD4<Float> {
    let alpha = Float(color.alpha) / 255
    return SIMD4<Float>(
        Float(color.red) / 255 * alpha,
        Float(color.green) / 255 * alpha,
        Float(color.blue) / 255 * alpha,
        alpha
    )
}

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

// MARK: - ガウスぼかし

/// ガウスぼかし。本家 `GaussianBlurEffect`（D2D 組み込み GaussianBlur）。
/// StandardDeviation = Blur の値そのもの（実測）、Optimization = Quality、
/// BorderMode は IsHardBorderMode で Hard / Soft を切り替える（実測）。
///
/// 実装は分離型の2パス。大きな σ では作業テクスチャを縮小してから
/// ぼかす（σ を作業解像度で 6 以下に収める）。これは D2D の Quality
/// 最適化の内部方式とは異なるが、ガウスぼかしの可視結果を保つための
/// 標準的な近似である（台帳に記録）。カーネルは ±3σ で打ち切る。
/// Soft 境界では出力境界が 3σ だけ広がり、範囲外は透明として読む。
/// Hard 境界では出力境界は入力と同じで、範囲外は鏡像として読む。
public final class MetalGaussianBlurProcessor: MetalEffectProcessor {
    private let definition: GaussianBlurEffectDefinition

    public init(context: MetalGraphicsContext, definition: GaussianBlurEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    /// ぼかしのユニフォーム（MetalGraphics のシェーダ定義と一致）。
    private struct BlurUniforms {
        var step: SIMD2<Float>
        var mapScale: SIMD2<Float>
        var mapOffset: SIMD2<Float>
        var radius: Int32
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        let sigma = definition.blur.value(atFrame: frame, length: length, fps: fps)
        guard sigma > 0 else { return input }
        let hardBorder = definition.isHardBorderMode

        // 作業解像度。σ が大きい場合は縮小して σ を 6 以下へ収める。
        let downsample = sigma > 6 ? Int(ceil(sigma / 6)) : 1
        let workSigma = sigma / Double(downsample)
        let radius = Int(ceil(3 * workSigma))
        var weights = [Float](repeating: 0, count: radius + 1)
        var total: Double = 0
        for index in 0...radius {
            let weight = exp(-Double(index * index) / (2 * workSigma * workSigma))
            weights[index] = Float(weight)
            total += index == 0 ? weight : 2 * weight
        }
        for index in 0...radius {
            weights[index] = Float(Double(weights[index]) / total)
        }

        // 出力境界。Soft では 3σ 広げ、Hard では入力と同じ。
        let expansion = hardBorder ? 0 : ceil(3 * sigma)
        let outBounds = RectF(
            left: input.bounds.left - expansion,
            top: input.bounds.top - expansion,
            right: input.bounds.right + expansion,
            bottom: input.bounds.bottom + expansion
        )
        let workWidth = max(1, Int(ceil((outBounds.right - outBounds.left) / Double(downsample))))
        let workHeight = max(1, Int(ceil((outBounds.bottom - outBounds.top) / Double(downsample))))
        guard let workA = makeTexture(
                width: workWidth, height: workHeight, usage: [.renderTarget, .shaderRead]),
              let workB = makeTexture(
                width: workWidth, height: workHeight, usage: [.renderTarget, .shaderRead])
        else { return nil }
        let sampler = hardBorder ? context.devices.mirrorSampler : context.devices.borderSampler

        // 準備パス: 入力を作業テクスチャへ写す（縮小と境界拡張を伴う）。
        // 入力テクスチャの UV は、内容境界ではなくテクスチャが張る平面
        // 範囲（texturePlaneRect）基準で求める（内容境界だけが小さい
        // 描画先画像でも画素対応が保たれる。MAC-0027）。
        let inputPlaneWidth = input.texturePlaneRect.right - input.texturePlaneRect.left
        let inputPlaneHeight = input.texturePlaneRect.bottom - input.texturePlaneRect.top
        try blurPass(
            input: input.texture, output: workA, sampler: sampler,
            uniforms: BlurUniforms(
                step: .zero,
                mapScale: SIMD2<Float>(
                    Float((outBounds.right - outBounds.left) / inputPlaneWidth),
                    Float((outBounds.bottom - outBounds.top) / inputPlaneHeight)
                ),
                mapOffset: SIMD2<Float>(
                    Float((outBounds.left + input.planeOffset.x - input.texturePlaneRect.left) / inputPlaneWidth),
                    Float((outBounds.top + input.planeOffset.y - input.texturePlaneRect.top) / inputPlaneHeight)
                ),
                radius: 0
            ),
            weights: [1]
        )
        // 横パス。
        try blurPass(
            input: workA, output: workB, sampler: sampler,
            uniforms: BlurUniforms(
                step: SIMD2<Float>(1 / Float(workWidth), 0),
                mapScale: SIMD2<Float>(1, 1), mapOffset: .zero,
                radius: Int32(radius)
            ),
            weights: weights
        )
        // 縦パス。
        try blurPass(
            input: workB, output: workA, sampler: sampler,
            uniforms: BlurUniforms(
                step: SIMD2<Float>(0, 1 / Float(workHeight)),
                mapScale: SIMD2<Float>(1, 1), mapOffset: .zero,
                radius: Int32(radius)
            ),
            weights: weights
        )
        return MetalImage(
            texture: workA, bounds: outBounds, interpolation: .linear
        )
    }

    private func blurPass(
        input: MTLTexture,
        output: MTLTexture,
        sampler: MTLSamplerState,
        uniforms: BlurUniforms,
        weights: [Float]
    ) throws {
        var uniforms = uniforms
        var weights = weights
        try executeRenderPass(
            output: output, pipeline: context.devices.blurPipeline
        ) { encoder in
            encoder.setFragmentTexture(input, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<BlurUniforms>.size, index: 0
            )
            encoder.setFragmentBytes(
                &weights, length: MemoryLayout<Float>.size * weights.count, index: 1
            )
        }
    }
}

// MARK: - モザイク

/// モザイク。本家 `MosaicEffect`。
///
/// 本家は形状パラメータ（MosaicParameter）が効果実体を決める。既定は
/// RectangleMosaicParameter で、その Size（Animation、既定 10）が
/// セル寸法になる（実測）。第1段では矩形のみを実装し、他の形状
/// （Circle / Triangle / Hexagon / Delaunay / Voronoi）は素通しとする。
/// セルの色はセル内テクセルの平均（本家カスタムシェーダの .cso は
/// 解析範囲に無く、平均か中心サンプルかは未確定。台帳に記録）。
public final class MetalMosaicProcessor: MetalEffectProcessor {
    private let definition: MosaicEffectDefinition

    public init(context: MetalGraphicsContext, definition: MosaicEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    /// モザイクのユニフォーム（MetalGraphics のシェーダ定義と一致）。
    private struct MosaicUniforms {
        var size: Float
        var width: UInt32
        var height: UInt32
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let size = rectangleCellSize(description: description) else {
            // 矩形以外の形状は第1段では未対応（素通し）。
            return input
        }
        guard let outputTexture = makeTexture(
            width: input.texture.width, height: input.texture.height,
            usage: [.shaderWrite, .shaderRead]
        ) else { return nil }
        guard let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        var uniforms = MosaicUniforms(
            size: Float(size),
            width: UInt32(input.texture.width),
            height: UInt32(input.texture.height)
        )
        encoder.setComputePipelineState(context.devices.mosaicPipeline)
        encoder.setTexture(input.texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MosaicUniforms>.size, index: 0)
        let cellsX = Int(ceil(Double(input.texture.width) / size))
        let cellsY = Int(ceil(Double(input.texture.height) / size))
        encoder.dispatchThreads(
            MTLSize(width: cellsX, height: cellsY, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw MetalRenderError.commandBufferFailed(underlying: commandBuffer.error)
        }
        return MetalImage(
            texture: outputTexture, bounds: input.bounds,
            texturePlaneRect: input.texturePlaneRect,
            planeOffset: input.planeOffset,
            interpolation: input.interpolation
        )
    }

    /// 矩形モザイクのセル寸法を取り出す。パラメータが矩形でなければ nil。
    ///
    /// パラメータは生保持（PreservedObject）のため、Size の Animation は
    /// ここで JSON から直接復元する（CodecSupport は Core 内部のため）。
    /// キーフレーム文脈は型付きパラメータでないため伝播しない（既存の
    /// 定義層の制約と同じ。台帳に記録）。
    private func rectangleCellSize(description: EffectDescription) -> Double? {
        guard let parameter = definition.mosaicParameter else {
            // パラメータ欠落時は本家の既定（RectangleMosaicParameter、
            // Size 既定 10）に従う。
            return 10
        }
        guard let typeName = parameter.typeName,
              typeName.hasPrefix(
                "YukkuriMovieMaker.Project.Effects.MosaicParameters.RectangleMosaicParameter")
        else {
            return nil
        }
        var animation = Animation(defaultValue: 10, minValue: 0, maxValue: 2000)
        if case .object(let fields) = parameter.value,
           let sizeValue = fields.first(where: { $0.key == "Size" })?.value {
            Self.decodeAnimationSubset(sizeValue, into: &animation)
        }
        let (frame, length, fps) = evaluationContext(description)
        let value = animation.value(atFrame: frame, length: length, fps: fps)
        // 本家カスタム効果の setter のクランプ（実測: 1〜5000）。
        return min(5000, max(1, value))
    }

    /// Animation の保存形式のうち、値列・種類・Span と旧互換の
    /// From / To だけを復元する（ベジェは対象外）。
    private static func decodeAnimationSubset(_ value: JSONValue, into animation: inout Animation) {
        guard case .object(let fields) = value else { return }
        for (key, fieldValue) in fields {
            switch key {
            case "Values":
                if case .array(let elements) = fieldValue {
                    animation.values = elements.map { element in
                        if let number = Self.number(of: element) {
                            return AnimationValue(number)
                        }
                        if case .object(let elementFields) = element,
                           let valueField = elementFields.first(where: { $0.key == "Value" })?.value,
                           let number = Self.number(of: valueField) {
                            return AnimationValue(number)
                        }
                        return AnimationValue(0)
                    }
                }
            case "Span":
                if let number = Self.number(of: fieldValue) {
                    animation.span = number
                }
            case "AnimationType":
                if case .string(let name) = fieldValue,
                   let type = AnimationType(honkeName: name) {
                    animation.animationType = type
                } else if let number = Self.number(of: fieldValue),
                          let type = AnimationType(rawValue: Int(number)) {
                    animation.animationType = type
                }
            case "From":
                let number = Self.number(of: fieldValue) ?? 0
                if animation.values.isEmpty {
                    animation.values = [AnimationValue(number)]
                } else {
                    animation.values[0] = AnimationValue(number)
                }
            case "To":
                let number = Self.number(of: fieldValue) ?? 0
                if animation.values.isEmpty {
                    animation.values = [AnimationValue(0)]
                }
                if animation.values.count == 1 {
                    animation.values.append(AnimationValue(number))
                } else {
                    animation.values[1] = AnimationValue(number)
                }
            default:
                break
            }
        }
    }

    private static func number(of value: JSONValue) -> Double? {
        switch value {
        case .numberLiteral(let literal):
            return Double(literal)
        case .string(let text):
            return Double(text)
        default:
            return nil
        }
    }
}
#endif
