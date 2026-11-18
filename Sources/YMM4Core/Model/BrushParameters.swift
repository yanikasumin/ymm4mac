import Foundation

/// ブラシの座標モード。本家 `YukkuriMovieMaker.Commons.CoordinateMode`
/// （Pixel = 0, Relative = 1）。
public enum BrushCoordinateMode: HonkeEnum {
    case pixel
    case relative
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .pixel: return "Pixel"
        case .relative: return "Relative"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Pixel": self = .pixel
        case "Relative": self = .relative
        default: self = .unknown(name)
        }
    }
}

/// パターン系ブラシ共通の配置変換。本家 `DrawingBrushParameterBase` の
/// X / Y / Angle / Aspect / IsInverted に対応する。
/// 描画行列は本家 `CreateBrushMatrix` の合成順（アスペクト拡縮 →
/// 左右反転拡縮 → 回転 → 平行移動。行ベクトル規約で左から適用）で、
/// GPU 側が逆行列を組み立てて使う。
public struct BrushDrawingTransform {
    /// X 位置（px）。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 位置（px）。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 回転（°）。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// アスペクト（-100〜100）。
    public var aspect = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// 左右反転するか。
    public var isInverted: Bool = false

    public init() {}

    /// 既知キーを読み込む。処理したら true。
    public mutating func decodeField(_ key: String, _ value: JSONValue) -> Bool {
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
        case "Aspect":
            CodecSupport.decodeAnimation(value, into: &aspect)
            return true
        case "IsInverted":
            isInverted = CodecSupport.bool(value, default: false)
            return true
        default:
            return false
        }
    }

    /// 本家の宣言順（X / Y / Angle / Aspect / IsInverted）で書き出す。
    public func encodeFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "Aspect", value: CodecSupport.encodeAnimation(aspect)),
            (key: "IsInverted", value: .bool(isInverted)),
        ]
    }

    public mutating func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&angle)
        body(&aspect)
    }
}

/// グラデーションの分岐点列の読み書き（本家 `GradientStop` の列。
/// 実ファイルの形式は `{"Offset": …, "Color": "#AARRGGBB"}`）。
private func decodeStops(_ value: JSONValue?) -> [GradientStopValue]? {
    guard let elements = value?.arrayValue else { return nil }
    return elements.map { GradientStopValue(jsonValue: $0) }
}

private func encodeStops(_ stops: [GradientStopValue]) -> JSONValue {
    .array(stops.map { $0.encode() })
}

/// ブラシ既定の分岐点列（本家の各グラデーションブラシの初期値:
/// 0 = 白、1 = 黒）。
private var defaultGradientStops: [GradientStopValue] {
    [
        GradientStopValue(offset: 0, color: .white),
        GradientStopValue(offset: 1, color: .black),
    ]
}

/// 線形グラデーションブラシ。本家 `LinearGradientBrushParameter`。
/// パラメータ（実測）: Stops の既定は [(0, 白), (1, 黒)]、
/// CoordinateMode の既定は Pixel、Size は Animation(既定 100)、
/// Offset は Animation(既定 0)、Angle は Animation(既定 0)、
/// ExtendMode の既定は Clamp。Size / Offset / Angle の定義範囲は
/// いずれも -100000〜100000。
public final class LinearGradientBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Brush.LinearGradientBrushParameter, YukkuriMovieMaker"

    /// 色分岐点。
    public var stops: [GradientStopValue] = defaultGradientStops
    /// 座標モード。
    public var coordinateMode: BrushCoordinateMode = .pixel
    /// 大きさ（Relative では境界の射影長に対する %、Pixel では px）。
    public var size = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)
    /// ずれ（同上）。
    public var offset = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 角度（°）。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 延長方式。
    public var extendMode: ExtendMode = .clamp

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&size)
        body(&offset)
        body(&angle)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "Stops", value: encodeStops(stops)),
            (key: "CoordinateMode", value: .string(coordinateMode.honkeName)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
            (key: "Offset", value: CodecSupport.encodeAnimation(offset)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "ExtendMode", value: .string(extendMode.honkeName)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> LinearGradientBrushParameter {
        let parameter = LinearGradientBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "Stops":
                if let decoded = decodeStops(fieldValue) { parameter.stops = decoded }
            case "CoordinateMode":
                parameter.coordinateMode = CodecSupport.enumeration(
                    fieldValue, default: BrushCoordinateMode.pixel
                )
            case "Size":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.size)
            case "Offset":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.offset)
            case "Angle":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.angle)
            case "ExtendMode":
                parameter.extendMode = CodecSupport.enumeration(
                    fieldValue, default: ExtendMode.clamp
                )
            default:
                parameter.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return parameter
    }
}

