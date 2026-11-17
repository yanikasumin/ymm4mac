import Foundation

/// 立ち絵アイテム。本家 `TachieItem` に対応する。
public final class TachieItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.TachieItem, YukkuriMovieMaker"
    }

    /// 紐づくキャラクター（無い場合もある）。
    public var character: Character?
    /// キャラクター名。
    public var characterName: String = ""
    /// 立ち絵パラメータ（プラグイン型、生 JSON で保持）。
    public var tachieItemParameter: PreservedObject?

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            // 本家は実行時参照 Character を [JsonIgnore] とし、保存は CharacterName のみ（MAC-0015）。
            (key: "CharacterName", value: .string(character?.name ?? characterName)),
            (key: "TachieItemParameter", value: tachieItemParameter?.value ?? .null),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Character":
            character = value == .null ? nil : Character.decode(from: value)
            return true
        case "CharacterName":
            characterName = CodecSupport.string(value, default: characterName)
            return true
        case "TachieItemParameter":
            tachieItemParameter = CodecSupport.preservedObject(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}

/// 立ち絵表情アイテム。本家 `TachieFaceItem` に対応する。
public final class TachieFaceItem: BaseItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.TachieFaceItem, YukkuriMovieMaker"
    }

    /// 紐づくキャラクター（無い場合もある）。
    public var character: Character?
    /// キャラクター名。
    public var characterName: String = ""
    /// 表情パラメータ（プラグイン型、生 JSON で保持）。
    public var tachieFaceParameter: PreservedObject?
    /// 表情エフェクト（生 JSON で保持）。
    public var tachieFaceEffects: [PreservedObject] = []

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            // 本家は実行時参照 Character を [JsonIgnore] とし、保存は CharacterName のみ（MAC-0015）。
            (key: "CharacterName", value: .string(character?.name ?? characterName)),
            (key: "TachieFaceParameter", value: tachieFaceParameter?.value ?? .null),
            (key: "TachieFaceEffects", value: .array(tachieFaceEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Character":
            character = value == .null ? nil : Character.decode(from: value)
            return true
        case "CharacterName":
            characterName = CodecSupport.string(value, default: characterName)
            return true
        case "TachieFaceParameter":
            tachieFaceParameter = CodecSupport.preservedObject(value)
            return true
        case "TachieFaceEffects":
            tachieFaceEffects = CodecSupport.preservedList(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}
