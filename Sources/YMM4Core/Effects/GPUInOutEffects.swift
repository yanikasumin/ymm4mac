import Foundation

// GPU 処理系の入出場エフェクトの定義層。
//
// 処理器はいずれも暫定の素通し（`GPUEffectPassthroughProcessor`）
// であり、本家の GPU 処理はまだ行われない。本家の `InOutEffectBase`
// を継承するものは `InOutEffectDefinitionBase` を土台にパラメータを
// 引き継ぎ、`createProcessor()` だけを暫定処理器へ差し替える。
// `InOutCrashEffect` / `InOutJumpEffect` / `InOutTransitionEffect` は
// 本家でも VideoEffectBase 直系で入出場パラメータを自前で持つため、
// その形に合わせる。パラメータは本家定義クラスの実測に基づく。

/// 入出場境界ぼかし。本家 `InOutBorderBlurEffect`。
/// パラメータ（実測）: Value は double（既定 10）＋ InOut 基底。
public final class InOutBorderBlurEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutBorderBlurEffect, YukkuriMovieMaker"
    }

    /// ぼかし量。
    public var value: Double = 10

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            self.value = CodecSupport.double(value, default: 10)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Value", value: .number(value)),
        ] + super.encodeKnownFields()
    }
}

/// 入出場ガウスぼかし。本家 `InOutGaussianBlurEffect`。
/// パラメータ（実測）: Value は double（既定 3）＋ InOut 基底。
public final class InOutGaussianBlurEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutGaussianBlurEffect, YukkuriMovieMaker"
    }

    /// ぼかし量。
    public var value: Double = 3

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            self.value = CodecSupport.double(value, default: 3)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Value", value: .number(value)),
        ] + super.encodeKnownFields()
    }
}

/// 入出場モザイク。本家 `InOutMosaicEffect`。
/// パラメータ（実測）: Value は double（既定 10）＋ InOut 基底。
public final class InOutMosaicEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutMosaicEffect, YukkuriMovieMaker"
    }

    /// モザイクの大きさ。
    public var value: Double = 10

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            self.value = CodecSupport.double(value, default: 10)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Value", value: .number(value)),
        ] + super.encodeKnownFields()
    }
}

/// 画像外からの入出場移動。本家 `InOutMoveFromOutsideImageEffect`。
/// パラメータ（実測）: Value は TopBottomLeftRight（既定 Left）
/// ＋ InOut 基底。
public final class InOutMoveFromOutsideImageEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutMoveFromOutsideImageEffect, YukkuriMovieMaker"
    }

    /// 画像外の方向。
    public var value: TopBottomLeftRight = .left

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            self.value = CodecSupport.enumeration(value, default: TopBottomLeftRight.left)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Value", value: .string(value.honkeName)),
        ] + super.encodeKnownFields()
    }
}

/// 起き上がり。本家 `InOutGetUpEffect`。
/// パラメータ（実測）: Base は InOutGetUpBaseLine（既定 Bottom）、
/// Direction は InOutGetUpDirection（既定 Back)、Is3D は bool
/// （既定 false）＋ InOut 基底。
public final class InOutGetUpEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutGetUpEffect, YukkuriMovieMaker"
    }

    /// 基準線。
    public var base: InOutGetUpBaseLine = .bottom
    /// 起き上がる方向。
    public var direction: InOutGetUpDirection = .back
    /// 3D にするか。
    public var is3D: Bool = false

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Base":
            base = CodecSupport.enumeration(value, default: InOutGetUpBaseLine.bottom)
            return true
        case "Direction":
            direction = CodecSupport.enumeration(value, default: InOutGetUpDirection.back)
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
            (key: "Base", value: .string(base.honkeName)),
            (key: "Direction", value: .string(direction.honkeName)),
            (key: "Is3D", value: .bool(is3D)),
        ] + super.encodeKnownFields()
    }
}

