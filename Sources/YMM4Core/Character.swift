import Foundation

/// キャラクター。本家 `Character` に対応する。
///
/// 本家の `Character` は音声・字幕・立ち絵など約50のプロパティを持つ。
/// 今回は識別と表示に必要な範囲（名前・グループ名・色・レイヤー）だけを
/// 型付きでモデル化し、残りは追加フィールドとして生のまま保持して
/// 書き戻す（データ保全のため）。
public final class Character {
    /// 名前。
    public var name: String = ""
    /// グループ名。
    public var groupName: String = ""
    /// キャラクター色（本家の既定は Colors.Red）。
    public var color: Color = .red
    /// レイヤー。
    public var layer: Int = 0

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    /// .ymmp のオブジェクト形式へ書き出す（型付きプロパティ＋追加フィールド）。
    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Name", value: .string(name)),
            (key: "GroupName", value: .string(groupName)),
            (key: "Color", value: .string(color.honkeString)),
            (key: "Layer", value: .number(layer)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    /// .ymmp のオブジェクト形式から読み込む。オブジェクトでなければ nil。
    static func decode(from value: JSONValue) -> Character? {
        guard let fields = value.objectFields else { return nil }
        let character = Character()
        for (key, fieldValue) in fields {
            switch key {
            case "Name":
                character.name = CodecSupport.string(fieldValue, default: character.name)
            case "GroupName":
                character.groupName = CodecSupport.string(fieldValue, default: character.groupName)
            case "Color":
                character.color = CodecSupport.color(fieldValue, default: character.color)
            case "Layer":
                character.layer = CodecSupport.int(fieldValue, default: character.layer)
            default:
                character.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return character
    }
}
