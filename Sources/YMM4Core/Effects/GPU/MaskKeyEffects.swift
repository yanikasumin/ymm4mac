import Foundation

// GPU 処理系のマスク・キー系エフェクトの定義層。
//
// いずれも処理器は暫定の素通し（`GPUEffectDefinitionBase` が返す
// `GPUEffectPassthroughProcessor`）であり、画像の加工はまだ行われない。
// パラメータの型・既定値・範囲は本家定義クラスの実測に基づく。

/// クロマキー（旧）。本家 `ChromaKeyEffect`。
/// パラメータ（実測）: Color は既定 白、Tolerance は Animation
/// (既定 10, 0〜100)、Feather / IsInvert は bool（既定 false）。
public final class ChromaKeyEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.ChromaKeyEffect, YukkuriMovieMaker"
    }

    /// キーの色。
    public var color: Color = .white
    /// 許容量（%）。
    public var tolerance = Animation(defaultValue: 10, minValue: 0, maxValue: 100)
    /// 境界をぼかすか。
    public var feather: Bool = false
    /// 反転するか。
    public var isInvert: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&tolerance)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Color":
            color = CodecSupport.color(value, default: .white)
            return true
        case "Tolerance":
            CodecSupport.decodeAnimation(value, into: &tolerance)
            return true
        case "Feather":
            feather = CodecSupport.bool(value, default: false)
            return true
        case "IsInvert":
            isInvert = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Color", value: .string(color.honkeString)),
            (key: "Tolerance", value: CodecSupport.encodeAnimation(tolerance)),
            (key: "Feather", value: .bool(feather)),
            (key: "IsInvert", value: .bool(isInvert)),
        ] + super.encodeKnownFields()
    }
}

/// クロマキー。本家 `ChromaKeyEffect2`。
/// パラメータ（実測）: DistanceMode は ChromakeyDistanceMode
/// （既定 YUVIgnoreLuma)、KeyColor は既定 緑（#FF00FF00)、
/// Threshold2 は Animation(既定 30, 0〜100)、Smoothness は
/// Animation(既定 2, 0〜100)、Despill は Animation(既定 0, 0〜200)、
/// IsInvert は bool（既定 false）。旧互換の set 専用 `Threshold` は
/// 読み込み時に Threshold2 へコピーされ、各値へ 21700/32767 が
/// 掛けられる（本家の変換どおり）。
public final class ChromaKeyEffect2Definition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.ChromaKeyEffect2, YukkuriMovieMaker"
    }

    /// 距離の計算方式。
    public var distanceMode: ChromakeyDistanceMode = .yuvIgnoreLuma
    /// キーの色。
    public var keyColor: Color = Color(alpha: 255, red: 0, green: 255, blue: 0)
    /// 閾値（%）。
    public var threshold2 = Animation(defaultValue: 30, minValue: 0, maxValue: 100)
    /// 滑らかさ（%）。
    public var smoothness = Animation(defaultValue: 2, minValue: 0, maxValue: 100)
    /// 色漏れ除去（%）。
    public var despill = Animation(defaultValue: 0, minValue: 0, maxValue: 200)
    /// 反転するか。
    public var isInvert: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&threshold2)
        body(&smoothness)
        body(&despill)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "DistanceMode":
            distanceMode = CodecSupport.enumeration(value, default: ChromakeyDistanceMode.yuvIgnoreLuma)
            return true
        case "KeyColor":
            keyColor = CodecSupport.color(value, default: keyColor)
            return true
        case "Threshold2":
            CodecSupport.decodeAnimation(value, into: &threshold2)
            return true
        case "Smoothness":
            CodecSupport.decodeAnimation(value, into: &smoothness)
            return true
        case "Despill":
            CodecSupport.decodeAnimation(value, into: &despill)
            return true
        case "IsInvert":
            isInvert = CodecSupport.bool(value, default: false)
            return true
        case "Threshold":
            // 旧互換（set 専用）: Threshold2 へコピーし、各値へ
            // 21700/32767 を掛ける（本家の変換どおり）
            let legacy = CodecSupport.decodeLegacyAnimation(value)
            CodecSupport.copyAnimationContents(from: legacy, into: &threshold2)
            threshold2.values = threshold2.values.map {
                AnimationValue($0.value * (21700.0 / 32767.0))
            }
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "DistanceMode", value: .string(distanceMode.honkeName)),
            (key: "KeyColor", value: .string(keyColor.honkeString)),
            (key: "Threshold2", value: CodecSupport.encodeAnimation(threshold2)),
            (key: "Smoothness", value: CodecSupport.encodeAnimation(smoothness)),
            (key: "Despill", value: CodecSupport.encodeAnimation(despill)),
            (key: "IsInvert", value: .bool(isInvert)),
        ] + super.encodeKnownFields()
    }
}

/// マスク。本家 `MaskEffect`。
/// パラメータ（実測）: X / Y / Angle は Animation(既定 0,
/// -100000〜100000)、Opacity は Animation(既定 100, 0〜100)、
/// ShapeType2 は図形プラグインの型名（既定は ShapeItem と同じ
/// プライマリプラグイン）、Blur は Animation(既定 0, 0〜250)、
/// InvertMask は bool（既定 false）。ShapeParameter は多態
/// オブジェクト（図形パラメータ）のため生保持に倒す。旧互換の
/// set 専用 `ShapeType` は読み込み時に ShapeType2 へ変換される
/// （モデル層の図形アイテムと同じ `LegacyShapeType` の対応表）。
public final class MaskEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.MaskEffect, YukkuriMovieMaker"
    }

    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 角度。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 図形プラグインの型名。
    public var shapeType2: String =
        "YukkuriMovieMaker.Shape.QuadrilateralShapePlugin, YukkuriMovieMaker"
    /// 図形パラメータ（生保持。本家 `IShapeParameter`）。
    public var shapeParameter: PreservedObject?
    /// ぼかし量。
    public var blur = Animation(defaultValue: 0, minValue: 0, maxValue: 250)
    /// マスクを反転するか。
    public var invertMask: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&opacity)
        body(&angle)
        body(&blur)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        case "Angle":
            CodecSupport.decodeAnimation(value, into: &angle)
            return true
        case "ShapeType2":
            shapeType2 = CodecSupport.string(value, default: shapeType2)
            return true
        case "ShapeParameter":
            shapeParameter = CodecSupport.preservedObject(value)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "InvertMask":
            invertMask = CodecSupport.bool(value, default: false)
            return true
        case "ShapeType":
            // 旧互換（set 専用）: ShapeType2 へ転送される
            shapeType2 = LegacyShapeType.pluginTypeName(for: value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "ShapeType2", value: .string(shapeType2)),
        ]
        if let shapeParameter {
            fields.append((key: "ShapeParameter", value: shapeParameter.value))
        }
        fields.append((key: "Blur", value: CodecSupport.encodeAnimation(blur)))
        fields.append((key: "InvertMask", value: .bool(invertMask)))
        return fields + super.encodeKnownFields()
    }
}
