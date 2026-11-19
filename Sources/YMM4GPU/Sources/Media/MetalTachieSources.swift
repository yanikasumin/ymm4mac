#if os(macOS)
import AVFoundation
import CoreGraphics
import Darwin
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
        signature: String, values: [Double]
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
                // 包絡は描画器が受け取る値であり、描画器が無い場合は
                // 声全体の同期計算をしない（R20-116-05）。
                let smooth = item.character?.mouseSmooth ?? 4
                if renderer != nil, smooth > 0, let volumeEnvelopeProvider,
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

    /// 包絡を決定する入力の署名。本家の再計算署名（音声ファイル、
    /// ContentOffset、ContentLength、更新世代など）に相当するもの
    /// として、包絡の入力音声（エフェクトチェーンの出力）を決める
    /// 項目を集めたもの: 声の指定、生成済み音声の世代、再生速度
    /// （種別・値列・キーフレーム・間隔・ベジェ）、音声処理モード、
    /// ContentOffset、ContentLength、ループ有無（R21-116-02、
    /// R22-116-02）。
    ///
    /// 音声キャッシュはバイト数ではなく VoiceItem の世代カウンタで
    /// 識別する（同サイズ差し替えを検出するため）。ベジェは点列と
    /// 2次フラグを文字列化して含める（ベジェだけの変更でもレート
    /// 曲線が変わるため）。処理モードは SOLA かリサンプリングかで
    /// エフェクトチェーンの出力が変わるため含める。
    ///
    /// カスタム音声（発音が実ファイルのパス）の場合は、ファイル
    /// 自体の同一性（サイズと更新時刻）も末尾に含める。アイテム側
    /// の項目だけでは、同じパスのファイルを別内容へ差し替えても
    /// 署名が変わらず、包絡キャッシュが古いまま残るため
    /// （Issue #134）。
    static func envelopeSignature(of voice: VoiceItem) -> String {
        let rate = voice.playbackRate2
        var components = [
            voice.hatsuon,
            String(voice.voiceCacheGeneration),
            String(describing: rate.animationType),
            rate.values.map { String($0.value) }.joined(separator: ","),
            rate.keyFrames.frames.map(String.init).joined(separator: ","),
            String(rate.span),
            bezierSignature(of: rate.bezier),
            voice.playbackRateAudioProcessingMode.honkeName,
            String(voice.contentOffset.ticks),
            String(voice.contentLength.ticks),
            String(voice.isLooped),
        ]
        if let fileIdentity = fileIdentityComponent(ofHatsuon: voice.hatsuon) {
            components.append(fileIdentity)
        }
        return components.joined(separator: "|")
    }

    /// カスタム音声ファイルの同一性を署名の部品として返す
    /// （Issue #134）。
    ///
    /// 「発音がファイルパスか」の判定は音声供給側
    /// （VoicePCMProviderResolver.isCustomVoicePath）と同一の基準を
    /// 使う。パスでない発音（音声エンジンの声名など、実ファイルが
    /// 存在しないケース）では nil を返し、署名は従来どおりアイテム
    /// 側の入力だけで決まる（stat も行わない）。
    ///
    /// 同一性はサイズと更新時刻（stat の st_size と st_mtimespec。
    /// 秒＋ナノ秒の整数）で表す。全ファイル読みのハッシュは採らない
    /// （署名は包絡を使うフレーム描画のたびに計算されるため、コスト
    /// は stat 1回に抑える。実測は台帳 ISSUE134 参照）。ファイルが
    /// 存在しない場合は固定の不在標識を返し、ファイルの消滅・出現
    /// の遷移も署名の変化として検出できるようにする。
    static func fileIdentityComponent(ofHatsuon hatsuon: String) -> String? {
        guard VoicePCMProviderResolver.isCustomVoicePath(hatsuon) else {
            return nil
        }
        // パスの解決は供給側（resolveMediaURL）の絶対パス経路と揃える:
        // file URL ならそのパス、それ以外は文字列自体をパスとして扱う
        // （Windows ドライブパスは Mac では stat が失敗し不在標識になる）。
        let path: String
        if let url = URL(string: hatsuon), url.isFileURL {
            path = url.path
        } else {
            path = hatsuon
        }
        var fileStat = stat()
        guard stat(path, &fileStat) == 0 else { return "file:missing" }
        let modified = fileStat.st_mtimespec
        return "file:\(fileStat.st_size):\(modified.tv_sec).\(modified.tv_nsec)"
    }

    /// ベジェ定義の文字列化。アンカー点と制御点（相対オフセット）の
    /// 全成分と2次フラグを含む。
    private static func bezierSignature(of bezier: BezierAnimation) -> String {
        let points = bezier.points.map { point in
            [point.point, point.controlPoint1, point.controlPoint2]
                .map { "\($0.x),\($0.y)" }
                .joined(separator: ";")
        }.joined(separator: "/")
        return (bezier.isQuadratic ? "q:" : "c:") + points
    }

    /// 声の包絡をキャッシュ経由で得る。声の同一性・長さ・fps・
    /// 平滑化・包絡を決定する入力の署名が変わったら計算し直す。
    private func envelopeValues(
        for voice: VoiceItem, fps: Int, smooth: Int,
        provider: (VoiceItem, Int, Int) -> [Double]?
    ) -> [Double]? {
        let signature = Self.envelopeSignature(of: voice)
        if let cache = envelopeCache,
           cache.voice == ObjectIdentifier(voice),
           cache.length == voice.length,
           cache.fps == fps, cache.smooth == smooth,
           cache.signature == signature {
            return cache.values
        }
        guard let values = provider(voice, fps, smooth) else {
            envelopeCache = nil
            return nil
        }
        envelopeCache = (
            voice: ObjectIdentifier(voice), length: voice.length,
            fps: fps, smooth: smooth, signature: signature, values: values
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
