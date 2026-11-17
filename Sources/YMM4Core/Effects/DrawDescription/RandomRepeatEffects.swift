import Foundation

/// ランダム系エフェクトの定義基盤。本家 `RandomEffectBase` に対応する。
///
/// パラメータ（実測）: Span は Animation(既定 0.13, 0〜100000) のみ。
open class RandomEffectDefinitionBase: VideoEffectDefinitionBase {
    /// 乱数が滑らかに変化する周期（秒相当の無次元量。0 ならフレーム毎に独立）。
    public var span = Animation(defaultValue: 0.13, minValue: 0, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&span)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Span":
            CodecSupport.decodeAnimation(value, into: &span)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Span", value: CodecSupport.encodeAnimation(span)),
        ] + super.encodeKnownFields()
    }
}

/// ランダム系処理器の基盤。本家 `RandomEffectBase` 処理器の
/// `GetRandomValue` に対応する。
///
/// Span ≠ 0 のときは周期で滑らかに補間された乱数（Cubic カーネルの加重和、
/// 正規化なし）、Span = 0 のときはフレーム毎の生の乱数を返す。乱数キーは
/// 本家では [定義の GetHashCode(), パラメータ ID, 周期番号, InputIndex]
/// （Span = 0 では周期番号の代わりにフレーム番号）であり、GetHashCode の
/// 部分は定義の `randomSeed` で代替する（対応付けは未解決事項）。
open class RandomEffectProcessorBase<Definition: RandomEffectDefinitionBase>: DrawDescriptionEffectProcessor {
    /// 対象の定義。
    public let definition: Definition

    public init(definition: Definition) {
        self.definition = definition
        super.init()
    }

    /// パラメータ ID ごとの乱数（0〜1 付近）。
    public func randomValue(_ description: EffectDescription, parameterID: Int64) -> Double {
        let frame = description.itemFrame
        let span = definition.span.value(
            atFrame: frame,
            length: description.itemDurationFrames,
            fps: description.fps
        )
        if span != 0 {
            return Animation.randomMoveRate(
                seed: definition.randomSeed,
                id: parameterID,
                frame: frame,
                fps: description.fps,
                span: span,
                seedOffset: Int64(description.inputIndex)
            )
        }
        return StatelessRandom.getDouble(keys: [
            definition.randomSeed,
            parameterID,
            Int64(frame),
            Int64(description.inputIndex),
        ])
    }
}

/// ランダム移動。本家 `RandomMoveEffect`。
/// パラメータ（実測）: X / Y は Animation(既定 100, 0〜100000)、
/// Z は Animation(既定 0, 0〜100000)、＋ 継承 Span。
public final class RandomMoveEffectDefinition: RandomEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RandomMoveEffect, YukkuriMovieMaker"
    }

    /// X の振れ幅。
    public var x = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// Y の振れ幅。
    public var y = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// Z の振れ幅。
    public var z = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        RandomMoveEffectProcessor(definition: self)
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
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `RandomMoveEffect` 処理器。各軸へ 振れ幅 × 乱数 − 振れ幅/2 を加算する。
public final class RandomMoveEffectProcessor: RandomEffectProcessorBase<RandomMoveEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let valueX = definition.x.value(atFrame: frame, length: duration, fps: fps)
        let valueY = definition.y.value(atFrame: frame, length: duration, fps: fps)
        let valueZ = definition.z.value(atFrame: frame, length: duration, fps: fps)
        var result = description.drawDescription
        result.draw = Vector3(
            x: result.draw.x + valueX * randomValue(description, parameterID: 0) - valueX / 2,
            y: result.draw.y + valueY * randomValue(description, parameterID: 1) - valueY / 2,
            z: result.draw.z + valueZ * randomValue(description, parameterID: 2) - valueZ / 2
        )
        return result
    }
}

/// ランダム不透明度。本家 `RandomOpacityEffect`。
/// パラメータ（実測）: Opacity は Animation(既定 0, 0〜100)、＋ 継承 Span。
public final class RandomOpacityEffectDefinition: RandomEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RandomOpacityEffect, YukkuriMovieMaker"
    }

    /// 不透明度の下限（%）。100 との間を乱数で補間する。
    public var opacity = Animation(defaultValue: 0, minValue: 0, maxValue: 100)

    public override func createProcessor() -> any VideoEffectProcessor {
        RandomOpacityEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&opacity)
        super.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `RandomOpacityEffect` 処理器。不透明度へ (100 + (Opacity − 100) × 乱数) / 100 を掛ける。
public final class RandomOpacityEffectProcessor: RandomEffectProcessorBase<RandomOpacityEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        let value = definition.opacity.value(
            atFrame: description.itemFrame,
            length: description.itemDurationFrames,
            fps: description.fps
        )
        let factor = 100 + (value - 100) * randomValue(description, parameterID: 0)
        var result = description.drawDescription
        result.opacity = result.opacity * factor / 100
        return result
    }
}

