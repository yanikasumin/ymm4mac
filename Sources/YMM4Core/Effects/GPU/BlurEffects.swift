import Foundation

// GPU 処理系のぼかし・質感・ハーフトーン系エフェクトの定義層。
//
// いずれも処理器は暫定の素通し（`GPUEffectDefinitionBase` が返す
// `GPUEffectPassthroughProcessor`）であり、画像の加工はまだ行われない。
// パラメータの型・既定値・範囲は本家定義クラスの実測に基づく。

/// 境界ぼかし。本家 `BorderBlurEffect`。
/// パラメータ（実測）: Blur は Animation(既定 10, 0〜250)。
public final class BorderBlurEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.BorderBlurEffect, YukkuriMovieMaker"
    }

    /// ぼかし量。
    public var blur = Animation(defaultValue: 10, minValue: 0, maxValue: 250)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&blur)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
        ] + super.encodeKnownFields()
    }
}

/// 方向ぼかし。本家 `DirectionalBlurEffect`。
/// パラメータ（実測）: StandardDeviation は Animation(既定 100,
/// 0〜250)、Angle は Animation(既定 0, -100000〜100000)、
/// IsHardBorderMode は bool（既定 false）。
public final class DirectionalBlurEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.DirectionalBlurEffect, YukkuriMovieMaker"
    }

    /// ぼかしの標準偏差。
    public var standardDeviation = Animation(defaultValue: 100, minValue: 0, maxValue: 250)
    /// 方向の角度。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 境界を硬くするか。
    public var isHardBorderMode: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&standardDeviation)
        body(&angle)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "StandardDeviation":
            CodecSupport.decodeAnimation(value, into: &standardDeviation)
            return true
        case "Angle":
            CodecSupport.decodeAnimation(value, into: &angle)
            return true
        case "IsHardBorderMode":
            isHardBorderMode = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "StandardDeviation", value: CodecSupport.encodeAnimation(standardDeviation)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "IsHardBorderMode", value: .bool(isHardBorderMode)),
        ] + super.encodeKnownFields()
    }
}

/// ガウスぼかし。本家 `GaussianBlurEffect`。
/// パラメータ（実測）: Blur は Animation(既定 10, 0〜250)、
/// IsHardBorderMode は bool（既定 false）。
public final class GaussianBlurEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.GaussianBlurEffect, YukkuriMovieMaker"
    }

    /// ぼかし量。
    public var blur = Animation(defaultValue: 10, minValue: 0, maxValue: 250)
    /// 境界を硬くするか。
    public var isHardBorderMode: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&blur)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "IsHardBorderMode":
            isHardBorderMode = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "IsHardBorderMode", value: .bool(isHardBorderMode)),
        ] + super.encodeKnownFields()
    }
}

/// 放射ぼかし。本家 `RadialBlurEffect`。
/// パラメータ（実測）: Blur は Animation(既定 10, 0〜75)、
/// X / Y は Animation(既定 0, -100000〜100000)、IsHardBorderMode は
/// bool（既定 false）。
public final class RadialBlurEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RadialBlurEffect, YukkuriMovieMaker"
    }

    /// ぼかし量。
    public var blur = Animation(defaultValue: 10, minValue: 0, maxValue: 75)
    /// 中心 X。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 中心 Y。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 境界を硬くするか。
    public var isHardBorderMode: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&blur)
        body(&x)
        body(&y)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "IsHardBorderMode":
            isHardBorderMode = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "IsHardBorderMode", value: .bool(isHardBorderMode)),
        ] + super.encodeKnownFields()
    }
}

/// シャープ。本家 `SharpenEffect`。
/// パラメータ（実測）: Sharpness は Animation(既定 0, 0〜10)、
/// Threshold は Animation(既定 0, 0〜100)。
public final class SharpenEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.SharpenEffect, YukkuriMovieMaker"
    }

    /// 鋭さ。
    public var sharpness = Animation(defaultValue: 0, minValue: 0, maxValue: 10)
    /// 閾値。
    public var threshold = Animation(defaultValue: 0, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&sharpness)
        body(&threshold)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Sharpness":
            CodecSupport.decodeAnimation(value, into: &sharpness)
            return true
        case "Threshold":
            CodecSupport.decodeAnimation(value, into: &threshold)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Sharpness", value: CodecSupport.encodeAnimation(sharpness)),
            (key: "Threshold", value: CodecSupport.encodeAnimation(threshold)),
        ] + super.encodeKnownFields()
    }
}