/// 放射グラデーションブラシ。本家 `RadiulGradientBrushParameter`
/// （$type 名の "Radiul" は本家の綴りのまま）。
/// パラメータ（実測）: Stops の既定は [(0, 白), (1, 黒)]、
/// CenterX / CenterY / OriginX / OriginY は Animation(既定 0)、
/// RadiusX / RadiusY は Animation(既定 100)、Zoom は Animation
/// (既定 100)、Angle は Animation(既定 0)、Aspect は Animation
/// (既定 0, -100〜100)、ExtendMode の既定は Clamp、IsInverted は
/// bool（既定 false）。中心・原点・半径は境界に依らない絶対 px
/// （本家ソースは BrushSourceDescription.Bounds を使わない）。
public final class RadialGradientBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Brush.RadiulGradientBrushParameter, YukkuriMovieMaker"

    /// 色分岐点。
    public var stops: [GradientStopValue] = defaultGradientStops
    /// 中心 X（px）。
    public var centerX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 中心 Y（px）。
    public var centerY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 焦点の中心からのずれ X（px）。
    public var originX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 焦点の中心からのずれ Y（px）。
    public var originY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 半径 X（px）。
    public var radiusX = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)
    /// 半径 Y（px）。
    public var radiusY = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)
    /// 拡大率（%）。
    public var zoom = Animation(defaultValue: 100, minValue: -100000, maxValue: 100000)
    /// 回転（°）。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// アスペクト（-100〜100）。
    public var aspect = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// 延長方式。
    public var extendMode: ExtendMode = .clamp
    /// 左右反転するか。
    public var isInverted: Bool = false

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&centerX)
        body(&centerY)
        body(&originX)
        body(&originY)
        body(&radiusX)
        body(&radiusY)
        body(&zoom)
        body(&angle)
        body(&aspect)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "Stops", value: encodeStops(stops)),
            (key: "CenterX", value: CodecSupport.encodeAnimation(centerX)),
            (key: "CenterY", value: CodecSupport.encodeAnimation(centerY)),
            (key: "OriginX", value: CodecSupport.encodeAnimation(originX)),
            (key: "OriginY", value: CodecSupport.encodeAnimation(originY)),
            (key: "RadiusX", value: CodecSupport.encodeAnimation(radiusX)),
            (key: "RadiusY", value: CodecSupport.encodeAnimation(radiusY)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "Aspect", value: CodecSupport.encodeAnimation(aspect)),
            (key: "ExtendMode", value: .string(extendMode.honkeName)),
            (key: "IsInverted", value: .bool(isInverted)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> RadialGradientBrushParameter {
        let parameter = RadialGradientBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "Stops":
                if let decoded = decodeStops(fieldValue) { parameter.stops = decoded }
            case "CenterX":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.centerX)
            case "CenterY":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.centerY)
            case "OriginX":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.originX)
            case "OriginY":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.originY)
            case "RadiusX":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.radiusX)
            case "RadiusY":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.radiusY)
            case "Zoom":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.zoom)
            case "Angle":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.angle)
            case "Aspect":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.aspect)
            case "ExtendMode":
                parameter.extendMode = CodecSupport.enumeration(
                    fieldValue, default: ExtendMode.clamp
                )
            case "IsInverted":
                parameter.isInverted = CodecSupport.bool(fieldValue, default: false)
            default:
                parameter.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return parameter
    }
}

