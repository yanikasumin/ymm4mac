import Foundation

/// 音声（ボイス）アイテム。本家 `VoiceItem` に対応する。
///
/// 音声本体と字幕（字幕側の外観・配置）の両方を持つ。`FilePath` は本家では
/// 計算プロパティ（保存対象外）のためモデル化しない。口形の時系列
/// `LipSyncFrames` は意味論を持たず生 JSON のまま保持する。
///
/// 映像プロパティ一式（x 〜 videoEffects）は字幕側の保持であり、本家では
/// `Jimaku*` プロパティとして保存される。本家の IVideoItem 実装は
/// JimakuVisibility とキャラクターによる解決（カスタム以外では
/// キャラクター側の値を優先する）を行うが、ここでは解決を行わず自前の
/// 保持値をそのまま公開する（解決は字幕 Source 実装の段で扱う。台帳に記録）。
public final class VoiceItem: BaseItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.VoiceItem, YukkuriMovieMaker"
    }

    /// 波形を表示するか。
    public var isWaveformEnabled: Bool = false
    /// 紐づくキャラクター（無い場合もある）。
    public var character: Character?
    /// キャラクター名。
    public var characterName: String = ""
    /// セリフ。
    public var serif: String = ""
    /// 部分装飾。
    public var decorations: [TextDecoration] = []
    /// 発音記号列。
    public var hatsuon: String = ""
    /// 発音情報（プラグイン型、生 JSON で保持）。
    public var pronounce: PreservedObject?
    /// 口形の時系列（生 JSON で保持）。
    public var lipSyncFrames: JSONValue = .array([])
    /// 音声の長さ。
    public var voiceLength: TimeSpanValue = .zero
    /// 音声キャッシュ（base64 で保存される）。
    public var voiceCache: Data? {
        didSet { voiceCacheGeneration += 1 }
    }

    /// 音声キャッシュの世代。差し替えのたびに増える単調カウンタで、
    /// 保存対象ではない。バイト数では検出できない同サイズ差し替えを
    /// 消費側（包絡キャッシュの署名など）が識別するために使う
    /// （R22-116-02）。
    public private(set) var voiceCacheGeneration: Int = 0
    /// 音量（%）。
    public var volume: Animation = Animation(defaultValue: 50, minValue: 0, maxValue: 10_000)
    /// パン（-100..100）。
    public var pan: Animation = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// 再生速度変更時の音声処理。
    public var playbackRateAudioProcessingMode: PlaybackRateAudioProcessingMode = .resampling
    /// 音声パラメータ（プラグイン型、生 JSON で保持）。
    public var voiceParameter: PreservedObject?
    /// 追加時間（秒）。本家では未設定時にキャラクター側→0.3 の順で解決する
    /// getter を持つが、ここでは解決済みの値として保持する。
    public var additionalTime: Double = 0.3
    /// 音声のフェードイン（秒）。
    public var voiceFadeIn: Double = 0
    /// 音声のフェードアウト（秒）。
    public var voiceFadeOut: Double = 0
    /// エコーを有効にするか。
    public var echoIsEnabled: Bool = false
    /// エコーの間隔（秒）。
    public var echoInterval: Double = 0.1
    /// エコーの減衰（%）。
    public var echoAttenuation: Double = 40
    /// 音声エフェクト（生 JSON で保持）。
    public var audioEffects: [PreservedObject] = []
    /// 字幕の表示方法。
    public var jimakuVisibility: JimakuVisibility = .useCharacterSetting
    /// 字幕の X 座標。本家 `JimakuX`。保存キーは "Y"（本家の
    /// [JsonProperty("Y")] 指定により X と Y が入れ替わる。互換層を参照）。
    public var x: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 字幕の Y 座標。本家 `JimakuY`。保存キーは "X"（同上）。
    public var y: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 字幕の Z 座標。本家 `JimakuZ`。
    public var z: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 字幕の不透明度（%）。本家 `JimakuOpacity`。
    public var opacity: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 字幕の拡大率（%）。本家 `JimakuZoom`。
    public var zoom: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 字幕の回転角。本家 `JimakuRotation`。
    public var rotation: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 字幕のフェードイン（秒）。本家 `JimakuFadeIn`。
    public var fadeIn: Double = 0
    /// 字幕のフェードアウト（秒）。本家 `JimakuFadeOut`。
    public var fadeOut: Double = 0
    /// 字幕の合成方法。本家 `JimakuBlend`。
    public var blend: Blend = .normal
    /// 字幕を反転するか。本家 `JimakuIsInverted`。
    public var isInverted: Bool = false
    /// 字幕を1つ上のオブジェクトで切り抜くか。本家 `JimakuIsClippingWithObjectAbove`。
    public var isClippingWithObjectAbove: Bool = false
    /// 字幕を常に手前に表示するか。本家 `JimakuIsAlwaysOnTop`。
    public var isAlwaysOnTop: Bool = false
    /// 字幕の Z オーダーを有効にするか。本家 `JimakuIsZOrderEnabled`。
    public var isZOrderEnabled: Bool = false
    /// 字幕のフォント外観。
    public var appearance = TextAppearance()
    /// 字幕の映像エフェクト（生 JSON で保持）。本家 `JimakuVideoEffects`。
    public var videoEffects: [PreservedObject] = []
    /// 立ち絵表情パラメータ（プラグイン型、生 JSON で保持）。
    public var tachieFaceParameter: PreservedObject?
    /// 立ち絵表情エフェクト（生 JSON で保持）。
    public var tachieFaceEffects: [PreservedObject] = []

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        body(&volume)
        body(&pan)
        body(&x)
        body(&y)
        body(&z)
        body(&opacity)
        body(&zoom)
        body(&rotation)
        appearance.forEachAnimation(body)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = super.encodeKnownFields()
        fields += [
            (key: "IsWaveformEnabled", value: .bool(isWaveformEnabled)),
            // 本家は実行時参照 Character を [JsonIgnore] とし、保存は CharacterName のみ。
            // CharacterName の getter は Character?.Name ?? characterName（MAC-0015）。
            (key: "CharacterName", value: .string(character?.name ?? characterName)),
            (key: "Serif", value: .string(serif)),
            (key: "Decorations", value: .array(decorations.map { $0.encodeToJSONValue() })),
            (key: "Hatsuon", value: .string(hatsuon)),
            (key: "Pronounce", value: pronounce?.value ?? .null),
            (key: "LipSyncFrames", value: lipSyncFrames),
            (key: "VoiceLength", value: .string(voiceLength.honkeString)),
            (key: "VoiceCache", value: voiceCache.map { .string($0.base64EncodedString()) } ?? .null),
            (key: "Volume", value: CodecSupport.encodeAnimation(volume)),
            (key: "Pan", value: CodecSupport.encodeAnimation(pan)),
            (key: "PlaybackRateAudioProcessingMode", value: .string(playbackRateAudioProcessingMode.honkeName)),
            (key: "VoiceParameter", value: voiceParameter?.value ?? .null),
            (key: "AdditionalTime", value: .number(additionalTime)),
            (key: "VoiceFadeIn", value: .number(voiceFadeIn)),
            (key: "VoiceFadeOut", value: .number(voiceFadeOut)),
            (key: "EchoIsEnabled", value: .bool(echoIsEnabled)),
            (key: "EchoInterval", value: .number(echoInterval)),
            (key: "EchoAttenuation", value: .number(echoAttenuation)),
            (key: "AudioEffects", value: .array(audioEffects.map { $0.value })),
            (key: "JimakuVisibility", value: .string(jimakuVisibility.honkeName)),
            // 映像プロパティの保存キーは本家の [JsonProperty] 指定どおり:
            // JimakuX は "Y"、JimakuY は "X"（X と Y が入れ替わる本家の
            // 指定をそのまま再現する）、JimakuZ 以降は IVideoItem と同じ
            // キー名（"Z" / "Opacity" / "Zoom" / "Rotation" / "Blend" /
            // "IsInverted" / "IsClippingWithObjectAbove" /
            // "IsAlwaysOnTop" / "IsZOrderEnabled"）になる。FadeIn /
            // FadeOut と VideoEffects だけは Jimaku* の名前のまま保存される。
            (key: "Y", value: CodecSupport.encodeAnimation(x)),
            (key: "X", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
            (key: "JimakuFadeIn", value: .number(fadeIn)),
            (key: "JimakuFadeOut", value: .number(fadeOut)),
            (key: "Blend", value: .string(blend.honkeName)),
            (key: "IsInverted", value: .bool(isInverted)),
            (key: "IsClippingWithObjectAbove", value: .bool(isClippingWithObjectAbove)),
            (key: "IsAlwaysOnTop", value: .bool(isAlwaysOnTop)),
            (key: "IsZOrderEnabled", value: .bool(isZOrderEnabled)),
        ]
        fields += appearance.encodeFields()
        fields += [
            (key: "JimakuVideoEffects", value: .array(videoEffects.map { $0.value })),
            (key: "TachieFaceParameter", value: tachieFaceParameter?.value ?? .null),
            (key: "TachieFaceEffects", value: .array(tachieFaceEffects.map { $0.value })),
        ]
        return fields
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsWaveformEnabled":
            isWaveformEnabled = CodecSupport.bool(value, default: isWaveformEnabled)
        case "Character":
            character = value == .null ? nil : Character.decode(from: value)
        case "CharacterName":
            characterName = CodecSupport.string(value, default: characterName)
        case "Serif":
            serif = CodecSupport.string(value, default: serif)
        case "Decorations":
            if let elements = value.arrayValue {
                decorations = elements.compactMap { TextDecoration.decode(from: $0) }
            }
        case "Hatsuon":
            hatsuon = CodecSupport.string(value, default: hatsuon)
        case "Pronounce":
            pronounce = CodecSupport.preservedObject(value)
        case "LipSyncFrames":
            lipSyncFrames = value
        case "VoiceLength":
            voiceLength = CodecSupport.timeSpan(value, default: voiceLength)
        case "VoiceCache":
            voiceCache = value == .null ? nil : value.stringValue.flatMap { Data(base64Encoded: $0) }
        case "Volume":
            CodecSupport.decodeAnimation(value, into: &volume)
        case "Pan":
            CodecSupport.decodeAnimation(value, into: &pan)
        case "PlaybackRateAudioProcessingMode":
            playbackRateAudioProcessingMode = CodecSupport.enumeration(value, default: playbackRateAudioProcessingMode)
        case "VoiceParameter":
            voiceParameter = CodecSupport.preservedObject(value)
        case "AdditionalTime":
            additionalTime = CodecSupport.double(value, default: additionalTime)
        case "VoiceFadeIn":
            voiceFadeIn = CodecSupport.double(value, default: voiceFadeIn)
        case "VoiceFadeOut":
            voiceFadeOut = CodecSupport.double(value, default: voiceFadeOut)
        case "EchoIsEnabled":
            echoIsEnabled = CodecSupport.bool(value, default: echoIsEnabled)
        case "EchoInterval":
            echoInterval = CodecSupport.double(value, default: echoInterval)
        case "EchoAttenuation":
            echoAttenuation = CodecSupport.double(value, default: echoAttenuation)
        case "AudioEffects":
            audioEffects = CodecSupport.preservedList(value)
        case "JimakuVisibility":
            jimakuVisibility = CodecSupport.enumeration(value, default: jimakuVisibility)
        case "Y":
            // 本家 JimakuX の保存キー（X と Y が入れ替わる。encode 側を参照）
            CodecSupport.decodeAnimation(value, into: &x)
        case "X":
            // 本家 JimakuY の保存キー（同上）
            CodecSupport.decodeAnimation(value, into: &y)
        case "Z":
            CodecSupport.decodeAnimation(value, into: &z)
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
        case "Rotation":
            CodecSupport.decodeAnimation(value, into: &rotation)
        case "JimakuFadeIn":
            fadeIn = CodecSupport.double(value, default: fadeIn)
        case "JimakuFadeOut":
            fadeOut = CodecSupport.double(value, default: fadeOut)
        case "Blend":
            blend = CodecSupport.enumeration(value, default: blend)
        case "IsInverted":
            isInverted = CodecSupport.bool(value, default: isInverted)
        case "IsClippingWithObjectAbove":
            isClippingWithObjectAbove = CodecSupport.bool(value, default: isClippingWithObjectAbove)
        case "IsAlwaysOnTop":
            isAlwaysOnTop = CodecSupport.bool(value, default: isAlwaysOnTop)
        case "IsZOrderEnabled":
            isZOrderEnabled = CodecSupport.bool(value, default: isZOrderEnabled)
        case "JimakuVideoEffects":
            videoEffects = CodecSupport.preservedList(value)
        case "TachieFaceParameter":
            tachieFaceParameter = CodecSupport.preservedObject(value)
        case "TachieFaceEffects":
            tachieFaceEffects = CodecSupport.preservedList(value)
        default:
            if appearance.decodeField(key, value) {
                return true
            }
            return super.decodeKnownField(key, value)
        }
        return true
    }
}

extension VoiceItem: VideoItemProperties {}
