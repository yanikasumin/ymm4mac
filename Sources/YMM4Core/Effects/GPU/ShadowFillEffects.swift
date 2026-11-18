import Foundation

// GPU 処理系の輪郭・影・塗り系エフェクトの定義層。
//
// いずれも処理器は暫定の素通し（`GPUEffectDefinitionBase` が返す
// `GPUEffectPassthroughProcessor`）であり、画像の加工はまだ行われない。
// パラメータの型・既定値・範囲は本家定義クラスの実測に基づく。
//
// ブラシ（本家 `YukkuriMovieMaker.Plugin.Brush.Brush`）は、影・
// 背景塗り・前景塗り・枠線では型付きモデル（`Brush`）で保持する
// （BRUSH46）。輪郭の StrokeBrush は処理器が未実装のため生保持の
// まま。旧互換の set 専用 `Color` / `StrokeColor` はブラシ内部の
// 単色パラメータへ転送されるもので、生保持の内部は書き換えない
// ため、追加フィールドとしてそのまま保持する（変換は行わない）。

/// 輪郭。本家 `OutlineEffect`。
/// パラメータ（実測）: StrokeThickness は Animation(既定 3, 0〜500)、
/// Blur は Animation(既定 0, 0〜1000)、Quality は Animation(既定 64,
/// 3〜256)、Smoothness は Animation(既定 100, 0〜100)、X / Y は
/// Animation(既定 0, -100000〜100000)、Opacity は Animation(既定 100,
/// 0〜100)、Zoom は Animation(既定 100, 0〜100000)、Rotation は
/// Animation(既定 0, -100000〜100000)、IsOutlineOnly / IsAngular は
/// bool（既定 false）。StrokeBrush はブラシのため生保持。
public final class OutlineEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.OutlineEffect, YukkuriMovieMaker"
    }

    /// 輪郭の太さ。
    public var strokeThickness = Animation(defaultValue: 3, minValue: 0, maxValue: 500)
    /// ぼかし量。
    public var blur = Animation(defaultValue: 0, minValue: 0, maxValue: 1000)
    /// 品質。
    public var quality = Animation(defaultValue: 64, minValue: 3, maxValue: 256)
    /// 滑らかさ（%）。
    public var smoothness = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 拡大率（%）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 回転。
    public var rotation = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 輪郭のブラシ（生保持）。
    public var strokeBrush: PreservedObject?
    /// 輪郭だけを残すか。
    public var isOutlineOnly: Bool = false
    /// 角を立てるか。
    public var isAngular: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&strokeThickness)
        body(&blur)
        body(&quality)
        body(&smoothness)
        body(&x)
        body(&y)
        body(&opacity)
        body(&zoom)
        body(&rotation)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "StrokeThickness":
            CodecSupport.decodeAnimation(value, into: &strokeThickness)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "Quality":
            CodecSupport.decodeAnimation(value, into: &quality)
            return true
        case "Smoothness":
            CodecSupport.decodeAnimation(value, into: &smoothness)
            return true
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
            return true
        case "Rotation":
            CodecSupport.decodeAnimation(value, into: &rotation)
            return true
        case "StrokeBrush":
            strokeBrush = CodecSupport.preservedObject(value)
            return true
        case "IsOutlineOnly":
            isOutlineOnly = CodecSupport.bool(value, default: false)
            return true
        case "IsAngular":
            isAngular = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "StrokeThickness", value: CodecSupport.encodeAnimation(strokeThickness)),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "Quality", value: CodecSupport.encodeAnimation(quality)),
            (key: "Smoothness", value: CodecSupport.encodeAnimation(smoothness)),
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
        ]
        if let strokeBrush {
            fields.append((key: "StrokeBrush", value: strokeBrush.value))
        }
        fields.append((key: "IsOutlineOnly", value: .bool(isOutlineOnly)))
        fields.append((key: "IsAngular", value: .bool(isAngular)))
        return fields + super.encodeKnownFields()
    }
}