/// モザイク。本家 `MosaicEffect`。
/// パラメータ（実測）: MosaicType は既定 Rectangle。MosaicParameter は
/// 形状ごとのパラメータ（多態オブジェクト）であり、プラグイン型の
/// パラメータとして生保持に倒す。
public final class MosaicEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.MosaicEffect, YukkuriMovieMaker"
    }

    /// モザイクの形状。
    public var mosaicType: MosaicType = .rectangle
    /// 形状パラメータ（生保持。本家 `MosaicParameterBase`）。
    public var mosaicParameter: PreservedObject?

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "MosaicType":
            mosaicType = CodecSupport.enumeration(value, default: MosaicType.rectangle)
            return true
        case "MosaicParameter":
            mosaicParameter = CodecSupport.preservedObject(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "MosaicType", value: .string(mosaicType.honkeName)),
        ]
        if let mosaicParameter {
            fields.append((key: "MosaicParameter", value: mosaicParameter.value))
        }
        return fields + super.encodeKnownFields()
    }
}

/// ハーフトーン境界ぼかし。本家 `HalfToneBorderBlurEffect`。
/// パラメータ（実測）: Blur は Animation(既定 10, 0〜250)、Layout は
/// HalfToneLayout（既定 Rhombus）、Distance は Animation(既定 5,
/// 0.1〜500)、Size / Strength は Animation(既定 100, 0〜100)。
public final class HalfToneBorderBlurEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.HalfToneBorderBlurEffect, YukkuriMovieMaker"
    }

    /// ぼかし量。
    public var blur = Animation(defaultValue: 10, minValue: 0, maxValue: 250)
    /// ハーフトーンの配置。
    public var layout: HalfToneLayout = .rhombus
    /// 点の間隔。
    public var distance = Animation(defaultValue: 5, minValue: 0.1, maxValue: 500)
    /// 点の大きさ（%）。
    public var size = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 強さ（%）。
    public var strength = Animation(defaultValue: 100, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&blur)
        body(&distance)
        body(&size)
        body(&strength)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "Layout":
            layout = CodecSupport.enumeration(value, default: HalfToneLayout.rhombus)
            return true
        case "Distance":
            CodecSupport.decodeAnimation(value, into: &distance)
            return true
        case "Size":
            CodecSupport.decodeAnimation(value, into: &size)
            return true
        case "Strength":
            CodecSupport.decodeAnimation(value, into: &strength)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "Layout", value: .string(layout.honkeName)),
            (key: "Distance", value: CodecSupport.encodeAnimation(distance)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
            (key: "Strength", value: CodecSupport.encodeAnimation(strength)),
        ] + super.encodeKnownFields()
    }
}

/// ハーフトーン。本家 `HalfToneEffect`。
/// パラメータ（実測）: Layout は HalfToneLayout（既定 Rhombus）、
/// Distance は Animation(既定 5, 0.1〜500)、Size / Strength は
/// Animation(既定 100, 0〜100)、Color は既定 白。
public final class HalfToneEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.HalfToneEffect, YukkuriMovieMaker"
    }

    /// ハーフトーンの配置。
    public var layout: HalfToneLayout = .rhombus
    /// 点の間隔。
    public var distance = Animation(defaultValue: 5, minValue: 0.1, maxValue: 500)
    /// 点の大きさ（%）。
    public var size = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 点の色。
    public var color: Color = .white
    /// 強さ（%）。
    public var strength = Animation(defaultValue: 100, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&distance)
        body(&size)
        body(&strength)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Layout":
            layout = CodecSupport.enumeration(value, default: HalfToneLayout.rhombus)
            return true
        case "Distance":
            CodecSupport.decodeAnimation(value, into: &distance)
            return true
        case "Size":
            CodecSupport.decodeAnimation(value, into: &size)
            return true
        case "Color":
            color = CodecSupport.color(value, default: .white)
            return true
        case "Strength":
            CodecSupport.decodeAnimation(value, into: &strength)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Layout", value: .string(layout.honkeName)),
            (key: "Distance", value: CodecSupport.encodeAnimation(distance)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
            (key: "Color", value: .string(color.honkeString)),
            (key: "Strength", value: CodecSupport.encodeAnimation(strength)),
        ] + super.encodeKnownFields()
    }
}

