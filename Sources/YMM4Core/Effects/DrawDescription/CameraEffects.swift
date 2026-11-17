import Foundation

/// カメラ系エフェクトの共有計算。本家 `CameraFovEffect` 処理器の
/// `CalculatePerspectiveDistance` に対応する。
public enum CameraEffectMath {
    /// 垂直画角（度）と画面の高さから透視距離を求める。
    ///
    /// 非有限の画角は 56.7380926（高さ 1080 で距離 1000 になる既定値）へ
    /// 置き換え、0〜179.9 にクランプする。0.1 未満は無限遠。高さが 0 以下
    /// なら 1080 とみなす。結果が非有限・0以下・float 最大値超なら 1000。
    /// 本家は float で返すが、この層は Double に統一している（描画層の
    /// 既存方針と同じ）。
    public static func perspectiveDistance(fovDegrees: Double, screenHeight: Int) -> Double {
        var fov = fovDegrees
        if !fov.isFinite {
            fov = 56.7380926
        }
        fov = min(max(fov, 0), 179.9)
        if fov < 0.1 {
            return .infinity
        }
        let height = screenHeight <= 0 ? 1080 : screenHeight
        let distance = Double(height) / 2 / tan(fov * .pi / 360)
        if !distance.isFinite || distance <= 0 || distance > 3.4028234663852886E+38 {
            return 1000
        }
        return distance
    }
}

/// System.Numerics の中心点つき回転と LookAt の再現（本家カメラ系処理器が
/// `CreateRotation*(角度, new Vector3(0, 0, 1000))` 等を使うため）。
extension Matrix4x4 {
    /// 中心点まわりの X 軸回転。
    public static func createRotationX(_ radians: Double, center: Vector3) -> Matrix4x4 {
        createTranslation(x: -center.x, y: -center.y, z: -center.z)
            * createRotationX(radians)
            * createTranslation(center)
    }

    /// 中心点まわりの Y 軸回転。
    public static func createRotationY(_ radians: Double, center: Vector3) -> Matrix4x4 {
        createTranslation(x: -center.x, y: -center.y, z: -center.z)
            * createRotationY(radians)
            * createTranslation(center)
    }

    /// 中心点まわりの Z 軸回転。
    public static func createRotationZ(_ radians: Double, center: Vector3) -> Matrix4x4 {
        createTranslation(x: -center.x, y: -center.y, z: -center.z)
            * createRotationZ(radians)
            * createTranslation(center)
    }

    /// 右手系の LookAt ビュー行列（System.Numerics `CreateLookAt`）。
    public static func createLookAt(eye: Vector3, target: Vector3, up: Vector3) -> Matrix4x4 {
        let zAxis = Self.normalized(Vector3(
            x: eye.x - target.x, y: eye.y - target.y, z: eye.z - target.z
        ))
        let xAxis = Self.normalized(Self.cross(up, zAxis))
        let yAxis = Self.cross(zAxis, xAxis)
        return Matrix4x4(
            m11: xAxis.x, m12: yAxis.x, m13: zAxis.x, m14: 0,
            m21: xAxis.y, m22: yAxis.y, m23: zAxis.y, m24: 0,
            m31: xAxis.z, m32: yAxis.z, m33: zAxis.z, m34: 0,
            m41: -xAxis.dot(eye), m42: -yAxis.dot(eye), m43: -zAxis.dot(eye), m44: 1
        )
    }

    private static func cross(_ a: Vector3, _ b: Vector3) -> Vector3 {
        a.cross(b)
    }

    private static func normalized(_ vector: Vector3) -> Vector3 {
        let length = vector.length
        guard length > 0 else { return vector }
        return Vector3(x: vector.x / length, y: vector.y / length, z: vector.z / length)
    }
}