/// 入出場回転。本家 `InOutRotateEffect`。
/// パラメータ（実測）: ValueX / ValueY は double（既定 0)、ValueZ は
/// double（既定 90)、Is3D は bool（既定 false）＋ InOut 基底。
/// set 専用の `Value` は読み込み時に ValueZ へ転送される。
public final class InOutRotateEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutRotateEffect, YukkuriMovieMaker"
    }

    /// X 軸回転。
    public var valueX: Double = 0
    /// Y 軸回転。
    public var valueY: Double = 0
    /// Z 軸回転。
    public var valueZ: Double = 90
    /// 3D 回転にするか。
    public var is3D: Bool = false

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "ValueX":
            valueX = CodecSupport.double(value, default: 0)
            return true
        case "ValueY":
            valueY = CodecSupport.double(value, default: 0)
            return true
        case "ValueZ":
            valueZ = CodecSupport.double(value, default: 90)
            return true
        case "Is3D":
            is3D = CodecSupport.bool(value, default: false)
            return true
        case "Value":
            // set 専用: ValueZ へ転送される
            valueZ = CodecSupport.double(value, default: valueZ)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "ValueX", value: .number(valueX)),
            (key: "ValueY", value: .number(valueY)),
            (key: "ValueZ", value: .number(valueZ)),
            (key: "Is3D", value: .bool(is3D)),
        ] + super.encodeKnownFields()
    }
}

/// 入出場傾斜。本家 `InOutSkewEffect`。
/// パラメータ（実測）: AngleX / AngleY / CenterX / CenterY は
/// double（既定 0)、CenterPoint は SkewCenterPoint（既定 Center）
/// ＋ InOut 基底。
public final class InOutSkewEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutSkewEffect, YukkuriMovieMaker"
    }

    /// X 方向の傾斜角度。
    public var angleX: Double = 0
    /// Y 方向の傾斜角度。
    public var angleY: Double = 0
    /// 中心点。
    public var centerPoint: SkewCenterPoint = .center
    /// 中心 X（Custom のとき）。
    public var centerX: Double = 0
    /// 中心 Y（Custom のとき）。
    public var centerY: Double = 0

    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "AngleX":
            angleX = CodecSupport.double(value, default: 0)
            return true
        case "AngleY":
            angleY = CodecSupport.double(value, default: 0)
            return true
        case "CenterPoint":
            centerPoint = CodecSupport.enumeration(value, default: SkewCenterPoint.center)
            return true
        case "CenterX":
            centerX = CodecSupport.double(value, default: 0)
            return true
        case "CenterY":
            centerY = CodecSupport.double(value, default: 0)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "AngleX", value: .number(angleX)),
            (key: "AngleY", value: .number(angleY)),
            (key: "CenterPoint", value: .string(centerPoint.honkeName)),
            (key: "CenterX", value: .number(centerX)),
            (key: "CenterY", value: .number(centerY)),
        ] + super.encodeKnownFields()
    }
}

/// 入出場崩壊。本家 `InOutCrashEffect`。
/// 本家でも `InOutEffectBase` ではなく `VideoEffectBase` 直系で、
/// 入出場パラメータを自前で持つ。パラメータ（実測）: IsInEffect /
/// IsOutEffect は bool（既定 true)、EffectTimeSeconds は double
/// （既定 3)、PlaybackRate / FlySpeed / FallSpeed / Delay / Impact /
/// RandomRotate / RandomVector は double（既定 100)、Size は double
/// （既定 50)、X / Y / Z は Animation(既定 0, -100000〜100000)。
public final class InOutCrashEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutCrashEffect, YukkuriMovieMaker"
    }

    /// イン側を有効にするか。
    public var isInEffect: Bool = true
    /// アウト側を有効にするか。
    public var isOutEffect: Bool = true
    /// イン／アウトにかける時間（秒）。
    public var effectTimeSeconds: Double = 3
    /// 再生速度（%）。
    public var playbackRate: Double = 100
    /// 大きさ（%）。
    public var size: Double = 50
    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Z 座標。
    public var z = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 飛散速度（%）。
    public var flySpeed: Double = 100
    /// 落下速度（%）。
    public var fallSpeed: Double = 100
    /// 遅延（%）。
    public var delay: Double = 100
    /// 衝撃（%）。
    public var impact: Double = 100
    /// ランダムな回転（%）。
    public var randomRotate: Double = 100
    /// ランダムな方向（%）。
    public var randomVector: Double = 100

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&z)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsInEffect":
            isInEffect = CodecSupport.bool(value, default: true)
            return true
        case "IsOutEffect":
            isOutEffect = CodecSupport.bool(value, default: true)
            return true
        case "EffectTimeSeconds":
            effectTimeSeconds = CodecSupport.double(value, default: 3)
            return true
        case "PlaybackRate":
            playbackRate = CodecSupport.double(value, default: 100)
            return true
        case "Size":
            size = CodecSupport.double(value, default: 50)
            return true
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "Z":
            CodecSupport.decodeAnimation(value, into: &z)
            return true
        case "FlySpeed":
            flySpeed = CodecSupport.double(value, default: 100)
            return true
        case "FallSpeed":
            fallSpeed = CodecSupport.double(value, default: 100)
            return true
        case "Delay":
            delay = CodecSupport.double(value, default: 100)
            return true
        case "Impact":
            impact = CodecSupport.double(value, default: 100)
            return true
        case "RandomRotate":
            randomRotate = CodecSupport.double(value, default: 100)
            return true
        case "RandomVector":
            randomVector = CodecSupport.double(value, default: 100)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "IsInEffect", value: .bool(isInEffect)),
            (key: "IsOutEffect", value: .bool(isOutEffect)),
            (key: "EffectTimeSeconds", value: .number(effectTimeSeconds)),
            (key: "PlaybackRate", value: .number(playbackRate)),
            (key: "Size", value: .number(size)),
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "FlySpeed", value: .number(flySpeed)),
            (key: "FallSpeed", value: .number(fallSpeed)),
            (key: "Delay", value: .number(delay)),
            (key: "Impact", value: .number(impact)),
            (key: "RandomRotate", value: .number(randomRotate)),
            (key: "RandomVector", value: .number(randomVector)),
        ] + super.encodeKnownFields()
    }
}

