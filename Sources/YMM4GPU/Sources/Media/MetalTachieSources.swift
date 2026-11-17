#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import Metal
import YMM4Core

/// 口の形。本家 MouthShape に対応する。
public enum MetalTachieMouthShape: Sendable {
    case silent
    case a
    case i
    case u
    case e
    case o
}

/// 顔アイテム1件の説明。本家 TachieFaceDescription に対応する。
public struct MetalTachieFaceDescription {
    /// 顔アイテム内位置（タイムライン位置 − アイテム開始）。
    public var itemPosition: FramePosition
    /// 顔アイテムの長さ。
    public var itemDuration: FramePosition
    /// レイヤー。
    public var layer: Int
    /// 顔パラメータ（プラグイン型のため生保持のまま渡す）。
    public var faceParameter: PreservedObject?

    public init(
        itemPosition: FramePosition, itemDuration: FramePosition,
        layer: Int, faceParameter: PreservedObject?
    ) {
        self.itemPosition = itemPosition
        self.itemDuration = itemDuration
        self.layer = layer
        self.faceParameter = faceParameter
    }
}

/// 立ち絵の更新説明。本家 TachieSourceDescription（アイテム説明＋
/// TachieDescription＋音量＋口形）に対応する。
public struct MetalTachieUpdateDescription {
    /// 元のアイテム説明。
    public var itemDescription: TimelineItemSourceDescription
    /// キャラクターの立ち絵パラメータ（プラグイン型のため生保持）。
    public var characterParameter: PreservedObject?
    /// 立ち絵アイテムのパラメータ（プラグイン型のため生保持）。
    public var itemParameter: PreservedObject?
    /// 顔アイテム列の説明（ActiveFaces の順）。
    public var faces: [MetalTachieFaceDescription]
    /// 口パク音量。本家は LipSyncEnvelope の非同期計算結果であり、
    /// 計算が無い場合のフォールバックは「声の範囲内なら 0、範囲外・
    /// 声なしなら -1」（本家 ReadVolumeAfterRequiredWait の経路）。
    /// 包絡計算そのものは差し替え点の先（音声側の基盤）にある。
    public var volume: Double
    /// 口形。LipSyncFrames はモデル層で生保持のため評価は未実装で、
    /// 常に .silent（本家の「リップシンク情報なし」の既定と同じ）。
    public var mouthShape: MetalTachieMouthShape

    public init(
        itemDescription: TimelineItemSourceDescription,
        characterParameter: PreservedObject?,
        itemParameter: PreservedObject?,
        faces: [MetalTachieFaceDescription],
        volume: Double,
        mouthShape: MetalTachieMouthShape
    ) {
        self.itemDescription = itemDescription
        self.characterParameter = characterParameter
        self.itemParameter = itemParameter
        self.faces = faces
        self.volume = volume
        self.mouthShape = mouthShape
    }
}

/// 立ち絵プラグインの描画境界。本家 ITachieSource2 に対応する
/// 差し替え点。立ち絵の描画は本家でも全面的にプラグインの責務であり、
/// プラグイン DLL はバイナリ互換が無いため、こちらでは境界だけを用意
/// する（パラメータはプラグイン型のため生保持のまま渡る）。
public protocol MetalTachieRenderer: AnyObject {
    /// 現在の出力（未生成なら nil）。
    var output: ImageReference? { get }
    /// 説明に基づいて出力を更新する。
    func update(_ description: MetalTachieUpdateDescription)
    /// 自身が所有する資源を解放する。
    func dispose()
}

/// 立ち絵描画器の生成境界。本家 TachieSourceFactory.CreateSource に
/// 対応する。プラグインが見つからなければ nil を返す。
public protocol MetalTachieRendererFactory {
    func makeRenderer(
        devices: MetalGraphicsDevices, tachieType: String?
    ) -> (any MetalTachieRenderer)?
}

/// 描画器を何も登録しない生成境界（既定）。本家で対応プラグインが
/// 無い場合と同じく、立ち絵は出力を持たない。
public struct EmptyTachieRendererFactory: MetalTachieRendererFactory {
    public init() {}

    public func makeRenderer(
        devices: MetalGraphicsDevices, tachieType: String?
    ) -> (any MetalTachieRenderer)? {
        nil
    }
}