/// ビルボード。本家 `BillboardEffect`。
/// パラメータ（実測）: Mode は BillboardMode（既定 Spherical、保存は
/// メンバ名文字列）。
public final class BillboardEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.BillboardEffect, YukkuriMovieMaker"
    }

    /// ビルボード方式。
    public var mode: BillboardMode = .spherical

    /// 未知の Mode 名の原文（データ保全用。通常は nil）。
    public private(set) var unrecognizedModeName: String?

    public override func createProcessor() -> any VideoEffectProcessor {
        BillboardEffectProcessor(definition: self)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Mode":
            if let name = value.stringValue {
                switch name {
                case "None":
                    mode = .none
                    unrecognizedModeName = nil
                case "Spherical":
                    mode = .spherical
                    unrecognizedModeName = nil
                case "Cylindrical":
                    mode = .cylindrical
                    unrecognizedModeName = nil
                default:
                    unrecognizedModeName = name
                }
            }
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        let name: String
        if let unrecognizedModeName {
            name = unrecognizedModeName
        } else {
            switch mode {
            case .none: name = "None"
            case .spherical: name = "Spherical"
            case .cylindrical: name = "Cylindrical"
            }
        }
        return [
            (key: "Mode", value: .string(name)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `BillboardEffect` 処理器。Mode が Spherical / Cylindrical のときは
/// その方式を、それ以外（None 含む）のときは Spherical を設定する
/// （本家の分岐どおり）。
public final class BillboardEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: BillboardEffectDefinition

    public init(definition: BillboardEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        var result = description.drawDescription
        switch definition.mode {
        case .spherical, .cylindrical:
            result.billboard = definition.mode
        case .none:
            result.billboard = .spherical
        }
        return result
    }
}

/// カメラ画角。本家 `CameraFovEffect`。
/// パラメータ（実測）: Fov は Animation(既定 56.7380926, 0〜179.9)。
public final class CameraFovEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CameraFovEffect, YukkuriMovieMaker"
    }

    /// 垂直画角（度）。
    public var fov = Animation(defaultValue: 56.7380926, minValue: 0, maxValue: 179.9)

    public override func createProcessor() -> any VideoEffectProcessor {
        CameraFovEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&fov)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Fov":
            CodecSupport.decodeAnimation(value, into: &fov)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Fov", value: CodecSupport.encodeAnimation(fov)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `CameraFovEffect` 処理器。透視距離を設定する。
public final class CameraFovEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: CameraFovEffectDefinition

    public init(definition: CameraFovEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        var result = description.drawDescription
        result.perspectiveDistance = CameraEffectMath.perspectiveDistance(
            fovDegrees: definition.fov.value(
                atFrame: description.itemFrame,
                length: description.itemDurationFrames,
                fps: description.fps
            ),
            screenHeight: description.itemDescription.screenSize.height
        )
        return result
    }
}

/// カメラ位置・Fov を持つ定義の共通部分（CameraPosition / CameraLookAt /
/// CameraWraparound の Fov 尾部）。本家では各定義が ChangeFov + Fov を
/// 個別に持つため、保存形式は各具象側でそのまま並べる。
open class CameraEffectDefinitionBase: VideoEffectDefinitionBase {
    /// 画角も変更するか。
    public var changeFov: Bool = false
    /// 垂直画角（度）。
    public var fov = Animation(defaultValue: 56.7380926, minValue: 0, maxValue: 179.9)

    /// ChangeFov / Fov の読み込み（具象側の末尾キーとして使う）。
    public func decodeCameraTailField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "ChangeFov":
            changeFov = CodecSupport.bool(value, default: false)
            return true
        case "Fov":
            CodecSupport.decodeAnimation(value, into: &fov)
            return true
        default:
            return false
        }
    }

    /// ChangeFov / Fov の書き出しフィールド。
    public func cameraTailFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "ChangeFov", value: .bool(changeFov)),
            (key: "Fov", value: CodecSupport.encodeAnimation(fov)),
        ]
    }

    /// ChangeFov が有効なら透視距離を書き換えた描画変換を返す。
    public func applyFov(to description: EffectDescription, result: DrawDescription) -> DrawDescription {
        guard changeFov else { return result }
        var result = result
        result.perspectiveDistance = CameraEffectMath.perspectiveDistance(
            fovDegrees: fov.value(
                atFrame: description.itemFrame,
                length: description.itemDurationFrames,
                fps: description.fps
            ),
            screenHeight: description.itemDescription.screenSize.height
        )
        return result
    }
}

