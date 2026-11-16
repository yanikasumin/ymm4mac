import Foundation

/// 図形アイテム。本家 `ShapeItem` に対応する。
///
/// 図形パラメータはプラグイン型のため生 JSON で保持する。旧互換プロパティ
/// （Size / AspectRate / StrokeThickness / Stroke / ShapeType）はパラメータの
/// 実型に依存するため型付けせず、追加フィールドとして往復保持する。
/// 新規作成時のパラメータ既定値は本家では `RectangleShapeParameter` の
/// インスタンスだが、その全プロパティはモデル化していないため、
/// $type のみの最小オブジェクトで代用する（既知の差異）。
public final class ShapeItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.ShapeItem, YukkuriMovieMaker"
    }

    /// 図形プラグインの型名（本家ではプライマリプラグインの型が既定）。
    public var shapeType2: String = ""
    /// 図形パラメータ（プラグイン型、生 JSON で保持）。
    public var shapeParameter: PreservedObject? = PreservedObject(.object([
        (key: "$type", value: .string("YukkuriMovieMaker.Project.Items.RectangleShapeParameter, YukkuriMovieMaker")),
    ]))

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "ShapeType2", value: .string(shapeType2)),
            (key: "ShapeParameter", value: shapeParameter?.value ?? .null),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "ShapeType2":
            shapeType2 = CodecSupport.string(value, default: shapeType2)
            return true
        case "ShapeParameter":
            shapeParameter = CodecSupport.preservedObject(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}

/// エフェクトアイテム。本家 `EffectItem` に対応する。
///
/// 本家では `Zoom` はアクセスのたびに新しい `Animation(100)` を返す
/// get 専用プロパティで、保存はされるが読み込み結果は保持されない。
/// `IsInverted` は [JsonIgnore] で保存対象外。どちらもその挙動に合わせ、
/// 保存時は Zoom に既定値を書き、読み込み時は両方とも捨てる。
public final class EffectItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.EffectItem, YukkuriMovieMaker"
    }

    /// 図形プラグインの型名。
    public var shapeType2: String = ""
    /// 図形パラメータ（プラグイン型、生 JSON で保持）。
    public var shapeParameter: PreservedObject? = PreservedObject(.object([
        (key: "$type", value: .string("YukkuriMovieMaker.Project.Items.RectangleShapeParameter, YukkuriMovieMaker")),
    ]))
    /// マスクを反転するか。
    public var invertMask: Bool = false

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields = super.encodeKnownFields().filter { $0.key != "IsInverted" }
        for index in fields.indices where fields[index].key == "Zoom" {
            fields[index].value = CodecSupport.encodeAnimation(
                Animation(defaultValue: 100, minValue: -100_000, maxValue: 100_000)
            )
        }
        fields += [
            (key: "ShapeType2", value: .string(shapeType2)),
            (key: "ShapeParameter", value: shapeParameter?.value ?? .null),
            (key: "InvertMask", value: .bool(invertMask)),
        ]
        return fields
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Zoom", "IsInverted":
            // 本家では保持されない（Zoom は get 専用、IsInverted は JsonIgnore）
            return true
        case "ShapeType2":
            shapeType2 = CodecSupport.string(value, default: shapeType2)
            return true
        case "ShapeParameter":
            shapeParameter = CodecSupport.preservedObject(value)
            return true
        case "InvertMask":
            invertMask = CodecSupport.bool(value, default: invertMask)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}

