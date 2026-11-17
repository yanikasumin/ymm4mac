import Foundation

// GPU 処理系の歪み・ワープ・生成系エフェクトの定義層。
//
// いずれも処理器は暫定の素通し（`GPUEffectDefinitionBase` が返す
// `GPUEffectPassthroughProcessor`）であり、画像の加工はまだ行われない。
// パラメータの型・既定値・範囲は本家定義クラスの実測に基づく。

/// 崩壊。本家 `CrashEffect`。
/// パラメータ（実測）: StartTime は double（既定 0）、PlaybackRate /
/// FlySpeed / FallSpeed / Delay / Impact / RandomRotate /
/// RandomVector は double（既定 100）、Size は double（既定 50）、
/// X / Y / Z は Animation(既定 0, -100000〜100000)。
public final class CrashEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CrashEffect, YukkuriMovieMaker"
    }

    /// 開始時刻（秒）。
    public var startTime: Double = 0
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
        case "StartTime":
            startTime = CodecSupport.double(value, default: 0)
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
            (key: "StartTime", value: .number(startTime)),
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

/// ディスプレイスメントマップ。本家 `DisplacementMapEffect`。
/// パラメータ（実測）: Mode は DisplacementMapTransformMode
/// （既定 Move）、Blur は Animation(既定 10, 0〜250)、
/// IsPatternMapPreviewEnabled は bool（既定 false）。Transform
/// （変形パラメータ）と Brush（パターンのブラシ）は多態オブジェクト
/// であり、プラグイン型のパラメータとして生保持に倒す。旧互換の
/// set 専用 `FilePath` / `XScale` / `YScale` / `X` / `Y` / `Rotation`
/// / `Aspect` は生保持の内部へ転送されるもので、内部は書き換えない
/// ため、追加フィールドとしてそのまま保持する（変換は行わない）。
public final class DisplacementMapEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.DisplacementMapEffect, YukkuriMovieMaker"
    }

    /// 変形方式。
    public var mode: DisplacementMapTransformMode = .move
    /// 変形パラメータ（生保持。本家 `DisplacementMapTransformBase`）。
    public var transform: PreservedObject?
    /// ぼかし量。
    public var blur = Animation(defaultValue: 10, minValue: 0, maxValue: 250)
    /// パターンマップのプレビューを表示するか。
    public var isPatternMapPreviewEnabled: Bool = false
    /// パターンのブラシ（生保持）。
    public var brush: PreservedObject?

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
        case "IsPatternMapPreviewEnabled":
            isPatternMapPreviewEnabled = CodecSupport.bool(value, default: false)
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
            (key: "Mode", value: .string(mode.honkeName)),
        ]
        if let transform {
            fields.append((key: "Transform", value: transform.value))
        }
        fields.append((key: "Blur", value: CodecSupport.encodeAnimation(blur)))
        fields.append((key: "IsPatternMapPreviewEnabled", value: .bool(isPatternMapPreviewEnabled)))
        if let brush {
            fields.append((key: "Brush", value: brush.value))
        }
        return fields + super.encodeKnownFields()
    }
}

/// メッシュ変形の制御点。本家 `MeshDeformationPoint`。
public struct MeshDeformationPointValue: Equatable, Sendable {
    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 選択されているか。
    public var isSelected: Bool = false
    /// 型付けしていないキーの生保持（データ保全）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    public static func == (lhs: MeshDeformationPointValue, rhs: MeshDeformationPointValue) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.isSelected == rhs.isSelected
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
            case "X":
                CodecSupport.decodeAnimation(value, into: &x)
            case "Y":
                CodecSupport.decodeAnimation(value, into: &y)
            case "IsSelected":
                isSelected = CodecSupport.bool(value, default: false)
            default:
                additionalFields.append((key: key, value: value))
            }
        }
    }

    /// オブジェクト形式へ書き出す。
    public func encode() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "IsSelected", value: .bool(isSelected)),
        ]
        fields += additionalFields.filter {
            $0.key != "X" && $0.key != "Y" && $0.key != "IsSelected"
        }
        return .object(fields)
    }
}