/// 影。本家 `ShadowEffect`。
/// パラメータ（実測）: X / Y / Angle は Animation(既定 0,
/// -100000〜100000)、Opacity は Animation(既定 50, 0〜100)、Zoom は
/// Animation(既定 100, 0〜100000)、Blur は Animation(既定 3, 0〜250)、
/// IsRotateAtCenter は bool（既定 false）。Brush は型付きモデル
/// （`Brush`。パラメータ内の Animation も走査対象に含める）。
public final class ShadowEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.ShadowEffect, YukkuriMovieMaker"
    }

    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 50, minValue: 0, maxValue: 100)
    /// 拡大率（%）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 角度。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// ぼかし量。
    public var blur = Animation(defaultValue: 3, minValue: 0, maxValue: 250)
    /// 中心で回転するか。
    public var isRotateAtCenter: Bool = false
    /// 影のブラシ。
    public var brush: Brush?

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&opacity)
        body(&zoom)
        body(&angle)
        body(&blur)
        brush?.forEachAnimation(body)
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
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
            return true
        case "Angle":
            CodecSupport.decodeAnimation(value, into: &angle)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "IsRotateAtCenter":
            isRotateAtCenter = CodecSupport.bool(value, default: false)
            return true
        case "Brush":
            brush = value == .null ? nil : Brush.decode(from: value)
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
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "IsRotateAtCenter", value: .bool(isRotateAtCenter)),
        ]
        if let brush {
            fields.append((key: "Brush", value: brush.encodeToJSONValue()))
        }
        return fields + super.encodeKnownFields()
    }
}

/// 内側の影。本家 `InnerShadowEffect`。
/// パラメータ（実測）: X / Y は Animation(既定 0, -100000〜100000)、
/// Opacity は Animation(既定 50, 0〜100)、Blur は Animation(既定 3,
/// 0〜250)、BlendMode は Blend（既定 Normal）。Brush は生保持。
public final class InnerShadowEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.InnerShadowEffect, YukkuriMovieMaker"
    }

    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 50, minValue: 0, maxValue: 100)
    /// ぼかし量。
    public var blur = Animation(defaultValue: 3, minValue: 0, maxValue: 250)
    /// 合成方法。
    public var blendMode: Blend = .normal
    /// 影のブラシ（生保持）。
    public var brush: PreservedObject?

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&opacity)
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
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "BlendMode":
            blendMode = CodecSupport.enumeration(value, default: Blend.normal)
            return true
        case "Brush":
            brush = CodecSupport.preservedObject(value)
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
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "BlendMode", value: .string(blendMode.honkeName)),
        ]
        if let brush {
            fields.append((key: "Brush", value: brush.value))
        }
        return fields + super.encodeKnownFields()
    }
}

/// 背景塗りつぶし。本家 `FillBackgroundEffect`。
/// パラメータ（実測）: Opacity は Animation(既定 100, 0〜100)、
/// Round は Animation(既定 0, 0〜100000)、BlendMode は Blend
/// （既定 Normal）、IsBackgroundOnly は bool（既定 false）、
/// Top / Bottom / Left / Right は Animation(既定 0, -100000〜100000)。
/// Brush は型付きモデル（`Brush`）。
public final class FillBackgroundEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.FillBackgroundEffect, YukkuriMovieMaker"
    }

    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 角丸。
    public var round = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 合成方法。
    public var blendMode: Blend = .normal
    /// 背景だけにするか。
    public var isBackgroundOnly: Bool = false
    /// 塗りのブラシ。
    public var brush: Brush?
    /// 上の余白。
    public var top = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 下の余白。
    public var bottom = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 左の余白。
    public var left = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 右の余白。
    public var right = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&opacity)
        body(&round)
        body(&top)
        body(&bottom)
        body(&left)
        body(&right)
        brush?.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        case "Round":
            CodecSupport.decodeAnimation(value, into: &round)
            return true
        case "BlendMode":
            blendMode = CodecSupport.enumeration(value, default: Blend.normal)
            return true
        case "IsBackgroundOnly":
            isBackgroundOnly = CodecSupport.bool(value, default: false)
            return true
        case "Brush":
            brush = value == .null ? nil : Brush.decode(from: value)
            return true
        case "Top":
            CodecSupport.decodeAnimation(value, into: &top)
            return true
        case "Bottom":
            CodecSupport.decodeAnimation(value, into: &bottom)
            return true
        case "Left":
            CodecSupport.decodeAnimation(value, into: &left)
            return true
        case "Right":
            CodecSupport.decodeAnimation(value, into: &right)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Round", value: CodecSupport.encodeAnimation(round)),
            (key: "BlendMode", value: .string(blendMode.honkeName)),
            (key: "IsBackgroundOnly", value: .bool(isBackgroundOnly)),
        ]
        if let brush {
            fields.append((key: "Brush", value: brush.encodeToJSONValue()))
        }
        fields += [
            (key: "Top", value: CodecSupport.encodeAnimation(top)),
            (key: "Bottom", value: CodecSupport.encodeAnimation(bottom)),
            (key: "Left", value: CodecSupport.encodeAnimation(left)),
            (key: "Right", value: CodecSupport.encodeAnimation(right)),
        ]
        return fields + super.encodeKnownFields()
    }
}

