#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// 画面遷移アイテム（TransitionItem）の Source。本家 TransitionSource
/// に対応する（MAC-0036 / AUD-02）。
///
/// 本家の意味論（TransitionSource.cs / TransitionItemPicker.cs で実測）:
/// - 内部に TimelineSource を2つ持ち、それぞれ専用の文脈で回す。
///   Before 側のピッカーはアイテム選定だけを transitionItem.Frame − 1 に
///   固定し、両側とも更新時刻は現在時刻（選定アイテムのアニメーションは
///   静止しない）。
/// - 各側の合成結果は EffectedTimelineSource（合成画像を画面矩形で切り
///   抜き → Before/AfterVideoEffects の連鎖 → DrawingEffect）を通る。
///   切り抜きは、内部合成器の出力テクスチャ（画面サイズ）を画面矩形の
///   境界・平面範囲で登録し直すことで等価に実現し、連鎖は Core の
///   EffectedOutput（applyItemTransform = false）で実行する。
///   初期 DrawDescription は
///   本家が固定する恒等変換であり、TransitionItem の実効値の既定
///   （X/Y = 0、Zoom/Opacity = 100、フェードなし）でも同じ値になる。
/// - ブレンドは ITransitionSource が担う。本家はパラメータの参照が
///   変わったときだけ生成し直すが、こちらは合成器の描画先がフレーム
///   ごとに新しい参照になるため、ブレンドへは毎回その時点の前後画像を
///   渡す（内部差分。観測できる結果は変わらない）。ブレンド自体の
///   作り直しはパラメータの保持値が変わったときだけ行う（本家は参照
///   変化、こちらは値変化という内部差分）。
/// - 出力は Source 自身の DrawingEffect を持つ SourceOutput で公開する
///   （本家と同じ）。
public final class MetalTransitionSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: TransitionItem
    private let drawingEffect: MetalDrawingEffect
    private let beforeComposer: TimelineComposer
    private let afterComposer: TimelineComposer
    private let beforeChain: EffectedOutput
    private let afterChain: EffectedOutput
    private let effectPairs: (TransitionItem, Bool) -> [EffectPair]
    private let emptyReference = ImageReference(label: "transition-source-empty")
    private let beforeScreenReference = ImageReference(label: "transition-before-screen")
    private let afterScreenReference = ImageReference(label: "transition-after-screen")
    private let emptyOutput: StandardSourceOutput
    private var output: StandardSourceOutput?
    private var currentOutputReference: ImageReference?
    private var blend: MetalTransitionBlend?
    private var blendParameterValue: PreservedObject?
    private var hasBlendParameter = false
    private var currentParameter: TransitionParameter?

    /// - Parameters:
    ///   - composerFactory: Before / After の内部合成器を生成する境界。
    ///     供給元が TransitionItemPicker（isBefore の別）を持つ合成器を、
    ///     渡された2つの文脈で構築する。
    ///   - effectPairsProvider: Before/AfterVideoEffects の定義供給。
    ///     nil の場合はこの Source が所有する型付き供給元を使う。
    public init(
        devices: MetalGraphicsDevices,
        item: TransitionItem,
        screenSize: PixelSize,
        composerFactory: (MetalGraphicsContext, MetalGraphicsContext)
            -> (before: TimelineComposer, after: TimelineComposer),
        effectPairsProvider: ((TransitionItem, Bool) -> [EffectPair])?
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.drawingEffect = MetalDrawingEffect(context: context)
        context.targetSize = screenSize
        let composers = composerFactory(devices.makeContext(), devices.makeContext())
        self.beforeComposer = composers.before
        self.afterComposer = composers.after
        self.beforeChain = EffectedOutput(item: item)
        self.afterChain = EffectedOutput(item: item)
        if let effectPairsProvider {
            self.effectPairs = effectPairsProvider
        } else {
            let typed = TypedEffectPairProvider()
            self.effectPairs = { typed.transitionEffectPairs(for: $0, isBefore: $1) }
        }
        context.devices.register(
            emptyReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
        self.emptyOutput = StandardSourceOutput(
            output: emptyReference, drawingEffect: drawingEffect, dontDispose: true
        )
        self.outputs = [emptyOutput]
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        // 本家は2つの TimelineSource を並列に更新する。こちらは逐次だが、
        // 観測できる結果（各側の合成画像）は同じである。
        let time = TimeSpanValue(seconds: description.timelinePosition.time)
        try beforeComposer.update(time: time, usage: description.usage)
        try afterComposer.update(time: time, usage: description.usage)

        let beforeImage = try effectedImage(
            composer: beforeComposer, chain: beforeChain,
            description: description, isBefore: true
        )
        let afterImage = try effectedImage(
            composer: afterComposer, chain: afterChain,
            description: description, isBefore: false
        )

        // パラメータの保持値が変わったらブレンドを作り直す（本家は
        // パラメータ参照の変化で作り直す。内部差分として記録）。
        if !hasBlendParameter || blendParameterValue != item.transitionParameter {
            blend?.dispose()
            currentParameter = TransitionParameter.decode(item.transitionParameter)
            blend = MetalTransitionBlend.make(
                kind: currentParameter!.kind, context: context
            )
            blendParameterValue = item.transitionParameter
            hasBlendParameter = true
        }
        guard let blend, let parameter = currentParameter else {
            publish(emptyReference)
            return
        }
        // キーフレーム文脈は所有アイテム側の変化がありうるため毎回伝播する。
        parameter.applyKeyFrames(item.keyFrames)
        let blended = try blend.blend(
            before: beforeImage, after: afterImage,
            parameter: parameter, description: description
        )
        publish(blended)
    }

    public func dispose() {
        beforeComposer.dispose()
        afterComposer.dispose()
        beforeChain.dispose()
        afterChain.dispose()
        blend?.dispose()
        blend = nil
        drawingEffect.dispose()
        context.devices.unregister(emptyReference)
        context.devices.unregister(beforeScreenReference)
        context.devices.unregister(afterScreenReference)
        outputs = []
    }

    /// 画面矩形（中心原点）。
    private var screenRect: RectF {
        RectF(
            left: -Double(context.targetSize.width) / 2,
            top: -Double(context.targetSize.height) / 2,
            right: Double(context.targetSize.width) / 2,
            bottom: Double(context.targetSize.height) / 2
        )
    }

    /// 内部合成の出力へ Before/AfterVideoEffects の連鎖を適用する
    /// （本家 EffectedTimelineSource に対応）。
    ///
    /// 本家は連鎖の前に合成画像を画面矩形で切り抜く（Crop）。こちらでは
    /// 内部合成器の出力テクスチャは画面サイズだが、その登録の境界は
    /// 内容境界（画面より大きいアイテムでは画面を超える）であり、
    /// そのまま平行移動すると空いた側が端画素の引き伸ばしで埋まって
    /// しまう。そこで同じテクスチャを画面矩形の境界・平面範囲で
    /// 登録し直した参照を連鎖とブレンドへ渡し、切り抜きと等価にする。
    private func effectedImage(
        composer: TimelineComposer,
        chain: EffectedOutput,
        description: TimelineItemSourceDescription,
        isBefore: Bool
    ) throws -> ImageReference {
        guard let composed = composer.output,
              let composedImage = context.devices.image(for: composed)
        else { return emptyReference }
        let screenReference = isBefore ? beforeScreenReference : afterScreenReference
        context.devices.register(
            screenReference,
            image: MetalImage(
                texture: composedImage.texture,
                bounds: screenRect,
                texturePlaneRect: screenRect,
                opacity: composedImage.opacity,
                interpolation: composedImage.interpolation
            )
        )
        let input = StandardSourceOutput(
            output: screenReference, drawingEffect: nil, dontDispose: true
        )
        let pairs = effectPairs(item, isBefore).filter { $0.definition.isEnabled }
        try chain.update(
            inputIndex: 0, inputCount: 1, input: input,
            itemDescription: description, effects: pairs,
            applyItemTransform: false
        )
        return chain.preRenderOutput ?? screenReference
    }

    private func publish(_ reference: ImageReference) {
        if currentOutputReference !== reference {
            currentOutputReference = reference
            output = StandardSourceOutput(
                output: reference, drawingEffect: drawingEffect, dontDispose: true
            )
        }
        outputs = [output ?? emptyOutput]
    }
}

#endif
