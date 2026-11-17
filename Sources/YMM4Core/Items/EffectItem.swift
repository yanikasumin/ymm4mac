import Foundation

/// エフェクトアイテム。本家 `EffectItem` に対応する。
///
/// 本家では `Zoom` はアクセスのたびに新しい `Animation(100)` を返す
/// get 専用プロパティで、保存はされるが読み込み結果は保持されない。
/// `IsInverted` は [JsonIgnore] で保存対象外。どちらもその挙動に合わせ、
/// 保存時は Zoom に既定値を書き、読み込み時は両方とも捨てる。
public final class EffectItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.EffectItem, YukkuriMovieMaker"
    }

    /// 図形プラグインの型名（本家ではプライマリプラグイン
    /// `QuadrilateralShapePlugin` の型が既定）。
    public var shapeType2: String =
        "YukkuriMovieMaker.Shape.QuadrilateralShapePlugin, YukkuriMovieMaker"
    /// 図形パラメータ（マスク形状。ShapeItem と同型）。
    public var shapeParameter: ShapeParameter = .defaultValue
    /// マスクのぼかし量（本家 `Blur`。Animation で、既定 0・範囲 0〜250）。
    public var blur: Animation = Animation(defaultValue: 0, minValue: 0, maxValue: 250)
    /// マスクを反転するか。
    public var invertMask: Bool = false

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields = super.encodeKnownFields().filter { $0.key != "IsInverted" }
        for index in fields.indices where fields[index].key == "Zoom" {
            fields[index].value = CodecSupport.encodeAnimation(
                Animation(defaultValue: 100, minValue: -100_000, maxValue: 100_000)
            )
        }
        fields += [
            (key: "ShapeType2", value: .string(shapeType2)),
            (key: "ShapeParameter", value: shapeParameter.encodeToJSONValue()),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "InvertMask", value: .bool(invertMask)),
        ]
        return fields
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        shapeParameter.forEachAnimation(body)
        body(&blur)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Zoom", "IsInverted":
            // 本家では保持されない（Zoom は get 専用、IsInverted は JsonIgnore）
            return true
        case "ShapeType2":
            shapeType2 = CodecSupport.string(value, default: shapeType2)
            return true
        case "ShapeParameter":
            // 本家では setter が null を無視し、既定インスタンスが残る
            if value != .null {
                shapeParameter = ShapeParameter.decode(from: value)
            }
            return true
        case "ShapeType":
            // 旧互換（set 専用）: ShapeType2 へ転送される
            shapeType2 = LegacyShapeType.pluginTypeName(for: value)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "InvertMask":
            invertMask = CodecSupport.bool(value, default: invertMask)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}
