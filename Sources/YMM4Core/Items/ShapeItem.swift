import Foundation

/// 図形アイテム。本家 `ShapeItem` に対応する。
///
/// 図形パラメータは `ShapeParameter` として保持する（既定の
/// `RectangleShapeParameter` は型付き、それ以外は生 JSON で保持）。
/// 旧互換プロパティ（Size / AspectRate / StrokeThickness / Stroke /
/// ShapeType）は本家では set 専用でパラメータ側へ転送されるため、
/// 読み込み時にだけ消費し、保存時には書き出さない。パラメータが
/// 型付き（rectangle）でない場合は本家ではキャスト例外で読み込み自体が
/// 失敗するが、ここでは追加フィールドとして保持して読み込みを継続する
/// （データ保全を優先する意図的な緩和）。
public final class ShapeItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.ShapeItem, YukkuriMovieMaker"
    }

    /// 図形プラグインの型名（本家ではプライマリプラグイン
    /// `QuadrilateralShapePlugin` の型が既定）。
    public var shapeType2: String =
        "YukkuriMovieMaker.Shape.QuadrilateralShapePlugin, YukkuriMovieMaker"
    /// 図形パラメータ。
    public var shapeParameter: ShapeParameter = .defaultValue

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        shapeParameter.forEachAnimation(body)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "ShapeType2", value: .string(shapeType2)),
            (key: "ShapeParameter", value: shapeParameter.encodeToJSONValue()),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "ShapeType2":
            shapeType2 = CodecSupport.string(value, default: shapeType2)
            return true
        case "ShapeParameter":
            // 本家では setter が null を無視し、既定インスタンスが残る
            if value != .null {
                shapeParameter = ShapeParameter.decode(from: value)
            }
            return true
        case "Size":
            guard case .rectangle(let parameter) = shapeParameter else { return false }
            CodecSupport.copyAnimationContents(
                from: CodecSupport.decodeLegacyAnimation(value), into: &parameter.size
            )
            return true
        case "AspectRate":
            guard case .rectangle(let parameter) = shapeParameter else { return false }
            CodecSupport.copyAnimationContents(
                from: CodecSupport.decodeLegacyAnimation(value), into: &parameter.aspectRate
            )
            return true
        case "StrokeThickness":
            guard case .rectangle(let parameter) = shapeParameter else { return false }
            CodecSupport.copyAnimationContents(
                from: CodecSupport.decodeLegacyAnimation(value), into: &parameter.strokeThickness
            )
            return true
        case "Stroke":
            guard case .rectangle(let parameter) = shapeParameter else { return false }
            // 本家 `StrokeShapeParameterBase.Stroke`: ブラシが単色の場合だけ
            // その色へ転送され、それ以外では黙って捨てられる
            if case .solidColor(let solidColor) = parameter.brush.parameter {
                solidColor.color = CodecSupport.color(value, default: solidColor.color)
            }
            return true
        case "ShapeType":
            shapeType2 = LegacyShapeType.pluginTypeName(for: value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}