/// 市松ブラシ。本家 `CheckeredBrushParameter`。
/// パラメータ（実測）: Color1 の既定は白、Color2 の既定は黒、
/// Size は Animation(既定 100, 1〜8192)。本家は 2×Size のタイルを
/// ビットマップブラシ（Wrap）で敷く。
public final class CheckeredBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Brush.CheckeredBrushParameter, YukkuriMovieMaker"

    /// 色1（既定は白）。
    public var color1: Color = .white
    /// 色2（既定は黒）。
    public var color2: Color = .black
    /// セルの大きさ（px）。
    public var size = Animation(defaultValue: 100, minValue: 1, maxValue: 8192)
    /// 配置変換（本家 DrawingBrushParameterBase）。
    public var drawing = BrushDrawingTransform()

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&size)
        drawing.forEachAnimation(body)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "Color1", value: .string(color1.honkeString)),
            (key: "Color2", value: .string(color2.honkeString)),
            (key: "Size", value: CodecSupport.encodeAnimation(size)),
        ]
        fields += drawing.encodeFields()
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> CheckeredBrushParameter {
        let parameter = CheckeredBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "Color1":
                parameter.color1 = CodecSupport.color(fieldValue, default: parameter.color1)
            case "Color2":
                parameter.color2 = CodecSupport.color(fieldValue, default: parameter.color2)
            case "Size":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.size)
            default:
                if !parameter.drawing.decodeField(key, fieldValue) {
                    parameter.additionalFields.append((key: key, value: fieldValue))
                }
            }
        }
        return parameter
    }
}

/// ドットブラシ。本家 `DotBrushParameter`。
/// パラメータ（実測）: Foreground の既定は白、Background の既定は黒、
/// Radius は Animation(既定 10, 0〜16384)、Span は Animation
/// (既定 50, 1〜16384)、Zoom は Animation(既定 100, 0〜100000)。
/// Zoom は行列ではなく半径と間隔へ乗算される（本家ソースの実測）。
public final class DotBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Brush.DotBrushParameter, YukkuriMovieMaker"

    /// 点の色（既定は白）。
    public var foreground: Color = .white
    /// 背景色（既定は黒）。
    public var background: Color = .black
    /// 点の半径（px）。
    public var radius = Animation(defaultValue: 10, minValue: 0, maxValue: 16384)
    /// 点の間隔（px）。
    public var span = Animation(defaultValue: 50, minValue: 1, maxValue: 16384)
    /// 拡大率（%。半径と間隔へ乗算）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 配置変換（本家 DrawingBrushParameterBase）。
    public var drawing = BrushDrawingTransform()

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&radius)
        body(&span)
        body(&zoom)
        drawing.forEachAnimation(body)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "Foreground", value: .string(foreground.honkeString)),
            (key: "Background", value: .string(background.honkeString)),
            (key: "Radius", value: CodecSupport.encodeAnimation(radius)),
            (key: "Span", value: CodecSupport.encodeAnimation(span)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
        ]
        fields += drawing.encodeFields()
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> DotBrushParameter {
        let parameter = DotBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "Foreground":
                parameter.foreground = CodecSupport.color(
                    fieldValue, default: parameter.foreground
                )
            case "Background":
                parameter.background = CodecSupport.color(
                    fieldValue, default: parameter.background
                )
            case "Radius":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.radius)
            case "Span":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.span)
            case "Zoom":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.zoom)
            default:
                if !parameter.drawing.decodeField(key, fieldValue) {
                    parameter.additionalFields.append((key: key, value: fieldValue))
                }
            }
        }
        return parameter
    }
}

