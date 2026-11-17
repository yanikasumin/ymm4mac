#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import Metal
import YMM4Core

/// シーンアイテムの Source。本家 SceneSource に対応する。
///
/// 本家と同じく、コンストラクタで自前の文脈（CreateContext）を生成して
/// 所有し、参照先シーンの内部 TimelineSource はその文脈を借用する
/// （第2章: 文脈は消費者ごとに新規生成し、TimelineSource は借用）。
/// シーンの解決は、本家では説明（desc.Scenes）に載る ISceneInfo 列から
/// 行うが、こちらでは SceneInfo が識別子のみの契約（MAC-0009）のため、
/// 供給元（MetalSourceProvider）が保持するプロジェクト全体の解決子で
/// 代替する（解決子は説明の列と同じプロジェクトから構築される）。
/// 入れ子上限は本家 Scene.TryCreateVideoSource と同じ: 親シーン列に
/// 参照先 ID が 10 回現れたら生成しない（その場合の出力は空の代替）。
/// SceneId が変わったときだけ内部合成器を作り直す。時刻変換は
/// PlaybackRateMap.GetSourceTime（ContentLength は参照先タイムラインの
/// 長さから求める。本家 SceneItem.ContentLength の定義どおり。エコー
/// 延長分は音声側の量であり、ここでは加算しない）、ループ時は参照先
/// シーンの尺で剰余を取る（VideoSource と同じ式）。
/// 出力は内部合成器の出力が差し替わったときだけ包み直す。
public final class MetalSceneSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: SceneItem
    private let drawingEffect: MetalDrawingEffect
    private let emptyReference = ImageReference(label: "scene-source-empty")
    private let emptyOutput: StandardSourceOutput
    /// シーン ID から内部合成器を生成する境界（供給元が解決と入れ子
    /// 上限を担う）。内部合成器の描画先は、この Source が所有する
    /// 文脈から作る（本家が SceneSource の文脈を内部 TimelineSource
    /// へ貸す構造と同じ）。生成できなければ nil。
    private let composerFactory: (UUID, MetalGraphicsContext) -> TimelineComposer?

    private var resolvedSceneID: UUID?
    private var innerComposer: TimelineComposer?
    private var innerOutput: ImageReference?
    private var output: StandardSourceOutput?

    public init(
        devices: MetalGraphicsDevices,
        item: SceneItem,
        composerFactory: @escaping (UUID, MetalGraphicsContext) -> TimelineComposer?
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.composerFactory = composerFactory
        self.drawingEffect = MetalDrawingEffect(context: context)
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
        let sceneID = item.sceneId
        if resolvedSceneID != sceneID {
            resolvedSceneID = sceneID
            innerComposer?.dispose()
            innerComposer = composerFactory(sceneID, context)
            innerOutput = nil
            output = nil
        }

        // 本家 SceneItem.ContentLength = 参照先タイムラインの長さ（時間）。
        let contentLength = innerComposer.map { composer in
            TimeSpanValue(seconds: FrameTime.time(
                fromFrame: composer.timeline.length, fps: composer.timeline.videoInfo.fps
            ))
        } ?? .zero

        let rateMap = PlaybackRateMap(rate: item.playbackRate2)
        var time = rateMap.getSourceTime(
            time: TimeSpanValue(seconds: description.itemPosition.time),
            itemLength: description.itemDuration.frame,
            fps: description.fps,
            contentOffset: item.contentOffset,
            contentLength: contentLength
        )
        if item.isLooped, innerComposer != nil {
            if contentLength == .zero {
                time = .zero
            } else {
                var ticks = time.ticks % contentLength.ticks
                if ticks < 0 && !rateMap.isConstant {
                    ticks += contentLength.ticks
                }
                time = TimeSpanValue(ticks: ticks)
            }
        }

        try innerComposer?.update(time: time, usage: description.usage)

        if innerComposer?.output !== innerOutput {
            innerOutput = innerComposer?.output
            if let innerOutput {
                output = StandardSourceOutput(
                    output: innerOutput, drawingEffect: drawingEffect, dontDispose: true
                )
            } else {
                output = nil
            }
        }
        outputs = [output ?? emptyOutput]
    }

    public func dispose() {
        innerComposer?.dispose()
        innerComposer = nil
        drawingEffect.dispose()
        context.devices.unregister(emptyReference)
        outputs = []
    }
}

#endif
