#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core

/// 未対応アイテム種別の Source。透明な出力を返す。
///
/// TransitionItem 等、対応する Source がまだ無い種別が対象であり、
/// 未対応であることは台帳に明記する。DrawingEffect は実物を
/// 持つため、変形・不透明度を適用しても結果は透明のままになる。
public final class MetalEmptySource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let drawingEffect: MetalDrawingEffect
    private let outputReference = ImageReference(label: "empty-source")

    public init(devices: MetalGraphicsDevices) {
        self.context = devices.makeContext()
        self.drawingEffect = MetalDrawingEffect(context: context)
        context.devices.register(
            outputReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
        outputs = [
            StandardSourceOutput(
                output: outputReference, drawingEffect: drawingEffect, dontDispose: true
            ),
        ]
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        // 未対応の種別は常に透明。評価する内容は無い。
    }

    public func dispose() {
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        outputs = []
    }
}

/// アイテム種別から Source を供給する境界（TimelineComposer の
/// sourceProvider に渡す）。対応は ImageItem / ShapeItem / TextItem /
/// VoiceItem（字幕）/ VideoItem / SceneItem / FrameBufferItem /
/// EffectItem / TachieItem / TransitionItem / 合成グループ
/// （GroupItem.IsComposite）で、それ以外は MetalEmptySource（透明）を返す。
public struct MetalSourceProvider {
    public let devices: MetalGraphicsDevices
    /// 相対パスの解決基準（.ymmp のあるフォルダ）。
    public let baseDirectory: URL?
    /// シーン参照の解決子（プロジェクト全体のタイムライン列から引く）。
    /// 本家では説明の Scenes 列が担う役割。未設定ならシーンは空になる。
    public let sceneResolver: ((UUID) -> Timeline?)?
    /// 親シーンの連鎖（入れ子上限の判定用。通常は呼び出し側で設定しない）。
    public let parentSceneChain: [UUID]
    /// 立ち絵描画器の生成境界。未設定なら立ち絵は出力を持たない
    /// （本家で対応プラグインが無い場合と同じ）。
    public let tachieRendererFactory: (any MetalTachieRendererFactory)?
    /// この供給元のアイテムが属するタイムライン。合成グループの内部
    /// 合成（同じタイムラインの再合成）に使う。本家では CreateVideoSource
    /// へシーンが渡ることが担う役割。未設定なら合成グループは空になる。
    public let timeline: Timeline?
    /// 内部合成器（シーン・合成グループ）へ伝播させるエフェクト供給元。
    /// 外側の合成器と同じインスタンスを渡すことで、内部の子にも GPU
    /// エフェクト（Metal 処理器）が外側と同じく効く（MAC-0028）。
    /// 未設定なら内部合成器は Core の型付き供給元を使う。
    public let effectProvider: (any EffectPairProvider)?

    public init(
        devices: MetalGraphicsDevices,
        baseDirectory: URL? = nil,
        sceneResolver: ((UUID) -> Timeline?)? = nil,
        parentSceneChain: [UUID] = [],
        tachieRendererFactory: (any MetalTachieRendererFactory)? = nil,
        timeline: Timeline? = nil,
        effectProvider: (any EffectPairProvider)? = nil
    ) {
        self.devices = devices
        self.baseDirectory = baseDirectory
        self.sceneResolver = sceneResolver
        self.parentSceneChain = parentSceneChain
        self.tachieRendererFactory = tachieRendererFactory
        self.timeline = timeline
        self.effectProvider = effectProvider
    }