/// ストライプブラシ。本家 `StripeBrushParameter`。
/// パラメータ（実測）: Color1 の既定は白、Width1 は Animation
/// (既定 50)、Color2 の既定は黒、Width2 は Animation(既定 50)、
/// Offset は Animation(既定 0)、Zoom は Animation(既定 100)、
/// Angle は Animation(既定 0)。定義範囲はいずれも -100000〜100000
/// （Zoom は 0〜100000）。本家は Wrap の線形グラデーション
/// （分岐点 0 / w1/(w1+w2) / 同位置 / 1）として描く。
public final class StripeBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Brush.StripeBrushParameter, YukkuriMovieMaker"

    /// 色1（既定は白）。
    public var color1: Color = .white
    /// 色1の幅（px）。
    public var width1 = Animation(defaultValue: 50, minValue: 0, maxValue: 100000)
    /// 色2（既定は黒）。
    public var color2: Color = .black
    /// 色2の幅（px）。
    public var width2 = Animation(defaultValue: 50, minValue: 0, maxValue: 100000)
    /// ずれ（px）。
    public var offset = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 拡大率（%。幅とずれへ乗算）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 角度（°）。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&width1)
        body(&width2)
        body(&offset)
        body(&zoom)
        body(&angle)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "Color1", value: .string(color1.honkeString)),
            (key: "Width1", value: CodecSupport.encodeAnimation(width1)),
            (key: "Color2", value: .string(color2.honkeString)),
            (key: "Width2", value: CodecSupport.encodeAnimation(width2)),
            (key: "Offset", value: CodecSupport.encodeAnimation(offset)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> StripeBrushParameter {
        let parameter = StripeBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "Color1":
                parameter.color1 = CodecSupport.color(fieldValue, default: parameter.color1)
            case "Width1":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.width1)
            case "Color2":
                parameter.color2 = CodecSupport.color(fieldValue, default: parameter.color2)
            case "Width2":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.width2)
            case "Offset":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.offset)
            case "Zoom":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.zoom)
            case "Angle":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.angle)
            default:
                parameter.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return parameter
    }
}

/// 格子線ブラシ。本家 `GridLineBrushParameter`。
/// パラメータ（実測）: StrokeColor の既定は白、BackgroundColor の
/// 既定は透明、Thickness は Animation(既定 1, 0〜16384)、Width /
/// Height は Animation(既定 100, 1〜16384)、Zoom は Animation
/// (既定 100, 0〜100000)。Zoom は太さとタイル寸法へ乗算される。
public final class GridLineBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Brush.GridLineBrushParameter, YukkuriMovieMaker"

    /// 線の色（既定は白）。
    public var strokeColor: Color = .white
    /// 背景色（既定は透明）。
    public var backgroundColor: Color = .transparent
    /// 線の太さ（px）。
    public var thickness = Animation(defaultValue: 1, minValue: 0, maxValue: 16384)
    /// タイルの幅（px）。
    public var width = Animation(defaultValue: 100, minValue: 1, maxValue: 16384)
    /// タイルの高さ（px）。
    public var height = Animation(defaultValue: 100, minValue: 1, maxValue: 16384)
    /// 拡大率（%。太さとタイル寸法へ乗算）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 配置変換（本家 DrawingBrushParameterBase）。
    public var drawing = BrushDrawingTransform()

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&thickness)
        body(&width)
        body(&height)
        body(&zoom)
        drawing.forEachAnimation(body)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "StrokeColor", value: .string(strokeColor.honkeString)),
            (key: "BackgroundColor", value: .string(backgroundColor.honkeString)),
            (key: "Thickness", value: CodecSupport.encodeAnimation(thickness)),
            (key: "Width", value: CodecSupport.encodeAnimation(width)),
            (key: "Height", value: CodecSupport.encodeAnimation(height)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
        ]
        fields += drawing.encodeFields()
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> GridLineBrushParameter {
        let parameter = GridLineBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "StrokeColor":
                parameter.strokeColor = CodecSupport.color(
                    fieldValue, default: parameter.strokeColor
                )
            case "BackgroundColor":
                parameter.backgroundColor = CodecSupport.color(
                    fieldValue, default: parameter.backgroundColor
                )
            case "Thickness":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.thickness)
            case "Width":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.width)
            case "Height":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.height)
            case "Zoom":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.zoom)
            default:
                if !parameter.drawing.decodeField(key, fieldValue) {
                    parameter.additionalFields.append((key: key, value: fieldValue))
                }
            }
        }
        return parameter
    }
}