/// 前景塗りつぶし。本家 `FillForegroundEffect`。
/// パラメータ（実測）: Opacity は Animation(既定 100, 0〜100)、
/// BlendMode は Blend（既定 Normal）、IsBrushOnly は bool
/// （既定 false）。Brush は型付きモデル（`Brush`）。
public final class FillForegroundEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.FillForegroundEffect, YukkuriMovieMaker"
    }

    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 合成方法。
    public var blendMode: Blend = .normal
    /// ブラシだけにするか。
    public var isBrushOnly: Bool = false
    /// 塗りのブラシ。
    public var brush: Brush?

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&opacity)
        brush?.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        case "BlendMode":
            blendMode = CodecSupport.enumeration(value, default: Blend.normal)
            return true
        case "IsBrushOnly":
            isBrushOnly = CodecSupport.bool(value, default: false)
            return true
        case "Brush":
            brush = value == .null ? nil : Brush.decode(from: value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "BlendMode", value: .string(blendMode.honkeName)),
            (key: "IsBrushOnly", value: .bool(isBrushOnly)),
        ]
        if let brush {
            fields.append((key: "Brush", value: brush.encodeToJSONValue()))
        }
        return fields + super.encodeKnownFields()
    }
}

/// 枠線。本家 `FrameLineEffect`。
/// パラメータ（実測）: Opacity は Animation(既定 100, 0〜100)、
/// Thickness は Animation(既定 10, 0〜100000)、RenderPlacement は
/// 既定 Back、Type は FrameLineType（既定 All）、Top / Bottom /
/// Left / Right は Animation(既定 0, -100000〜100000)。Brush は
/// 型付きモデル（`Brush`）。
public final class FrameLineEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.FrameLineEffect, YukkuriMovieMaker"
    }

    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 線の太さ。
    public var thickness = Animation(defaultValue: 10, minValue: 0, maxValue: 100000)
    /// 描画の配置。
    public var renderPlacement: RenderPlacement = .back
    /// 枠線の種類。
    public var type: FrameLineType = .all
    /// 上の位置。
    public var top = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 下の位置。
    public var bottom = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 左の位置。
    public var left = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 右の位置。
    public var right = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 線のブラシ。
    public var brush: Brush?

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&opacity)
        body(&thickness)
        body(&top)
        body(&bottom)
        body(&left)
        body(&right)
        brush?.forEachAnimation(body)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        case "Thickness":
            CodecSupport.decodeAnimation(value, into: &thickness)
            return true
        case "RenderPlacement":
            renderPlacement = CodecSupport.enumeration(value, default: RenderPlacement.back)
            return true
        case "Type":
            type = CodecSupport.enumeration(value, default: FrameLineType.all)
            return true
        case "Top":
            CodecSupport.decodeAnimation(value, into: &top)
            return true
        case "Bottom":
            CodecSupport.decodeAnimation(value, into: &bottom)
            return true
        case "Left":
            CodecSupport.decodeAnimation(value, into: &left)
            return true
        case "Right":
            CodecSupport.decodeAnimation(value, into: &right)
            return true
        case "Brush":
            brush = value == .null ? nil : Brush.decode(from: value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Thickness", value: CodecSupport.encodeAnimation(thickness)),
            (key: "RenderPlacement", value: .string(renderPlacement.honkeName)),
            (key: "Type", value: .string(type.honkeName)),
            (key: "Top", value: CodecSupport.encodeAnimation(top)),
            (key: "Bottom", value: CodecSupport.encodeAnimation(bottom)),
            (key: "Left", value: CodecSupport.encodeAnimation(left)),
            (key: "Right", value: CodecSupport.encodeAnimation(right)),
        ]
        if let brush {
            fields.append((key: "Brush", value: brush.encodeToJSONValue()))
        }
        return fields + super.encodeKnownFields()
    }
}

