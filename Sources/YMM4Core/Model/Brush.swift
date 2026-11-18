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

    /// オブジェクトでない値が読み込まれた場合の生保持（そのまま書き戻す）。
    /// 本家が生成するファイルでは到達しないが、手編集等で壊れた値が
    /// 来てもデータを落とさないための保全経路。
    public var nonObjectRawValue: JSONValue?

    public init() {}

    /// パラメータ内の Animation を走査する（キーフレーム文脈の注入用。
    /// 本家では Brush 自身が Animatable で Parameter を子に持つ）。
    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        parameter.forEachAnimation(body)
    }

    func encodeToJSONValue() -> JSONValue {
        if let nonObjectRawValue {
            return nonObjectRawValue
        }
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Type", value: .string(type)),
            (key: "Parameter", value: parameter.encodeToJSONValue()),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> Brush {
        let brush = Brush()
        guard let fields = value.objectFields else {
            brush.nonObjectRawValue = value
            return brush
        }
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
/// 本家組み込みのパラメータ型は型付きでモデル化し（各型の根拠は
/// BrushParameters.swift）、それ以外の $type（コミュニティプラグイン等）
/// は生 JSON のまま保持する。グラデーションメッシュは BRUSH46 では
/// 生保持に倒していたが、GRADMESH で逆コンパイル済みモデルから
/// 保存形式を確定し型付き化した（実ファイルでの出現は未確認）。
public enum BrushParameter {
    case solidColor(SolidColorBrushParameter)
    case linearGradient(LinearGradientBrushParameter)
    case radialGradient(RadialGradientBrushParameter)
    case checkered(CheckeredBrushParameter)
    case dot(DotBrushParameter)
    case stripe(StripeBrushParameter)
    case gridLine(GridLineBrushParameter)
    case bitmap(BitmapBrushParameter)
    case noise(NoiseBrushParameter)
    case gradientMesh(GradientMeshBrushParameter)
    case preserved(PreservedObject)

    func encodeToJSONValue() -> JSONValue {
        switch self {
        case .solidColor(let parameter):
            return parameter.encodeToJSONValue()
        case .linearGradient(let parameter):
            return parameter.encodeToJSONValue()
        case .radialGradient(let parameter):
            return parameter.encodeToJSONValue()
        case .checkered(let parameter):
            return parameter.encodeToJSONValue()
        case .dot(let parameter):
            return parameter.encodeToJSONValue()
        case .stripe(let parameter):
            return parameter.encodeToJSONValue()
        case .gridLine(let parameter):
            return parameter.encodeToJSONValue()
        case .bitmap(let parameter):
            return parameter.encodeToJSONValue()
        case .noise(let parameter):
            return parameter.encodeToJSONValue()
        case .gradientMesh(let parameter):
            return parameter.encodeToJSONValue()
        case .preserved(let object):
            return object.value
        }
    }

    /// パラメータ内の Animation を走査する。
    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        switch self {
        case .solidColor, .preserved:
            break
        case .linearGradient(let parameter):
            parameter.forEachAnimation(body)
        case .radialGradient(let parameter):
            parameter.forEachAnimation(body)
        case .checkered(let parameter):
            parameter.forEachAnimation(body)
        case .dot(let parameter):
            parameter.forEachAnimation(body)
        case .stripe(let parameter):
            parameter.forEachAnimation(body)
        case .gridLine(let parameter):
            parameter.forEachAnimation(body)
        case .bitmap(let parameter):
            parameter.forEachAnimation(body)
        case .noise(let parameter):
            parameter.forEachAnimation(body)
        case .gradientMesh(let parameter):
            parameter.forEachAnimation(body)
        }
    }

    static func decode(from value: JSONValue) -> BrushParameter {
        // 本家では null のまま保持されうるが、実ファイルでは到達しない
        // 前提で既定（単色）へ倒す。オブジェクトでない値も同様。
        guard let object = CodecSupport.preservedObject(value),
              object.value.objectFields != nil else {
            return .solidColor(SolidColorBrushParameter())
        }
        switch object.typeName {
        case SolidColorBrushParameter.typeName:
            return .solidColor(SolidColorBrushParameter.decode(from: object.value))
        case LinearGradientBrushParameter.typeName:
            return .linearGradient(LinearGradientBrushParameter.decode(from: object.value))
        case RadialGradientBrushParameter.typeName:
            return .radialGradient(RadialGradientBrushParameter.decode(from: object.value))
        case CheckeredBrushParameter.typeName:
            return .checkered(CheckeredBrushParameter.decode(from: object.value))
        case DotBrushParameter.typeName:
            return .dot(DotBrushParameter.decode(from: object.value))
        case StripeBrushParameter.typeName:
            return .stripe(StripeBrushParameter.decode(from: object.value))
        case GridLineBrushParameter.typeName:
            return .gridLine(GridLineBrushParameter.decode(from: object.value))
        case BitmapBrushParameter.typeName:
            return .bitmap(BitmapBrushParameter.decode(from: object.value))
        case NoiseBrushParameter.typeName:
            return .noise(NoiseBrushParameter.decode(from: object.value))
        case GradientMeshBrushParameter.typeName:
            return .gradientMesh(GradientMeshBrushParameter.decode(from: object.value))
        default:
            return .preserved(object)
        }
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