/// ハーフトーン輪郭。本家 `HalfToneOutlineEffect`。
/// パラメータ（実測）: StrokeThickness は Animation(既定 20, 0〜500)、
/// Opacity は Animation(既定 100, 0〜100)、Blur は Animation(既定 10,
/// 0〜1000)、IsOutlineOnly は bool（既定 false）、Layout は
/// HalfToneLayout（既定 Rhombus）、Distance は Animation(既定 15,
/// 0.1〜500)、Size は Animation(既定 100, 0〜100)、Color は既定 白、
/// Strength は Animation(既定 0, 0〜100)。
public final class HalfToneOutlineEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.HalfToneOutlineEffect, YukkuriMovieMaker"
    }

    /// 輪郭の太さ。
    public var strokeThickness = Animation(defaultValue: 20, minValue: 0, maxValue: 500)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// ぼかし量。
    public var blur = Animation(defaultValue: 10, minValue: 0, maxValue: 1000)
    /// 輪郭だけを残すか。
    public var isOutlineOnly: Bool = false
    /// ハーフトーンの配置。
    public var layout: HalfToneLayout = .rhombus
    /// 点の間隔。
    public var distance = Animation(defaultValue: 15, minValue: 0.1, maxValue: 500)
    /// 点の大きさ（%）。
    public var size = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 点の色。
    public var color: Color = .white
    /// 強さ（%）。
    public var strength = Animation(defaultValue: 0, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&strokeThickness)
        body(&opacity)
        body(&blur)
        body(&distance)
        body(&size)
        body(&strength)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "StrokeThickness":
            CodecSupport.decodeAnimation(value, into: &strokeThickness)
            return true
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "IsOutlineOnly":
            isOutlineOnly = CodecSupport.bool(value, default: false)
            return true
        case "Layout":
            layout = CodecSupport.enumeration(value, default: HalfToneLayout.rhombus)
            return true
        case "Distance":
            CodecSupport.decodeAnimation(value, into: &distance)
            return true
        case "Size":
            CodecSupport.decodeAnimation(value, into: &size)
            return true
        case "Color":
            color = CodecSupport.color(value, default: .white)
            return true
        case "Strength":
            CodecSupport.decodeAnimation(value, into: &strength)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "StrokeThickness", value: CodecSupport.encodeAnimation(strokeThickness)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "IsOutlineOnly", value: .bool(isOutlineOnly)),
            (key: "Layout", value: .string(layout.honkeName)),
            (key: "Distance", value: CodecSupport.encodeAnimation(distance)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
            (key: "Color", value: .string(color.honkeString)),
            (key: "Strength", value: CodecSupport.encodeAnimation(strength)),
        ] + super.encodeKnownFields()
    }
}

/// ハーフトーン影。本家 `HalfToneShadowEffect`。
/// パラメータ（実測）: X / Y / Angle は Animation(既定 0,
/// -100000〜100000)、Opacity は Animation(既定 100, 0〜100)、Blur は
/// Animation(既定 3, 0〜250)、Layout は HalfToneLayout（既定 Rhombus）、
/// Distance は Animation(既定 5, 0.1〜500)、Size / Strength は
/// Animation(既定 100, 0〜100)、Color は既定 白、KeepBrightness /
/// IsRotateAtCenter は bool（既定 false）。
public final class HalfToneShadowEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.HalfToneShadowEffect, YukkuriMovieMaker"
    }

    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 角度。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// ぼかし量。
    public var blur = Animation(defaultValue: 3, minValue: 0, maxValue: 250)
    /// ハーフトーンの配置。
    public var layout: HalfToneLayout = .rhombus
    /// 点の間隔。
    public var distance = Animation(defaultValue: 5, minValue: 0.1, maxValue: 500)
    /// 点の大きさ（%）。
    public var size = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 影の色。
    public var color: Color = .white
    /// 強さ（%）。
    public var strength = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 明るさを維持するか。
    public var keepBrightness: Bool = false
    /// 中心で回転するか。
    public var isRotateAtCenter: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&opacity)
        body(&angle)
        body(&blur)
        body(&distance)
        body(&size)
        body(&strength)
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
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "Layout":
            layout = CodecSupport.enumeration(value, default: HalfToneLayout.rhombus)
            return true
        case "Distance":
            CodecSupport.decodeAnimation(value, into: &distance)
            return true
        case "Size":
            CodecSupport.decodeAnimation(value, into: &size)
            return true
        case "Color":
            color = CodecSupport.color(value, default: .white)
            return true
        case "Strength":
            CodecSupport.decodeAnimation(value, into: &strength)
            return true
        case "KeepBrightness":
            keepBrightness = CodecSupport.bool(value, default: false)
            return true
        case "IsRotateAtCenter":
            isRotateAtCenter = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "Layout", value: .string(layout.honkeName)),
            (key: "Distance", value: CodecSupport.encodeAnimation(distance)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
            (key: "Color", value: .string(color.honkeString)),
            (key: "Strength", value: CodecSupport.encodeAnimation(strength)),
            (key: "KeepBrightness", value: .bool(keepBrightness)),
            (key: "IsRotateAtCenter", value: .bool(isRotateAtCenter)),
        ] + super.encodeKnownFields()
    }
}