    public func source(for item: BaseItem & VideoItemProperties) -> any Source {
        switch item {
        case let imageItem as ImageItem:
            return MetalImageSource(
                devices: devices, item: imageItem, baseDirectory: baseDirectory
            )
        case let shapeItem as ShapeItem:
            return MetalShapeSource(devices: devices, item: shapeItem)
        case let textItem as TextItem:
            return MetalTextSource(devices: devices, item: textItem)
        case let voiceItem as VoiceItem:
            return MetalJimakuSource(devices: devices, item: voiceItem)
        case let videoItem as VideoItem:
            return MetalVideoSource(
                devices: devices, item: videoItem, baseDirectory: baseDirectory
            )
        case let sceneItem as SceneItem:
            return MetalSceneSource(
                devices: devices, item: sceneItem, composerFactory: sceneComposerFactory()
            )
        case let frameBufferItem as FrameBufferItem:
            return MetalFrameBufferSource(devices: devices, item: frameBufferItem)
        case let effectItem as EffectItem:
            return MetalEffectSource(devices: devices, item: effectItem)
        case let transitionItem as TransitionItem:
            // 画面遷移は内部合成（Before / After）を2つ持つ Source を返す。
            // 属するタイムラインが分からない供給元では内部合成を作れない
            // ため空に倒す（合成グループと同じ扱い）。
            guard let timeline else { return MetalEmptySource(devices: devices) }
            return MetalTransitionSource(
                devices: devices, item: transitionItem,
                screenSize: PixelSize(
                    width: timeline.videoInfo.width, height: timeline.videoInfo.height
                ),
                composerFactory: transitionComposerFactory(
                    item: transitionItem, timeline: timeline
                ),
                effectPairsProvider: transitionEffectPairsProvider()
            )
        case let tachieItem as TachieItem:
            return MetalTachieSource(
                devices: devices, item: tachieItem, rendererFactory: tachieRendererFactory
            )
        case let groupItem as GroupItem where groupItem.isComposite:
            // 合成グループは内部合成を持つ Source を返す。属するタイム
            // ラインが分からない供給元では内部合成を作れないため空に倒す
            // （通常の配線では常に設定される）。
            guard let timeline else { return MetalEmptySource(devices: devices) }
            return MetalCompositeSource(
                devices: devices, item: groupItem,
                composerFactory: compositeComposerFactory(group: groupItem, timeline: timeline)
            )
        default:
            return MetalEmptySource(devices: devices)
        }
    }

    /// 合成グループの内部合成器を生成する境界。内部合成器は対象グループに
    /// 束縛した CompositeItemPicker で、同じタイムラインを再合成する。
    /// 描画先の文脈は呼び出し側（MetalCompositeSource が所有する文脈）を
    /// 借り、その寸法をタイムラインの VideoInfo へ合わせる。子の供給元は
    /// 同じタイムラインを引き継ぐため、入れ子の合成グループも再帰的に
    /// 内部合成を持つ（階層はレイヤー範囲で有限に閉じる）。
    private func compositeComposerFactory(
        group: GroupItem, timeline: Timeline
    ) -> (MetalGraphicsContext) -> TimelineComposer {
        let devices = self.devices
        let baseDirectory = self.baseDirectory
        let sceneResolver = self.sceneResolver
        let parentSceneChain = self.parentSceneChain
        let tachieRendererFactory = self.tachieRendererFactory
        let effectProvider = self.effectProvider
        return { context in
            context.targetSize = PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
            let childProvider = MetalSourceProvider(
                devices: devices,
                baseDirectory: baseDirectory,
                sceneResolver: sceneResolver,
                parentSceneChain: parentSceneChain,
                tachieRendererFactory: tachieRendererFactory,
                timeline: timeline,
                effectProvider: effectProvider
            )
            let scene = TimelineScene(sceneID: timeline.id, timeline: timeline)
            return TimelineComposer(
                scene: scene,
                picker: CompositeItemPicker(groupItem: group),
                targetFactory: context,
                sourceProvider: { item in childProvider.source(for: item) },
                effectProvider: effectProvider ?? TypedEffectPairProvider(),
                alphaMaskFactory: MetalAlphaMaskEffectFactory(context: context)
            )
        }
    }

