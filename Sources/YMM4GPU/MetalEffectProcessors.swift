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

    /// トランジション前後の全体エフェクト（MAC-0036）。内包供給元の
    /// 型付き定義を、通常の連鎖と同じく Metal 処理器へ差し替える。
    public func transitionEffectPairs(
        for item: TransitionItem, isBefore: Bool
    ) -> [EffectPair] {
        wrap(inner.transitionEffectPairs(for: item, isBefore: isBefore))
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

    /// Metal 処理器が用意できる定義か（第1段＋第2段の対象）。
    /// 第2段の対象は MetalEffectProcessorsStage2.swift に根拠とともに記す。
    /// ここに無い GPU 系定義は Core の素通り処理器のままになる。
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
             is MosaicEffectDefinition,
             // 第2段: 幾何変換系
             is RotateEffectDefinition,
             is SkewEffectDefinition,
             is CenterPointEffectDefinition,
             is CropEffectDefinition,
             is MarginEffectDefinition,
             is CopyAndReverseEffectDefinition,
             is TilingEffectDefinition,
             is AutomaticZoomEffectDefinition,
             is RoundCornerEffectDefinition,
             // 第2段: ぼかし・色収差
             is BorderBlurEffectDefinition,
             is DirectionalBlurEffectDefinition,
             is ChromaticAberrationEffectDefinition,
             // 第2段: 影・塗り・枠線（単色ブラシのみ）
             is ShadowEffectDefinition,
             is FillBackgroundEffectDefinition,
             is FillForegroundEffectDefinition,
             is FrameLineEffectDefinition,
             // 第2段: ワープ系
             is MorphologyEffectDefinition,
             is DrawLazyEffectEffectDefinition,
             is JumpEffectDefinition,
             // 第2段: イン／アウト系
             is InOutBorderBlurEffectDefinition,
             is InOutGaussianBlurEffectDefinition,
             is InOutMosaicEffectDefinition,
             is InOutMoveFromOutsideImageEffectDefinition,
             is InOutGetUpEffectDefinition,
             is InOutRotateEffectDefinition,
             is InOutSkewEffectDefinition,
             is InOutJumpEffectDefinition,
             // 第2段: ランダム／反復系
             is RandomRotateEffectDefinition,
             is RandomSkewEffectDefinition,
             is RepeatRotateEffectDefinition,
             is RepeatSkewEffectDefinition:
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
        // 第2段（MetalEffectProcessorsStage2.swift）
        case let definition as RotateEffectDefinition:
            return MetalRotateProcessor(context: context, definition: definition)
        case let definition as SkewEffectDefinition:
            return MetalSkewProcessor(context: context, definition: definition)
        case let definition as CenterPointEffectDefinition:
            return MetalCenterPointProcessor(context: context, definition: definition)
        case let definition as CropEffectDefinition:
            return MetalCropProcessor(context: context, definition: definition)
        case let definition as MarginEffectDefinition:
            return MetalMarginProcessor(context: context, definition: definition)
        case let definition as CopyAndReverseEffectDefinition:
            return MetalCopyAndReverseProcessor(context: context, definition: definition)
        case let definition as TilingEffectDefinition:
            return MetalTilingProcessor(context: context, definition: definition)
        case let definition as AutomaticZoomEffectDefinition:
            return MetalAutomaticZoomProcessor(context: context, definition: definition)
        case let definition as RoundCornerEffectDefinition:
            return MetalRoundCornerProcessor(context: context, definition: definition)
        case let definition as BorderBlurEffectDefinition:
            return MetalBorderBlurProcessor(context: context, definition: definition)
        case let definition as DirectionalBlurEffectDefinition:
            return MetalDirectionalBlurProcessor(context: context, definition: definition)
        case let definition as ChromaticAberrationEffectDefinition:
            return MetalChromaticAberrationProcessor(context: context, definition: definition)
        case let definition as ShadowEffectDefinition:
            return MetalShadowProcessor(context: context, definition: definition)
        case let definition as FillBackgroundEffectDefinition:
            return MetalFillBackgroundProcessor(context: context, definition: definition)
        case let definition as FillForegroundEffectDefinition:
            return MetalFillForegroundProcessor(context: context, definition: definition)
        case let definition as FrameLineEffectDefinition:
            return MetalFrameLineProcessor(context: context, definition: definition)
        case let definition as MorphologyEffectDefinition:
            return MetalMorphologyProcessor(context: context, definition: definition)
        case let definition as DrawLazyEffectEffectDefinition:
            return MetalDrawLazyProcessor(context: context, definition: definition)
        case let definition as JumpEffectDefinition:
            return MetalJumpProcessor(context: context, definition: definition)
        case let definition as InOutBorderBlurEffectDefinition:
            return MetalInOutBorderBlurProcessor(context: context, definition: definition)
        case let definition as InOutGaussianBlurEffectDefinition:
            return MetalInOutGaussianBlurProcessor(context: context, definition: definition)
        case let definition as InOutMosaicEffectDefinition:
            return MetalInOutMosaicProcessor(context: context, definition: definition)
        case let definition as InOutMoveFromOutsideImageEffectDefinition:
            return MetalInOutMoveFromOutsideImageProcessor(context: context, definition: definition)
        case let definition as InOutGetUpEffectDefinition:
            return MetalInOutGetUpProcessor(context: context, definition: definition)
        case let definition as InOutRotateEffectDefinition:
            return MetalInOutRotateProcessor(context: context, definition: definition)
        case let definition as InOutSkewEffectDefinition:
            return MetalInOutSkewProcessor(context: context, definition: definition)
        case let definition as InOutJumpEffectDefinition:
            return MetalInOutJumpProcessor(context: context, definition: definition)
        case let definition as RandomRotateEffectDefinition:
            return MetalRandomRotateProcessor(context: context, definition: definition)
        case let definition as RandomSkewEffectDefinition:
            return MetalRandomSkewProcessor(context: context, definition: definition)
        case let definition as RepeatRotateEffectDefinition:
            return MetalRepeatRotateProcessor(context: context, definition: definition)
        case let definition as RepeatSkewEffectDefinition:
            return MetalRepeatSkewProcessor(context: context, definition: definition)
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
            return modifiedDrawDescription(description, input: nil)
        }
        guard input.transform == .identity, input.opacity == 1 else {
            register(input)
            return modifiedDrawDescription(description, input: input)
        }
        if let rendered = try render(input: input, description: description) {
            register(rendered)
        } else {
            register(input)
        }
        return modifiedDrawDescription(description, input: input)
    }

    /// 戻り DrawDescription を書き換える処理器（回転の 3D 分岐・中心点・
    /// 自動ズーム・ジャンプ・描画遅延等、第2段）用のフック。既定は無変更
    /// （第1段の対象処理器はいずれも DrawDescription を無変換で返す）。
    /// 本家では DrawDescription の書き換えは画像変換とは独立に行われる
    /// ため、入力がプレーンでない素通し経路でもフックは通す。`input` は
    /// 登録表で解決した入力実体（入力が無い場合は nil）。
    func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        description.drawDescription
    }

    /// 効果の適用。具象処理器が差し替える。返した実体が出力として
    /// 登録される。入力自身を返せば素通しになる。nil を返してよいのは
    /// 「効果なし」が正当な場合だけであり、テクスチャ確保などの資源
    /// 失敗は `MetalRenderError` を投げる（GPU28-03 / MAC-0033:
    /// 確保失敗を無言の素通しとして公開しない）。
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
    /// 確保失敗は nil でなく `MetalRenderError.textureCreationFailed` を
    /// 投げる（GPU28-03 / MAC-0033: MAC-0021 の失敗通知契約へ統一し、
    /// 確保失敗が「効果なしの素通し」と区別されずに公開されることを防ぐ）。
    func makeTexture(width: Int, height: Int, usage: MTLTextureUsage) throws -> MTLTexture {
        let width = max(1, width)
        let height = max(1, height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .shared
        guard let texture = context.devices.device.makeTexture(descriptor: descriptor) else {
            throw MetalRenderError.textureCreationFailed(width: width, height: height)
        }
        return texture
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
        try executePass(
            output: output, pipeline: pipeline, vertices: fullscreenQuad, configure: configure
        )
    }

    /// 頂点を指定できる版の1パス描画（第2段の変換系が使う）。
    func executePass(
        output: MTLTexture,
        pipeline: MTLRenderPipelineState,
        vertices: [QuadVertex],
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
    ) throws -> MetalImage {
        let outputTexture = try makeTexture(
            width: input.texture.width, height: input.texture.height,
            usage: [.renderTarget, .shaderRead]
        )
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

    // MARK: - 第2段の共通描画ヘルパ

    /// ぼかしパスのユニフォーム（MetalGraphics のシェーダ定義と一致）。
    struct BlurUniforms {
        var step: SIMD2<Float>
        var mapScale: SIMD2<Float>
        var mapOffset: SIMD2<Float>
        var radius: Int32
    }

    /// ぼかしの1パス（準備パスは radius = 0 で写像だけを行う）。
    func blurPass(
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

    /// ガウスぼかしの重み（±3σ 打ち切り、正規化済み）と作業 σ。
    func gaussianKernel(sigma: Double) -> (weights: [Float], radius: Int, workSigma: Double) {
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
        return (weights, radius, workSigma)
    }

    /// 入力を作業テクスチャへ写す準備パス（縮小と境界拡張を伴う）。
    /// UV はテクスチャが張る平面範囲（texturePlaneRect）基準で求める
    /// （MAC-0027 の画素対応の維持）。
    func blurPreparationPass(
        input: MetalImage,
        output: MTLTexture,
        outputBounds: RectF,
        downsample: Int,
        sampler: MTLSamplerState
    ) throws {
        let inputPlaneWidth = input.texturePlaneRect.right - input.texturePlaneRect.left
        let inputPlaneHeight = input.texturePlaneRect.bottom - input.texturePlaneRect.top
        try blurPass(
            input: input.texture, output: output, sampler: sampler,
            uniforms: BlurUniforms(
                step: .zero,
                mapScale: SIMD2<Float>(
                    Float((outputBounds.right - outputBounds.left) / inputPlaneWidth),
                    Float((outputBounds.bottom - outputBounds.top) / inputPlaneHeight)
                ),
                mapOffset: SIMD2<Float>(
                    Float((outputBounds.left + input.planeOffset.x - input.texturePlaneRect.left) / inputPlaneWidth),
                    Float((outputBounds.top + input.planeOffset.y - input.texturePlaneRect.top) / inputPlaneHeight)
                ),
                radius: 0
            ),
            weights: [1]
        )
        _ = downsample
    }

    /// ガウスぼかし本体（分離型2パス）。第1段の `MetalGaussianBlurProcessor`
    /// と縁ぼかし・角丸・影・イン／アウトぼかしが共有する。
    /// Soft 境界では出力境界が 3σ 広がり範囲外は透明、Hard 境界では
    /// 出力境界は入力と同じで範囲外は鏡像として読む。
    func renderGaussianBlurred(
        input: MetalImage, sigma: Double, hardBorder: Bool
    ) throws -> MetalImage {
        guard sigma > 0 else { return input }
        let downsample = sigma > 6 ? Int(ceil(sigma / 6)) : 1
        let (weights, radius, _) = gaussianKernel(sigma: sigma)
        let expansion = hardBorder ? 0 : ceil(3 * sigma)
        let outBounds = RectF(
            left: input.bounds.left - expansion,
            top: input.bounds.top - expansion,
            right: input.bounds.right + expansion,
            bottom: input.bounds.bottom + expansion
        )
        let workWidth = max(1, Int(ceil((outBounds.right - outBounds.left) / Double(downsample))))
        let workHeight = max(1, Int(ceil((outBounds.bottom - outBounds.top) / Double(downsample))))
        let workA = try makeTexture(
            width: workWidth, height: workHeight, usage: [.renderTarget, .shaderRead]
        )
        let workB = try makeTexture(
            width: workWidth, height: workHeight, usage: [.renderTarget, .shaderRead]
        )
        let sampler = hardBorder ? context.devices.mirrorSampler : context.devices.borderSampler
        try blurPreparationPass(
            input: input, output: workA, outputBounds: outBounds,
            downsample: downsample, sampler: sampler
        )
        try blurPass(
            input: workA, output: workB, sampler: sampler,
            uniforms: BlurUniforms(
                step: SIMD2<Float>(1 / Float(workWidth), 0),
                mapScale: SIMD2<Float>(1, 1), mapOffset: .zero,
                radius: Int32(radius)
            ),
            weights: weights
        )
        try blurPass(
            input: workB, output: workA, sampler: sampler,
            uniforms: BlurUniforms(
                step: SIMD2<Float>(0, 1 / Float(workHeight)),
                mapScale: SIMD2<Float>(1, 1), mapOffset: .zero,
                radius: Int32(radius)
            ),
            weights: weights
        )
        return MetalImage(texture: workA, bounds: outBounds, interpolation: .linear)
    }

    /// 方向ぼかし本体。本家 D2D DirectionalBlur の分離不可能な1方向
    /// ガウスを、指定角度方向の1パスで近似する（厳密な D2D 内部方式は
    /// 非公開。台帳に記録）。`angleDegrees` は D2D の Angle 値そのもの
    /// （画面座標系、y 下向きで時計回り正）。
    func renderDirectionalBlurred(
        input: MetalImage, sigma: Double, angleDegrees: Double, hardBorder: Bool
    ) throws -> MetalImage {
        guard sigma > 0 else { return input }
        // 縮小はしない。作業テクスチャを縮小すると、ぼかし方向と直交
        // する境界まで双線形拡大で鈍ってしまう（本家は直交方向の
        // 鮮明さを保つ。MAC-0028 検証で実測: 縦方向ぼかしで縦境界が
        // 約4px鈍った）。カーネルは実解像度で組み立てる。
        let downsample = 1
        let radius = Int(ceil(3 * sigma))
        var weights = [Float](repeating: 0, count: radius + 1)
        var total = 0.0
        for index in 0...radius {
            let weight = exp(-Double(index * index) / (2 * sigma * sigma))
            weights[index] = Float(weight)
            total += index == 0 ? weight : 2 * weight
        }
        for index in 0...radius {
            weights[index] = Float(Double(weights[index]) / total)
        }
        let radians = angleDegrees * Double.pi / 180
        let dirX = cos(radians)
        let dirY = sin(radians)
        let expandX = hardBorder ? 0 : ceil(3 * sigma * abs(dirX))
        let expandY = hardBorder ? 0 : ceil(3 * sigma * abs(dirY))
        let outBounds = RectF(
            left: input.bounds.left - expandX,
            top: input.bounds.top - expandY,
            right: input.bounds.right + expandX,
            bottom: input.bounds.bottom + expandY
        )
        let workWidth = max(1, Int(ceil((outBounds.right - outBounds.left) / Double(downsample))))
        let workHeight = max(1, Int(ceil((outBounds.bottom - outBounds.top) / Double(downsample))))
        let workA = try makeTexture(
            width: workWidth, height: workHeight, usage: [.renderTarget, .shaderRead]
        )
        let workB = try makeTexture(
            width: workWidth, height: workHeight, usage: [.renderTarget, .shaderRead]
        )
        let sampler = hardBorder ? context.devices.mirrorSampler : context.devices.borderSampler
        try blurPreparationPass(
            input: input, output: workA, outputBounds: outBounds,
            downsample: downsample, sampler: sampler
        )
        try blurPass(
            input: workA, output: workB, sampler: sampler,
            uniforms: BlurUniforms(
                step: SIMD2<Float>(Float(dirX) / Float(workWidth), Float(dirY) / Float(workHeight)),
                mapScale: SIMD2<Float>(1, 1), mapOffset: .zero,
                radius: Int32(radius)
            ),
            weights: weights
        )
        return MetalImage(texture: workB, bounds: outBounds, interpolation: .linear)
    }

    /// 矩形モザイク本体（セル内テクセルの平均）。第1段の
    /// `MetalMosaicProcessor` とイン／アウトモザイクが共有する。
    func renderRectangleMosaic(input: MetalImage, cellSize: Double) throws -> MetalImage {
        let outputTexture = try makeTexture(
            width: input.texture.width, height: input.texture.height,
            usage: [.shaderWrite, .shaderRead]
        )
        guard let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        var uniforms = RectangleMosaicUniforms(
            size: Float(cellSize),
            width: UInt32(input.texture.width),
            height: UInt32(input.texture.height)
        )
        encoder.setComputePipelineState(context.devices.mosaicPipeline)
        encoder.setTexture(input.texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<RectangleMosaicUniforms>.size, index: 0)
        let cellsX = Int(ceil(Double(input.texture.width) / cellSize))
        let cellsY = Int(ceil(Double(input.texture.height) / cellSize))
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

    /// 平面行列で入力を変換して新しいテクスチャへ焼く（本家の
    /// AffineTransform2D / Transform3D の実体化に相当）。出力テクスチャは
    /// `outputBounds` を張り、頂点は入力境界の四隅を行列で写したもの、
    /// UV は変換前の平面座標から求める（透視補正つき。MetalRenderTarget
    /// の描画頂点と同じ構成）。
    func renderTransformed(
        input: MetalImage,
        matrix: Matrix4x4,
        outputBounds: RectF,
        interpolation: InterpolationMode
    ) throws -> MetalImage {
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        guard outWidth > 0, outHeight > 0 else {
            // 空の境界は透明として返す（本家の空画像に相当）。
            return MetalImage(texture: context.devices.transparentTexture, bounds: outputBounds)
        }
        let outputTexture = try makeTexture(
            width: Int(ceil(outWidth)), height: Int(ceil(outHeight)),
            usage: [.renderTarget, .shaderRead]
        )
        let corners: [(Double, Double)] = [
            (input.bounds.left, input.bounds.top), (input.bounds.right, input.bounds.top),
            (input.bounds.left, input.bounds.bottom), (input.bounds.right, input.bounds.bottom),
        ]
        let vertices: [QuadVertex] = corners.map { corner in
            let v = matrix.transform(x: corner.0, y: corner.1, z: 0, w: 1)
            let w = v.w == 0 ? 1 : v.w
            let u = (v.x / w - outputBounds.left) / outWidth
            let t = (v.y / w - outputBounds.top) / outHeight
            return QuadVertex(
                position: SIMD4<Float>(
                    Float(2 * u - 1) * Float(w), Float(-(2 * t - 1)) * Float(w), 0, Float(w)
                ),
                uv: input.uv(forLocalX: corner.0, y: corner.1)
            )
        }
        var opacity: Float = 1
        try executePass(
            output: outputTexture, pipeline: context.devices.texturedPipeline, vertices: vertices
        ) { encoder in
            encoder.setFragmentTexture(input.texture, index: 0)
            encoder.setFragmentSamplerState(
                interpolation == .nearestNeighbor
                    ? context.devices.nearestSampler : context.devices.linearSampler,
                index: 0
            )
            encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
        }
        return MetalImage(
            texture: outputTexture, bounds: outputBounds, interpolation: interpolation
        )
    }

    /// ワープ系パス（MetalGraphics の ymm4WarpFragment）。
    /// `mask` が nil の場合はマスクテクスチャへ入力自身を渡す。
    /// `maskPlane` を指定するとマスク側の平面写像を差し替える
    /// （複写反転のパラメータ受け渡しに使う）。
    /// サンプラは範囲外を透明として読む borderSampler 固定: マスク画像は
    /// 有限の境界を持つ平面画像であり、その外側は透明という本家の
    /// 意味論に対応する（MAC-0035 で clampToEdge を試したが、図形マスク
    /// の縁テクセルが外側へ複写されて漏れるため不採用）。
    func renderWarp(
        input: MetalImage,
        mask: MetalImage?,
        outputBounds: RectF,
        mode: UInt32,
        param0: SIMD4<Float> = .zero,
        param1: SIMD4<Float> = .zero,
        maskPlane: SIMD4<Float>? = nil
    ) throws -> MetalImage {
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        guard outWidth > 0, outHeight > 0 else {
            return MetalImage(texture: context.devices.transparentTexture, bounds: outputBounds)
        }
        let outputTexture = try makeTexture(
            width: Int(ceil(outWidth)), height: Int(ceil(outHeight)),
            usage: [.renderTarget, .shaderRead]
        )
        let maskImage = mask ?? input
        var uniforms = WarpPassUniforms(
            inputPlane: planeVector(input),
            maskPlane: maskPlane ?? planeVector(maskImage),
            param0: param0,
            param1: param1,
            inputOffset: SIMD2<Float>(Float(input.planeOffset.x), Float(input.planeOffset.y)),
            maskOffset: SIMD2<Float>(Float(maskImage.planeOffset.x), Float(maskImage.planeOffset.y)),
            outputOrigin: SIMD2<Float>(Float(outputBounds.left), Float(outputBounds.top)),
            outputSize: SIMD2<Float>(Float(outWidth), Float(outHeight)),
            mode: mode,
            pad0: 0, pad1: 0, pad2: 0
        )
        try executeRenderPass(
            output: outputTexture, pipeline: context.devices.warpPipeline
        ) { encoder in
            encoder.setFragmentTexture(input.texture, index: 0)
            encoder.setFragmentTexture(maskImage.texture, index: 1)
            encoder.setFragmentSamplerState(context.devices.borderSampler, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<WarpPassUniforms>.size, index: 0
            )
        }
        return MetalImage(
            texture: outputTexture, bounds: outputBounds, interpolation: input.interpolation
        )
    }

    /// 合成系パス（MetalGraphics の ymm4CompositeFragment）。
    /// mode 0 = A over B（SourceOver）、mode 1 = B × (1 − A.α)。
    func renderComposite(
        top: MetalImage,
        bottom: MetalImage,
        outputBounds: RectF,
        mode: UInt32,
        opacityTop: Double = 1,
        opacityBottom: Double = 1
    ) throws -> MetalImage {
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        guard outWidth > 0, outHeight > 0 else {
            return MetalImage(texture: context.devices.transparentTexture, bounds: outputBounds)
        }
        let outputTexture = try makeTexture(
            width: Int(ceil(outWidth)), height: Int(ceil(outHeight)),
            usage: [.renderTarget, .shaderRead]
        )
        var uniforms = CompositePassUniforms(
            planeA: planeVector(top),
            planeB: planeVector(bottom),
            offsetA: SIMD2<Float>(Float(top.planeOffset.x), Float(top.planeOffset.y)),
            offsetB: SIMD2<Float>(Float(bottom.planeOffset.x), Float(bottom.planeOffset.y)),
            outputOrigin: SIMD2<Float>(Float(outputBounds.left), Float(outputBounds.top)),
            outputSize: SIMD2<Float>(Float(outWidth), Float(outHeight)),
            opacityA: Float(opacityTop),
            opacityB: Float(opacityBottom),
            mode: mode,
            pad0: 0
        )
        try executeRenderPass(
            output: outputTexture, pipeline: context.devices.compositePipeline
        ) { encoder in
            encoder.setFragmentTexture(top.texture, index: 0)
            encoder.setFragmentTexture(bottom.texture, index: 1)
            // 範囲外は透明として読む必要がある（clampToEdge だと端の
            // 色が画面外へ伸びて影・背景塗りを汚染する。MAC-0028 検証で
            // 実測: 影の位置に原画の端色が出た）。
            encoder.setFragmentSamplerState(context.devices.borderSampler, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<CompositePassUniforms>.size, index: 0
            )
        }
        return MetalImage(
            texture: outputTexture, bounds: outputBounds, interpolation: top.interpolation
        )
    }

    /// モルフォロジー本体（横・縦の2パス。本家 D2D Morphology の
    /// 矩形近傍の最大／最小。偶数寸法の中心は −(n−1)/2 始まりとする
    /// （整数除算の切り捨て。本家未計測の仮定として台帳に記録）。
    func renderMorphology(
        input: MetalImage, width: Int, height: Int, dilate: Bool
    ) throws -> MetalImage {
        guard width > 1 || height > 1 else { return input }
        let textureA = try makeTexture(
            width: input.texture.width, height: input.texture.height,
            usage: [.shaderWrite, .shaderRead]
        )
        let textureB = try makeTexture(
            width: input.texture.width, height: input.texture.height,
            usage: [.shaderWrite, .shaderRead]
        )
        var current = input.texture
        var target = textureA
        if width > 1 {
            try morphologyPass(
                input: current, output: target,
                start: -(width - 1) / 2, count: width, dilate: dilate, axis: 0
            )
            current = target
            target = textureB
        }
        if height > 1 {
            try morphologyPass(
                input: current, output: target,
                start: -(height - 1) / 2, count: height, dilate: dilate, axis: 1
            )
            current = target
        }
        return MetalImage(
            texture: current, bounds: input.bounds,
            texturePlaneRect: input.texturePlaneRect,
            planeOffset: input.planeOffset,
            interpolation: input.interpolation
        )
    }

    private func morphologyPass(
        input: MTLTexture,
        output: MTLTexture,
        start: Int,
        count: Int,
        dilate: Bool,
        axis: UInt32
    ) throws {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        var uniforms = MorphologyPassUniforms(
            start: Int32(start), count: UInt32(count), mode: dilate ? 1 : 0, axis: axis
        )
        encoder.setComputePipelineState(context.devices.morphologyPipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MorphologyPassUniforms>.size, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw MetalRenderError.commandBufferFailed(underlying: commandBuffer.error)
        }
    }

    /// 画像のテクスチャ平面写像を (原点X, 原点Y, 幅, 高さ) で返す。
    func planeVector(_ image: MetalImage) -> SIMD4<Float> {
        SIMD4<Float>(
            Float(image.texturePlaneRect.left), Float(image.texturePlaneRect.top),
            Float(image.texturePlaneRect.right - image.texturePlaneRect.left),
            Float(image.texturePlaneRect.bottom - image.texturePlaneRect.top)
        )
    }
}

/// ワープ系シェーダのユニフォーム（MetalGraphics のシェーダ定義と一致）。
struct WarpPassUniforms {
    var inputPlane: SIMD4<Float>
    var maskPlane: SIMD4<Float>
    var param0: SIMD4<Float>
    var param1: SIMD4<Float>
    var inputOffset: SIMD2<Float>
    var maskOffset: SIMD2<Float>
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var mode: UInt32
    var pad0: Float
    var pad1: Float
    var pad2: Float
}

/// 合成系シェーダのユニフォーム（MetalGraphics のシェーダ定義と一致）。
struct CompositePassUniforms {
    var planeA: SIMD4<Float>
    var planeB: SIMD4<Float>
    var offsetA: SIMD2<Float>
    var offsetB: SIMD2<Float>
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var opacityA: Float
    var opacityB: Float
    var mode: UInt32
    var pad0: Float
}

/// モルフォロジーのユニフォーム（MetalGraphics のシェーダ定義と一致）。
struct MorphologyPassUniforms {
    var start: Int32
    var count: UInt32
    var mode: UInt32
    var axis: UInt32
}

/// 矩形モザイクのユニフォーム（MetalGraphics のシェーダ定義と一致）。
struct RectangleMosaicUniforms {
    var size: Float
    var width: UInt32
    var height: UInt32
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

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        let sigma = definition.blur.value(atFrame: frame, length: length, fps: fps)
        // 本体は基底の共通ヘルパ（第2段の縁ぼかし・角丸・影と共有）。
        return try renderGaussianBlurred(
            input: input, sigma: sigma, hardBorder: definition.isHardBorderMode
        )
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

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let size = rectangleCellSize(description: description) else {
            // 矩形以外の形状は第1段では未対応（素通し）。
            return input
        }
        // 本体は基底の共通ヘルパ（第2段のイン／アウトモザイクと共有）。
        return try renderRectangleMosaic(input: input, cellSize: size)
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
