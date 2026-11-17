import Foundation

// GPU 処理系の変形・配置エフェクトの定義層。
//
// いずれも処理器は暫定の素通し（`GPUEffectPassthroughProcessor`。
// `GPUEffectDefinitionBase` が返す）であり、画像の加工はまだ行われない。
// パラメータの型・既定値・範囲は本家定義クラスの実測に基づく。

/// 円弧湾曲。本家 `ArcBendEffect`。
/// パラメータ（実測）: BendAngle / AxisAngle は Animation(既定 0,
/// -100000〜100000)、Anchor は Animation(既定 50, 0〜100)。
public final class ArcBendEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.ArcBendEffect, YukkuriMovieMaker"
    }

    /// 湾曲の角度。
    public var bendAngle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 軸の角度。
    public var axisAngle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 基準位置（%）。
    public var anchor = Animation(defaultValue: 50, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&bendAngle)
        body(&axisAngle)
        body(&anchor)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "BendAngle":
            CodecSupport.decodeAnimation(value, into: &bendAngle)
            return true
        case "AxisAngle":
            CodecSupport.decodeAnimation(value, into: &axisAngle)
            return true
        case "Anchor":
            CodecSupport.decodeAnimation(value, into: &anchor)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "BendAngle", value: CodecSupport.encodeAnimation(bendAngle)),
            (key: "AxisAngle", value: CodecSupport.encodeAnimation(axisAngle)),
            (key: "Anchor", value: CodecSupport.encodeAnimation(anchor)),
        ] + super.encodeKnownFields()
    }
}

/// 画面内に収まるように拡大縮小。本家 `AutomaticZoomEffect`。
/// パラメータ（実測）: AutomaticZoomMode は既定 DownOnly、
/// AutomaticZoomTarget は既定 WidthHeight、余白は Animation(既定 0,
/// -100000〜100000)、IgnoreRotation は bool（既定 false）。
/// 余白は上下用・左右用の2本のみ（本家に Bottom / Right はない）。
public final class AutomaticZoomEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.AutomaticZoomEffect, YukkuriMovieMaker"
    }

    /// 拡大縮小の方向。
    public var automaticZoomMode: AutomaticZoomMode = .downOnly
    /// 対象の寸法。
    public var automaticZoomTarget: AutomaticZoomTarget = .widthHeight
    /// 上下の余白。
    public var automaticZoomMarginTop = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 左右の余白。
    public var automaticZoomMarginLeft = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 回転を無視するか。
    public var ignoreRotation: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&automaticZoomMarginTop)
        body(&automaticZoomMarginLeft)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "AutomaticZoomMode":
            automaticZoomMode = CodecSupport.enumeration(value, default: AutomaticZoomMode.downOnly)
            return true
        case "AutomaticZoomTarget":
            automaticZoomTarget = CodecSupport.enumeration(value, default: AutomaticZoomTarget.widthHeight)
            return true
        case "AutomaticZoomMarginTop":
            CodecSupport.decodeAnimation(value, into: &automaticZoomMarginTop)
            return true
        case "AutomaticZoomMarginLeft":
            CodecSupport.decodeAnimation(value, into: &automaticZoomMarginLeft)
            return true
        case "IgnoreRotation":
            ignoreRotation = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "AutomaticZoomMode", value: .string(automaticZoomMode.honkeName)),
            (key: "AutomaticZoomTarget", value: .string(automaticZoomTarget.honkeName)),
            (key: "AutomaticZoomMarginTop", value: CodecSupport.encodeAnimation(automaticZoomMarginTop)),
            (key: "AutomaticZoomMarginLeft", value: CodecSupport.encodeAnimation(automaticZoomMarginLeft)),
            (key: "IgnoreRotation", value: .bool(ignoreRotation)),
        ] + super.encodeKnownFields()
    }
}

