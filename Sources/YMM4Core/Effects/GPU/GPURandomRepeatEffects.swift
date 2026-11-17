import Foundation

// GPU 処理系のランダム系・反復系エフェクトの定義層。
//
// 本家の Random / Repeat 基底は DrawDescription 変換群にも同系統の
// エフェクトがあるため、その定義基底（`RandomEffectDefinitionBase` /
// `RepeatEffectDefinitionBase`）を継承し、パラメータの受け口だけを
// 引き継ぐ。処理器は本家の DrawDescription 変換とは異なる（GPU 側で
// 描画時に評価される）ため、次段の GPU 処理器が入るまでは暫定の
// 素通し（`GPUEffectPassthroughProcessor`）を返す。パラメータは
// 本家定義クラスの実測に基づく。

/// ランダム回転。本家 `RandomRotateEffect`。
/// パラメータ（実測）: X / Y は Animation(既定 0, 0〜100000)、
/// Z は Animation(既定 30, 0〜100000)、Is3D は bool（既定 false）
/// ＋ Random 基底（Span）。
public final class RandomRotateEffectDefinition: RandomEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RandomRotateEffect, YukkuriMovieMaker"
    }

    /// X 軸の最大回転角。
    public var x = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// Y 軸の最大回転角。
    public var y = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// Z 軸の最大回転角。
    public var z = Animation(defaultValue: 30, minValue: 0, maxValue: 100000)
    /// 3D 回転にするか。
    public var is3D: Bool = false

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&z)
        super.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "Z":
            CodecSupport.decodeAnimation(value, into: &z)
            return true
        case "Is3D":
            is3D = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "Is3D", value: .bool(is3D)),
        ] + super.encodeKnownFields()
    }
}

/// ランダム傾斜。本家 `RandomSkewEffect`。
/// パラメータ（実測）: AngleX / AngleY / CenterX / CenterY は
/// Animation(既定 0, -100000〜100000)、CenterPoint は
/// SkewCenterPoint（既定 Center）＋ Random 基底。
public final class RandomSkewEffectDefinition: RandomEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RandomSkewEffect, YukkuriMovieMaker"
    }

    /// X 方向の最大傾斜角度。
    public var angleX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 方向の最大傾斜角度。
    public var angleY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 中心点。
    public var centerPoint: SkewCenterPoint = .center
    /// 中心 X（Custom のとき）。
    public var centerX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 中心 Y（Custom のとき）。
    public var centerY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&angleX)
        body(&angleY)
        body(&centerX)
        body(&centerY)
        super.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "AngleX":
            CodecSupport.decodeAnimation(value, into: &angleX)
            return true
        case "AngleY":
            CodecSupport.decodeAnimation(value, into: &angleY)
            return true
        case "CenterPoint":
            centerPoint = CodecSupport.enumeration(value, default: SkewCenterPoint.center)
            return true
        case "CenterX":
            CodecSupport.decodeAnimation(value, into: &centerX)
            return true
        case "CenterY":
            CodecSupport.decodeAnimation(value, into: &centerY)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "AngleX", value: CodecSupport.encodeAnimation(angleX)),
            (key: "AngleY", value: CodecSupport.encodeAnimation(angleY)),
            (key: "CenterPoint", value: .string(centerPoint.honkeName)),
            (key: "CenterX", value: CodecSupport.encodeAnimation(centerX)),
            (key: "CenterY", value: CodecSupport.encodeAnimation(centerY)),
        ] + super.encodeKnownFields()
    }
}

/// 反復回転。本家 `RepeatRotateEffect`。
/// パラメータ（実測）: X / Y は Animation(既定 0, -100000〜100000)、
/// Z は Animation(既定 30, -100000〜100000)、Is3D は bool
/// （既定 false）＋ Repeat 基底（Span 等）。
public final class RepeatRotateEffectDefinition: RepeatEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RepeatRotateEffect, YukkuriMovieMaker"
    }

    /// X 軸回転。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 軸回転。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Z 軸回転。
    public var z = Animation(defaultValue: 30, minValue: -100000, maxValue: 100000)
    /// 3D 回転にするか。
    public var is3D: Bool = false

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&z)
        super.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "Z":
            CodecSupport.decodeAnimation(value, into: &z)
            return true
        case "Is3D":
            is3D = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "Is3D", value: .bool(is3D)),
        ] + super.encodeKnownFields()
    }
}

/// 反復傾斜。本家 `RepeatSkewEffect`。
/// パラメータ（実測）: AngleX / AngleY / CenterX / CenterY は
/// Animation(既定 0, -100000〜100000)、CenterPoint は
/// SkewCenterPoint（既定 Center）＋ Repeat 基底。
public final class RepeatSkewEffectDefinition: RepeatEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RepeatSkewEffect, YukkuriMovieMaker"
    }

    /// X 方向の傾斜角度。
    public var angleX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 方向の傾斜角度。
    public var angleY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 中心点。
    public var centerPoint: SkewCenterPoint = .center
    /// 中心 X（Custom のとき）。
    public var centerX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 中心 Y（Custom のとき）。
    public var centerY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&angleX)
        body(&angleY)
        body(&centerX)
        body(&centerY)
        super.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "AngleX":
            CodecSupport.decodeAnimation(value, into: &angleX)
            return true
        case "AngleY":
            CodecSupport.decodeAnimation(value, into: &angleY)
            return true
        case "CenterPoint":
            centerPoint = CodecSupport.enumeration(value, default: SkewCenterPoint.center)
            return true
        case "CenterX":
            CodecSupport.decodeAnimation(value, into: &centerX)
            return true
        case "CenterY":
            CodecSupport.decodeAnimation(value, into: &centerY)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "AngleX", value: CodecSupport.encodeAnimation(angleX)),
            (key: "AngleY", value: CodecSupport.encodeAnimation(angleY)),
            (key: "CenterPoint", value: .string(centerPoint.honkeName)),
            (key: "CenterX", value: CodecSupport.encodeAnimation(centerX)),
            (key: "CenterY", value: CodecSupport.encodeAnimation(centerY)),
        ] + super.encodeKnownFields()
    }
}