/// 入出場ジャンプ。本家 `InOutJumpEffect`。
/// 本家でも `VideoEffectBase` 直系で入出場パラメータを自前で持つ。
/// パラメータ（実測）: IsInEffect / IsOutEffect / IsOutReverse は
/// bool（既定 true)、IsInReverse は bool（既定 false)、
/// EffectTimeSeconds は double（既定 3)、JumpHeight は double
/// （既定 100)、Stretch は double（既定 10)、Period は double
/// （既定 0.5)、Distortion は double（既定 25)、Interval は double
/// （既定 0.3)、X は double（既定 1000)、Y は double（既定 0)。
public final class InOutJumpEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutJumpEffect, YukkuriMovieMaker"
    }

    /// イン側を有効にするか。
    public var isInEffect: Bool = true
    /// イン側を逆転させるか。
    public var isInReverse: Bool = false
    /// アウト側を有効にするか。
    public var isOutEffect: Bool = true
    /// アウト側を逆転させるか。
    public var isOutReverse: Bool = true
    /// イン／アウトにかける時間（秒）。
    public var effectTimeSeconds: Double = 3
    /// ジャンプの高さ。
    public var jumpHeight: Double = 100
    /// 伸縮量。
    public var stretch: Double = 10
    /// 周期（秒）。
    public var period: Double = 0.5
    /// 歪み量。
    public var distortion: Double = 25
    /// 間隔（秒）。
    public var interval: Double = 0.3
    /// X の移動量。
    public var x: Double = 1000
    /// Y の移動量。
    public var y: Double = 0

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsInEffect":
            isInEffect = CodecSupport.bool(value, default: true)
            return true
        case "IsInReverse":
            isInReverse = CodecSupport.bool(value, default: false)
            return true
        case "IsOutEffect":
            isOutEffect = CodecSupport.bool(value, default: true)
            return true
        case "IsOutReverse":
            isOutReverse = CodecSupport.bool(value, default: true)
            return true
        case "EffectTimeSeconds":
            effectTimeSeconds = CodecSupport.double(value, default: 3)
            return true
        case "JumpHeight":
            jumpHeight = CodecSupport.double(value, default: 100)
            return true
        case "Stretch":
            stretch = CodecSupport.double(value, default: 10)
            return true
        case "Period":
            period = CodecSupport.double(value, default: 0.5)
            return true
        case "Distortion":
            distortion = CodecSupport.double(value, default: 25)
            return true
        case "Interval":
            interval = CodecSupport.double(value, default: 0.3)
            return true
        case "X":
            x = CodecSupport.double(value, default: 1000)
            return true
        case "Y":
            y = CodecSupport.double(value, default: 0)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "IsInEffect", value: .bool(isInEffect)),
            (key: "IsInReverse", value: .bool(isInReverse)),
            (key: "IsOutEffect", value: .bool(isOutEffect)),
            (key: "IsOutReverse", value: .bool(isOutReverse)),
            (key: "EffectTimeSeconds", value: .number(effectTimeSeconds)),
            (key: "JumpHeight", value: .number(jumpHeight)),
            (key: "Stretch", value: .number(stretch)),
            (key: "Period", value: .number(period)),
            (key: "Distortion", value: .number(distortion)),
            (key: "Interval", value: .number(interval)),
            (key: "X", value: .number(x)),
            (key: "Y", value: .number(y)),
        ] + super.encodeKnownFields()
    }
}

