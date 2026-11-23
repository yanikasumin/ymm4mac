import Foundation

/// シーンアイテム。本家 `SceneItem` に対応する（映像＋音声）。
///
/// 本家の `IAudioItem` の FadeIn / FadeOut はインタフェースの既定実装で
/// 値を持たず、SceneItem には保存されるプロパティが存在しない。
public final class SceneItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.SceneItem, YukkuriMovieMaker"
    }

    /// 波形を表示するか。
    public var isWaveformEnabled: Bool = false
    /// 参照先シーン（タイムライン）の ID。
    public var sceneId: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    /// 参照先シーンの長さ（尾なし）の供給（保存対象外）。
    ///
    /// 本家は `GlobalSceneInfo` のライブ参照でシーン長を引くが、
    /// Mac 側のアイテムはプロジェクトへの参照を持たないため、
    /// プロジェクト側から注入されるクロージャを継ぎ目とする
    /// （合成層の `sceneTimelineResolver` 注入と同じ形。注入は
    /// `Project.injectSceneLengthProviders()` が担い、読み込み時は
    /// `YmmpCodec.decode` が呼ぶ）。供給は引くたびに評価される
    /// ため、参照先シーンの長さの変化は再注入なしで反映される。
    public var sceneLengthProvider: ((UUID) -> TimeSpanValue?)?
    /// 参照先シーンの素材長（尾なし）。本家 `SceneItem` の
    /// `OriginalContentLength` に相当する。供給が無い・シーンが
    /// 解決できない場合は 0（本家 `GlobalSceneInfo.GetValue` が
    /// 未登録の ID に対して default を返す規則と一致する）。
    public var sceneContentLength: TimeSpanValue {
        sceneLengthProvider?(sceneId) ?? .zero
    }
    /// 音量（%）。
    public var volume: Animation = Animation(defaultValue: 50, minValue: 0, maxValue: 10_000)
    /// パン（-100..100）。
    public var pan: Animation = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// 再生速度変更時の音声処理。
    public var playbackRateAudioProcessingMode: PlaybackRateAudioProcessingMode = .resampling
    /// ループするか。
    public var isLooped: Bool = false
    /// エコーを有効にするか。
    public var echoIsEnabled: Bool = false
    /// エコーの間隔（秒）。
    public var echoInterval: Double = 0.1
    /// エコーの減衰（%）。
    public var echoAttenuation: Double = 40
    /// 音声エフェクト（生 JSON で保持）。
    public var audioEffects: [PreservedObject] = []

    /// コンテンツの区切り位置。本家 `SceneItem.ContentSeparations`
    /// の上書き形（本体は参照先シーンの長さで構成される）。
    public override var contentSeparations: AnySequence<TimeSpanValue> {
        sceneContentSeparations(
            sceneLength: sceneContentLength,
            isLooped: isLooped,
            echoIsEnabled: echoIsEnabled,
            echoInterval: echoInterval,
            echoAttenuation: echoAttenuation
        )
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        body(&volume)
        body(&pan)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "IsWaveformEnabled", value: .bool(isWaveformEnabled)),
            (key: "SceneId", value: .string(sceneId.uuidString.lowercased())),
            (key: "Volume", value: CodecSupport.encodeAnimation(volume)),
            (key: "Pan", value: CodecSupport.encodeAnimation(pan)),
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
        case "SceneId":
            sceneId = CodecSupport.uuid(value, default: sceneId)
        case "Volume":
            CodecSupport.decodeAnimation(value, into: &volume)
        case "Pan":
            CodecSupport.decodeAnimation(value, into: &pan)
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