/// ランダム拡大縮小。本家 `RandomZoomEffect`。
/// パラメータ（実測）: Zoom は Animation(既定 0, 0〜800)、
/// ZoomX / ZoomY は Animation(既定 100, 0〜800)、＋ 継承 Span。
public final class RandomZoomEffectDefinition: RandomEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RandomZoomEffect, YukkuriMovieMaker"
    }

    /// 全体の拡大率の下限（%）。
    public var zoom = Animation(defaultValue: 0, minValue: 0, maxValue: 800)
    /// X 方向の拡大率の下限（%）。
    public var zoomX = Animation(defaultValue: 100, minValue: 0, maxValue: 800)
    /// Y 方向の拡大率の下限（%）。
    public var zoomY = Animation(defaultValue: 100, minValue: 0, maxValue: 800)

    public override func createProcessor() -> any VideoEffectProcessor {
        RandomZoomEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&zoom)
        body(&zoomX)
        body(&zoomY)
        super.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
            return true
        case "ZoomX":
            CodecSupport.decodeAnimation(value, into: &zoomX)
            return true
        case "ZoomY":
            CodecSupport.decodeAnimation(value, into: &zoomY)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "ZoomX", value: CodecSupport.encodeAnimation(zoomX)),
            (key: "ZoomY", value: CodecSupport.encodeAnimation(zoomY)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `RandomZoomEffect` 処理器。各倍率を 100 + (下限 − 100) × 乱数 で決める。
public final class RandomZoomEffectProcessor: RandomEffectProcessorBase<RandomZoomEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let uniform = 100 + (definition.zoom.value(atFrame: frame, length: duration, fps: fps) - 100)
            * randomValue(description, parameterID: 0)
        let factorX = 100 + (definition.zoomX.value(atFrame: frame, length: duration, fps: fps) - 100)
            * randomValue(description, parameterID: 1)
        let factorY = 100 + (definition.zoomY.value(atFrame: frame, length: duration, fps: fps) - 100)
            * randomValue(description, parameterID: 2)
        var result = description.drawDescription
        result.zoom = Vector2(
            x: result.zoom.x * uniform / 100 * factorX / 100,
            y: result.zoom.y * uniform / 100 * factorY / 100
        )
        return result
    }
}

/// 反復系エフェクトの定義基盤。本家 `RepeatEffectBase` に対応する。
///
/// パラメータ（実測）: Span は Animation(既定 1.0, 0〜100000)、
/// EasingType は既定 Sine、EasingMode は既定 InOut、IsCentering は
/// bool（既定 true)。IsCentering の保存可否は具象側で差し替えられる
/// （RepeatOpacityEffect は本家で [JsonIgnore] のため保存しない）。
open class RepeatEffectDefinitionBase: VideoEffectDefinitionBase {
    /// 反復の周期（秒）。
    public var span = Animation(defaultValue: 1.0, minValue: 0, maxValue: 100000)
    /// イージングの種類。
    public var easingFamily: EasingFamily = .sine
    /// イージングの方式。
    public var easingMode: EasingMode = .inOut
    /// 中央寄せするか。
    public var isCentering: Bool = true

    /// 未知の EasingType 名の原文（データ保全用。通常は nil）。
    public private(set) var unrecognizedEasingTypeName: String?
    /// 未知の EasingMode 名の原文（データ保全用。通常は nil）。
    public private(set) var unrecognizedEasingModeName: String?

    /// IsCentering をファイルへ保存するか（RepeatOpacityEffect は false）。
    open var savesCentering: Bool { true }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&span)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Span":
            CodecSupport.decodeAnimation(value, into: &span)
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
        case "IsCentering":
            guard savesCentering else { return false }
            isCentering = CodecSupport.bool(value, default: true)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Span", value: CodecSupport.encodeAnimation(span)),
            (key: "EasingType", value: .string(unrecognizedEasingTypeName ?? easingFamily.effectHonkeName)),
            (key: "EasingMode", value: .string(unrecognizedEasingModeName ?? easingMode.effectHonkeName)),
        ]
        if savesCentering {
            fields.append((key: "IsCentering", value: .bool(isCentering)))
        }
        return fields + super.encodeKnownFields()
    }
}

/// 反復系処理器の基盤。本家 `RepeatEffectBase` 処理器の `GetEasingValue`
/// に対応する。
///
/// Span = 0 のときはフレームの偶奇で from / to を切り替える（本家の処理器
/// コードでは奇数フレームが to、偶数フレームが from。Animation 本体の
/// 反復移動とは偶奇の対応が逆であることを実測で確認したため、こちらは
/// 処理器コードに従う）。Span > 0 のときは三角波＋イージングの率で補間し、
/// IsCentering の場合は範囲の半分だけ負側へずらし、InOut の場合は時間を
/// Span/4 進める。
open class RepeatEffectProcessorBase<Definition: RepeatEffectDefinitionBase>: DrawDescriptionEffectProcessor {
    /// 対象の定義。
    public let definition: Definition

    public init(definition: Definition) {
        self.definition = definition
        super.init()
    }