/// カメラ位置。本家 `CameraPositionEffect`。
/// パラメータ（実測）: X / Y / Z / RotationY / RotationX / RotationZ は
/// Animation(既定 0, -100000〜100000)、ChangeFov は bool、Fov は
/// Animation(既定 56.7380926, 0〜179.9)。並びは実ファイル実測どおり
/// X, Y, Z, RotationY, RotationX, RotationZ の順。
public final class CameraPositionEffectDefinition: CameraEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CameraPositionEffect, YukkuriMovieMaker"
    }

    /// カメラ X 位置。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// カメラ Y 位置。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// カメラ Z 位置。
    public var z = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Y 軸回転（度）。
    public var rotationY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// X 軸回転（度）。
    public var rotationX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Z 軸回転（度）。
    public var rotationZ = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        CameraPositionEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&z)
        body(&rotationY)
        body(&rotationX)
        body(&rotationZ)
        body(&fov)
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
        case "RotationY":
            CodecSupport.decodeAnimation(value, into: &rotationY)
            return true
        case "RotationX":
            CodecSupport.decodeAnimation(value, into: &rotationX)
            return true
        case "RotationZ":
            CodecSupport.decodeAnimation(value, into: &rotationZ)
            return true
        default:
            if decodeCameraTailField(key, value) { return true }
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "RotationY", value: CodecSupport.encodeAnimation(rotationY)),
            (key: "RotationX", value: CodecSupport.encodeAnimation(rotationX)),
            (key: "RotationZ", value: CodecSupport.encodeAnimation(rotationZ)),
        ] + cameraTailFields() + super.encodeKnownFields()
    }
}

/// 本家 `CameraPositionEffect` 処理器。カメラ行列へ
/// 平行移動 → Y → X → Z 回転（中心 (0, 0, 1000)）を合成する。
/// Z 位置と回転の符号は本家の式どおり（位置 Z は反転して使う）。
public final class CameraPositionEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: CameraPositionEffectDefinition

    public init(definition: CameraPositionEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let position = Vector3(
            x: definition.x.value(atFrame: frame, length: duration, fps: fps),
            y: definition.y.value(atFrame: frame, length: duration, fps: fps),
            z: -definition.z.value(atFrame: frame, length: duration, fps: fps)
        )
        let center = Vector3(x: 0, y: 0, z: 1000)
        var result = description.drawDescription
        result.camera = result.camera
            * .createTranslation(x: -position.x, y: -position.y, z: -position.z)
            * .createRotationY(
                definition.rotationY.value(atFrame: frame, length: duration, fps: fps) * .pi / 180,
                center: center)
            * .createRotationX(
                definition.rotationX.value(atFrame: frame, length: duration, fps: fps) * .pi / 180,
                center: center)
            * .createRotationZ(
                definition.rotationZ.value(atFrame: frame, length: duration, fps: fps) * .pi / 180,
                center: center)
        return definition.applyFov(to: description, result: result)
    }
}