/// 入出場トランジション。本家 `InOutTransitionEffect`。
/// 本家でも `VideoEffectBase` 直系で入出場パラメータを自前で持つ。
/// パラメータ（実測）: File は既定 null、Tolerance は Animation
/// (既定 3, -50〜450)、Angle は Animation(既定 0, -100000〜100000)、
/// KeepAspect / IsInEffect / IsOutEffect は bool（既定 true)、
/// IsFixedCoveringScale / IsReversedInEffect / IsReversedOutEffect
/// は bool（既定 false)、EffectTimeSeconds は double（既定 1)、
/// EasingType は既定 Linear、EasingMode は既定 InOut。
public final class InOutTransitionEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutTransitionEffect, YukkuriMovieMaker"
    }

    /// ルール画像のファイルパス（未指定は nil）。
    public var file: String?
    /// 許容量。
    public var tolerance = Animation(defaultValue: 3, minValue: -50, maxValue: 450)
    /// 角度。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// アスペクト比を維持するか。
    public var keepAspect: Bool = true
    /// 覆う拡大率を固定するか。
    public var isFixedCoveringScale: Bool = false
    /// イン側を有効にするか。
    public var isInEffect: Bool = true
    /// イン側を反転させるか。
    public var isReversedInEffect: Bool = false
    /// アウト側を有効にするか。
    public var isOutEffect: Bool = true
    /// アウト側を反転させるか。
    public var isReversedOutEffect: Bool = false
    /// イン／アウトにかける時間（秒）。
    public var effectTimeSeconds: Double = 1
    /// イージングの種類。
    public var easingFamily: EasingFamily = .linear
    /// イージングの方式。
    public var easingMode: EasingMode = .inOut

    /// 未知の EasingType 名の原文（データ保全用。通常は nil）。
    public private(set) var unrecognizedEasingTypeName: String?
    /// 未知の EasingMode 名の原文（データ保全用。通常は nil）。
    public private(set) var unrecognizedEasingModeName: String?

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&tolerance)
        body(&angle)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "File":
            file = value.stringValue
            return true
        case "Tolerance":
            CodecSupport.decodeAnimation(value, into: &tolerance)
            return true
        case "Angle":
            CodecSupport.decodeAnimation(value, into: &angle)
            return true
        case "KeepAspect":
            keepAspect = CodecSupport.bool(value, default: true)
            return true
        case "IsFixedCoveringScale":
            isFixedCoveringScale = CodecSupport.bool(value, default: false)
            return true
        case "IsInEffect":
            isInEffect = CodecSupport.bool(value, default: true)
            return true
        case "IsReversedInEffect":
            isReversedInEffect = CodecSupport.bool(value, default: false)
            return true
        case "IsOutEffect":
            isOutEffect = CodecSupport.bool(value, default: true)
            return true
        case "IsReversedOutEffect":
            isReversedOutEffect = CodecSupport.bool(value, default: false)
            return true
        case "EffectTimeSeconds":
            effectTimeSeconds = CodecSupport.double(value, default: 1)
            return true
        case "EasingType":
            if let name = value.stringValue {
                if let family = EasingFamily(effectHonkeName: name) {
                    easingFamily = family
                    unrecognizedEasingTypeName = nil
                } else {
                    unrecognizedEasingTypeName = name
                }
            }
            return true
        case "EasingMode":
            if let name = value.stringValue {
                if let mode = EasingMode(effectHonkeName: name) {
                    easingMode = mode
                    unrecognizedEasingModeName = nil
                } else {
                    unrecognizedEasingModeName = name
                }
            }
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "File", value: file.map(JSONValue.string) ?? .null),
            (key: "Tolerance", value: CodecSupport.encodeAnimation(tolerance)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "KeepAspect", value: .bool(keepAspect)),
            (key: "IsFixedCoveringScale", value: .bool(isFixedCoveringScale)),
            (key: "IsInEffect", value: .bool(isInEffect)),
            (key: "IsReversedInEffect", value: .bool(isReversedInEffect)),
            (key: "IsOutEffect", value: .bool(isOutEffect)),
            (key: "IsReversedOutEffect", value: .bool(isReversedOutEffect)),
            (key: "EffectTimeSeconds", value: .number(effectTimeSeconds)),
            (key: "EasingType", value: .string(unrecognizedEasingTypeName ?? easingFamily.effectHonkeName)),
            (key: "EasingMode", value: .string(unrecognizedEasingModeName ?? easingMode.effectHonkeName)),
        ] + super.encodeKnownFields()
    }
}