/// 中心位置。本家 `CenterPointEffect`。
/// パラメータ（実測）: Horizontal / Vertical は既定 Origin（各 enum の
/// 先頭メンバ）、X / Y は Animation(既定 0, -100000〜100000)、
/// IsKeepPosition は bool（既定 false）。旧互換の set 専用 `Mode` は
/// 読み込み時に Horizontal / Vertical の組へ変換される（本家の変換表
/// どおり）。
public final class CenterPointEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CenterPointEffect, YukkuriMovieMaker"
    }

    /// 横の中心位置。
    public var horizontal: CenterPointHorizontal = .origin
    /// 縦の中心位置。
    public var vertical: CenterPointVertical = .origin
    /// X 座標（Custom のとき）。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標（Custom のとき）。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 描画位置を維持するか。
    public var isKeepPosition: Bool = false

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Horizontal":
            horizontal = CodecSupport.enumeration(value, default: CenterPointHorizontal.origin)
            return true
        case "Vertical":
            vertical = CodecSupport.enumeration(value, default: CenterPointVertical.origin)
            return true
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "IsKeepPosition":
            isKeepPosition = CodecSupport.bool(value, default: false)
            return true
        case "Mode":
            // 旧互換（set 専用）: Horizontal / Vertical へ転送される。
            // 未知の名前は本家では到達不能な入力のため、消費せず
            // 追加フィールドとして保持する。
            let mode = CodecSupport.enumeration(value, default: CenterPointMode.unknown(""))
            switch mode {
            case .custom:
                vertical = .custom
                horizontal = .custom
            case .leftTop, .centerTop, .rightTop:
                vertical = .top
                horizontal = mode == .leftTop ? .left : (mode == .rightTop ? .right : .origin)
            case .leftBottom, .centerBottom, .rightBottom:
                vertical = .bottom
                horizontal = mode == .leftBottom ? .left : (mode == .rightBottom ? .right : .origin)
            case .leftCenter, .centerCenter, .rightCenter:
                vertical = .origin
                horizontal = mode == .leftCenter ? .left : (mode == .rightCenter ? .right : .origin)
            case .unknown:
                return false
            }
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Horizontal", value: .string(horizontal.honkeName)),
            (key: "Vertical", value: .string(vertical.honkeName)),
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "IsKeepPosition", value: .bool(isKeepPosition)),
        ] + super.encodeKnownFields()
    }
}

/// コピーして反転。本家 `CopyAndReverseEffect`。
/// パラメータ（実測）: Position は TopBottomLeftRight（既定 Bottom）、
/// Distance は Animation(既定 0, -100000〜100000)、IsTopBottomReversed
/// は bool（既定 true）、IsLeftRightReversed は bool（既定 false）、
/// IsCentering は bool（既定 true）。
public final class CopyAndReverseEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CopyAndReverseEffect, YukkuriMovieMaker"
    }

    /// コピー先の方向。
    public var position: TopBottomLeftRight = .bottom
    /// 間隔。
    public var distance = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 上下を反転するか。
    public var isTopBottomReversed: Bool = true
    /// 左右を反転するか。
    public var isLeftRightReversed: Bool = false
    /// 中心に寄せるか。
    public var isCentering: Bool = true

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&distance)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Position":
            position = CodecSupport.enumeration(value, default: TopBottomLeftRight.bottom)
            return true
        case "Distance":
            CodecSupport.decodeAnimation(value, into: &distance)
            return true
        case "IsTopBottomReversed":
            isTopBottomReversed = CodecSupport.bool(value, default: true)
            return true
        case "IsLeftRightReversed":
            isLeftRightReversed = CodecSupport.bool(value, default: false)
            return true
        case "IsCentering":
            isCentering = CodecSupport.bool(value, default: true)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Position", value: .string(position.honkeName)),
            (key: "Distance", value: CodecSupport.encodeAnimation(distance)),
            (key: "IsTopBottomReversed", value: .bool(isTopBottomReversed)),
            (key: "IsLeftRightReversed", value: .bool(isLeftRightReversed)),
            (key: "IsCentering", value: .bool(isCentering)),
        ] + super.encodeKnownFields()
    }
}

/// 角度で切り抜き。本家 `CropByAngleEffect`。
/// パラメータ（実測）: X / Y / Angle / Width は Animation(既定 0,
/// -100000〜100000)、Blur は Animation(既定 0, 0〜250)。
public final class CropByAngleEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CropByAngleEffect, YukkuriMovieMaker"
    }

    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 角度。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// ぼかし量。
    public var blur = Animation(defaultValue: 0, minValue: 0, maxValue: 250)
    /// 幅。
    public var width = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&angle)
        body(&blur)
        body(&width)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        case "Angle":
            CodecSupport.decodeAnimation(value, into: &angle)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        case "Width":
            CodecSupport.decodeAnimation(value, into: &width)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "Width", value: CodecSupport.encodeAnimation(width)),
        ] + super.encodeKnownFields()
    }
}

