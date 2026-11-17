import Foundation

/// プレビュー時のみ表示。本家 `ShowOnlyPreviewEffect`。
/// パラメータ（実測）: IsPlaying は bool（既定 true）、IsPaused は
/// bool（既定 false)。Animation は持たない。
public final class ShowOnlyPreviewEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.ShowOnlyPreviewEffect, YukkuriMovieMaker"
    }

    /// 再生中に表示するか。
    public var isPlaying: Bool = true
    /// 一時停止中に表示するか。
    public var isPaused: Bool = false

    public override func createProcessor() -> any VideoEffectProcessor {
        ShowOnlyPreviewEffectProcessor(definition: self)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsPlaying":
            isPlaying = CodecSupport.bool(value, default: true)
            return true
        case "IsPaused":
            isPaused = CodecSupport.bool(value, default: false)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "IsPlaying", value: .bool(isPlaying)),
            (key: "IsPaused", value: .bool(isPaused)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `ShowOnlyPreviewEffect` 処理器。用途が再生中で IsPlaying、または
/// 一時停止中で IsPaused のときだけ不透明度を維持し、それ以外は 0 にする
/// （書き出し用途では常に隠れるのが本家の挙動）。
public final class ShowOnlyPreviewEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: ShowOnlyPreviewEffectDefinition

    public init(definition: ShowOnlyPreviewEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let usage = description.itemDescription.usage
        let visible = (usage == .playing && definition.isPlaying)
            || (usage == .paused && definition.isPaused)
        var result = description.drawDescription
        result.opacity = visible ? result.opacity : 0
        return result
    }
}

/// グループ描画。本家 `GroupedDrawingEffect` に対応する定義。
///
/// これはファイルに保存されるエフェクトではない。本家では GroupItem が
/// 自身から合成して `GroupEffects`（= 自身の VideoEffects ＋ この効果）を
/// 作り、子の親エフェクトとして適用する。そのため `$type` を持たず、
/// レジストリにも登録しない。パラメータはグループアイテム自身の
/// X / Y / Z / Rotation / Zoom である。
public final class GroupedDrawingEffectDefinition: VideoEffectDefinition {
    /// 対象のグループアイテム（借用）。
    public let group: GroupItem

    public init(group: GroupItem) {
        self.group = group
    }

    /// 本家では合成エフェクトは常時有効。
    public var isEnabled: Bool { true }

    public func createProcessor() -> any VideoEffectProcessor {
        GroupedDrawingEffectProcessor(group: group)
    }
}

/// 本家 `GroupedDrawingEffect` 処理器。子の Draw を グループの拡縮→回転で
/// 変換してからグループ位置を加え、Rotation と Zoom にもグループ分を合成する。
public final class GroupedDrawingEffectProcessor: DrawDescriptionEffectProcessor {
    private let group: GroupItem

    public init(group: GroupItem) {
        self.group = group
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let frame = description.itemFrame
        let duration = description.itemDurationFrames
        let fps = description.fps
        let scale = group.zoom.value(atFrame: frame, length: duration, fps: fps) / 100
        let rotationDegrees = group.rotation.value(atFrame: frame, length: duration, fps: fps)
        let transform = Matrix4x4.createScale(x: scale, y: scale, z: scale, center: .zero)
            * .createRotationZ(rotationDegrees * .pi / 180)
        let source = description.drawDescription
        let transformed = transform.transform(source.draw)
        var result = source
        result.draw = Vector3(
            x: group.x.value(atFrame: frame, length: duration, fps: fps) + transformed.x,
            y: group.y.value(atFrame: frame, length: duration, fps: fps) + transformed.y,
            z: group.z.value(atFrame: frame, length: duration, fps: fps) + transformed.z
        )
        result.rotation = Vector3(
            x: source.rotation.x,
            y: source.rotation.y,
            z: source.rotation.z + rotationDegrees
        )
        result.zoom = Vector2(x: source.zoom.x * scale, y: source.zoom.y * scale)
        return result
    }
}