    /// from → to を反復イージングで補間した値。
    public func easingValue(_ description: EffectDescription, from: Double, to: Double) -> Double {
        let frame = description.itemFrame
        let span = definition.span.value(
            atFrame: frame,
            length: description.itemDurationFrames,
            fps: description.fps
        )
        let centerOffset = definition.isCentering ? -(to - from) / 2 : 0
        if span == 0 {
            return centerOffset + (frame % 2 != 0 ? to : from)
        }
        var seconds = description.itemDescription.itemPosition.time
        if definition.isCentering && definition.easingMode == .inOut {
            seconds += span / 4
        }
        let rate = Animation.repeatMoveRate(
            sec: seconds, span: span,
            family: definition.easingFamily, mode: definition.easingMode
        )
        return centerOffset + from + (to - from) * rate
    }
}

/// 反復移動。本家 `RepeatMoveEffect`。
/// パラメータ（実測）: X / Z は Animation(既定 0, -100000〜100000)、
/// Y は Animation(既定 -100, -100000〜100000)、＋ 継承 Span 等。
public final class RepeatMoveEffectDefinition: RepeatEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RepeatMoveEffect, YukkuriMovieMaker"
    }

    /// X の移動量。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y の移動量。
    public var y = Animation(defaultValue: -100, minValue: -100000, maxValue: 100000)
    /// Z の移動量。
    public var z = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        RepeatMoveEffectProcessor(definition: self)
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
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `RepeatMoveEffect` 処理器。各軸を 0 → 移動量 で反復補間して加算する。
public final class RepeatMoveEffectProcessor: RepeatEffectProcessorBase<RepeatMoveEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        var result = description.drawDescription
        result.draw = Vector3(
            x: result.draw.x + easingValue(
                description, from: 0,
                to: definition.x.value(atFrame: frame, length: duration, fps: fps)),
            y: result.draw.y + easingValue(
                description, from: 0,
                to: definition.y.value(atFrame: frame, length: duration, fps: fps)),
            z: result.draw.z + easingValue(
                description, from: 0,
                to: definition.z.value(atFrame: frame, length: duration, fps: fps))
        )
        return result
    }
}

/// 反復不透明度。本家 `RepeatOpacityEffect`。
/// パラメータ（実測）: Opacity は Animation(既定 0, 0〜100)、＋ 継承 Span 等。
/// IsCentering は本家で常に false（getter 固定・[JsonIgnore]）のため、
/// 保存せず評価でも中央寄せしない。
public final class RepeatOpacityEffectDefinition: RepeatEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RepeatOpacityEffect, YukkuriMovieMaker"
    }

    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 0, minValue: 0, maxValue: 100)

    public override var isCentering: Bool {
        get { false }
        set { /* 本家は setter が何もしない */ }
    }

    public override var savesCentering: Bool { false }

    public override func createProcessor() -> any VideoEffectProcessor {
        RepeatOpacityEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&opacity)
        super.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `RepeatOpacityEffect` 処理器。不透明度へ 100 → Opacity の反復補間係数を掛ける。
public final class RepeatOpacityEffectProcessor: RepeatEffectProcessorBase<RepeatOpacityEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        let value = easingValue(
            description, from: 100,
            to: definition.opacity.value(
                atFrame: description.itemFrame,
                length: description.itemDurationFrames,
                fps: description.fps
            )
        )
        var result = description.drawDescription
        result.opacity = result.opacity * value / 100
        return result
    }
}

/// 反復拡大縮小。本家 `RepeatZoomEffect`。
/// パラメータ（実測）: Zoom は Animation(既定 90, 0〜100000)、
/// ZoomX / ZoomY は Animation(既定 100, 0〜100000)、＋ 継承 Span 等。
public final class RepeatZoomEffectDefinition: RepeatEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RepeatZoomEffect, YukkuriMovieMaker"
    }

    /// 全体の拡大率（%）。
    public var zoom = Animation(defaultValue: 90, minValue: 0, maxValue: 100000)
    /// X 方向の拡大率（%）。
    public var zoomX = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// Y 方向の拡大率（%）。
    public var zoomY = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        RepeatZoomEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&zoom)
        body(&zoomX)
        body(&zoomY)
        super.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
            return true
        case "ZoomX":
            CodecSupport.decodeAnimation(value, into: &zoomX)
            return true
        case "ZoomY":
            CodecSupport.decodeAnimation(value, into: &zoomY)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "ZoomX", value: CodecSupport.encodeAnimation(zoomX)),
            (key: "ZoomY", value: CodecSupport.encodeAnimation(zoomY)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `RepeatZoomEffect` 処理器。各倍率を 100 → 設定値 で反復補間する。
public final class RepeatZoomEffectProcessor: RepeatEffectProcessorBase<RepeatZoomEffectDefinition> {
    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let uniform = easingValue(
            description, from: 100,
            to: definition.zoom.value(atFrame: frame, length: duration, fps: fps))
        let factorX = easingValue(
            description, from: 100,
            to: definition.zoomX.value(atFrame: frame, length: duration, fps: fps))
        let factorY = easingValue(
            description, from: 100,
            to: definition.zoomY.value(atFrame: frame, length: duration, fps: fps))
        var result = description.drawDescription
        result.zoom = Vector2(
            x: result.zoom.x * uniform / 100 * factorX / 100,
            y: result.zoom.y * uniform / 100 * factorY / 100
        )
        return result
    }
}
