import Foundation

/// 音声アイテムの共通プロパティ。本家 `IAudioItem` に対応する。
///
/// 本家で IAudioItem を実装するのは AudioItem / VoiceItem / VideoItem /
/// SceneItem の4種。フェードはアイテムごとに実体が異なるため
/// （VoiceItem は VoiceFadeIn / VoiceFadeOut、VideoItem と SceneItem は
/// 映像側の FadeIn / FadeOut へ委譲）、名前を `audioFadeIn` /
/// `audioFadeOut` として衝突を避ける（VoiceItem には字幕側の
/// `fadeIn` が別に存在する）。
public protocol AudioItemProperties: AnyObject {
    /// 音量（%）。
    var volume: Animation { get }
    /// パン（-100..100）。
    var pan: Animation { get }
    /// 音声のフェードイン（秒）。
    var audioFadeIn: Double { get }
    /// 音声のフェードアウト（秒）。
    var audioFadeOut: Double { get }
    /// エコーを有効にするか。
    var echoIsEnabled: Bool { get }
    /// エコーの間隔（秒）。
    var echoInterval: Double { get }
    /// エコーの減衰（%）。
    var echoAttenuation: Double { get }
    /// 音声エフェクト（生 JSON で保持）。
    var audioEffects: [PreservedObject] { get }
    /// 再生速度変更時の音声処理。
    var playbackRateAudioProcessingMode: PlaybackRateAudioProcessingMode { get }
    /// ループするか（本家で対象になるのは Audio / Video / Scene のみ）。
    var isLooped: Bool { get }
}

extension AudioItem: AudioItemProperties {
    public var audioFadeIn: Double { fadeIn }
    public var audioFadeOut: Double { fadeOut }
}

extension VideoItem: AudioItemProperties {
    // 本家ではインタフェースの既定実装で映像側（VisualItem）の
    // FadeIn / FadeOut に委ねられる。
    public var audioFadeIn: Double { fadeIn }
    public var audioFadeOut: Double { fadeOut }
}

extension SceneItem: AudioItemProperties {
    public var audioFadeIn: Double { fadeIn }
    public var audioFadeOut: Double { fadeOut }
}

extension VoiceItem: AudioItemProperties {
    public var audioFadeIn: Double { voiceFadeIn }
    public var audioFadeOut: Double { voiceFadeOut }
    public var isLooped: Bool { false }
}

/// 音声エフェクトの定義（パラメータ側）。本家 `IAudioEffect` に対応する。
///
/// モデル層の音声エフェクトは現在 PreservedObject（生 JSON）で保持され
/// ており、定義への橋渡しは個別エフェクト実装の段で行う。ここでは
/// 有効状態と処理器の生成だけを契約とする（映像側の
/// `VideoEffectDefinition` と同じ考え方）。
public protocol AudioEffectDefinition: AnyObject {
    /// 有効か。無効な定義はチェーンから除外される（本家 IsEnabled）。
    var isEnabled: Bool { get }
    /// 処理器を新規生成する。生成した処理器の所有権は呼び出し側へ移る。
    /// - Parameters:
    ///   - duration: 対象アイテム（またはグループ）の長さ。
    ///   - fps: プロジェクトの FPS。
    func createProcessor(duration: TimeSpanValue, fps: Int) -> AudioEffectProcessorBase
}

/// 音声エフェクト定義の供給元。モデル層のエフェクト列（PreservedObject）
/// から定義インスタンスへの橋渡しを担う境界。既定実装は何も供給しない
/// （チェーンは素通しになる）。
public protocol AudioEffectProvider {
    func definitions(for effects: [PreservedObject]) -> [any AudioEffectDefinition]
}

extension AudioEffectProvider {
    /// 有効な定義だけを処理器化する（本家は IsEnabled で選別してから
    /// CreateAudioEffect を呼ぶ）。
    func processors(
        for effects: [PreservedObject], duration: TimeSpanValue, fps: Int
    ) -> [AudioEffectProcessorBase] {
        definitions(for: effects)
            .filter { $0.isEnabled }
            .map { $0.createProcessor(duration: duration, fps: fps) }
    }
}

/// エフェクトを何も供給しない供給元（この層の既定）。
public struct EmptyAudioEffectProvider: AudioEffectProvider {
    public init() {}
    public func definitions(for effects: [PreservedObject]) -> [any AudioEffectDefinition] { [] }
}

/// VoiceItem のアップサンプリング方式。本家 `ResamplerMode` に対応する。
/// MediaFoundation が選ばれた場合は Upsampler を挿入せず MFT
/// リサンプラのみに任せる（ここでは `ResamplerStream` のみ）。
/// それ以外のカーネル（Lanczos / Blackman 等）は差し替え点として
/// 未実装（台帳に記録）。
public enum VoiceUpsamplingMode {
    case mediaFoundation
    case linear
    case cubic
}

/// チェーン構築の無効化フラグ。本家 EffectedItemSource の
/// `noVolumeControl` / `noEcho` / `noEffect` に対応する
/// （EXO 出力時の音声ファイル生成などで使う）。
public struct AudioChainOptions {
    public var noVolumeControl: Bool = false
    public var noEcho: Bool = false
    public var noEffect: Bool = false
    /// VoiceItem のアップサンプリング方式。本家の設定
    /// `YMMSettings.GetVoiceUpsamplingMode()` の既定は実コードから
    /// 特定できていないため、フォールバック分岐（Cubic）に置く。
    public var voiceUpsampling: VoiceUpsamplingMode = .cubic

    public init() {}
}
