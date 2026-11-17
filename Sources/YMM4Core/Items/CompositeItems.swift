import Foundation

/// 図形アイテム。本家 `ShapeItem` に対応する。
///
/// 図形パラメータは `ShapeParameter` として保持する（既定の
/// `RectangleShapeParameter` は型付き、それ以外は生 JSON で保持）。
/// 旧互換プロパティ（Size / AspectRate / StrokeThickness / Stroke /
/// ShapeType）は本家では set 専用でパラメータ側へ転送されるため、
/// 読み込み時にだけ消費し、保存時には書き出さない。パラメータが
/// 型付き（rectangle）でない場合は本家ではキャスト例外で読み込み自体が
/// 失敗するが、ここでは追加フィールドとして保持して読み込みを継続する
/// （データ保全を優先する意図的な緩和）。
public final class ShapeItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.ShapeItem, YukkuriMovieMaker"
    }

    /// 図形プラグインの型名（本家ではプライマリプラグイン
    /// `QuadrilateralShapePlugin` の型が既定）。
    public var shapeType2: String =
        "YukkuriMovieMaker.Shape.QuadrilateralShapePlugin, YukkuriMovieMaker"
    /// 図形パラメータ。
    public var shapeParameter: ShapeParameter = .defaultValue

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        shapeParameter.forEachAnimation(body)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "ShapeType2", value: .string(shapeType2)),
            (key: "ShapeParameter", value: shapeParameter.encodeToJSONValue()),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "ShapeType2":
            shapeType2 = CodecSupport.string(value, default: shapeType2)
            return true
        case "ShapeParameter":
            // 本家では setter が null を無視し、既定インスタンスが残る
            if value != .null {
                shapeParameter = ShapeParameter.decode(from: value)
            }
            return true
        case "Size":
            guard case .rectangle(let parameter) = shapeParameter else { return false }
            CodecSupport.copyAnimationContents(
                from: CodecSupport.decodeLegacyAnimation(value), into: &parameter.size
            )
            return true
        case "AspectRate":
            guard case .rectangle(let parameter) = shapeParameter else { return false }
            CodecSupport.copyAnimationContents(
                from: CodecSupport.decodeLegacyAnimation(value), into: &parameter.aspectRate
            )
            return true
        case "StrokeThickness":
            guard case .rectangle(let parameter) = shapeParameter else { return false }
            CodecSupport.copyAnimationContents(
                from: CodecSupport.decodeLegacyAnimation(value), into: &parameter.strokeThickness
            )
            return true
        case "Stroke":
            guard case .rectangle(let parameter) = shapeParameter else { return false }
            // 本家 `StrokeShapeParameterBase.Stroke`: ブラシが単色の場合だけ
            // その色へ転送され、それ以外では黙って捨てられる
            if case .solidColor(let solidColor) = parameter.brush.parameter {
                solidColor.color = CodecSupport.color(value, default: solidColor.color)
            }
            return true
        case "ShapeType":
            shapeType2 = LegacyShapeType.pluginTypeName(for: value)
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

    /// 図形プラグインの型名（本家ではプライマリプラグイン
    /// `QuadrilateralShapePlugin` の型が既定）。
    public var shapeType2: String =
        "YukkuriMovieMaker.Shape.QuadrilateralShapePlugin, YukkuriMovieMaker"
    /// 図形パラメータ（マスク形状。ShapeItem と同型）。
    public var shapeParameter: ShapeParameter = .defaultValue
    /// マスクのぼかし量（本家 `Blur`。Animation で、既定 0・範囲 0〜250）。
    public var blur: Animation = Animation(defaultValue: 0, minValue: 0, maxValue: 250)
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
            (key: "ShapeParameter", value: shapeParameter.encodeToJSONValue()),
            (key: "Blur", value: CodecSupport.encodeAnimation(blur)),
            (key: "InvertMask", value: .bool(invertMask)),
        ]
        return fields
    }

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        shapeParameter.forEachAnimation(body)
        body(&blur)
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
            // 本家では setter が null を無視し、既定インスタンスが残る
            if value != .null {
                shapeParameter = ShapeParameter.decode(from: value)
            }
            return true
        case "ShapeType":
            // 旧互換（set 専用）: ShapeType2 へ転送される
            shapeType2 = LegacyShapeType.pluginTypeName(for: value)
            return true
        case "Blur":
            CodecSupport.decodeAnimation(value, into: &blur)
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
            // 本家は実行時参照 Character を [JsonIgnore] とし、保存は CharacterName のみ（MAC-0015）。
            (key: "CharacterName", value: .string(character?.name ?? characterName)),
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
            // 本家は実行時参照 Character を [JsonIgnore] とし、保存は CharacterName のみ（MAC-0015）。
            (key: "CharacterName", value: .string(character?.name ?? characterName)),
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
/// IsInverted / IsAlwaysOnTop / IsZOrderEnabled /
/// IsClippingWithObjectAbove / VideoEffects は、本家では式本体の
/// get 専用プロパティ（アクセスのたびに既定値を返す）で、保存はされるが
/// 読み込み結果は保持されない（IsClippingWithObjectAbove と
/// VideoEffects は setter が何もしない）。ここでは既定値を初期値として
/// 型付きで保持し、読み込んだ値を往復させる（意図的な差分: データ保全を
/// 優先する。本家が書き出すファイルでは常に既定値のため、実ファイルでは
/// 差は現れない）。アニメーション文脈の伝播にも参加させる点も本家と
/// 異なる（本家では GetAnimatables に含まれない）。
public final class TransitionItem: BaseItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.TransitionItem, YukkuriMovieMaker"
    }

    /// X 座標（本家の get 専用プロパティが返す既定値で初期化）。
    public var x: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// Y 座標（同上）。
    public var y: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// Z 座標（同上）。
    public var z: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 不透明度（%、同上）。
    public var opacity: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 拡大率（%、同上）。
    public var zoom: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 回転角（同上）。
    public var rotation: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// フェードイン（秒）。
    public var fadeIn: Double = 0
    /// フェードアウト（秒）。
    public var fadeOut: Double = 0
    /// 反転するか。
    public var isInverted: Bool = false
    /// 合成方法。
    public var blend: Blend = .normal
    /// 常に手前に表示するか。
    public var isAlwaysOnTop: Bool = false
    /// Z オーダーを有効にするか。
    public var isZOrderEnabled: Bool = false
    /// 1つ上のオブジェクトで切り抜くか。
    public var isClippingWithObjectAbove: Bool = false
    /// 映像エフェクト（生 JSON で保持）。
    public var videoEffects: [PreservedObject] = []
    /// 遷移プラグインの型名（本家ではプライマリプラグインの型が既定）。
    public var transitionType: String = ""
    /// 遷移パラメータ（プラグイン型、生 JSON で保持）。
    public var transitionParameter: PreservedObject?
    /// 遷移前に適用する映像エフェクト（生 JSON で保持）。
    public var beforeVideoEffects: [PreservedObject] = []
    /// 遷移後に適用する映像エフェクト（生 JSON で保持）。
    public var afterVideoEffects: [PreservedObject] = []

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        body(&x)
        body(&y)
        body(&z)
        body(&opacity)
        body(&zoom)
        body(&rotation)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
            (key: "FadeIn", value: .number(fadeIn)),
            (key: "FadeOut", value: .number(fadeOut)),
            (key: "IsInverted", value: .bool(isInverted)),
            (key: "Blend", value: .string(blend.honkeName)),
            (key: "IsAlwaysOnTop", value: .bool(isAlwaysOnTop)),
            (key: "IsZOrderEnabled", value: .bool(isZOrderEnabled)),
            (key: "IsClippingWithObjectAbove", value: .bool(isClippingWithObjectAbove)),
            (key: "VideoEffects", value: .array(videoEffects.map { $0.value })),
            (key: "TransitionType", value: .string(transitionType)),
            (key: "TransitionParameter", value: transitionParameter?.value ?? .null),
            (key: "BeforeVideoEffects", value: .array(beforeVideoEffects.map { $0.value })),
            (key: "AfterVideoEffects", value: .array(afterVideoEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
        case "Z":
            CodecSupport.decodeAnimation(value, into: &z)
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
        case "Rotation":
            CodecSupport.decodeAnimation(value, into: &rotation)
        case "FadeIn":
            fadeIn = CodecSupport.double(value, default: fadeIn)
        case "FadeOut":
            fadeOut = CodecSupport.double(value, default: fadeOut)
        case "IsInverted":
            isInverted = CodecSupport.bool(value, default: isInverted)
        case "Blend":
            blend = CodecSupport.enumeration(value, default: blend)
        case "IsAlwaysOnTop":
            isAlwaysOnTop = CodecSupport.bool(value, default: isAlwaysOnTop)
        case "IsZOrderEnabled":
            isZOrderEnabled = CodecSupport.bool(value, default: isZOrderEnabled)
        case "IsClippingWithObjectAbove":
            isClippingWithObjectAbove = CodecSupport.bool(value, default: isClippingWithObjectAbove)
        case "VideoEffects":
            videoEffects = CodecSupport.preservedList(value)
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
        return true
    }
}

extension TransitionItem: VideoItemProperties {}
