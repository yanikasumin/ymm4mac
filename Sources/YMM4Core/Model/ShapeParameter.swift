import Foundation

/// 図形パラメータの保存モデル。本家 `IShapeParameter` に対応する。
///
/// 本家では図形プラグインごとにパラメータ型が増える。ここでは新規作成時の
/// 既定インスタンスである `RectangleShapeParameter`（本家
/// `ShapeItem` / `EffectItem` のフィールド初期値）だけを型付きでモデル化し、
/// それ以外の $type は `PreservedObject` として生 JSON のまま保持する。
public enum ShapeParameter {
    case rectangle(RectangleShapeParameter)
    case preserved(PreservedObject)

    /// 新規作成時の既定値（本家のフィールド初期値）。
    public static var defaultValue: ShapeParameter {
        .rectangle(RectangleShapeParameter())
    }

    /// .ymmp のオブジェクト形式へ書き出す。
    func encodeToJSONValue() -> JSONValue {
        switch self {
        case .rectangle(let parameter):
            return parameter.encodeToJSONValue()
        case .preserved(let object):
            return object.value
        }
    }

    /// .ymmp のオブジェクト形式から読み込む。null は呼び出し側で扱う
    /// （本家では setter が null を無視し、既定インスタンスが残る）。
    static func decode(from value: JSONValue) -> ShapeParameter {
        guard let object = CodecSupport.preservedObject(value) else {
            return .preserved(PreservedObject(value))
        }
        if object.typeName == RectangleShapeParameter.typeName {
            return .rectangle(RectangleShapeParameter.decode(from: object.value))
        }
        return .preserved(object)
    }

    /// パラメータ内の全 `Animation` へ順にアクセスする（アイテム側の
    /// `forEachAnimation` から呼ばれる。本家ではパラメータも
    /// `GetAnimatables` の一部としてキーフレーム連動の対象になる）。
    func forEachAnimation(_ body: (inout Animation) -> Void) {
        if case .rectangle(let parameter) = self {
            parameter.forEachAnimation(body)
        }
    }
}

/// 既定の図形パラメータ。本家 `RectangleShapeParameter` に対応する。
///
/// 継承列は ShapeParameterBase → GeometryShapeParameterBase →
/// StrokeShapeParameterBase（StrokeThickness / Brush）→
/// SizeAndAspectShapeParameterBase（SizeMode / Size / AspectRate /
/// Width / Height）→ CommonShapeParameterBase（Round）→
/// RectangleShapeParameter（追加プロパティなし）。保存時のキー順は
/// 本家（Newtonsoft の基底側から書く順）に合わせる。
public final class RectangleShapeParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Project.Items.RectangleShapeParameter, YukkuriMovieMaker"

    /// 枠線の太さ。本家の既定は 4000（StrokeShapeParameterBase の
    /// コンストラクタ値そのまま）。
    public var strokeThickness: Animation = Animation(defaultValue: 4000, minValue: 0, maxValue: 100_000)
    /// 塗りブラシ。
    public var brush: Brush = Brush()
    /// サイズ指定方法。
    public var sizeMode: SizeMode = .sizeAspect
    /// サイズ（SizeAspect 時の基準値）。
    public var size: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 縦横比（%）。
    public var aspectRate: Animation = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// 幅（WidthHeight 時）。
    public var width: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 高さ（WidthHeight 時）。
    public var height: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 角の丸み。
    public var round: Animation = Animation(defaultValue: 0, minValue: 0, maxValue: 100_000)

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&strokeThickness)
        body(&size)
        body(&aspectRate)
        body(&width)
        body(&height)
        body(&round)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "StrokeThickness", value: CodecSupport.encodeAnimation(strokeThickness)),
            (key: "Brush", value: brush.encodeToJSONValue()),
            (key: "SizeMode", value: .string(sizeMode.honkeName)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
            (key: "AspectRate", value: CodecSupport.encodeAnimation(aspectRate)),
            (key: "Width", value: CodecSupport.encodeAnimation(width)),
            (key: "Height", value: CodecSupport.encodeAnimation(height)),
            (key: "Round", value: CodecSupport.encodeAnimation(round)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> RectangleShapeParameter {
        let parameter = RectangleShapeParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "StrokeThickness":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.strokeThickness)
            case "Brush":
                parameter.brush = Brush.decode(from: fieldValue)
            case "SizeMode":
                parameter.sizeMode = CodecSupport.enumeration(fieldValue, default: parameter.sizeMode)
            case "Size":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.size)
            case "AspectRate":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.aspectRate)
            case "Width":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.width)
            case "Height":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.height)
            case "Round":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.round)
            default:
                parameter.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return parameter
    }
}