/// グラデーションの色分岐点。本家 `GradientStop`。
public struct GradientStopValue: Equatable, Sendable {
    /// 位置（0〜1）。
    public var offset: Double = 0
    /// 色。
    public var color: Color = .transparent
    /// 型付けしていないキーの生保持（データ保全）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init(offset: Double = 0, color: Color = .transparent) {
        self.offset = offset
        self.color = color
    }

    public static func == (lhs: GradientStopValue, rhs: GradientStopValue) -> Bool {
        lhs.offset == rhs.offset && lhs.color == rhs.color
            && lhs.additionalFields.count == rhs.additionalFields.count
            && zip(lhs.additionalFields, rhs.additionalFields).allSatisfy {
                $0.key == $1.key && $0.value == $1.value
            }
    }

    /// オブジェクト形式から読み込む。
    public init(jsonValue: JSONValue) {
        guard let fields = jsonValue.objectFields else { return }
        for (key, value) in fields {
            switch key {
            case "Offset":
                offset = CodecSupport.double(value, default: 0)
            case "Color":
                color = CodecSupport.color(value, default: .transparent)
            default:
                additionalFields.append((key: key, value: value))
            }
        }
    }

    /// オブジェクト形式へ書き出す。
    public func encode() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Offset", value: .number(offset)),
            (key: "Color", value: .string(color.honkeString)),
        ]
        fields += additionalFields.filter { $0.key != "Offset" && $0.key != "Color" }
        return .object(fields)
    }
}

/// グラデーション。本家 `GradientEffect`。
/// パラメータ（実測）: GradientType は既定 Linear、Stops の既定は
/// [(0, 黒), (1, 白)]、X / Y / Rotation は Animation(既定 0,
/// -100000〜100000)、Opacity は Animation(既定 100, 0〜100)、Size は
/// Animation(既定 100, 0〜100000)、ExtendMode は既定 Clamp、Blend は
/// 既定 Normal。旧互換の set 専用 `ColorFrom` / `ColorTo` は
/// 読み込み時に Stops の先頭 / 2番目の色へ転送される。
public final class GradientEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.GradientEffect, YukkuriMovieMaker"
    }

    /// グラデーションの形状。
    public var gradientType: GradientType = .linear
    /// 色分岐点。
    public var stops: [GradientStopValue] = [
        GradientStopValue(offset: 0, color: .black),
        GradientStopValue(offset: 1, color: .white),
    ]
    /// 中心 X。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 中心 Y。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 大きさ。
    public var size = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 回転。
    public var rotation = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 延長方式。
    public var extendMode: ExtendMode = .clamp
    /// 合成方法。
    public var blend: Blend = .normal

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&opacity)
        body(&size)
        body(&rotation)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "GradientType":
            gradientType = CodecSupport.enumeration(value, default: GradientType.linear)
            return true
        case "Stops":
            if let elements = value.arrayValue {
                stops = elements.map { GradientStopValue(jsonValue: $0) }
            }
            return true
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
            return true
        case "Size":
            CodecSupport.decodeAnimation(value, into: &size)
            return true
        case "Rotation":
            CodecSupport.decodeAnimation(value, into: &rotation)
            return true
        case "ExtendMode":
            extendMode = CodecSupport.enumeration(value, default: ExtendMode.clamp)
            return true
        case "Blend":
            blend = CodecSupport.enumeration(value, default: Blend.normal)
            return true
        case "ColorFrom":
            // 旧互換（set 専用）: 先頭の分岐点の色へ転送される
            if !stops.isEmpty {
                stops[0].color = CodecSupport.color(value, default: stops[0].color)
            }
            return true
        case "ColorTo":
            // 旧互換（set 専用）: 2番目の分岐点の色へ転送される
            // （本家は要素が不足すると例外になるが、ここでは保全を優先
            // して要素がある場合だけ転送する）
            if stops.count > 1 {
                stops[1].color = CodecSupport.color(value, default: stops[1].color)
            }
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "GradientType", value: .string(gradientType.honkeName)),
            (key: "Stops", value: .array(stops.map { $0.encode() })),
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
            (key: "ExtendMode", value: .string(extendMode.honkeName)),
            (key: "Blend", value: .string(blend.honkeName)),
        ] + super.encodeKnownFields()
    }
}