/// グラデーションメッシュの格子点。本家 `GradientMeshPoint`。
/// X / Y は格子位置へのオフセット（% 座標。配置はパラメータ側が
/// 幅・高さから決める）、8 本のハンドル値は点位置へのオフセット。
/// ハンドルはカスタムフラグが立った方向だけが有効で、それ以外は
/// パッチ構築時に隣接点から導出される。
public final class GradientMeshPointValue {
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var leftHandleX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var leftHandleY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var rightHandleX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var rightHandleY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var upHandleX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var upHandleY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var downHandleX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var downHandleY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    public var isLeftHandleCustom = false
    public var isRightHandleCustom = false
    public var isUpHandleCustom = false
    public var isDownHandleCustom = false
    public var color: Color = .white
    public var isSelected = false
    /// 本家に無い、または型付き化していないフィールドの生保持。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public convenience init(color: Color) {
        self.init()
        self.color = color
    }

    func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&leftHandleX)
        body(&leftHandleY)
        body(&rightHandleX)
        body(&rightHandleY)
        body(&upHandleX)
        body(&upHandleY)
        body(&downHandleX)
        body(&downHandleY)
    }

    /// 本家の宣言順にキーを並べる。
    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = []
        fields.append(("X", CodecSupport.encodeAnimation(x)))
        fields.append(("Y", CodecSupport.encodeAnimation(y)))
        fields.append(("LeftHandleX", CodecSupport.encodeAnimation(leftHandleX)))
        fields.append(("LeftHandleY", CodecSupport.encodeAnimation(leftHandleY)))
        fields.append(("RightHandleX", CodecSupport.encodeAnimation(rightHandleX)))
        fields.append(("RightHandleY", CodecSupport.encodeAnimation(rightHandleY)))
        fields.append(("UpHandleX", CodecSupport.encodeAnimation(upHandleX)))
        fields.append(("UpHandleY", CodecSupport.encodeAnimation(upHandleY)))
        fields.append(("DownHandleX", CodecSupport.encodeAnimation(downHandleX)))
        fields.append(("DownHandleY", CodecSupport.encodeAnimation(downHandleY)))
        fields.append(("IsLeftHandleCustom", .bool(isLeftHandleCustom)))
        fields.append(("IsRightHandleCustom", .bool(isRightHandleCustom)))
        fields.append(("IsUpHandleCustom", .bool(isUpHandleCustom)))
        fields.append(("IsDownHandleCustom", .bool(isDownHandleCustom)))
        fields.append(("Color", .string(color.honkeString)))
        fields.append(("IsSelected", .bool(isSelected)))
        fields.append(contentsOf: additionalFields)
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> GradientMeshPointValue {
        let point = GradientMeshPointValue()
        guard let fields = value.objectFields else { return point }
        for (key, fieldValue) in fields {
            switch key {
            case "X": CodecSupport.decodeAnimation(fieldValue, into: &point.x)
            case "Y": CodecSupport.decodeAnimation(fieldValue, into: &point.y)
            case "LeftHandleX": CodecSupport.decodeAnimation(fieldValue, into: &point.leftHandleX)
            case "LeftHandleY": CodecSupport.decodeAnimation(fieldValue, into: &point.leftHandleY)
            case "RightHandleX": CodecSupport.decodeAnimation(fieldValue, into: &point.rightHandleX)
            case "RightHandleY": CodecSupport.decodeAnimation(fieldValue, into: &point.rightHandleY)
            case "UpHandleX": CodecSupport.decodeAnimation(fieldValue, into: &point.upHandleX)
            case "UpHandleY": CodecSupport.decodeAnimation(fieldValue, into: &point.upHandleY)
            case "DownHandleX": CodecSupport.decodeAnimation(fieldValue, into: &point.downHandleX)
            case "DownHandleY": CodecSupport.decodeAnimation(fieldValue, into: &point.downHandleY)
            case "IsLeftHandleCustom": point.isLeftHandleCustom = CodecSupport.bool(fieldValue, default: false)
            case "IsRightHandleCustom": point.isRightHandleCustom = CodecSupport.bool(fieldValue, default: false)
            case "IsUpHandleCustom": point.isUpHandleCustom = CodecSupport.bool(fieldValue, default: false)
            case "IsDownHandleCustom": point.isDownHandleCustom = CodecSupport.bool(fieldValue, default: false)
            case "Color": point.color = CodecSupport.color(fieldValue, default: point.color)
            case "IsSelected": point.isSelected = CodecSupport.bool(fieldValue, default: false)
            default: point.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return point
    }
}

/// グラデーションメッシュブラシ。本家
/// `GradientMeshBrushParameter`（`ScalableDrawingBrushParameterBase`
/// 派生）。格子点の色を Coons パッチで補間して塗る。点の論理配置・
/// ハンドル導出・パッチ構築は本家の
/// `GradientMeshCoordinateHelper` / `GradientMeshPatchBuilder` の
/// 仕様どおり（GPU 側 `GradientMeshGeometry`）。
public final class GradientMeshBrushParameter {
    public static let typeName = "YukkuriMovieMaker.Brush.GradientMeshBrushParameter, YukkuriMovieMaker"

    /// 描画に使う点数の上限（本家 UI の範囲 2〜50 の上限）。
    /// 保存データは範囲外の値もそのまま保持するが、描画側は
    /// 点数の乗算より前にこの上限で検証する。外部ファイル由来の
    /// 極端な値で乗算がオーバーフローし、プロセスが停止するのを防ぐ。
    public static let maximumPointCount = 50

    /// 横の点数（2〜50。本家 UI の範囲）。
    public var horizontalCount: Int = 2
    /// 縦の点数（2〜50）。
    public var verticalCount: Int = 2
    public var coordinateMode: BrushCoordinateMode = .relative
    /// メッシュの論理幅（% 座標）。
    public var width = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// メッシュの論理高さ（% 座標）。
    public var height = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// メッシュの外側へ拡張パッチで塗りを広げるか。
    public var extendOutside: Bool = true
    /// 格子点（行優先: index = row * horizontalCount + column）。
    public var points: [GradientMeshPointValue] = GradientMeshBrushParameter.defaultPoints
    /// 本家 `ScalableDrawingBrushParameterBase.Zoom`。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    public var drawing = BrushDrawingTransform()
    /// 本家に無い、または型付き化していないフィールドの生保持。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    /// 本家の既定点（2×2: Red / Gold / RoyalBlue / Cyan。
    /// 本家コンストラクタでは先頭点だけ IsSelected が立つ）。
    public static var defaultPoints: [GradientMeshPointValue] {
        let first = GradientMeshPointValue(
            color: Color(alpha: 255, red: 255, green: 0, blue: 0)
        )
        first.isSelected = true
        return [
            first,
            GradientMeshPointValue(color: Color(alpha: 255, red: 255, green: 215, blue: 0)),
            GradientMeshPointValue(color: Color(alpha: 255, red: 65, green: 105, blue: 225)),
            GradientMeshPointValue(color: Color(alpha: 255, red: 0, green: 255, blue: 255)),
        ]
    }

    public init() {}

    /// 格子寸法と点列を一体で変更し、常に
    /// `points.count == horizontalCount * verticalCount` を保つ。
    /// 既存の点は (行, 列) の位置で保持し、新しい位置は既定点で
    /// 埋める。寸法は本家 UI の範囲（2〜上限）へ丸める。編集操作は
    /// 寸法と点列を別々に触らず、必ずこの経路を通す（R21-117-02）。
    public func resizeGrid(horizontal newHorizontal: Int, vertical newVertical: Int) {
        let h = min(max(newHorizontal, 2), Self.maximumPointCount)
        let v = min(max(newVertical, 2), Self.maximumPointCount)
        let oldPoints = points
        let oldHorizontal = horizontalCount
        let oldVertical = verticalCount
        var rebuilt: [GradientMeshPointValue] = []
        rebuilt.reserveCapacity(h * v)
        for row in 0..<v {
            for column in 0..<h {
                let oldIndex = row * oldHorizontal + column
                if row < oldVertical, column < oldHorizontal,
                   oldPoints.indices.contains(oldIndex) {
                    rebuilt.append(oldPoints[oldIndex])
                } else {
                    rebuilt.append(GradientMeshPointValue())
                }
            }
        }
        horizontalCount = h
        verticalCount = v
        points = rebuilt
    }

    func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&width)
        body(&height)
        body(&zoom)
        drawing.forEachAnimation(body)
        for point in points {
            point.forEachAnimation(body)
        }
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "HorizontalCount", value: .number(Double(horizontalCount))),
            (key: "VerticalCount", value: .number(Double(verticalCount))),
            (key: "CoordinateMode", value: .string(coordinateMode.honkeName)),
            (key: "Width", value: CodecSupport.encodeAnimation(width)),
            (key: "Height", value: CodecSupport.encodeAnimation(height)),
            (key: "ExtendOutside", value: .bool(extendOutside)),
            (key: "Points", value: .array(points.map { $0.encodeToJSONValue() })),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
        ]
        fields += drawing.encodeFields()
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> GradientMeshBrushParameter {
        let parameter = GradientMeshBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "HorizontalCount":
                parameter.horizontalCount = CodecSupport.int(fieldValue, default: 2)
            case "VerticalCount":
                parameter.verticalCount = CodecSupport.int(fieldValue, default: 2)
            case "CoordinateMode":
                parameter.coordinateMode = CodecSupport.enumeration(
                    fieldValue, default: BrushCoordinateMode.relative
                )
            case "Width":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.width)
            case "Height":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.height)
            case "ExtendOutside":
                parameter.extendOutside = CodecSupport.bool(fieldValue, default: true)
            case "Points":
                if case .array(let items) = fieldValue {
                    parameter.points = items.map { GradientMeshPointValue.decode(from: $0) }
                }
            case "Zoom":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.zoom)
            default:
                if !parameter.drawing.decodeField(key, fieldValue) {
                    parameter.additionalFields.append((key: key, value: fieldValue))
                }
            }
        }
        return parameter
    }
}

