import Foundation

// GPU 処理系の色調・色変換エフェクトの定義層。
//
// いずれも処理器は暫定の素通し（`GPUEffectDefinitionBase` が返す
// `GPUEffectPassthroughProcessor`）であり、画像の加工はまだ行われない。
// パラメータの型・既定値・範囲は本家定義クラスの実測に基づく。

/// 色収差。本家 `ChromaticAberrationEffect`。
/// パラメータ（実測）: Strength は Animation(既定 1, 0〜100)。
public final class ChromaticAberrationEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.ChromaticAberrationEffect, YukkuriMovieMaker"
    }

    /// ずれの強さ。
    public var strength = Animation(defaultValue: 1, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&strength)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Strength":
            CodecSupport.decodeAnimation(value, into: &strength)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Strength", value: CodecSupport.encodeAnimation(strength)),
        ] + super.encodeKnownFields()
    }
}

/// 露出。本家 `ExposureEffect`。
/// パラメータ（実測）: Value は Animation(既定 0, -200〜200)。
public final class ExposureEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.ExposureEffect, YukkuriMovieMaker"
    }

    /// 露出量。
    public var value = Animation(defaultValue: 0, minValue: -200, maxValue: 200)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&value)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            CodecSupport.decodeAnimation(value, into: &self.value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Value", value: CodecSupport.encodeAnimation(value)),
        ] + super.encodeKnownFields()
    }
}

/// ガンマ補正。本家 `GammaCorrectionEffect`。
/// パラメータ（実測）: Gamma / Red / Green / Blue は Animation
/// (既定 1, 0.01〜10)。
public final class GammaCorrectionEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.GammaCorrectionEffect, YukkuriMovieMaker"
    }

    /// 全体のガンマ。
    public var gamma = Animation(defaultValue: 1, minValue: 0.01, maxValue: 10)
    /// 赤のガンマ。
    public var red = Animation(defaultValue: 1, minValue: 0.01, maxValue: 10)
    /// 緑のガンマ。
    public var green = Animation(defaultValue: 1, minValue: 0.01, maxValue: 10)
    /// 青のガンマ。
    public var blue = Animation(defaultValue: 1, minValue: 0.01, maxValue: 10)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&gamma)
        body(&red)
        body(&green)
        body(&blue)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Gamma":
            CodecSupport.decodeAnimation(value, into: &gamma)
            return true
        case "Red":
            CodecSupport.decodeAnimation(value, into: &red)
            return true
        case "Green":
            CodecSupport.decodeAnimation(value, into: &green)
            return true
        case "Blue":
            CodecSupport.decodeAnimation(value, into: &blue)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Gamma", value: CodecSupport.encodeAnimation(gamma)),
            (key: "Red", value: CodecSupport.encodeAnimation(red)),
            (key: "Green", value: CodecSupport.encodeAnimation(green)),
            (key: "Blue", value: CodecSupport.encodeAnimation(blue)),
        ] + super.encodeKnownFields()
    }
}

/// ハイライトとシャドウ。本家 `HightlightsAndShadowsEffect`
/// （本家の綴りどおり Hightlights）。
/// パラメータ（実測）: Highlights / Shadows は Animation(既定 0,
/// -100〜100)。
public final class HightlightsAndShadowsEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.HightlightsAndShadowsEffect, YukkuriMovieMaker"
    }

    /// ハイライトの調整量。
    public var highlights = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// シャドウの調整量。
    public var shadows = Animation(defaultValue: 0, minValue: -100, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&highlights)
        body(&shadows)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Highlights":
            CodecSupport.decodeAnimation(value, into: &highlights)
            return true
        case "Shadows":
            CodecSupport.decodeAnimation(value, into: &shadows)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Highlights", value: CodecSupport.encodeAnimation(highlights)),
            (key: "Shadows", value: CodecSupport.encodeAnimation(shadows)),
        ] + super.encodeKnownFields()
    }
}

/// 色反転。本家 `InvertEffect`。パラメータはない（基底の
/// IsEnabled / Remark のみ）。
public final class InvertEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InvertEffect, YukkuriMovieMaker"
    }
}

