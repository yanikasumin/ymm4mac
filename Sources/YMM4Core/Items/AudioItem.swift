import Foundation

/// 音声アイテム。本家 `AudioItem` に対応する。
public final class AudioItem: BaseItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.AudioItem, YukkuriMovieMaker"
    }

    /// 波形を表示するか。
    public var isWaveformEnabled: Bool = false
    /// ファイルパス（未指定は空文字列）。
    public var filePath: String? = ""
    /// 音声トラックのインデックス。
    public var audioTrackIndex: Int = 0
    /// 音量（%）。
    public var volume: Animation = Animation(defaultValue: 50, minValue: 0, maxValue: 10_000)
    /// パン（-100..100）。
    public var pan: Animation = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// フェードイン（秒）。
    public var fadeIn: Double = 0
    /// フェードアウト（秒）。
    public var fadeOut: Double = 0
    /// 再生速度変更時の音声処理。
    public var playbackRateAudioProcessingMode: PlaybackRateAudioProcessingMode = .resampling
    /// ループするか。
    public var isLooped: Bool = false
    /// エコーを有効にするか。書き込み時に素材長（エコー尾込み）を
    /// 現在の設定で計算し直す（FE-R15-006。本家は取得時に計算）。
    public var echoIsEnabled: Bool = false {
        didSet { refreshContentLengthForEchoSettings() }
    }
    /// エコーの間隔（秒）。
    public var echoInterval: Double = 0.1 {
        didSet { refreshContentLengthForEchoSettings() }
    }
    /// エコーの減衰（%）。
    public var echoAttenuation: Double = 40 {
        didSet { refreshContentLengthForEchoSettings() }
    }
    /// 音声エフェクト（生 JSON で保持）。
    public var audioEffects: [PreservedObject] = []

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        body(&volume)
        body(&pan)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "IsWaveformEnabled", value: .bool(isWaveformEnabled)),
            (key: "FilePath", value: filePath.map(JSONValue.string) ?? .null),
            (key: "AudioTrackIndex", value: .number(audioTrackIndex)),
            (key: "Volume", value: CodecSupport.encodeAnimation(volume)),
            (key: "Pan", value: CodecSupport.encodeAnimation(pan)),
            (key: "FadeIn", value: .number(fadeIn)),
            (key: "FadeOut", value: .number(fadeOut)),
            (key: "PlaybackRateAudioProcessingMode", value: .string(playbackRateAudioProcessingMode.honkeName)),
            (key: "IsLooped", value: .bool(isLooped)),
            (key: "EchoIsEnabled", value: .bool(echoIsEnabled)),
            (key: "EchoInterval", value: .number(echoInterval)),
            (key: "EchoAttenuation", value: .number(echoAttenuation)),
            (key: "AudioEffects", value: .array(audioEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsWaveformEnabled":
            isWaveformEnabled = CodecSupport.bool(value, default: isWaveformEnabled)
        case "FilePath":
            filePath = value == .null ? nil : CodecSupport.string(value, default: filePath ?? "")
        case "AudioTrackIndex":
            audioTrackIndex = CodecSupport.int(value, default: audioTrackIndex)
        case "Volume":
            CodecSupport.decodeAnimation(value, into: &volume)
        case "Pan":
            CodecSupport.decodeAnimation(value, into: &pan)
        case "FadeIn":
            fadeIn = CodecSupport.double(value, default: fadeIn)
        case "FadeOut":
            fadeOut = CodecSupport.double(value, default: fadeOut)
        case "PlaybackRateAudioProcessingMode":
            playbackRateAudioProcessingMode = CodecSupport.enumeration(value, default: playbackRateAudioProcessingMode)
        case "IsLooped":
            isLooped = CodecSupport.bool(value, default: isLooped)
        case "EchoIsEnabled":
            echoIsEnabled = CodecSupport.bool(value, default: echoIsEnabled)
        case "EchoInterval":
            echoInterval = CodecSupport.double(value, default: echoInterval)
        case "EchoAttenuation":
            echoAttenuation = CodecSupport.double(value, default: echoAttenuation)
        case "AudioEffects":
            audioEffects = CodecSupport.preservedList(value)
        default:
            return super.decodeKnownField(key, value)
        }
        return true
    }
}