/// 切り抜き。本家 `CropEffect`。
/// パラメータ（実測）: Top / Bottom / Left / Right は Animation
/// (既定 0, 0〜100000)、IsCentering は bool（既定 true）。
public final class CropEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CropEffect, YukkuriMovieMaker"
    }

    /// 上の切り抜き量。
    public var top = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 下の切り抜き量。
    public var bottom = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 左の切り抜き量。
    public var left = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 右の切り抜き量。
    public var right = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 中心に寄せるか。
    public var isCentering: Bool = true

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&top)
        body(&bottom)
        body(&left)
        body(&right)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
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
        case "IsCentering":
            isCentering = CodecSupport.bool(value, default: true)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Top", value: CodecSupport.encodeAnimation(top)),
            (key: "Bottom", value: CodecSupport.encodeAnimation(bottom)),
            (key: "Left", value: CodecSupport.encodeAnimation(left)),
            (key: "Right", value: CodecSupport.encodeAnimation(right)),
            (key: "IsCentering", value: .bool(isCentering)),
        ] + super.encodeKnownFields()
    }
}

/// 余白。本家 `MarginEffect`。
/// パラメータ（実測）: Top / Bottom / Left / Right は Animation
/// (既定 0, 0〜100000)。
public final class MarginEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.MarginEffect, YukkuriMovieMaker"
    }

    /// 上の余白。
    public var top = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 下の余白。
    public var bottom = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 左の余白。
    public var left = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 右の余白。
    public var right = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&top)
        body(&bottom)
        body(&left)
        body(&right)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
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
            (key: "Top", value: CodecSupport.encodeAnimation(top)),
            (key: "Bottom", value: CodecSupport.encodeAnimation(bottom)),
            (key: "Left", value: CodecSupport.encodeAnimation(left)),
            (key: "Right", value: CodecSupport.encodeAnimation(right)),
        ] + super.encodeKnownFields()
    }
}

/// 極座標変換。本家 `PolarTransformEffect`。
/// パラメータ（実測）: CoreWidth は Animation(既定 0, 0〜2000)、
/// TwistAngle は Animation(既定 0, -2880〜2880)。
public final class PolarTransformEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.PolarTransformEffect, YukkuriMovieMaker"
    }

    /// 中心部の幅。
    public var coreWidth = Animation(defaultValue: 0, minValue: 0, maxValue: 2000)
    /// ねじれ角度。
    public var twistAngle = Animation(defaultValue: 0, minValue: -2880, maxValue: 2880)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&coreWidth)
        body(&twistAngle)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "CoreWidth":
            CodecSupport.decodeAnimation(value, into: &coreWidth)
            return true
        case "TwistAngle":
            CodecSupport.decodeAnimation(value, into: &twistAngle)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "CoreWidth", value: CodecSupport.encodeAnimation(coreWidth)),
            (key: "TwistAngle", value: CodecSupport.encodeAnimation(twistAngle)),
        ] + super.encodeKnownFields()
    }
}

/// 回転。本家 `RotateEffect`。
/// パラメータ（実測）: X / Y / Z は Animation(既定 0, -100000〜100000)、
/// Is3D は bool（既定 false）。
public final class RotateEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RotateEffect, YukkuriMovieMaker"
    }

    /// X 軸回転。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 軸回転。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Z 軸回転。
    public var z = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 3D 回転にするか。
    public var is3D: Bool = false

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

/// 角丸。本家 `RoundCornerEffect`。
/// パラメータ（実測）: Radius は Animation(既定 10, 0〜250)、
/// Blur は Animation(既定 1, 0〜100)。
public final class RoundCornerEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RoundCornerEffect, YukkuriMovieMaker"
    }

    /// 角の半径。
    public var radius = Animation(defaultValue: 10, minValue: 0, maxValue: 250)
    /// ぼかし量。
    public var blur = Animation(defaultValue: 1, minValue: 0, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&radius)
        body(&blur)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Radius":
            CodecSupport.decodeAnimation(value, into: &radius)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Radius", value: CodecSupport.encodeAnimation(radius)),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
        ] + super.encodeKnownFields()
    }
}

/// 傾斜。本家 `SkewEffect`。
/// パラメータ（実測）: AngleX / AngleY / CenterX / CenterY は
/// Animation(既定 0, -100000〜100000)、CenterPoint は SkewCenterPoint
/// （既定 Center）。
public final class SkewEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.SkewEffect, YukkuriMovieMaker"
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

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&angleX)
        body(&angleY)
        body(&centerX)
        body(&centerY)
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

