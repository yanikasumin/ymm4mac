import Foundation

/// グループアイテム。本家 `GroupItem` に対応する。
///
/// 本家では FadeIn / FadeOut / Blend / Opacity 等を独自の保持で上書きするが、
/// 保存形式は VisualItem と同一のため、ここでは継承した保持をそのまま使う
/// （内部実装の違いのみ）。旧互換の `IsCompressFrame` は set 専用で、
/// 読み込み時に `IsComposite` へ転送されるだけである。
public final class GroupItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.GroupItem, YukkuriMovieMaker"
    }

    /// グループの対象レイヤー範囲。
    public var groupRange: Int = 50
    /// グループのみを対象にするか。
    public var isGroupOnly: Bool = false
    /// 合成するか。
    public var isComposite: Bool = false
    /// 音声を合成するか。
    public var isAudioComposite: Bool = false
    /// 合成の中心。
    public var compositeCenter: GroupItemCompositeCenter = .screenCenter
    /// 音声エフェクト（生 JSON で保持）。
    public var audioEffects: [PreservedObject] = []

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "GroupRange", value: .number(groupRange)),
            (key: "IsGroupOnly", value: .bool(isGroupOnly)),
            (key: "IsComposite", value: .bool(isComposite)),
            (key: "IsAudioComposite", value: .bool(isAudioComposite)),
            (key: "CompositeCenter", value: .string(compositeCenter.honkeName)),
            (key: "AudioEffects", value: .array(audioEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "GroupRange":
            groupRange = CodecSupport.int(value, default: groupRange)
        case "IsGroupOnly":
            isGroupOnly = CodecSupport.bool(value, default: isGroupOnly)
        case "IsComposite":
            isComposite = CodecSupport.bool(value, default: isComposite)
        case "IsAudioComposite":
            isAudioComposite = CodecSupport.bool(value, default: isAudioComposite)
        case "CompositeCenter":
            compositeCenter = CodecSupport.enumeration(value, default: compositeCenter)
        case "AudioEffects":
            audioEffects = CodecSupport.preservedList(value)
        case "IsCompressFrame":
            // 旧互換（set 専用）: IsComposite へ転送される
            isComposite = CodecSupport.bool(value, default: isComposite)
        default:
            return super.decodeKnownField(key, value)
        }
        return true
    }
}
