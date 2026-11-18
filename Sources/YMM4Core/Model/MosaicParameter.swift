import Foundation

/// モザイクの形状パラメータの保存モデル。本家
/// `YukkuriMovieMaker.Project.Effects.MosaicParameters.MosaicParameterBase`
/// に対応する。
///
/// 本家の組み込みパラメータは6形状とも `SizeMosaicParameterBase` を継承し、
/// 持つプロパティは `Size`（`Animation`、既定 10、範囲 0〜2000）だけである
/// （デコンパイル済みコードで実測）。そのため形状は `$type` 名で区別し、
/// パラメータ本体は1つの型付きモデルで表す。それ以外の $type（プラグイン
/// 由来など）は `PreservedObject` として生 JSON のまま保持する
/// （`ShapeParameter` / `BrushParameter` と同じ方針）。
public enum MosaicParameter {
    case sized(SizedMosaicParameter)
    case preserved(PreservedObject)

    /// .ymmp のオブジェクト形式へ書き出す。
    func encodeToJSONValue() -> JSONValue {
        switch self {
        case .sized(let parameter):
            return parameter.encodeToJSONValue()
        case .preserved(let object):
            return object.value
        }
    }

    /// .ymmp のオブジェクト形式から読み込む。
    static func decode(from value: JSONValue) -> MosaicParameter {
        guard let object = CodecSupport.preservedObject(value),
              object.value.objectFields != nil else {
            return .preserved(PreservedObject(value))
        }
        if let shape = SizedMosaicParameter.shape(forTypeName: object.typeName) {
            return .sized(SizedMosaicParameter.decode(from: object.value, shape: shape))
        }
        return .preserved(object)
    }

    /// パラメータ内の全 `Animation` へ順にアクセスする（定義側の
    /// `forEachAnimation` から呼ばれる。本家ではパラメータも
    /// `GetAnimatables` の一部としてキーフレーム連動の対象になる）。
    func forEachAnimation(_ body: (inout Animation) -> Void) {
        if case .sized(let parameter) = self {
            parameter.forEachAnimation(body)
        }
    }
}

/// サイズだけを持つモザイクパラメータ。本家 `SizeMosaicParameterBase` の
/// 具象型（Rectangle / Circle / Triangle / Hexagon / Delaunay / Voronoi の
/// 各パラメータ）に対応する。形状ごとの差は保存形式には現れない
/// （`SetParameterTo` が渡すのも全形状とも `Size` だけである）。
public final class SizedMosaicParameter {
    /// 形状と $type 名の対応（本家 `MosaicParameterFactory` の対応表）。
    public static func typeName(for shape: MosaicType) -> String? {
        let base = "YukkuriMovieMaker.Project.Effects.MosaicParameters"
        switch shape {
        case .rectangle: return "\(base).RectangleMosaicParameter, YukkuriMovieMaker"
        case .circle: return "\(base).CircleMosaicParameter, YukkuriMovieMaker"
        case .triangle: return "\(base).TriangleMosaicParameter, YukkuriMovieMaker"
        case .hexagon: return "\(base).HexagonMosaicParameter, YukkuriMovieMaker"
        case .delaunay: return "\(base).DelaunayMosaicParameter, YukkuriMovieMaker"
        case .voronoi: return "\(base).VoronoiMosaicParameter, YukkuriMovieMaker"
        case .unknown: return nil
        }
    }

    /// $type 名から形状を引く。組み込み6形状でなければ nil。
    public static func shape(forTypeName name: String?) -> MosaicType? {
        guard let name else { return nil }
        for shape in [MosaicType.rectangle, .circle, .triangle, .hexagon, .delaunay, .voronoi] {
            if typeName(for: shape) == name {
                return shape
            }
        }
        return nil
    }

    /// 形状（$type 名が正本。本家の処理器はパラメータの具象型で効果を
    /// 決めるため、`MosaicEffect.MosaicType` フィールドとは独立に持つ）。
    public var shape: MosaicType

    /// モザイクのセル寸法。本家 `Size`（`Animation`、既定 10、0〜2000）。
    public var size = Animation(defaultValue: 10, minValue: 0, maxValue: 2000)

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init(shape: MosaicType) {
        self.shape = shape
    }

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&size)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = []
        if let typeName = Self.typeName(for: shape) {
            fields.append((key: "$type", value: .string(typeName)))
        }
        fields.append((key: "Size", value: CodecSupport.encodeAnimation(size)))
        fields += additionalFields.filter { $0.key != "Size" }
        return .object(fields)
    }

    static func decode(from value: JSONValue, shape: MosaicType) -> SizedMosaicParameter {
        let parameter = SizedMosaicParameter(shape: shape)
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "Size":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.size)
            default:
                parameter.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return parameter
    }
}