/// グループアイテム。本家 `GroupItem` に対応する。
///
/// 本家では FadeIn / FadeOut / Blend / Opacity 等を独自の保持で上書きするが、
/// 保存形式は VisualItem と同一のため、ここでは継承した保持をそのまま使う
/// （内部実装の違いのみ）。旧互換の `IsCompressFrame` は set 専用で、
/// 読み込み時に `IsComposite` へ転送されるだけである。
public final class GroupItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.GroupItem, YukkuriMovieMaker"
    }

    /// グループの対象レイヤー範囲。
    public var groupRange: Int = 50
    /// グループのみを対象にするか。
    public var isGroupOnly: Bool = false
    /// 合成するか。
    public var isComposite: Bool = false
    /// 音声を合成するか。
    public var isAudioComposite: Bool = false
    /// 合成の中心。
    public var compositeCenter: GroupItemCompositeCenter = .screenCenter
    /// 音声エフェクト（生 JSON で保持）。
    public var audioEffects: [PreservedObject] = []

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "GroupRange", value: .number(groupRange)),
            (key: "IsGroupOnly", value: .bool(isGroupOnly)),
            (key: "IsComposite", value: .bool(isComposite)),
            (key: "IsAudioComposite", value: .bool(isAudioComposite)),
            (key: "CompositeCenter", value: .string(compositeCenter.honkeName)),
            (key: "AudioEffects", value: .array(audioEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "GroupRange":
            groupRange = CodecSupport.int(value, default: groupRange)
        case "IsGroupOnly":
            isGroupOnly = CodecSupport.bool(value, default: isGroupOnly)
        case "IsComposite":
            isComposite = CodecSupport.bool(value, default: isComposite)
        case "IsAudioComposite":
            isAudioComposite = CodecSupport.bool(value, default: isAudioComposite)
        case "CompositeCenter":
            compositeCenter = CodecSupport.enumeration(value, default: compositeCenter)
        case "AudioEffects":
            audioEffects = CodecSupport.preservedList(value)
        case "IsCompressFrame":
            // 旧互換（set 専用）: IsComposite へ転送される
            isComposite = CodecSupport.bool(value, default: isComposite)
        default:
            return super.decodeKnownField(key, value)
        }
        return true
    }
}

/// シーンアイテム。本家 `SceneItem` に対応する（映像＋音声）。
///
/// 本家の `IAudioItem` の FadeIn / FadeOut はインタフェースの既定実装で
/// 値を持たず、SceneItem には保存されるプロパティが存在しない。
public final class SceneItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.SceneItem, YukkuriMovieMaker"
    }

    /// 波形を表示するか。
    public var isWaveformEnabled: Bool = false
    /// 参照先シーン（タイムライン）の ID。
    public var sceneId: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    /// 音量（%）。
    public var volume: Animation = Animation(defaultValue: 50, minValue: 0, maxValue: 10_000)
    /// パン（-100..100）。
    public var pan: Animation = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// 再生速度変更時の音声処理。
    public var playbackRateAudioProcessingMode: PlaybackRateAudioProcessingMode = .resampling
    /// ループするか。
    public var isLooped: Bool = false
    /// エコーを有効にするか。
    public var echoIsEnabled: Bool = false
    /// エコーの間隔（秒）。
    public var echoInterval: Double = 0.1
    /// エコーの減衰（%）。
    public var echoAttenuation: Double = 40
    /// 音声エフェクト（生 JSON で保持）。
    public var audioEffects: [PreservedObject] = []

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        body(&volume)
        body(&pan)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "IsWaveformEnabled", value: .bool(isWaveformEnabled)),
            (key: "SceneId", value: .string(sceneId.uuidString.lowercased())),
            (key: "Volume", value: CodecSupport.encodeAnimation(volume)),
            (key: "Pan", value: CodecSupport.encodeAnimation(pan)),
            (key: "PlaybackRateAudioProcessingMode", value: .string(playbackRateAudioProcessingMode.honkeName)),
            (key: "IsLooped", value: .bool(isLooped)),
            (key: "EchoIsEnabled", value: .bool(echoIsEnabled)),
            (key: "EchoInterval", value: .number(echoInterval)),
            (key: "EchoAttenuation", value: .number(echoAttenuation)),
            (key: "AudioEffects", value: .array(audioEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsWaveformEnabled":
            isWaveformEnabled = CodecSupport.bool(value, default: isWaveformEnabled)
        case "SceneId":
            sceneId = CodecSupport.uuid(value, default: sceneId)
        case "Volume":
            CodecSupport.decodeAnimation(value, into: &volume)
        case "Pan":
            CodecSupport.decodeAnimation(value, into: &pan)
        case "PlaybackRateAudioProcessingMode":
            playbackRateAudioProcessingMode = CodecSupport.enumeration(value, default: playbackRateAudioProcessingMode)
        case "IsLooped":
            isLooped = CodecSupport.bool(value, default: isLooped)
        case "EchoIsEnabled":
            echoIsEnabled = CodecSupport.bool(value, default: echoIsEnabled)
        case "EchoInterval":
            echoInterval = CodecSupport.double(value, default: echoInterval)
        case "EchoAttenuation":
            echoAttenuation = CodecSupport.double(value, default: echoAttenuation)
        case "AudioEffects":
            audioEffects = CodecSupport.preservedList(value)
        default:
            return super.decodeKnownField(key, value)
        }
        return true
    }
}

