import Foundation

/// 画面端の方向。本家 `TopBottomLeftRight`（宣言順 Top / Bottom / Left /
/// Right、保存はメンバ名文字列）。
public enum TopBottomLeftRight: HonkeEnum {
    case top
    case bottom
    case left
    case right
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Top": self = .top
        case "Bottom": self = .bottom
        case "Left": self = .left
        case "Right": self = .right
        default: self = .unknown(name)
        }
    }
}

/// イン／アウト系エフェクトの定義基盤。本家 `InOutEffectBase` に対応する。
///
/// パラメータ（実測）: IsInEffect / IsOutEffect は bool（既定 true）、
/// EffectTimeSeconds は double（既定 0.3)、EasingType は既定 Expo、
/// EasingMode は既定 Out。
open class InOutEffectDefinitionBase: VideoEffectDefinitionBase {
    /// イン側を有効にするか。
    public var isInEffect: Bool = true
    /// アウト側を有効にするか。
    public var isOutEffect: Bool = true
    /// イン／アウトにかける時間（秒）。
    public var effectTimeSeconds: Double = 0.3
    /// イージングの種類。
    public var easingFamily: EasingFamily = .expo
    /// イージングの方式。
    public var easingMode: EasingMode = .out

    /// 未知の EasingType 名の原文（データ保全用。通常は nil）。
    public private(set) var unrecognizedEasingTypeName: String?
    /// 未知の EasingMode 名の原文（データ保全用。通常は nil）。
    public private(set) var unrecognizedEasingModeName: String?

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsInEffect":
            isInEffect = CodecSupport.bool(value, default: true)
            return true
        case "IsOutEffect":
            isOutEffect = CodecSupport.bool(value, default: true)
            return true
        case "EffectTimeSeconds":
            effectTimeSeconds = CodecSupport.double(value, default: 0.3)
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
            (key: "IsInEffect", value: .bool(isInEffect)),
            (key: "IsOutEffect", value: .bool(isOutEffect)),
            (key: "EffectTimeSeconds", value: .number(effectTimeSeconds)),
            (key: "EasingType", value: .string(unrecognizedEasingTypeName ?? easingFamily.effectHonkeName)),
            (key: "EasingMode", value: .string(unrecognizedEasingModeName ?? easingMode.effectHonkeName)),
        ] + super.encodeKnownFields()
    }
}

/// イン／アウト系処理器の基盤。本家 `InOutEffectBase` 処理器の
/// `GetEasingValue` に対応する。
///
/// 時刻は秒で扱う: イン側の率は 経過秒 / EffectTimeSeconds、アウト側の率は
/// 残り秒 / EffectTimeSeconds で、それぞれ 0〜1 にクランプし、小さい方を
/// 採用する。無効側・時間 0 以下の側は率 1（= 完全に効いた状態）。
open class InOutEffectProcessorBase<Definition: InOutEffectDefinitionBase>: DrawDescriptionEffectProcessor {
    /// 対象の定義。
    public let definition: Definition

    public init(definition: Definition) {
        self.definition = definition
        super.init()
    }

    /// from → to をイン／アウトのイージング率で補間した値。
    public func easingValue(_ description: EffectDescription, from: Double, to: Double) -> Double {
        let positionSeconds = description.itemDescription.itemPosition.time
        let durationSeconds = description.itemDescription.itemDuration.time
        let time = definition.effectTimeSeconds
        let inRate = (definition.isInEffect && time > 0)
            ? min(max(positionSeconds / time, 0), 1)
            : 1
        let outRate = (definition.isOutEffect && time > 0)
            ? min(max((durationSeconds - positionSeconds) / time, 0), 1)
            : 1
        let rate = min(inRate, outRate)
        let eased = EasingFamily.getValue(
            family: definition.easingFamily, mode: definition.easingMode, rate: rate
        )
        return from + (to - from) * eased
    }
}

/// イン／アウトフェード。本家 `InOutFadeEffect`。
/// パラメータ（実測）: Value は double（既定 0, 0〜100）。
public final class InOutFadeEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutFadeEffect, YukkuriMovieMaker"
    }

    /// フェードの到達点（%）。
    public var value: Double = 0

    public override func createProcessor() -> any VideoEffectProcessor {
        InOutFadeEffectProcessor(definition: self)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            self.value = CodecSupport.double(value, default: 0)
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

/// 本家 `InOutFadeEffect` 処理器。不透明度へ Value/100 → 1 の補間係数を掛ける。
public final class InOutFadeEffectProcessor: InOutEffectProcessorBase<InOutFadeEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        var result = description.drawDescription
        result.opacity = result.opacity * easingValue(
            description, from: definition.value / 100, to: 1
        )
        return result
    }
}