    /// 画面遷移の内部合成器（Before / After）を生成する境界。各側は
    /// TransitionItemPicker（isBefore の別）で同じタイムラインを再合成し、
    /// 描画先の文脈は MetalTransitionSource が所有する文脈を借りる。
    /// 子の供給元は同じタイムラインを引き継ぐため、下位レイヤーの
    /// トランジションも再帰的に内部合成を持つ（階層はレイヤーで閉じる）。
    private func transitionComposerFactory(
        item: TransitionItem, timeline: Timeline
    ) -> (MetalGraphicsContext, MetalGraphicsContext)
        -> (before: TimelineComposer, after: TimelineComposer) {
        let devices = self.devices
        let baseDirectory = self.baseDirectory
        let sceneResolver = self.sceneResolver
        let parentSceneChain = self.parentSceneChain
        let tachieRendererFactory = self.tachieRendererFactory
        let effectProvider = self.effectProvider
        return { beforeContext, afterContext in
            func makeComposer(
                context: MetalGraphicsContext, isBefore: Bool
            ) -> TimelineComposer {
                context.targetSize = PixelSize(
                    width: timeline.videoInfo.width, height: timeline.videoInfo.height
                )
                let childProvider = MetalSourceProvider(
                    devices: devices,
                    baseDirectory: baseDirectory,
                    sceneResolver: sceneResolver,
                    parentSceneChain: parentSceneChain,
                    tachieRendererFactory: tachieRendererFactory,
                    timeline: timeline,
                    effectProvider: effectProvider
                )
                let scene = TimelineScene(sceneID: timeline.id, timeline: timeline)
                return TimelineComposer(
                    scene: scene,
                    picker: TransitionItemPicker(
                        transitionItem: item, isBefore: isBefore
                    ),
                    targetFactory: context,
                    sourceProvider: { child in childProvider.source(for: child) },
                    effectProvider: effectProvider ?? TypedEffectPairProvider(),
                    alphaMaskFactory: MetalAlphaMaskEffectFactory(context: context)
                )
            }
            return (
                before: makeComposer(context: beforeContext, isBefore: true),
                after: makeComposer(context: afterContext, isBefore: false)
            )
        }
    }

    /// Before/AfterVideoEffects の定義供給。合成器と同じ供給元を使い、
    /// GPU エフェクトの差し替え（MetalEffectPairProvider）を全体エフェクト
    /// にも効かせる。供給元が無い場合は nil を返し、Source 側の型付き
    /// 供給元へ倒す。どちらでもない供給元では全体エフェクトは供給しない
    /// （本家では常にアイテムの保持列が使われるため、これはカスタム
    /// 供給元向けの制限として記録する）。
    private func transitionEffectPairsProvider()
        -> ((TransitionItem, Bool) -> [EffectPair])? {
        if let metal = effectProvider as? MetalEffectPairProvider {
            return { item, isBefore in
                metal.transitionEffectPairs(for: item, isBefore: isBefore)
            }
        }
        if let typed = effectProvider as? TypedEffectPairProvider {
            return { item, isBefore in
                typed.transitionEffectPairs(for: item, isBefore: isBefore)
            }
        }
        if effectProvider == nil { return nil }
        return { _, _ in [] }
    }

    /// シーンの内部合成器を生成する境界。解決・入れ子上限（本家
    /// Scene.TryCreateVideoSource: 親シーン列に参照先 ID が 10 回
    /// 現れたら生成しない）を担う。描画先の文脈は呼び出し側
    /// （MetalSceneSource が所有する文脈）を借り、その寸法を参照先
    /// タイムラインの VideoInfo へ合わせる。内部合成器は子の供給元を
    /// 持ち、その供給元がさらに内側のシーンを解決する。
    private func sceneComposerFactory() -> (UUID, MetalGraphicsContext) -> TimelineComposer? {
        let devices = self.devices
        let baseDirectory = self.baseDirectory
        let sceneResolver = self.sceneResolver
        let parentSceneChain = self.parentSceneChain
        let tachieRendererFactory = self.tachieRendererFactory
        let effectProvider = self.effectProvider
        return { sceneID, context in
            guard let timeline = sceneResolver?(sceneID) else { return nil }
            if parentSceneChain.filter({ $0 == sceneID }).count >= 10 { return nil }
            context.targetSize = PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
            let childProvider = MetalSourceProvider(
                devices: devices,
                baseDirectory: baseDirectory,
                sceneResolver: sceneResolver,
                parentSceneChain: parentSceneChain + [sceneID],
                tachieRendererFactory: tachieRendererFactory,
                timeline: timeline,
                effectProvider: effectProvider
            )
            let scene = TimelineScene(sceneID: timeline.id, timeline: timeline)
            return TimelineComposer(
                scene: scene,
                targetFactory: context,
                sourceProvider: { item in childProvider.source(for: item) },
                effectProvider: effectProvider ?? TypedEffectPairProvider(),
                alphaMaskFactory: MetalAlphaMaskEffectFactory(context: context)
            )
        }
    }
}
#endif