/// カメラ注視。本家 `CameraLookAtEffect`。
/// パラメータ（実測）: X / Y / Z / LookAtX / LookAtY は Animation(既定 0,
/// -100000〜100000)、LookAtZ は Animation(既定 1000, -100000〜100000)、
/// RotationZ は Animation(既定 0)、ChangeFov / Fov はカメラ共通尾部。
public final class CameraLookAtEffectDefinition: CameraEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CameraLookAtEffect, YukkuriMovieMaker"
    }

    /// カメラ X 位置。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// カメラ Y 位置。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// カメラ Z 位置。
    public var z = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 注視点 X。
    public var lookAtX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 注視点 Y。
    public var lookAtY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 注視点 Z。
    public var lookAtZ = Animation(defaultValue: 1000, minValue: -100000, maxValue: 100000)
    /// Z 軸回転（ロール、度）。
    public var rotationZ = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        CameraLookAtEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&z)
        body(&lookAtX)
        body(&lookAtY)
        body(&lookAtZ)
        body(&rotationZ)
        body(&fov)
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
        case "LookAtX":
            CodecSupport.decodeAnimation(value, into: &lookAtX)
            return true
        case "LookAtY":
            CodecSupport.decodeAnimation(value, into: &lookAtY)
            return true
        case "LookAtZ":
            CodecSupport.decodeAnimation(value, into: &lookAtZ)
            return true
        case "RotationZ":
            CodecSupport.decodeAnimation(value, into: &rotationZ)
            return true
        default:
            if decodeCameraTailField(key, value) { return true }
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "LookAtX", value: CodecSupport.encodeAnimation(lookAtX)),
            (key: "LookAtY", value: CodecSupport.encodeAnimation(lookAtY)),
            (key: "LookAtZ", value: CodecSupport.encodeAnimation(lookAtZ)),
            (key: "RotationZ", value: CodecSupport.encodeAnimation(rotationZ)),
        ] + cameraTailFields() + super.encodeKnownFields()
    }
}

/// 本家 `CameraLookAtEffect` 処理器。カメラ行列へ
/// T(0,0,-1000) → LookAt → T(0,0,1000) → Z 回転（中心 (0,0,1000)）を合成する。
public final class CameraLookAtEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: CameraLookAtEffectDefinition

    public init(definition: CameraLookAtEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let eye = Vector3(
            x: definition.x.value(atFrame: frame, length: duration, fps: fps),
            y: definition.y.value(atFrame: frame, length: duration, fps: fps),
            z: -definition.z.value(atFrame: frame, length: duration, fps: fps)
        )
        let target = Vector3(
            x: definition.lookAtX.value(atFrame: frame, length: duration, fps: fps),
            y: definition.lookAtY.value(atFrame: frame, length: duration, fps: fps),
            z: -definition.lookAtZ.value(atFrame: frame, length: duration, fps: fps)
        )
        var result = description.drawDescription
        result.camera = result.camera
            * .createTranslation(x: 0, y: 0, z: -1000)
            * .createLookAt(eye: eye, target: target, up: Vector3(x: 0, y: 1, z: 0))
            * .createTranslation(x: 0, y: 0, z: 1000)
            * .createRotationZ(
                definition.rotationZ.value(atFrame: frame, length: duration, fps: fps) * .pi / 180,
                center: Vector3(x: 0, y: 0, z: 1000))
        return definition.applyFov(to: description, result: result)
    }
}

/// カメラ周回。本家 `CameraWraparoundEffect`。
/// パラメータ（実測）: X / Y / Z は Animation(既定 0, -100000〜100000)、
/// Radius は Animation(既定 1000, -100000〜100000)、RotationY / RotationX /
/// RotationZ は Animation(既定 0)、ChangeFov / Fov はカメラ共通尾部。
public final class CameraWraparoundEffectDefinition: CameraEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.CameraWraparoundEffect, YukkuriMovieMaker"
    }

    /// 注視点 X。
    public var x = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 注視点 Y。
    public var y = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 注視点 Z。
    public var z = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 周回半径。
    public var radius = Animation(defaultValue: 1000, minValue: -100000, maxValue: 100000)
    /// Y 軸回転（度）。
    public var rotationY = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// X 軸回転（度）。
    public var rotationX = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// Z 軸回転（度）。
    public var rotationZ = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)

    public override func createProcessor() -> any VideoEffectProcessor {
        CameraWraparoundEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&x)
        body(&y)
        body(&z)
        body(&radius)
        body(&rotationY)
        body(&rotationX)
        body(&rotationZ)
        body(&fov)
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
        case "Radius":
            CodecSupport.decodeAnimation(value, into: &radius)
            return true
        case "RotationY":
            CodecSupport.decodeAnimation(value, into: &rotationY)
            return true
        case "RotationX":
            CodecSupport.decodeAnimation(value, into: &rotationX)
            return true
        case "RotationZ":
            CodecSupport.decodeAnimation(value, into: &rotationZ)
            return true
        default:
            if decodeCameraTailField(key, value) { return true }
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "Radius", value: CodecSupport.encodeAnimation(radius)),
            (key: "RotationY", value: CodecSupport.encodeAnimation(rotationY)),
            (key: "RotationX", value: CodecSupport.encodeAnimation(rotationX)),
            (key: "RotationZ", value: CodecSupport.encodeAnimation(rotationZ)),
        ] + cameraTailFields() + super.encodeKnownFields()
    }
}