/// ビットマップブラシ。本家 `BitmapBrushParameter`。
/// パラメータ（実測）: FilePath の既定は ""、PlaybackRate は double
/// （既定 100)、ContentOffset は TimeSpan（既定 0)、ExtendModeX /
/// ExtendModeY の既定は Wrap。配置変換は ScalableDrawingBrush
/// ParameterBase（Zoom + DrawingBrushParameterBase）。
/// 動画ファイルも指定できるが、GPU 側の供給は画像のみ（実装記録参照）。
public final class BitmapBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Brush.BitmapBrushParameter, YukkuriMovieMaker"

    /// テクスチャのファイルパス（null もありうる）。
    public var filePath: String? = ""
    /// 再生速度（%。動画用）。
    public var playbackRate: Double = 100
    /// 内容の開始位置（動画用）。
    public var contentOffset: TimeSpanValue = .zero
    /// 横方向の延長方式。
    public var extendModeX: ExtendMode = .wrap
    /// 縦方向の延長方式。
    public var extendModeY: ExtendMode = .wrap
    /// 拡大率（%。配置変換の先頭に拡縮として入る）。
    public var zoom = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 配置変換（本家 DrawingBrushParameterBase）。
    public var drawing = BrushDrawingTransform()

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&zoom)
        drawing.forEachAnimation(body)
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "FilePath", value: filePath.map { JSONValue.string($0) } ?? .null),
            (key: "PlaybackRate", value: .number(playbackRate)),
            (key: "ContentOffset", value: .string(contentOffset.honkeString)),
            (key: "ExtendModeX", value: .string(extendModeX.honkeName)),
            (key: "ExtendModeY", value: .string(extendModeY.honkeName)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
        ]
        fields += drawing.encodeFields()
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> BitmapBrushParameter {
        let parameter = BitmapBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "FilePath":
                parameter.filePath = fieldValue == .null ? nil : fieldValue.stringValue
            case "PlaybackRate":
                parameter.playbackRate = CodecSupport.double(fieldValue, default: 100)
            case "ContentOffset":
                parameter.contentOffset = CodecSupport.timeSpan(fieldValue, default: .zero)
            case "ExtendModeX":
                parameter.extendModeX = CodecSupport.enumeration(
                    fieldValue, default: ExtendMode.wrap
                )
            case "ExtendModeY":
                parameter.extendModeY = CodecSupport.enumeration(
                    fieldValue, default: ExtendMode.wrap
                )
            case "Zoom":
                CodecSupport.decodeAnimation(fieldValue, into: &parameter.zoom)
            default:
                if !parameter.drawing.decodeField(key, fieldValue) {
                    parameter.additionalFields.append((key: key, value: fieldValue))
                }
            }
        }
        return parameter
    }
}