/// イン／アウト移動。本家 `InOutMoveEffect`。
/// パラメータ（実測）: Value / Value2 / Value3 は double（既定 0,
/// -100000〜100000)、X / Y / Z の移動量に対応する。
public final class InOutMoveEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutMoveEffect, YukkuriMovieMaker"
    }

    /// X の移動量。
    public var value: Double = 0
    /// Y の移動量。
    public var value2: Double = 0
    /// Z の移動量。
    public var value3: Double = 0

    public override func createProcessor() -> any VideoEffectProcessor {
        InOutMoveEffectProcessor(definition: self)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            self.value = CodecSupport.double(value, default: 0)
            return true
        case "Value2":
            value2 = CodecSupport.double(value, default: 0)
            return true
        case "Value3":
            value3 = CodecSupport.double(value, default: 0)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Value", value: .number(value)),
            (key: "Value2", value: .number(value2)),
            (key: "Value3", value: .number(value3)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `InOutMoveEffect` 処理器。各軸を 移動量 → 0 へ補間して加算する。
public final class InOutMoveEffectProcessor: InOutEffectProcessorBase<InOutMoveEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        var result = description.drawDescription
        result.draw = Vector3(
            x: result.draw.x + easingValue(description, from: definition.value, to: 0),
            y: result.draw.y + easingValue(description, from: definition.value2, to: 0),
            z: result.draw.z + easingValue(description, from: definition.value3, to: 0)
        )
        return result
    }
}

/// イン／アウト拡大縮小。本家 `InOutZoomEffect`。
/// パラメータ（実測）: Value は double（既定 0, 0〜100000)、
/// X / Y は double（既定 100, 0〜100000）。
public final class InOutZoomEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutZoomEffect, YukkuriMovieMaker"
    }

    /// 全体の拡大率（%）。
    public var value: Double = 0
    /// X 方向の拡大率（%）。
    public var x: Double = 100
    /// Y 方向の拡大率（%）。
    public var y: Double = 100

    public override func createProcessor() -> any VideoEffectProcessor {
        InOutZoomEffectProcessor(definition: self)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Value":
            self.value = CodecSupport.double(value, default: 0)
            return true
        case "X":
            x = CodecSupport.double(value, default: 100)
            return true
        case "Y":
            y = CodecSupport.double(value, default: 100)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Value", value: .number(value)),
            (key: "X", value: .number(x)),
            (key: "Y", value: .number(y)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `InOutZoomEffect` 処理器。Zoom へ (X/100 → 1) × (Value/100 → 1) 等を掛ける。
public final class InOutZoomEffectProcessor: InOutEffectProcessorBase<InOutZoomEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        let factorX = easingValue(description, from: definition.x / 100, to: 1)
        let factorY = easingValue(description, from: definition.y / 100, to: 1)
        let uniform = easingValue(description, from: definition.value / 100, to: 1)
        var result = description.drawDescription
        result.zoom = Vector2(
            x: result.zoom.x * factorX * uniform,
            y: result.zoom.y * factorY * uniform
        )
        return result
    }
}

/// 画面外からのイン／アウト移動。本家 `InOutMoveFromOutsideFrameEffect`。
/// パラメータ（実測）: Value は TopBottomLeftRight（既定 Left）。
public final class InOutMoveFromOutsideFrameEffectDefinition: InOutEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InOutMoveFromOutsideFrameEffect, YukkuriMovieMaker"
    }

    /// 画面外の方向。
    public var value: TopBottomLeftRight = .left

    public override func createProcessor() -> any VideoEffectProcessor {
        InOutMoveFromOutsideFrameEffectProcessor(definition: self)
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

/// 本家 `InOutMoveFromOutsideFrameEffect` 処理器。方向に応じた画面外
/// オフセット（左 = (-画面幅, 0) 等）から 0 へ補間して加算する。
public final class InOutMoveFromOutsideFrameEffectProcessor: InOutEffectProcessorBase<InOutMoveFromOutsideFrameEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        let size = description.itemDescription.screenSize
        var offsetX = 0.0
        var offsetY = 0.0
        switch definition.value {
        case .left:
            offsetX = -Double(size.width)
        case .right:
            offsetX = Double(size.width)
        case .top:
            offsetY = -Double(size.height)
        case .bottom:
            offsetY = Double(size.height)
        case .unknown:
            break
        }
        var result = description.drawDescription
        result.draw = Vector3(
            x: result.draw.x + easingValue(description, from: offsetX, to: 0),
            y: result.draw.y + easingValue(description, from: offsetY, to: 0),
            z: result.draw.z
        )
        return result
    }
}
