import Foundation

/// 拡大縮小エフェクト。本家 `ZoomEffect`。
///
/// パラメータ（実測）: Zoom / ZoomX / ZoomY は Animation(既定 100,
/// 0〜100000)、IsNearestNeighbor は bool（既定 false）。
public final class ZoomEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.ZoomEffect, YukkuriMovieMaker"
    }

    /// 全体の拡大率（%）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// X 方向の拡大率（%）。
    public var zoomX = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// Y 方向の拡大率（%）。
    public var zoomY = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 最近傍補間を使うか。
    public var isNearestNeighbor: Bool = false

    public override func createProcessor() -> any VideoEffectProcessor {
        ZoomEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&zoom)
        body(&zoomX)
        body(&zoomY)
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
        case "IsNearestNeighbor":
            isNearestNeighbor = CodecSupport.bool(value, default: false)
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
            (key: "IsNearestNeighbor", value: .bool(isNearestNeighbor)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `ZoomEffect` 処理器。Zoom = 既存 Zoom × (ZoomX, ZoomY) / 100 × Zoom / 100。
public final class ZoomEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: ZoomEffectDefinition

    public init(definition: ZoomEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let uniform = definition.zoom.value(atFrame: frame, length: duration, fps: fps) / 100
        let factorX = definition.zoomX.value(atFrame: frame, length: duration, fps: fps) / 100
        let factorY = definition.zoomY.value(atFrame: frame, length: duration, fps: fps) / 100
        var result = description.drawDescription
        result.zoom = Vector2(
            x: result.zoom.x * factorX * uniform,
            y: result.zoom.y * factorY * uniform
        )
        if definition.isNearestNeighbor {
            result.zoomInterpolationMode = .nearestNeighbor
        }
        // 本家は IsNearestNeighbor が false の場合、設定
        // （YMMSettings.GetZoomMode()）から補間方式を読み直す。設定層が
        // 未実装のため、こちらでは入力の方式（EffectedItemSource が注入した
        // 差し替え点の値）を維持する（意図的な差分）。
        return result
    }
}

/// 不透明度エフェクト。本家 `OpacityEffect`。
///
/// パラメータ（実測）: Opacity は Animation(既定 100, 0〜100)、
/// IsAbsolute は bool（既定 false）。
public final class OpacityEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.OpacityEffect, YukkuriMovieMaker"
    }

    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 絶対値として適用するか（false なら既存の不透明度へ乗算）。
    public var isAbsolute: Bool = false

    public override func createProcessor() -> any VideoEffectProcessor {
        OpacityEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&opacity)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        case "IsAbsolute":
            isAbsolute = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "IsAbsolute", value: .bool(isAbsolute)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `OpacityEffect` 処理器。
public final class OpacityEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: OpacityEffectDefinition

    public init(definition: OpacityEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let value = definition.opacity.value(
            atFrame: description.itemFrame,
            length: description.itemDurationFrames,
            fps: description.fps
        )
        var result = description.drawDescription
        result.opacity = definition.isAbsolute
            ? value / 100
            : result.opacity * value / 100
        return result
    }
}

/// 描画位置エフェクト。本家 `DrawPositionEffect`。
///
/// パラメータ（実測）: X / Y / Z は Animation(既定 0, -100000〜100000)。
public final class DrawPositionEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.DrawPositionEffect, YukkuriMovieMaker"
    }

    /// X 座標の加算量。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標の加算量。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Z 座標の加算量。
    public var z = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        DrawPositionEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&z)
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

/// 本家 `DrawPositionEffect` 処理器。Draw へ評価値を加算し、原点の操作点を
/// 1つ追加する（ドラッグ等の対話コールバックは編集 UI 層の関心であり、
/// MAC-0009 の方針どおり含めない）。
public final class DrawPositionEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: DrawPositionEffectDefinition

    public init(definition: DrawPositionEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        var result = description.drawDescription
        result.draw = Vector3(
            x: result.draw.x + definition.x.value(atFrame: frame, length: duration, fps: fps),
            y: result.draw.y + definition.y.value(atFrame: frame, length: duration, fps: fps),
            z: result.draw.z + definition.z.value(atFrame: frame, length: duration, fps: fps)
        )
        result.controllers.append(VideoEffectController(
            owner: definition,
            points: [ControllerPoint(position: .zero)]
        ))
        return result
    }
}