/// 本家 `CameraWraparoundEffect` 処理器。回転中心は (0, 0, -Radius + 1000)。
/// Y / X 回転は符号が反転し、Z 回転はそのまま（本家の式どおり）。
public final class CameraWraparoundEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: CameraWraparoundEffectDefinition

    public init(definition: CameraWraparoundEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let radius = definition.radius.value(atFrame: frame, length: duration, fps: fps)
        let center = Vector3(x: 0, y: 0, z: -radius + 1000)
        var result = description.drawDescription
        result.camera = result.camera
            * .createTranslation(
                x: -definition.x.value(atFrame: frame, length: duration, fps: fps),
                y: -definition.y.value(atFrame: frame, length: duration, fps: fps),
                z: -definition.z.value(atFrame: frame, length: duration, fps: fps))
            * .createTranslation(x: 0, y: 0, z: -radius + 1000)
            * .createRotationY(
                -definition.rotationY.value(atFrame: frame, length: duration, fps: fps) * .pi / 180,
                center: center)
            * .createRotationX(
                -definition.rotationX.value(atFrame: frame, length: duration, fps: fps) * .pi / 180,
                center: center)
            * .createRotationZ(
                definition.rotationZ.value(atFrame: frame, length: duration, fps: fps) * .pi / 180,
                center: center)
        return definition.applyFov(to: description, result: result)
    }
}

/// 極座標描画位置。本家 `PolarDrawPositionEffect`。
/// パラメータ（実測）: Radius / Angle / Angle2 は Animation(既定 0,
/// -100000〜100000)、IsSyncRotation は bool（既定 true）。
public final class PolarDrawPositionEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.PolarDrawPositionEffect, YukkuriMovieMaker"
    }

    /// 半径。
    public var radius = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 角度（度、Z 回転）。
    public var angle = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 角度2（度、Y 回転）。
    public var angle2 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 回転を同期するか。
    public var isSyncRotation: Bool = true

    public override func createProcessor() -> any VideoEffectProcessor {
        PolarDrawPositionEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&radius)
        body(&angle)
        body(&angle2)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Radius":
            CodecSupport.decodeAnimation(value, into: &radius)
            return true
        case "Angle":
            CodecSupport.decodeAnimation(value, into: &angle)
            return true
        case "Angle2":
            CodecSupport.decodeAnimation(value, into: &angle2)
            return true
        case "IsSyncRotation":
            isSyncRotation = CodecSupport.bool(value, default: true)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Radius", value: CodecSupport.encodeAnimation(radius)),
            (key: "Angle", value: CodecSupport.encodeAnimation(angle)),
            (key: "Angle2", value: CodecSupport.encodeAnimation(angle2)),
            (key: "IsSyncRotation", value: .bool(isSyncRotation)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `PolarDrawPositionEffect` 処理器。(Radius, 0, 0) を Z 回転 → Y 回転
/// で回したベクトルを Draw へ加算し、同期時は回転も加える。
public final class PolarDrawPositionEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: PolarDrawPositionEffectDefinition

    public init(definition: PolarDrawPositionEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let radius = definition.radius.value(atFrame: frame, length: duration, fps: fps)
        let angleDegrees = definition.angle.value(atFrame: frame, length: duration, fps: fps)
        let angle2Degrees = definition.angle2.value(atFrame: frame, length: duration, fps: fps)
        let rotation = Matrix4x4.createRotationZ(angleDegrees * .pi / 180)
            * .createRotationY(angle2Degrees * .pi / 180)
        let offset = rotation.transform(Vector3(x: radius, y: 0, z: 0))
        var result = description.drawDescription
        result.draw = Vector3(
            x: result.draw.x + offset.x,
            y: result.draw.y + offset.y,
            z: result.draw.z + offset.z
        )
        if definition.isSyncRotation {
            result.rotation = Vector3(
                x: result.rotation.x,
                y: result.rotation.y - angle2Degrees,
                z: result.rotation.z + angleDegrees + 90
            )
        }
        return result
    }
}