/// メッシュ変形。本家 `MeshDeformationEffect`。
/// パラメータ（実測）: HorizontalCount / VerticalCount は int
/// （既定 2)、Smoothness は Animation(既定 0, 0〜100)、Points の
/// 既定は既定値の制御点4件。
public final class MeshDeformationEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.MeshDeformationEffect, YukkuriMovieMaker"
    }

    /// 横の分割数。
    public var horizontalCount: Int = 2
    /// 縦の分割数。
    public var verticalCount: Int = 2
    /// 滑らかさ（%）。
    public var smoothness = Animation(defaultValue: 0, minValue: 0, maxValue: 100)
    /// 制御点。
    public var points: [MeshDeformationPointValue] = [
        MeshDeformationPointValue(), MeshDeformationPointValue(),
        MeshDeformationPointValue(), MeshDeformationPointValue(),
    ]

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        for index in points.indices {
            body(&points[index].x)
            body(&points[index].y)
        }
        body(&smoothness)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "HorizontalCount":
            horizontalCount = CodecSupport.int(value, default: 2)
            return true
        case "VerticalCount":
            verticalCount = CodecSupport.int(value, default: 2)
            return true
        case "Smoothness":
            CodecSupport.decodeAnimation(value, into: &smoothness)
            return true
        case "Points":
            if let elements = value.arrayValue {
                points = elements.map { MeshDeformationPointValue(jsonValue: $0) }
            }
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "HorizontalCount", value: .number(horizontalCount)),
            (key: "VerticalCount", value: .number(verticalCount)),
            (key: "Smoothness", value: CodecSupport.encodeAnimation(smoothness)),
            (key: "Points", value: .array(points.map { $0.encode() })),
        ] + super.encodeKnownFields()
    }
}

/// ノイズディスプレイスメントマップ。本家 `NoiseDisplacementMapEffect`。
/// パラメータ（実測）: Mode は DisplacementMapTransformMode
/// （既定 Move)、Blur は Animation(既定 0, 0〜250)、NoiseType は
/// 既定 Perlin。Transform と NoiseParameter は多態オブジェクトの
/// ため生保持に倒す。旧互換の set 専用 `X` / `Y` は追加フィールド
/// としてそのまま保持する（`NoiseColorShiftEffect` と同じ扱い）。
public final class NoiseDisplacementMapEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.NoiseDisplacementMapEffect, YukkuriMovieMaker"
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

/// ノイズ。本家 `NoiseEffect`。
/// パラメータ（実測）: NoiseType は既定 Fractal（enum の先頭メンバ）、
/// IsColor は bool（既定 false）、IsAlpha は bool（既定 true）、
/// IsUniqueSeed は bool（既定 false）。NoiseParameter は多態
/// オブジェクトのため生保持に倒す。
public final class NoiseEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.NoiseEffect, YukkuriMovieMaker"
    }

    /// ノイズの生成方式。
    public var noiseType: NoiseType = .fractal
    /// ノイズパラメータ（生保持。本家 `NoiseParameterBase`）。
    public var noiseParameter: PreservedObject?
    /// カラーノイズにするか。
    public var isColor: Bool = false
    /// アルファにも適用するか。
    public var isAlpha: Bool = true
    /// 固有のシードを使うか。
    public var isUniqueSeed: Bool = false

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "NoiseType":
            noiseType = CodecSupport.enumeration(value, default: NoiseType.fractal)
            return true
        case "NoiseParameter":
            noiseParameter = CodecSupport.preservedObject(value)
            return true
        case "IsColor":
            isColor = CodecSupport.bool(value, default: false)
            return true
        case "IsAlpha":
            isAlpha = CodecSupport.bool(value, default: true)
            return true
        case "IsUniqueSeed":
            isUniqueSeed = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "NoiseType", value: .string(noiseType.honkeName)),
        ]
        if let noiseParameter {
            fields.append((key: "NoiseParameter", value: noiseParameter.value))
        }
        fields += [
            (key: "IsColor", value: .bool(isColor)),
            (key: "IsAlpha", value: .bool(isAlpha)),
            (key: "IsUniqueSeed", value: .bool(isUniqueSeed)),
        ]
        return fields + super.encodeKnownFields()
    }
}

/// モルフォロジー。本家 `MorphologyEffect`。
/// パラメータ（実測）: Mode は MorphologyEffectMode（既定 Erode)、
/// Width / Height は Animation(既定 1, 1〜100)。
public final class MorphologyEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.MorphologyEffect, YukkuriMovieMaker"
    }

    /// 方式。
    public var mode: MorphologyEffectMode = .erode
    /// 幅。
    public var width = Animation(defaultValue: 1, minValue: 1, maxValue: 100)
    /// 高さ。
    public var height = Animation(defaultValue: 1, minValue: 1, maxValue: 100)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&width)
        body(&height)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Mode":
            mode = CodecSupport.enumeration(value, default: MorphologyEffectMode.erode)
            return true
        case "Width":
            CodecSupport.decodeAnimation(value, into: &width)
            return true
        case "Height":
            CodecSupport.decodeAnimation(value, into: &height)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Mode", value: .string(mode.honkeName)),
            (key: "Width", value: CodecSupport.encodeAnimation(width)),
            (key: "Height", value: CodecSupport.encodeAnimation(height)),
        ] + super.encodeKnownFields()
    }
}

