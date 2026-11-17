import Foundation

/// 図形の塗りブラシ。本家 `YukkuriMovieMaker.Plugin.Brush.Brush` に対応する。
///
/// 既定のブラシプラグインは `[PrimaryPlugin]` の付いた
/// `SolidColorBrushPlugin`（PluginLoader.GetPrimaryPluginType の解決先）。
public final class Brush {
    /// 既定のブラシプラグイン型名。
    public static let defaultTypeName =
        "YukkuriMovieMaker.Plugin.Brush.SolidColorBrushPlugin, YukkuriMovieMaker"

    /// ブラシプラグインの型名。
    public var type: String = Brush.defaultTypeName
    /// ブラシパラメータ。
    public var parameter: BrushParameter = .solidColor(SolidColorBrushParameter())

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Type", value: .string(type)),
            (key: "Parameter", value: parameter.encodeToJSONValue()),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> Brush {
        let brush = Brush()
        guard let fields = value.objectFields else { return brush }
        for (key, fieldValue) in fields {
            switch key {
            case "Type":
                brush.type = CodecSupport.string(fieldValue, default: brush.type)
            case "Parameter":
                brush.parameter = BrushParameter.decode(from: fieldValue)
            default:
                brush.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return brush
    }
}

/// ブラシパラメータ。本家 `IBrushParameter` に対応する。
///
/// 既定プラグインの `SolidColorBrushParameter` だけを型付きでモデル化し、
/// それ以外の $type は生 JSON のまま保持する。
public enum BrushParameter {
    case solidColor(SolidColorBrushParameter)
    case preserved(PreservedObject)

    func encodeToJSONValue() -> JSONValue {
        switch self {
        case .solidColor(let parameter):
            return parameter.encodeToJSONValue()
        case .preserved(let object):
            return object.value
        }
    }

    static func decode(from value: JSONValue) -> BrushParameter {
        // 本家では null のまま保持されうるが、実ファイルでは到達しない
        // 前提で既定（単色）へ倒す。オブジェクトでない値も同様。
        guard let object = CodecSupport.preservedObject(value),
              object.value.objectFields != nil else {
            return .solidColor(SolidColorBrushParameter())
        }
        if object.typeName == SolidColorBrushParameter.typeName {
            return .solidColor(SolidColorBrushParameter.decode(from: object.value))
        }
        return .preserved(object)
    }
}

/// 単色ブラシのパラメータ。本家 `SolidColorBrushParameter` に対応する。
public final class SolidColorBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Plugin.Brush.SolidColorBrushParameter, YukkuriMovieMaker"

    /// 塗りの色（本家の既定は Colors.White）。
    public var color: Color = .white

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "Color", value: .string(color.honkeString)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> SolidColorBrushParameter {
        let parameter = SolidColorBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "Color":
                parameter.color = CodecSupport.color(fieldValue, default: parameter.color)
            default:
                parameter.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return parameter
    }
}
