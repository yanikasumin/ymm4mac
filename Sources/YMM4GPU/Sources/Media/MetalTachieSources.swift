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

    /// モデル層の口形からの変換。
    public init(_ shape: MouthShapeValue) {
        switch shape {
        case .silent: self = .silent
        case .a: self = .a
        case .i: self = .i
        case .u: self = .u
        case .e: self = .e
        case .o: self = .o
        }
    }
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
    /// 口パク音量。本家は LipSyncEnvelope の計算結果であり、計算が
    /// 無い場合のフォールバックは「声の範囲内なら 0、範囲外・声なし
    /// なら -1」（本家 ReadVolumeAfterRequiredWait の経路）。
    public var volume: Double
    /// 口形。声の LipSyncFrames を評価した結果（時系列が無ければ
    /// 本家の既定どおり .silent）。
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
/// 口パク音量は、包絡の供給（volumeEnvelopeProvider）が注入されて
/// いれば LipSyncEnvelope の計算結果を使い、無ければ本家の
/// フォールバック値になる。口形は声の LipSyncFrames の評価結果。
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
    /// 口パク包絡の供給（声・fps・平滑化 → フレームごとの音量）。
    /// 本家は非同期セッションで計算するが、こちらは同期計算の結果を
    /// 声ごとにキャッシュする。未注入なら音量はフォールバック値。
    private let volumeEnvelopeProvider: ((VoiceItem, Int, Int) -> [Double]?)?
    private var envelopeCache: (
        voice: ObjectIdentifier, length: Int, fps: Int, smooth: Int,
        values: [Double]
    )?

    private var renderer: (any MetalTachieRenderer)?
    private var currentTachieType: String?
    private var hasResolvedType = false
    private var currentRendererOutput: ImageReference?
    private var output: StandardSourceOutput?

    public init(
        devices: MetalGraphicsDevices,
        item: TachieItem,
        rendererFactory: (any MetalTachieRendererFactory)? = nil,
        volumeEnvelopeProvider: ((VoiceItem, Int, Int) -> [Double]?)? = nil
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.rendererFactory = rendererFactory ?? EmptyTachieRendererFactory()
        self.volumeEnvelopeProvider = volumeEnvelopeProvider
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

        // 音量と口形（本家 TachieSource.Update の経路）。音量の既定は
        // 本家のフォールバック値: 声の範囲内なら 0、範囲外・声なし
        // なら -1。包絡が計算できればその値で置き換える。口形は声の
        // LipSyncFrames の評価結果（範囲外・声なし・時系列なしは
        // .silent）。
        var volume: Double = -1
        var mouthShape = MetalTachieMouthShape.silent
        if let voice = activeVoice {
            let voiceFrame = description.timelinePosition.frame - voice.frame
            if voiceFrame >= 0, voiceFrame < voice.length {
                volume = 0
                mouthShape = MetalTachieMouthShape(
                    voice.lipSyncShape(atFrame: voiceFrame, fps: description.fps)
                )
                let smooth = item.character?.mouseSmooth ?? 4
                if smooth > 0, let volumeEnvelopeProvider,
                   let values = envelopeValues(
                       for: voice, fps: description.fps, smooth: smooth,
                       provider: volumeEnvelopeProvider
                   ), voiceFrame < values.count {
                    volume = values[voiceFrame]
                }
            }
        }

        renderer?.update(MetalTachieUpdateDescription(
            itemDescription: description,
            characterParameter: item.character?.tachieCharacterParameter,
            itemParameter: item.tachieItemParameter,
            faces: faces,
            volume: volume,
            mouthShape: mouthShape
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

    /// 声の包絡をキャッシュ経由で得る。声の同一性・長さ・fps・
    /// 平滑化が変わったら計算し直す（本家の署名による再計算条件に
    /// 相当する簡約形。声の内容差し替えは同一性と長さでは検出でき
    /// ないため、その場合は Source の作り直しで解消する）。
    private func envelopeValues(
        for voice: VoiceItem, fps: Int, smooth: Int,
        provider: (VoiceItem, Int, Int) -> [Double]?
    ) -> [Double]? {
        if let cache = envelopeCache,
           cache.voice == ObjectIdentifier(voice),
           cache.length == voice.length,
           cache.fps == fps, cache.smooth == smooth {
            return cache.values
        }
        guard let values = provider(voice, fps, smooth) else {
            envelopeCache = nil
            return nil
        }
        envelopeCache = (
            voice: ObjectIdentifier(voice), length: voice.length,
            fps: fps, smooth: smooth, values: values
        )
        return values
    }

    public func dispose() {
        renderer?.dispose()
        renderer = nil
        drawingEffect.dispose()
        outputs = []
    }
}
#endif