/// 描画遅延。本家 `DrawLazyEffectEffect`。
/// パラメータ（実測）: IsXYZ / IsOpacity / IsZoom / IsRotation /
/// IsInvert / IsCamera は全て bool（既定 false）。Animation は持たない。
public final class DrawLazyEffectEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.DrawLazyEffectEffect, YukkuriMovieMaker"
    }

    /// 座標を遅延させるか。
    public var isXYZ: Bool = false
    /// 不透明度を遅延させるか。
    public var isOpacity: Bool = false
    /// 拡大率を遅延させるか。
    public var isZoom: Bool = false
    /// 回転を遅延させるか。
    public var isRotation: Bool = false
    /// 反転を遅延させるか。
    public var isInvert: Bool = false
    /// カメラを遅延させるか。
    public var isCamera: Bool = false

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsXYZ":
            isXYZ = CodecSupport.bool(value, default: false)
            return true
        case "IsOpacity":
            isOpacity = CodecSupport.bool(value, default: false)
            return true
        case "IsZoom":
            isZoom = CodecSupport.bool(value, default: false)
            return true
        case "IsRotation":
            isRotation = CodecSupport.bool(value, default: false)
            return true
        case "IsInvert":
            isInvert = CodecSupport.bool(value, default: false)
            return true
        case "IsCamera":
            isCamera = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "IsXYZ", value: .bool(isXYZ)),
            (key: "IsOpacity", value: .bool(isOpacity)),
            (key: "IsZoom", value: .bool(isZoom)),
            (key: "IsRotation", value: .bool(isRotation)),
            (key: "IsInvert", value: .bool(isInvert)),
            (key: "IsCamera", value: .bool(isCamera)),
        ] + super.encodeKnownFields()
    }
}

/// ジャンプ。本家 `JumpEffect`。
/// パラメータ（実測）: JumpHeight は Animation(既定 100, 0〜100000)、
/// Stretch は Animation(既定 25, 0〜100000)、Period は Animation
/// (既定 0.5, 0〜100000)、Distortion は Animation(既定 25, 0〜100)、
/// Interval は Animation(既定 0.3, 0〜100000)、X / Y は Animation
/// (既定 0, -100000〜100000)。
public final class JumpEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.JumpEffect, YukkuriMovieMaker"
    }

    /// ジャンプの高さ。
    public var jumpHeight = Animation(defaultValue: 100, minValue: 0, maxValue: 100000)
    /// 伸縮量。
    public var stretch = Animation(defaultValue: 25, minValue: 0, maxValue: 100000)
    /// 周期（秒）。
    public var period = Animation(defaultValue: 0.5, minValue: 0, maxValue: 100000)
    /// 歪み量。
    public var distortion = Animation(defaultValue: 25, minValue: 0, maxValue: 100)
    /// 間隔（秒）。
    public var interval = Animation(defaultValue: 0.3, minValue: 0, maxValue: 100000)
    /// X 座標。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 座標。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&jumpHeight)
        body(&stretch)
        body(&period)
        body(&distortion)
        body(&interval)
        body(&x)
        body(&y)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "JumpHeight":
            CodecSupport.decodeAnimation(value, into: &jumpHeight)
            return true
        case "Stretch":
            CodecSupport.decodeAnimation(value, into: &stretch)
            return true
        case "Period":
            CodecSupport.decodeAnimation(value, into: &period)
            return true
        case "Distortion":
            CodecSupport.decodeAnimation(value, into: &distortion)
            return true
        case "Interval":
            CodecSupport.decodeAnimation(value, into: &interval)
            return true
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
            (key: "JumpHeight", value: CodecSupport.encodeAnimation(jumpHeight)),
            (key: "Stretch", value: CodecSupport.encodeAnimation(stretch)),
            (key: "Period", value: CodecSupport.encodeAnimation(period)),
            (key: "Distortion", value: CodecSupport.encodeAnimation(distortion)),
            (key: "Interval", value: CodecSupport.encodeAnimation(interval)),
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
        ] + super.encodeKnownFields()
    }
}