/// テクスチャ。本家 `TextureEffect`。
/// パラメータ（実測）: X / Y / Rotation は Animation(既定 0,
/// -100000〜100000)、Zoom は Animation(既定 100, 0〜100000)、
/// FilePath は既定 ""、PlaybackRate は double（既定 100）、
/// ContentOffset は TimeSpan（既定 0）、IsInverted は bool
/// （既定 false）。
public final class TextureEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.TextureEffect, YukkuriMovieMaker"
    }

    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 拡大率（%）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 回転。
    public var rotation = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// テクスチャのファイルパス。
    public var filePath: String = ""
    /// 再生速度（%）。
    public var playbackRate: Double = 100
    /// 内容の開始位置。
    public var contentOffset: TimeSpanValue = .zero
    /// 反転するか。
    public var isInverted: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&zoom)
        body(&rotation)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
            return true
        case "Rotation":
            CodecSupport.decodeAnimation(value, into: &rotation)
            return true
        case "FilePath":
            filePath = CodecSupport.string(value, default: filePath)
            return true
        case "PlaybackRate":
            playbackRate = CodecSupport.double(value, default: 100)
            return true
        case "ContentOffset":
            contentOffset = CodecSupport.timeSpan(value, default: .zero)
            return true
        case "IsInverted":
            isInverted = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
            (key: "FilePath", value: .string(filePath)),
            (key: "PlaybackRate", value: .number(playbackRate)),
            (key: "ContentOffset", value: .string(contentOffset.honkeString)),
            (key: "IsInverted", value: .bool(isInverted)),
        ] + super.encodeKnownFields()
    }
}

/// 背景画像。本家 `BackgroundImageEffect`。
/// パラメータ（実測）: X / Y は Animation(既定 0, -100000〜100000)、
/// Opacity は Animation(既定 100, 0〜100)、Zoom は Animation
/// (既定 100, 0〜100000)、PlaybackRate は double（既定 100）、
/// FilePath は既定 ""、Top / Bottom / Left / Right は Animation
/// (既定 0, 0〜100000)。
public final class BackgroundImageEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.BackgroundImageEffect, YukkuriMovieMaker"
    }

    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 不透明度（%）。
    public var opacity = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 拡大率（%）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 再生速度（%）。
    public var playbackRate: Double = 100
    /// 背景のファイルパス。
    public var filePath: String = ""
    /// 上の余白。
    public var top = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 下の余白。
    public var bottom = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 左の余白。
    public var left = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 右の余白。
    public var right = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&opacity)
        body(&zoom)
        body(&top)
        body(&bottom)
        body(&left)
        body(&right)
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
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
            return true
        case "PlaybackRate":
            playbackRate = CodecSupport.double(value, default: 100)
            return true
        case "FilePath":
            filePath = CodecSupport.string(value, default: filePath)
            return true
        case "Top":
            CodecSupport.decodeAnimation(value, into: &top)
            return true
        case "Bottom":
            CodecSupport.decodeAnimation(value, into: &bottom)
            return true
        case "Left":
            CodecSupport.decodeAnimation(value, into: &left)
            return true
        case "Right":
            CodecSupport.decodeAnimation(value, into: &right)
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
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "PlaybackRate", value: .number(playbackRate)),
            (key: "FilePath", value: .string(filePath)),
            (key: "Top", value: CodecSupport.encodeAnimation(top)),
            (key: "Bottom", value: CodecSupport.encodeAnimation(bottom)),
            (key: "Left", value: CodecSupport.encodeAnimation(left)),
            (key: "Right", value: CodecSupport.encodeAnimation(right)),
        ] + super.encodeKnownFields()
    }
}