/// ノイズブラシ。本家 `NoiseBrushParameter`。
/// パラメータ（実測）: NoiseType の既定は Fractal、Color1 の既定は
/// 白、Color2 の既定は黒、IsColor / IsUniqueSeed は bool（既定
/// false）。NoiseParameter はノイズエフェクトと同じ多態オブジェクト
/// で、そちらの定義と同じく生保持に倒す（型付き化はノイズ生成器の
/// 実装と一体のため）。
public final class NoiseBrushParameter {
    /// $type 名。
    public static let typeName =
        "YukkuriMovieMaker.Brush.NoiseBrushParameter, YukkuriMovieMaker"

    /// ノイズの生成方式。
    public var noiseType: NoiseType = .fractal
    /// ノイズパラメータ（生保持。本家 `NoiseParameterBase`）。
    public var noiseParameter: PreservedObject?
    /// 色1（既定は白）。
    public var color1: Color = .white
    /// 色2（既定は黒）。
    public var color2: Color = .black
    /// カラーノイズにするか。
    public var isColor: Bool = false
    /// 固有シードを使うか。
    public var isUniqueSeed: Bool = false

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        // 本家 GetAnimatables は NoiseParameter だけを返すが、その内部は
        // 生保持のため走査対象が無い。
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(Self.typeName)),
            (key: "NoiseType", value: .string(noiseType.honkeName)),
        ]
        if let noiseParameter {
            fields.append((key: "NoiseParameter", value: noiseParameter.value))
        }
        fields += [
            (key: "Color1", value: .string(color1.honkeString)),
            (key: "Color2", value: .string(color2.honkeString)),
            (key: "IsColor", value: .bool(isColor)),
            (key: "IsUniqueSeed", value: .bool(isUniqueSeed)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> NoiseBrushParameter {
        let parameter = NoiseBrushParameter()
        guard let fields = value.objectFields else { return parameter }
        for (key, fieldValue) in fields {
            switch key {
            case "$type":
                break
            case "NoiseType":
                parameter.noiseType = CodecSupport.enumeration(
                    fieldValue, default: NoiseType.fractal
                )
            case "NoiseParameter":
                parameter.noiseParameter = CodecSupport.preservedObject(fieldValue)
            case "Color1":
                parameter.color1 = CodecSupport.color(fieldValue, default: parameter.color1)
            case "Color2":
                parameter.color2 = CodecSupport.color(fieldValue, default: parameter.color2)
            case "IsColor":
                parameter.isColor = CodecSupport.bool(fieldValue, default: false)
            case "IsUniqueSeed":
                parameter.isUniqueSeed = CodecSupport.bool(fieldValue, default: false)
            default:
                parameter.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return parameter
    }
}