/// XY→極座標変換。本家 `XYToPolarTransformEffect`。
/// パラメータ（実測）: XRange / ZRange は Animation(既定 500, 0〜100000)、
/// IsClockwise / IsSyncRotation は bool（既定 true）。
public final class XYToPolarTransformEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.XYToPolarTransformEffect, YukkuriMovieMaker"
    }

    /// X の周期幅。
    public var xRange = Animation(defaultValue: 500, minValue: 0, maxValue: 100000)
    /// Z の周期幅。
    public var zRange = Animation(defaultValue: 500, minValue: 0, maxValue: 100000)
    /// 時計回りか。
    public var isClockwise: Bool = true
    /// 回転を同期するか。
    public var isSyncRotation: Bool = true

    public override func createProcessor() -> any VideoEffectProcessor {
        XYToPolarTransformEffectProcessor(definition: self)
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&xRange)
        body(&zRange)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "XRange":
            CodecSupport.decodeAnimation(value, into: &xRange)
            return true
        case "ZRange":
            CodecSupport.decodeAnimation(value, into: &zRange)
            return true
        case "IsClockwise":
            isClockwise = CodecSupport.bool(value, default: true)
            return true
        case "IsSyncRotation":
            isSyncRotation = CodecSupport.bool(value, default: true)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "XRange", value: CodecSupport.encodeAnimation(xRange)),
            (key: "ZRange", value: CodecSupport.encodeAnimation(zRange)),
            (key: "IsClockwise", value: .bool(isClockwise)),
            (key: "IsSyncRotation", value: .bool(isSyncRotation)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `XYToPolarTransformEffect` 処理器。Draw を置き換える（加算ではない）。
/// 範囲が 0 の軸の角度は π/2。同期時の Z 回転には +170 度の定数が入る
/// （本家の式どおり）。
public final class XYToPolarTransformEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: XYToPolarTransformEffectDefinition

    public init(definition: XYToPolarTransformEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let xRange = definition.xRange.value(atFrame: frame, length: duration, fps: fps)
        let zRange = definition.zRange.value(atFrame: frame, length: duration, fps: fps)
        let source = description.drawDescription
        let angleX = xRange == 0 ? Double.pi / 2 : 2 * .pi * source.draw.x / xRange
        let angleZ = zRange == 0 ? Double.pi / 2 : 2 * .pi * source.draw.z / zRange
        let direction: Double = definition.isClockwise ? 1 : -1
        let rotation = Matrix4x4.createRotationZ(angleX * direction)
            * .createRotationY(angleZ)
        var result = source
        result.draw = rotation.transform(Vector3(x: 0, y: -source.draw.y, z: 0))
        if definition.isSyncRotation {
            result.rotation = Vector3(
                x: source.rotation.x,
                y: source.rotation.y - angleZ / .pi * 180,
                z: source.rotation.z + angleX / .pi * 180 * direction + 170
            )
        }
        return result
    }
}