/// 線形変換。本家 `LinearTransferEffect`。
/// パラメータ（実測）: 各チャンネルの YIntercept は Animation(既定 0,
/// -100000〜100000)、Slope は Animation(既定 100, -100000〜100000)。
public final class LinearTransferEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.LinearTransferEffect, YukkuriMovieMaker"
    }

    /// 赤の切片。
    public var redYIntercept = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 赤の傾き。
    public var redSlope = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)
    /// 緑の切片。
    public var greenYIntercept = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 緑の傾き。
    public var greenSlope = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)
    /// 青の切片。
    public var blueYIntercept = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 青の傾き。
    public var blueSlope = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)
    /// アルファの切片。
    public var alphaYIntercept = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// アルファの傾き。
    public var alphaSlope = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&redYIntercept)
        body(&redSlope)
        body(&greenYIntercept)
        body(&greenSlope)
        body(&blueYIntercept)
        body(&blueSlope)
        body(&alphaYIntercept)
        body(&alphaSlope)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "RedYIntercept":
            CodecSupport.decodeAnimation(value, into: &redYIntercept)
            return true
        case "RedSlope":
            CodecSupport.decodeAnimation(value, into: &redSlope)
            return true
        case "GreenYIntercept":
            CodecSupport.decodeAnimation(value, into: &greenYIntercept)
            return true
        case "GreenSlope":
            CodecSupport.decodeAnimation(value, into: &greenSlope)
            return true
        case "BlueYIntercept":
            CodecSupport.decodeAnimation(value, into: &blueYIntercept)
            return true
        case "BlueSlope":
            CodecSupport.decodeAnimation(value, into: &blueSlope)
            return true
        case "AlphaYIntercept":
            CodecSupport.decodeAnimation(value, into: &alphaYIntercept)
            return true
        case "AlphaSlope":
            CodecSupport.decodeAnimation(value, into: &alphaSlope)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "RedYIntercept", value: CodecSupport.encodeAnimation(redYIntercept)),
            (key: "RedSlope", value: CodecSupport.encodeAnimation(redSlope)),
            (key: "GreenYIntercept", value: CodecSupport.encodeAnimation(greenYIntercept)),
            (key: "GreenSlope", value: CodecSupport.encodeAnimation(greenSlope)),
            (key: "BlueYIntercept", value: CodecSupport.encodeAnimation(blueYIntercept)),
            (key: "BlueSlope", value: CodecSupport.encodeAnimation(blueSlope)),
            (key: "AlphaYIntercept", value: CodecSupport.encodeAnimation(alphaYIntercept)),
            (key: "AlphaSlope", value: CodecSupport.encodeAnimation(alphaSlope)),
        ] + super.encodeKnownFields()
    }
}

/// 単色化。本家 `MonocolorizationEffect`。
/// パラメータ（実測）: Strength は Animation(既定 100, 0〜100)、
/// Color は既定 白、KeepBrightness は bool（既定 true）。
public final class MonocolorizationEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.MonocolorizationEffect, YukkuriMovieMaker"
    }

    /// 単色化の強さ（%）。
    public var strength = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 基準の色。
    public var color: Color = .white
    /// 明るさを維持するか。
    public var keepBrightness: Bool = true

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&strength)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Strength":
            CodecSupport.decodeAnimation(value, into: &strength)
            return true
        case "Color":
            color = CodecSupport.color(value, default: .white)
            return true
        case "KeepBrightness":
            keepBrightness = CodecSupport.bool(value, default: true)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Strength", value: CodecSupport.encodeAnimation(strength)),
            (key: "Color", value: .string(color.honkeString)),
            (key: "KeepBrightness", value: .bool(keepBrightness)),
        ] + super.encodeKnownFields()
    }
}

/// ポスタリゼーション。本家 `PosterizeEffect`。
/// パラメータ（実測）: R / G / B は Animation(既定 4, 2〜16)。
public final class PosterizeEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.PosterizeEffect, YukkuriMovieMaker"
    }

    /// 赤の階調数。
    public var r = Animation(defaultValue: 4, minValue: 2, maxValue: 16)
    /// 緑の階調数。
    public var g = Animation(defaultValue: 4, minValue: 2, maxValue: 16)
    /// 青の階調数。
    public var b = Animation(defaultValue: 4, minValue: 2, maxValue: 16)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&r)
        body(&g)
        body(&b)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "R":
            CodecSupport.decodeAnimation(value, into: &r)
            return true
        case "G":
            CodecSupport.decodeAnimation(value, into: &g)
            return true
        case "B":
            CodecSupport.decodeAnimation(value, into: &b)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "R", value: CodecSupport.encodeAnimation(r)),
            (key: "G", value: CodecSupport.encodeAnimation(g)),
            (key: "B", value: CodecSupport.encodeAnimation(b)),
        ] + super.encodeKnownFields()
    }
}