/// フレームバッファアイテム。本家 `FrameBufferItem` に対応する。
public final class FrameBufferItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.FrameBufferItem, YukkuriMovieMaker"
    }

    /// 背景をクリアするか。
    public var clearBackground: Bool = false
    /// アルファを有効にするか。
    public var isAlphaEnabled: Bool = false
    /// フレーム外の描画を有効にするか。
    public var isFrameOutImageRenderingEnabled: Bool = false

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "ClearBackground", value: .bool(clearBackground)),
            (key: "IsAlphaEnabled", value: .bool(isAlphaEnabled)),
            (key: "IsFrameOutImageRenderingEnabled", value: .bool(isFrameOutImageRenderingEnabled)),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "ClearBackground":
            clearBackground = CodecSupport.bool(value, default: clearBackground)
        case "IsAlphaEnabled":
            isAlphaEnabled = CodecSupport.bool(value, default: isAlphaEnabled)
        case "IsFrameOutImageRenderingEnabled":
            isFrameOutImageRenderingEnabled = CodecSupport.bool(value, default: isFrameOutImageRenderingEnabled)
        default:
            return super.decodeKnownField(key, value)
        }
        return true
    }
}

/// 立ち絵アイテム。本家 `TachieItem` に対応する。
public final class TachieItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.TachieItem, YukkuriMovieMaker"
    }

    /// 紐づくキャラクター（無い場合もある）。
    public var character: Character?
    /// キャラクター名。
    public var characterName: String = ""
    /// 立ち絵パラメータ（プラグイン型、生 JSON で保持）。
    public var tachieItemParameter: PreservedObject?

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "Character", value: character?.encodeToJSONValue() ?? .null),
            (key: "CharacterName", value: .string(characterName)),
            (key: "TachieItemParameter", value: tachieItemParameter?.value ?? .null),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Character":
            character = value == .null ? nil : Character.decode(from: value)
            return true
        case "CharacterName":
            characterName = CodecSupport.string(value, default: characterName)
            return true
        case "TachieItemParameter":
            tachieItemParameter = CodecSupport.preservedObject(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}