/// タイリング。本家 `TilingEffect`。
/// パラメータ（実測）: X / Y は Animation(既定 3, 1〜100000)。
public final class TilingEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.TilingEffect, YukkuriMovieMaker"
    }

    /// 横の分割数。
    public var x = Animation(defaultValue: 3, minValue: 1, maxValue: 100000)
    /// 縦の分割数。
    public var y = Animation(defaultValue: 3, minValue: 1, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
            return true
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
        ] + super.encodeKnownFields()
    }
}

/// 円形複製。本家 `CircularDuplicatorEffect`。
/// パラメータ（実測）: Count は Animation(既定 4, 1〜100000)、
/// Radius は Animation(既定 100, -100000〜100000)、CircumferenceRate
/// は Animation(既定 100, 0〜100000)、IsSyncedAngle は bool（既定 true）。
public final class CircularDuplicatorEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CircularDuplicatorEffect, YukkuriMovieMaker"
    }

    /// 複製数。
    public var count = Animation(defaultValue: 4, minValue: 1, maxValue: 100000)
    /// 半径。
    public var radius = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)
    /// 円周の割合（%）。
    public var circumferenceRate = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 角度を同期するか。
    public var isSyncedAngle: Bool = true

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&count)
        body(&radius)
        body(&circumferenceRate)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Count":
            CodecSupport.decodeAnimation(value, into: &count)
            return true
        case "Radius":
            CodecSupport.decodeAnimation(value, into: &radius)
            return true
        case "CircumferenceRate":
            CodecSupport.decodeAnimation(value, into: &circumferenceRate)
            return true
        case "IsSyncedAngle":
            isSyncedAngle = CodecSupport.bool(value, default: true)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Count", value: CodecSupport.encodeAnimation(count)),
            (key: "Radius", value: CodecSupport.encodeAnimation(radius)),
            (key: "CircumferenceRate", value: CodecSupport.encodeAnimation(circumferenceRate)),
            (key: "IsSyncedAngle", value: .bool(isSyncedAngle)),
        ] + super.encodeKnownFields()
    }
}

/// ランダム複製。本家 `RandomDuplicatorEffect`。
/// パラメータ（実測）: Count は Animation(既定 1, 1〜100000)、
/// Range は Animation(既定 500, 0〜100000)、Rotation / RandomMove /
/// RandomRotation は Animation(既定 0, 0〜100000)、
/// IsThreeDimensional は bool（既定 false）。
public final class RandomDuplicatorEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.RandomDuplicatorEffect, YukkuriMovieMaker"
    }

    /// 複製数。
    public var count = Animation(defaultValue: 1, minValue: 1, maxValue: 100000)
    /// 配置範囲。
    public var range = Animation(defaultValue: 500, minValue: 0, maxValue: 100000)
    /// 回転量。
    public var rotation = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// 3D 配置にするか。
    public var isThreeDimensional: Bool = false
    /// ランダムな移動量。
    public var randomMove = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)
    /// ランダムな回転量。
    public var randomRotation = Animation(defaultValue: 0, minValue: 0, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&count)
        body(&range)
        body(&rotation)
        body(&randomMove)
        body(&randomRotation)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Count":
            CodecSupport.decodeAnimation(value, into: &count)
            return true
        case "Range":
            CodecSupport.decodeAnimation(value, into: &range)
            return true
        case "Rotation":
            CodecSupport.decodeAnimation(value, into: &rotation)
            return true
        case "IsThreeDimensional":
            isThreeDimensional = CodecSupport.bool(value, default: false)
            return true
        case "RandomMove":
            CodecSupport.decodeAnimation(value, into: &randomMove)
            return true
        case "RandomRotation":
            CodecSupport.decodeAnimation(value, into: &randomRotation)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Count", value: CodecSupport.encodeAnimation(count)),
            (key: "Range", value: CodecSupport.encodeAnimation(range)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
            (key: "IsThreeDimensional", value: .bool(isThreeDimensional)),
            (key: "RandomMove", value: CodecSupport.encodeAnimation(randomMove)),
            (key: "RandomRotation", value: CodecSupport.encodeAnimation(randomRotation)),
        ] + super.encodeKnownFields()
    }
}