/// 立ち絵アイテムの Source。本家 TachieSource に対応する。
///
/// 本家と同じく、コンストラクタで自前の文脈（CreateContext）を生成
/// して所有する。描画器は Character の TachieType が変わったときだけ
/// 生成し直す（本家の再生成条件）。ActiveVoice / ActiveFaces は
/// TimelineSource 相当（TimelineComposer）が顔解決の結果として
/// 書き込む受け口であり、Update はその内容から顔説明列を組み立てて
/// 描画器へ渡す（本家 TachieSource.Update の ITachieSource2 経路）。
/// 出力の公開条件も本家どおり: 描画器の出力の境界の最大辺が 2 未満
/// なら出力なし（isEmptyOutput）とする。
/// 口パクの包絡計算（本家 LipSyncEnvelope の非同期基盤）と口形の評価
/// は未実装であり、音量は本家のフォールバック値、口形は .silent を
/// 渡す（MetalTachieUpdateDescription の説明を参照）。
public final class MetalTachieSource: TachieSource {
    /// 現在の声（TimelineComposer が書き込む）。
    public var activeVoice: VoiceItem?
    /// 現在の顔アイテム列（TimelineComposer が書き込む。レイヤー降順）。
    public var activeFaces: [any FaceItem] = []

    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: TachieItem
    private let drawingEffect: MetalDrawingEffect
    private let rendererFactory: any MetalTachieRendererFactory

    private var renderer: (any MetalTachieRenderer)?
    private var currentTachieType: String?
    private var hasResolvedType = false
    private var currentRendererOutput: ImageReference?
    private var output: StandardSourceOutput?

    public init(
        devices: MetalGraphicsDevices,
        item: TachieItem,
        rendererFactory: (any MetalTachieRendererFactory)? = nil
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.rendererFactory = rendererFactory ?? EmptyTachieRendererFactory()
        self.drawingEffect = MetalDrawingEffect(context: context)
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        let tachieType = item.character?.tachieType
        if !hasResolvedType || currentTachieType != tachieType {
            hasResolvedType = true
            currentTachieType = tachieType
            renderer?.dispose()
            renderer = rendererFactory.makeRenderer(
                devices: context.devices, tachieType: tachieType
            )
            currentRendererOutput = nil
            output = nil
        }

        // 顔説明列（本家 TachieSource.Update の faces 構築どおり:
        // 位置 = タイムライン位置 − アイテム開始、長さ、レイヤー、
        // 顔パラメータ）。
        let faces: [MetalTachieFaceDescription] = activeFaces.compactMap { face in
            guard let base = face as? BaseItem else { return nil }
            let parameter: PreservedObject?
            if let faceItem = face as? TachieFaceItem {
                parameter = faceItem.tachieFaceParameter
            } else if let voiceItem = face as? VoiceItem {
                parameter = voiceItem.tachieFaceParameter
            } else {
                parameter = nil
            }
            return MetalTachieFaceDescription(
                itemPosition: FramePosition(
                    frame: description.timelinePosition.frame - base.frame, fps: description.fps
                ),
                itemDuration: FramePosition(frame: base.length, fps: description.fps),
                layer: base.layer,
                faceParameter: parameter
            )
        }

        // 音量は本家のフォールバック値（包絡未計算時）: 声の範囲内なら
        // 0、範囲外・声なしなら -1。
        let volume: Double
        if let voice = activeVoice {
            let voiceFrame = description.timelinePosition.frame - voice.frame
            volume = (voiceFrame >= 0 && voiceFrame < voice.length) ? 0 : -1
        } else {
            volume = -1
        }

        renderer?.update(MetalTachieUpdateDescription(
            itemDescription: description,
            characterParameter: item.character?.tachieCharacterParameter,
            itemParameter: item.tachieItemParameter,
            faces: faces,
            volume: volume,
            mouthShape: .silent
        ))

        // 出力の公開（本家: 出力境界の最大辺が 2 未満なら出力なし）。
        let rendererOutput = renderer?.output
        if rendererOutput !== currentRendererOutput {
            currentRendererOutput = rendererOutput
            if let rendererOutput,
               let image = context.devices.image(for: rendererOutput),
               max(image.bounds.right - image.bounds.left,
                   image.bounds.bottom - image.bounds.top) >= 2 {
                output = StandardSourceOutput(
                    output: rendererOutput, drawingEffect: drawingEffect, dontDispose: true
                )
            } else {
                output = nil
            }
        }
        outputs = output.map { [$0] } ?? []
    }

    public func dispose() {
        renderer?.dispose()
        renderer = nil
        drawingEffect.dispose()
        outputs = []
    }
}
#endif