/// セピア。本家 `SepiaEffect`。
/// パラメータ（実測）: Strength は Animation(既定 100, 0〜100)、
/// SepiaIntensity は Animation(既定 0.5, 0〜100)。旧互換の set 専用
/// `Intensity`（double）は読み込み時に SepiaIntensity の先頭値へ
/// 転送される（本家は `SepiaIntensity.From` への代入）。
public final class SepiaEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.SepiaEffect, YukkuriMovieMaker"
    }

    /// セピアの強さ（%）。
    public var strength = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// セピアの濃さ。
    public var sepiaIntensity = Animation(defaultValue: 0.5, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&strength)
        body(&sepiaIntensity)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Strength":
            CodecSupport.decodeAnimation(value, into: &strength)
            return true
        case "SepiaIntensity":
            CodecSupport.decodeAnimation(value, into: &sepiaIntensity)
            return true
        case "Intensity":
            // 旧互換（set 専用）: SepiaIntensity の先頭値へ転送される
            sepiaIntensity.setFirstValue(CodecSupport.double(value, default: 0))
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Strength", value: CodecSupport.encodeAnimation(strength)),
            (key: "SepiaIntensity", value: CodecSupport.encodeAnimation(sepiaIntensity)),
        ] + super.encodeKnownFields()
    }
}

/// 色調補正（単色）。本家 `TintEffect`。
/// パラメータ（実測）: Color は既定 白。
public final class TintEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.TintEffect, YukkuriMovieMaker"
    }

    /// 乗せる色。
    public var color: Color = .white

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Color":
            color = CodecSupport.color(value, default: .white)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Color", value: .string(color.honkeString)),
        ] + super.encodeKnownFields()
    }
}

/// ノイズ色ずれ。本家 `NoiseColorShiftEffect`。
/// パラメータ（実測）: Mode は DisplacementMapTransformMode（既定
/// Move）、Blur は Animation(既定 0, 0〜250)、NoiseType は既定 Perlin。
/// Transform（変形パラメータ）と NoiseParameter（ノイズパラメータ）は
/// 多態オブジェクトであり、プラグイン型のパラメータとして生保持に
/// 倒す。旧互換の set 専用 `X` / `Y` は Transform の内部へ転送される
/// もので、生保持の内部は書き換えないため、追加フィールドとして
/// そのまま保持する（変換は行わない）。
public final class NoiseColorShiftEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.NoiseColorShiftEffect, YukkuriMovieMaker"
    }

    /// 変形方式。
    public var mode: DisplacementMapTransformMode = .move
    /// 変形パラメータ（生保持。本家 `DisplacementMapTransformBase`）。
    public var transform: PreservedObject?
    /// ぼかし量。
    public var blur = Animation(defaultValue: 0, minValue: 0, maxValue: 250)
    /// ノイズの生成方式。
    public var noiseType: NoiseType = .perlin
    /// ノイズパラメータ（生保持。本家 `NoiseParameterBase`）。
    public var noiseParameter: PreservedObject?

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&blur)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Mode":
            mode = CodecSupport.enumeration(value, default: DisplacementMapTransformMode.move)
            return true
        case "Transform":
            transform = CodecSupport.preservedObject(value)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "NoiseType":
            noiseType = CodecSupport.enumeration(value, default: NoiseType.perlin)
            return true
        case "NoiseParameter":
            noiseParameter = CodecSupport.preservedObject(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Mode", value: .string(mode.honkeName)),
        ]
        if let transform {
            fields.append((key: "Transform", value: transform.value))
        }
        fields.append((key: "Blur", value: CodecSupport.encodeAnimation(blur)))
        fields.append((key: "NoiseType", value: .string(noiseType.honkeName)))
        if let noiseParameter {
            fields.append((key: "NoiseParameter", value: noiseParameter.value))
        }
        return fields + super.encodeKnownFields()
    }
}