/// 旧形式の図形種別（本家 `ShapeType` 列挙型）から、現行の図形プラグイン
/// 型名への変換。本家 `ShapeTypeEx.ToPluginType` の対応表おり。
///
/// 旧互換プロパティ `ShapeType`（set 専用）の読み込み時にだけ使う。
/// 未知の名前・値に対する本家の既定も Quadrilateral（四角形）である。
public enum LegacyShapeType {
    /// プラグイン型名の接頭辞とアセンブリ名。
    private static func pluginTypeName(_ pluginClass: String) -> String {
        "YukkuriMovieMaker.Shape.\(pluginClass), YukkuriMovieMaker"
    }

    /// 列挙型のメンバ名からプラグイン型名へ変換する。
    public static func pluginTypeName(forEnumName name: String) -> String {
        switch name {
        case "Background": return pluginTypeName("BackgroundShapePlugin")
        case "Circle": return pluginTypeName("CircleShapePlugin")
        case "Triangle": return pluginTypeName("TriangleShapePlugin")
        case "Quadrilateral": return pluginTypeName("QuadrilateralShapePlugin")
        case "Pentagon": return pluginTypeName("PentagonShapePlugin")
        case "Hexagon": return pluginTypeName("HexagonShapePlugin")
        case "Star": return pluginTypeName("StarShapePlugin")
        case "RoundedRectangle": return pluginTypeName("QuadrilateralShapePlugin")
        case "Fan": return pluginTypeName("FanShapePlugin")
        case "Wedge": return pluginTypeName("WedgeShapePlugin")
        case "Arrow": return pluginTypeName("ArrowShapePlugin")
        case "Superformula": return pluginTypeName("SuperformulaShapePlugin")
        case "ConcentrationLine": return pluginTypeName("ConcentrationLineShapePlugin")
        case "Timer": return pluginTypeName("TimerShapePlugin")
        default: return pluginTypeName("QuadrilateralShapePlugin")
        }
    }

    /// 列挙型の数値（本家の生値。Triangle = 3 / Quadrilateral = 2 のように
    /// 宣言順と一致しない）からプラグイン型名へ変換する。
    public static func pluginTypeName(forRawValue rawValue: Int) -> String {
        switch rawValue {
        case 0: return pluginTypeName(forEnumName: "Background")
        case 1: return pluginTypeName(forEnumName: "Circle")
        case 3: return pluginTypeName(forEnumName: "Triangle")
        case 2: return pluginTypeName(forEnumName: "Quadrilateral")
        case 4: return pluginTypeName(forEnumName: "Pentagon")
        case 5: return pluginTypeName(forEnumName: "Hexagon")
        case 6: return pluginTypeName(forEnumName: "Star")
        case 100: return pluginTypeName(forEnumName: "RoundedRectangle")
        case 101: return pluginTypeName(forEnumName: "Fan")
        case 102: return pluginTypeName(forEnumName: "Wedge")
        case 103: return pluginTypeName(forEnumName: "Arrow")
        case 104: return pluginTypeName(forEnumName: "Superformula")
        case 201: return pluginTypeName(forEnumName: "ConcentrationLine")
        case 202: return pluginTypeName(forEnumName: "Timer")
        default: return pluginTypeName(forEnumName: "Quadrilateral")
        }
    }

    /// JSON 値（メンバ名の文字列、または数値）からプラグイン型名へ変換する。
    public static func pluginTypeName(for value: JSONValue) -> String {
        if let name = value.stringValue {
            return pluginTypeName(forEnumName: name)
        }
        if let rawValue = value.intValue {
            return pluginTypeName(forRawValue: rawValue)
        }
        return pluginTypeName(forEnumName: "Quadrilateral")
    }
}