/// 内側ハーフトーン影。本家 `InnerHalfToneShadowEffect`。
/// パラメータ（実測）: X / Y は Animation(既定 0, -100000〜100000)、
/// Opacity は Animation(既定 100, 0〜100)、Blur は Animation(既定 20,
/// 0〜250)、BlendMode は Blend（既定 Normal）、Layout は
/// HalfToneLayout（既定 Rhombus）、Distance は Animation(既定 5,
/// 0.1〜500)、Size / Strength は Animation(既定 100, 0〜100)、
/// Color は既定 白。
public final class InnerHalfToneShadowEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InnerHalfToneShadowEffect, YukkuriMovieMaker"
    }

    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// ぼかし量。
    public var blur = Animation(defaultValue: 20, minValue: 0, maxValue: 250)
    /// 合成方法。
    public var blendMode: Blend = .normal
    /// ハーフトーンの配置。
    public var layout: HalfToneLayout = .rhombus
    /// 点の間隔。
    public var distance = Animation(defaultValue: 5, minValue: 0.1, maxValue: 500)
    /// 点の大きさ（%）。
    public var size = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 影の色。
    public var color: Color = .white
    /// 強さ（%）。
    public var strength = Animation(defaultValue: 100, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&opacity)
        body(&blur)
        body(&distance)
        body(&size)
        body(&strength)
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
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "BlendMode":
            blendMode = CodecSupport.enumeration(value, default: Blend.normal)
            return true
        case "Layout":
            layout = CodecSupport.enumeration(value, default: HalfToneLayout.rhombus)
            return true
        case "Distance":
            CodecSupport.decodeAnimation(value, into: &distance)
            return true
        case "Size":
            CodecSupport.decodeAnimation(value, into: &size)
            return true
        case "Color":
            color = CodecSupport.color(value, default: .white)
            return true
        case "Strength":
            CodecSupport.decodeAnimation(value, into: &strength)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "BlendMode", value: .string(blendMode.honkeName)),
            (key: "Layout", value: .string(layout.honkeName)),
            (key: "Distance", value: CodecSupport.encodeAnimation(distance)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
            (key: "Color", value: .string(color.honkeString)),
            (key: "Strength", value: CodecSupport.encodeAnimation(strength)),
        ] + super.encodeKnownFields()
    }
}

/// 放射光。本家 `RadialLightEffect`。
/// パラメータ（実測）: Value は Animation(既定 10, 0〜100)、
/// X / Y は Animation(既定 0, -100000〜100000)、IsHardBorderMode は
/// bool（既定 false）。
public final class RadialLightEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RadialLightEffect, YukkuriMovieMaker"
    }

    /// 光の強さ。
    public var value = Animation(defaultValue: 10, minValue: 0, maxValue: 100)
    /// 中心 X。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 中心 Y。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 境界を硬くするか。
    public var isHardBorderMode: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&value)
        body(&x)
        body(&y)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            CodecSupport.decodeAnimation(value, into: &self.value)
            return true
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "IsHardBorderMode":
            isHardBorderMode = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Value", value: CodecSupport.encodeAnimation(value)),
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "IsHardBorderMode", value: .bool(isHardBorderMode)),
        ] + super.encodeKnownFields()
    }
}