/// 立ち絵表情アイテム。本家 `TachieFaceItem` に対応する。
public final class TachieFaceItem: BaseItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.TachieFaceItem, YukkuriMovieMaker"
    }

    /// 紐づくキャラクター（無い場合もある）。
    public var character: Character?
    /// キャラクター名。
    public var characterName: String = ""
    /// 表情パラメータ（プラグイン型、生 JSON で保持）。
    public var tachieFaceParameter: PreservedObject?
    /// 表情エフェクト（生 JSON で保持）。
    public var tachieFaceEffects: [PreservedObject] = []

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "Character", value: character?.encodeToJSONValue() ?? .null),
            (key: "CharacterName", value: .string(characterName)),
            (key: "TachieFaceParameter", value: tachieFaceParameter?.value ?? .null),
            (key: "TachieFaceEffects", value: .array(tachieFaceEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Character":
            character = value == .null ? nil : Character.decode(from: value)
            return true
        case "CharacterName":
            characterName = CodecSupport.string(value, default: characterName)
            return true
        case "TachieFaceParameter":
            tachieFaceParameter = CodecSupport.preservedObject(value)
            return true
        case "TachieFaceEffects":
            tachieFaceEffects = CodecSupport.preservedList(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}

/// 画面遷移アイテム。本家 `TransitionItem` に対応する。
///
/// X / Y / Z / Opacity / Zoom / Rotation / FadeIn / FadeOut / Blend /
/// IsInverted / IsAlwaysOnTop / IsZOrderEnabled は本家では式本体の
/// get 専用プロパティ（毎回既定値を返す）で、保存はされるが読み込み
/// 結果は保持されない。IsClippingWithObjectAbove と VideoEffects も
/// setter が何もしないため同様である。ここでは保存時に本家の既定値を
/// 書き、読み込み時は捨てる（既知プロパティとして消費する）。
public final class TransitionItem: BaseItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.TransitionItem, YukkuriMovieMaker"
    }

    /// 遷移プラグインの型名（本家ではプライマリプラグインの型が既定）。
    public var transitionType: String = ""
    /// 遷移パラメータ（プラグイン型、生 JSON で保持）。
    public var transitionParameter: PreservedObject?
    /// 遷移前に適用する映像エフェクト（生 JSON で保持）。
    public var beforeVideoEffects: [PreservedObject] = []
    /// 遷移後に適用する映像エフェクト（生 JSON で保持）。
    public var afterVideoEffects: [PreservedObject] = []

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "X", value: CodecSupport.encodeAnimation(Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000))),
            (key: "Y", value: CodecSupport.encodeAnimation(Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000))),
            (key: "Z", value: CodecSupport.encodeAnimation(Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000))),
            (key: "Opacity", value: CodecSupport.encodeAnimation(Animation(defaultValue: 100, minValue: 0, maxValue: 100))),
            (key: "Zoom", value: CodecSupport.encodeAnimation(Animation(defaultValue: 100, minValue: 0, maxValue: 100_000))),
            (key: "Rotation", value: CodecSupport.encodeAnimation(Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000))),
            (key: "FadeIn", value: .number(0.0)),
            (key: "FadeOut", value: .number(0.0)),
            (key: "IsInverted", value: .bool(false)),
            (key: "Blend", value: .string(Blend.normal.honkeName)),
            (key: "IsAlwaysOnTop", value: .bool(false)),
            (key: "IsZOrderEnabled", value: .bool(false)),
            (key: "IsClippingWithObjectAbove", value: .bool(false)),
            (key: "VideoEffects", value: .array([])),
            (key: "TransitionType", value: .string(transitionType)),
            (key: "TransitionParameter", value: transitionParameter?.value ?? .null),
            (key: "BeforeVideoEffects", value: .array(beforeVideoEffects.map { $0.value })),
            (key: "AfterVideoEffects", value: .array(afterVideoEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X", "Y", "Z", "Opacity", "Zoom", "Rotation", "FadeIn", "FadeOut",
             "IsInverted", "Blend", "IsAlwaysOnTop", "IsZOrderEnabled",
             "IsClippingWithObjectAbove", "VideoEffects":
            // 本家では保持されない一時プロパティ
            return true
        case "TransitionType":
            transitionType = CodecSupport.string(value, default: transitionType)
            return true
        case "TransitionParameter":
            transitionParameter = CodecSupport.preservedObject(value)
            return true
        case "BeforeVideoEffects":
            beforeVideoEffects = CodecSupport.preservedList(value)
            return true
        case "AfterVideoEffects":
            afterVideoEffects = CodecSupport.preservedList(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}
