import Foundation

/// キャラクター呼び出し用ショートカット。本家 `System.Windows.Input.KeyGesture`
/// に対応する。
///
/// 保存形式は本家 `KeyGestureJsonConverter` のとおり
/// `{"Key": 列挙型名, "Modifiers": 列挙型名}` で、WPF の列挙型名がそのまま
/// ファイル形式の一部になっているため、名前文字列のまま保持する。
public struct KeyGesture: Equatable, Sendable {
    /// キー名（本家の既定は Key.None）。
    public var key: String = "None"
    /// 修飾キー名（本家の既定は ModifierKeys.Control）。
    public var modifiers: String = "Control"

    public init(key: String = "None", modifiers: String = "Control") {
        self.key = key
        self.modifiers = modifiers
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "Key", value: .string(key)),
            (key: "Modifiers", value: .string(modifiers)),
        ])
    }

    static func decode(from value: JSONValue) -> KeyGesture {
        var gesture = KeyGesture()
        if let name = value.field("Key")?.stringValue {
            gesture.key = name
        } else if case .numberLiteral(let literal)? = value.field("Key") {
            // 数値形式で書かれていた場合はリテラルをそのまま保持する
            gesture.key = literal
        }
        if let name = value.field("Modifiers")?.stringValue {
            gesture.modifiers = name
        } else if case .numberLiteral(let literal)? = value.field("Modifiers") {
            gesture.modifiers = literal
        }
        return gesture
    }
}

/// 音声エンジンと話者の指定。本家 `VoiceDescription` に対応する。
///
/// 保存されるのは `API`（エンジン名）と `Arg`（話者 ID 文字列）だけで、
/// 話者オブジェクト自体は保存対象外（本家でも JsonIgnore）。
public struct VoiceDescription: Equatable, Sendable {
    /// 音声エンジン名。
    public var api: String = ""
    /// 話者 ID 文字列。
    public var arg: String = ""

    public init(api: String = "", arg: String = "") {
        self.api = api
        self.arg = arg
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "API", value: .string(api)),
            (key: "Arg", value: .string(arg)),
        ])
    }

    static func decode(from value: JSONValue) -> VoiceDescription {
        VoiceDescription(
            api: CodecSupport.string(value.field("API"), default: ""),
            arg: CodecSupport.string(value.field("Arg"), default: "")
        )
    }
}

/// キャラクター。本家 `Character` に対応する。
///
/// 本家の全プロパティ（音声・字幕・立ち絵まわりの保存対象86件）を型付きで
/// モデル化する。プラグインインタフェース型の値（VoiceParameter、
/// TachieCharacterParameter、各種エフェクト列など）は他モデルと同様に
/// `PreservedObject` として生 JSON のまま保持する。型名そのものへの参照
/// （TachieType）はプラグイン型名の文字列として保持する。
/// 書き出しのキー順は本家の宣言順に合わせる。
/// 旧互換の `LineHeight` / `LetterSpacing`（set 専用）は読み込み時に
/// `LineHeight2` / `LetterSpacing2` の先頭値へ転送され、書き出さない。
public final class Character {
    /// 名前。
    public var name: String = ""
    /// グループ名。ファイル上の値はこの保持値そのもので、本家 getter が
    /// 空のときに返すリソース文字列は表示専用であり保存されない。
    public var groupName: String = ""
    /// キャラクター色（本家の既定は Colors.Red）。
    public var color: Color = .red
    /// レイヤー。
    public var layer: Int = 0
    /// 呼び出し用ショートカット。
    public var keyGesture: KeyGesture = KeyGesture()
    /// 備考。
    public var remark: String = ""
    /// 音声エンジンと話者（未設定なら nil）。
    public var voice: VoiceDescription?
    /// 音量（%）。
    public var volume: Animation = Animation(defaultValue: 50, minValue: 0, maxValue: 10_000)
    /// パン（-100..100）。
    public var pan: Animation = Animation(defaultValue: 0, minValue: -100, maxValue: 100)
    /// 再生速度（%）。
    public var playbackRate: Double = 100
    /// 音声パラメータ（プラグイン型、生 JSON で保持）。
    public var voiceParameter: PreservedObject?
    /// 音声アイテムのコンテンツオフセット。
    public var contentOffset: TimeSpanValue = .zero
    /// 追加時間（秒）。
    public var additionalTime: Double = 0.3
    /// 音声のフェードイン（秒）。
    public var voiceFadeIn: Double = 0
    /// 音声のフェードアウト（秒）。
    public var voiceFadeOut: Double = 0
    /// エコーを有効にするか。
    public var echoIsEnabled: Bool = false
    /// エコーの間隔（秒）。
    public var echoInterval: Double = 0.1
    /// エコーの減衰（%）。
    public var echoAttenuation: Double = 40
    /// カスタムボイスを使うか。
    public var customVoiceIsEnabled: Bool = false
    /// カスタムボイスでサブディレクトリも対象にするか。
    public var customVoiceIncludeSubdirectories: Bool = false
    /// カスタムボイスのディレクトリ。
    public var customVoiceDirectory: String = ""
    /// カスタムボイスのファイル名パターン。
    public var customVoiceFileName: String = ""
    /// 音声エフェクト（生 JSON で保持）。
    public var audioEffects: [PreservedObject] = []
    /// 字幕を表示するか。
    public var isJimakuVisible: Bool = true
    /// 字幕をロックするか。
    public var isJimakuLocked: Bool = false
    /// 字幕の X 座標。
    public var x: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 字幕の Y 座標。
    public var y: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 字幕の Z 座標。
    public var z: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 字幕の不透明度（%）。
    public var opacity: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 字幕の拡大率（%）。
    public var zoom: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 字幕の回転角。
    public var rotation: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 字幕のフェードイン（秒）。
    public var jimakuFadeIn: Double = 0
    /// 字幕のフェードアウト（秒）。
    public var jimakuFadeOut: Double = 0
    /// 字幕の合成方法。
    public var blend: Blend = .normal
    /// 字幕を反転するか。
    public var isInverted: Bool = false
    /// 字幕を常に手前に表示するか。
    public var isAlwaysOnTop: Bool = false
    /// 字幕の Z オーダーを有効にするか。
    public var isZOrderEnabled: Bool = false
    /// 字幕を1つ上のオブジェクトで切り抜くか。
    public var isClippingWithObjectAbove: Bool = false
    /// フォント名（本家の既定は「メイリオ」）。
    public var font: String = "メイリオ"
    /// フォントサイズ。
    public var fontSize: Animation = Animation(defaultValue: 34, minValue: 1, maxValue: 100_000)
    /// 行の高さ（%）。
    public var lineHeight2: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 字間（%）。
    public var letterSpacing2: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// テキストの折り返し。
    public var wordWrap: WordWrap = .noWrap
    /// 最大幅。
    public var maxWidth: Animation = Animation(defaultValue: 1920, minValue: 0, maxValue: 100_000)
    /// 基準点。
    public var basePoint: BasePoint = .leftTop
    /// フォント色（本家の既定は Colors.White）。
    public var fontColor: Color = .white
    /// 文字スタイル。
    public var style: TextStyle = .normal
    /// スタイル色（本家の既定は Colors.Black）。
    public var styleColor: Color = .black
    /// 太字か。
    public var bold: Bool = false
    /// 斜体か。
    public var italic: Bool = false
    /// 下線か。
    public var underline: Bool = false
    /// 打ち消し線か。
    public var strikethrough: Bool = false
    /// 行末の空白を詰めるか。
    public var isTrimEndSpace: Bool = false
    /// 1文字ずつ分割するか（キー名の綴り `Devided` は本家どおり）。
    public var isDevidedPerCharacter: Bool = false
    /// タイプライター表示の間隔（秒）。
    public var displayInterval: Double = 0
    /// タイプライター表示の方向。
    public var displayDirection: TypewriterAnimationDirection = .fromFirst
    /// タイプライター消去の間隔（秒）。
    public var hideInterval: Double = 0
    /// タイプライター消去の方向。
    public var hideDirection: TypewriterAnimationDirection = .fromFirst
    /// 字幕の映像エフェクト（生 JSON で保持）。
    public var jimakuVideoEffects: [PreservedObject] = []
    /// 立ち絵プラグインの型名（未設定なら nil）。
    public var tachieType: String?
    /// 立ち絵キャラクターパラメータ（プラグイン型、生 JSON で保持）。
    public var tachieCharacterParameter: PreservedObject?
    /// 口の滑らかさ（本家のプロパティ名は MouseSmooth、既定 4）。
    public var mouseSmooth: Int = 4
    /// 立ち絵をロックするか。
    public var isTachieLocked: Bool = false
    /// 立ち絵の X 座標。
    public var tachieX: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 立ち絵の Y 座標。
    public var tachieY: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 立ち絵の Z 座標。
    public var tachieZ: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 立ち絵の不透明度（%）。
    public var tachieOpacity: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 立ち絵の拡大率（%）。
    public var tachieZoom: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 立ち絵の回転角。
    public var tachieRotation: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 立ち絵のフェードイン（秒）。
    public var tachieFadeIn: Double = 0
    /// 立ち絵のフェードアウト（秒）。
    public var tachieFadeOut: Double = 0
    /// 立ち絵の合成方法。
    public var tachieBlend: Blend = .normal
    /// 立ち絵を反転するか。
    public var tachieIsInverted: Bool = false
    /// 立ち絵を常に手前に表示するか。
    public var tachieIsAlwaysOnTop: Bool = false
    /// 立ち絵の Z オーダーを有効にするか。
    public var tachieIsZOrderEnabled: Bool = false
    /// 立ち絵を1つ上のオブジェクトで切り抜くか。
    public var tachieIsClippingWithObjectAbove: Bool = false
    /// 立ち絵アイテムの既定パラメータ（プラグイン型、生 JSON で保持）。
    public var tachieDefaultItemParameter: PreservedObject?
    /// 立ち絵アイテムの映像エフェクト（生 JSON で保持）。
    public var tachieItemVideoEffects: [PreservedObject] = []
    /// 立ち絵表情の既定パラメータ（プラグイン型、生 JSON で保持）。
    public var tachieDefaultFaceParameter: PreservedObject?
    /// 立ち絵表情の既定エフェクト（生 JSON で保持）。
    public var tachieDefaultFaceEffects: [PreservedObject] = []
    /// 追加前景テンプレート名（本家では未設定時 null）。
    public var additionalForegroundTemplateName: String?
    /// 追加背景テンプレート名（本家では未設定時 null）。
    public var additionalBackgroundTemplateName: String?
    /// 音声アイテムの長さ（フレーム。アニメーション評価用）。
    public var voiceItemLength: Int = 300
    /// 立ち絵アイテムの長さ（フレーム。アニメーション評価用）。
    public var tachieItemLength: Int = 300
    /// 音声アイテム用キーフレーム。
    public var voiceItemKeyFrames: KeyFrames = KeyFrames()
    /// 立ち絵アイテム用キーフレーム。
    public var tachieItemKeyFrames: KeyFrames = KeyFrames()

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    /// .ymmp のオブジェクト形式へ書き出す（型付きプロパティ＋追加フィールド）。
    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Name", value: .string(name)),
            (key: "GroupName", value: .string(groupName)),
            (key: "Color", value: .string(color.honkeString)),
            (key: "Layer", value: .number(layer)),
            (key: "KeyGesture", value: keyGesture.encodeToJSONValue()),
            (key: "Remark", value: .string(remark)),
            (key: "Voice", value: voice?.encodeToJSONValue() ?? .null),
            (key: "Volume", value: CodecSupport.encodeAnimation(volume)),
            (key: "Pan", value: CodecSupport.encodeAnimation(pan)),
            (key: "PlaybackRate", value: .number(playbackRate)),
            (key: "VoiceParameter", value: voiceParameter?.value ?? .null),
            (key: "ContentOffset", value: .string(contentOffset.honkeString)),
            (key: "AdditionalTime", value: .number(additionalTime)),
            (key: "VoiceFadeIn", value: .number(voiceFadeIn)),
            (key: "VoiceFadeOut", value: .number(voiceFadeOut)),
            (key: "EchoIsEnabled", value: .bool(echoIsEnabled)),
            (key: "EchoInterval", value: .number(echoInterval)),
            (key: "EchoAttenuation", value: .number(echoAttenuation)),
            (key: "CustomVoiceIsEnabled", value: .bool(customVoiceIsEnabled)),
            (key: "CustomVoiceIncludeSubdirectories", value: .bool(customVoiceIncludeSubdirectories)),
            (key: "CustomVoiceDirectory", value: .string(customVoiceDirectory)),
            (key: "CustomVoiceFileName", value: .string(customVoiceFileName)),
            (key: "AudioEffects", value: .array(audioEffects.map { $0.value })),
            (key: "IsJimakuVisible", value: .bool(isJimakuVisible)),
            (key: "IsJimakuLocked", value: .bool(isJimakuLocked)),
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
            (key: "JimakuFadeIn", value: .number(jimakuFadeIn)),
            (key: "JimakuFadeOut", value: .number(jimakuFadeOut)),
            (key: "Blend", value: .string(blend.honkeName)),
            (key: "IsInverted", value: .bool(isInverted)),
            (key: "IsAlwaysOnTop", value: .bool(isAlwaysOnTop)),
            (key: "IsZOrderEnabled", value: .bool(isZOrderEnabled)),
            (key: "IsClippingWithObjectAbove", value: .bool(isClippingWithObjectAbove)),
            (key: "Font", value: .string(font)),
            (key: "FontSize", value: CodecSupport.encodeAnimation(fontSize)),
            (key: "LineHeight2", value: CodecSupport.encodeAnimation(lineHeight2)),
            (key: "LetterSpacing2", value: CodecSupport.encodeAnimation(letterSpacing2)),
            (key: "WordWrap", value: .string(wordWrap.honkeName)),
            (key: "MaxWidth", value: CodecSupport.encodeAnimation(maxWidth)),
            (key: "BasePoint", value: .string(basePoint.honkeName)),
            (key: "FontColor", value: .string(fontColor.honkeString)),
            (key: "Style", value: .string(style.honkeName)),
            (key: "StyleColor", value: .string(styleColor.honkeString)),
            (key: "Bold", value: .bool(bold)),
            (key: "Italic", value: .bool(italic)),
            (key: "Underline", value: .bool(underline)),
            (key: "Strikethrough", value: .bool(strikethrough)),
            (key: "IsTrimEndSpace", value: .bool(isTrimEndSpace)),
            (key: "IsDevidedPerCharacter", value: .bool(isDevidedPerCharacter)),
            (key: "DisplayInterval", value: .number(displayInterval)),
            (key: "DisplayDirection", value: .string(displayDirection.honkeName)),
            (key: "HideInterval", value: .number(hideInterval)),
            (key: "HideDirection", value: .string(hideDirection.honkeName)),
            (key: "JimakuVideoEffects", value: .array(jimakuVideoEffects.map { $0.value })),
            (key: "TachieType", value: tachieType.map { .string($0) } ?? .null),
            (key: "TachieCharacterParameter", value: tachieCharacterParameter?.value ?? .null),
            (key: "MouseSmooth", value: .number(mouseSmooth)),
            (key: "IsTachieLocked", value: .bool(isTachieLocked)),
            (key: "TachieX", value: CodecSupport.encodeAnimation(tachieX)),
            (key: "TachieY", value: CodecSupport.encodeAnimation(tachieY)),
            (key: "TachieZ", value: CodecSupport.encodeAnimation(tachieZ)),
            (key: "TachieOpacity", value: CodecSupport.encodeAnimation(tachieOpacity)),
            (key: "TachieZoom", value: CodecSupport.encodeAnimation(tachieZoom)),
            (key: "TachieRotation", value: CodecSupport.encodeAnimation(tachieRotation)),
            (key: "TachieFadeIn", value: .number(tachieFadeIn)),
            (key: "TachieFadeOut", value: .number(tachieFadeOut)),
            (key: "TachieBlend", value: .string(tachieBlend.honkeName)),
            (key: "TachieIsInverted", value: .bool(tachieIsInverted)),
            (key: "TachieIsAlwaysOnTop", value: .bool(tachieIsAlwaysOnTop)),
            (key: "TachieIsZOrderEnabled", value: .bool(tachieIsZOrderEnabled)),
            (key: "TachieIsClippingWithObjectAbove", value: .bool(tachieIsClippingWithObjectAbove)),
            (key: "TachieDefaultItemParameter", value: tachieDefaultItemParameter?.value ?? .null),
            (key: "TachieItemVideoEffects", value: .array(tachieItemVideoEffects.map { $0.value })),
            (key: "TachieDefaultFaceParameter", value: tachieDefaultFaceParameter?.value ?? .null),
            (key: "TachieDefaultFaceEffects", value: .array(tachieDefaultFaceEffects.map { $0.value })),
            (key: "AdditionalForegroundTemplateName", value: additionalForegroundTemplateName.map { .string($0) } ?? .null),
            (key: "AdditionalBackgroundTemplateName", value: additionalBackgroundTemplateName.map { .string($0) } ?? .null),
            (key: "VoiceItemLength", value: .number(voiceItemLength)),
            (key: "TachieItemLength", value: .number(tachieItemLength)),
            (key: "VoiceItemKeyFrames", value: CodecSupport.encodeKeyFrames(voiceItemKeyFrames)),
            (key: "TachieItemKeyFrames", value: CodecSupport.encodeKeyFrames(tachieItemKeyFrames)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    /// .ymmp のオブジェクト形式から読み込む。オブジェクトでなければ nil。
    static func decode(from value: JSONValue) -> Character? {
        guard let fields = value.objectFields else { return nil }
        let character = Character()
        for (key, fieldValue) in fields {
            switch key {
            case "Name":
                character.name = CodecSupport.string(fieldValue, default: character.name)
            case "GroupName":
                character.groupName = CodecSupport.string(fieldValue, default: character.groupName)
            case "Color":
                character.color = CodecSupport.color(fieldValue, default: character.color)
            case "Layer":
                character.layer = CodecSupport.int(fieldValue, default: character.layer)
            case "KeyGesture":
                character.keyGesture = KeyGesture.decode(from: fieldValue)
            case "Remark":
                character.remark = CodecSupport.string(fieldValue, default: character.remark)
            case "Voice":
                character.voice = fieldValue == .null ? nil : VoiceDescription.decode(from: fieldValue)
            case "Volume":
                CodecSupport.decodeAnimation(fieldValue, into: &character.volume)
            case "Pan":
                CodecSupport.decodeAnimation(fieldValue, into: &character.pan)
            case "PlaybackRate":
                character.playbackRate = CodecSupport.double(fieldValue, default: character.playbackRate)
            case "VoiceParameter":
                character.voiceParameter = CodecSupport.preservedObject(fieldValue)
            case "ContentOffset":
                character.contentOffset = CodecSupport.timeSpan(fieldValue, default: character.contentOffset)
            case "AdditionalTime":
                character.additionalTime = CodecSupport.double(fieldValue, default: character.additionalTime)
            case "VoiceFadeIn":
                character.voiceFadeIn = CodecSupport.double(fieldValue, default: character.voiceFadeIn)
            case "VoiceFadeOut":
                character.voiceFadeOut = CodecSupport.double(fieldValue, default: character.voiceFadeOut)
            case "EchoIsEnabled":
                character.echoIsEnabled = CodecSupport.bool(fieldValue, default: character.echoIsEnabled)
            case "EchoInterval":
                character.echoInterval = CodecSupport.double(fieldValue, default: character.echoInterval)
            case "EchoAttenuation":
                character.echoAttenuation = CodecSupport.double(fieldValue, default: character.echoAttenuation)
            case "CustomVoiceIsEnabled":
                character.customVoiceIsEnabled = CodecSupport.bool(fieldValue, default: character.customVoiceIsEnabled)
            case "CustomVoiceIncludeSubdirectories":
                character.customVoiceIncludeSubdirectories = CodecSupport.bool(fieldValue, default: character.customVoiceIncludeSubdirectories)
            case "CustomVoiceDirectory":
                character.customVoiceDirectory = CodecSupport.string(fieldValue, default: character.customVoiceDirectory)
            case "CustomVoiceFileName":
                character.customVoiceFileName = CodecSupport.string(fieldValue, default: character.customVoiceFileName)
            case "AudioEffects":
                character.audioEffects = CodecSupport.preservedList(fieldValue)
            case "IsJimakuVisible":
                character.isJimakuVisible = CodecSupport.bool(fieldValue, default: character.isJimakuVisible)
            case "IsJimakuLocked":
                character.isJimakuLocked = CodecSupport.bool(fieldValue, default: character.isJimakuLocked)
            case "X":
                CodecSupport.decodeAnimation(fieldValue, into: &character.x)
            case "Y":
                CodecSupport.decodeAnimation(fieldValue, into: &character.y)
            case "Z":
                CodecSupport.decodeAnimation(fieldValue, into: &character.z)
            case "Opacity":
                CodecSupport.decodeAnimation(fieldValue, into: &character.opacity)
            case "Zoom":
                CodecSupport.decodeAnimation(fieldValue, into: &character.zoom)
            case "Rotation":
                CodecSupport.decodeAnimation(fieldValue, into: &character.rotation)
            case "JimakuFadeIn":
                character.jimakuFadeIn = CodecSupport.double(fieldValue, default: character.jimakuFadeIn)
            case "JimakuFadeOut":
                character.jimakuFadeOut = CodecSupport.double(fieldValue, default: character.jimakuFadeOut)
            case "Blend":
                character.blend = CodecSupport.enumeration(fieldValue, default: character.blend)
            case "IsInverted":
                character.isInverted = CodecSupport.bool(fieldValue, default: character.isInverted)
            case "IsAlwaysOnTop":
                character.isAlwaysOnTop = CodecSupport.bool(fieldValue, default: character.isAlwaysOnTop)
            case "IsZOrderEnabled":
                character.isZOrderEnabled = CodecSupport.bool(fieldValue, default: character.isZOrderEnabled)
            case "IsClippingWithObjectAbove":
                character.isClippingWithObjectAbove = CodecSupport.bool(fieldValue, default: character.isClippingWithObjectAbove)
            case "Font":
                character.font = CodecSupport.string(fieldValue, default: character.font)
            case "FontSize":
                CodecSupport.decodeAnimation(fieldValue, into: &character.fontSize)
            case "LineHeight2":
                CodecSupport.decodeAnimation(fieldValue, into: &character.lineHeight2)
            case "LetterSpacing2":
                CodecSupport.decodeAnimation(fieldValue, into: &character.letterSpacing2)
            case "WordWrap":
                character.wordWrap = CodecSupport.enumeration(fieldValue, default: character.wordWrap)
            case "MaxWidth":
                CodecSupport.decodeAnimation(fieldValue, into: &character.maxWidth)
            case "BasePoint":
                character.basePoint = CodecSupport.enumeration(fieldValue, default: character.basePoint)
            case "FontColor":
                character.fontColor = CodecSupport.color(fieldValue, default: character.fontColor)
            case "Style":
                character.style = CodecSupport.enumeration(fieldValue, default: character.style)
            case "StyleColor":
                character.styleColor = CodecSupport.color(fieldValue, default: character.styleColor)
            case "Bold":
                character.bold = CodecSupport.bool(fieldValue, default: character.bold)
            case "Italic":
                character.italic = CodecSupport.bool(fieldValue, default: character.italic)
            case "Underline":
                character.underline = CodecSupport.bool(fieldValue, default: character.underline)
            case "Strikethrough":
                character.strikethrough = CodecSupport.bool(fieldValue, default: character.strikethrough)
            case "IsTrimEndSpace":
                character.isTrimEndSpace = CodecSupport.bool(fieldValue, default: character.isTrimEndSpace)
            case "IsDevidedPerCharacter":
                character.isDevidedPerCharacter = CodecSupport.bool(fieldValue, default: character.isDevidedPerCharacter)
            case "DisplayInterval":
                character.displayInterval = CodecSupport.double(fieldValue, default: character.displayInterval)
            case "DisplayDirection":
                character.displayDirection = CodecSupport.enumeration(fieldValue, default: character.displayDirection)
            case "HideInterval":
                character.hideInterval = CodecSupport.double(fieldValue, default: character.hideInterval)
            case "HideDirection":
                character.hideDirection = CodecSupport.enumeration(fieldValue, default: character.hideDirection)
            case "JimakuVideoEffects":
                character.jimakuVideoEffects = CodecSupport.preservedList(fieldValue)
            case "TachieType":
                character.tachieType = fieldValue == .null ? nil : fieldValue.stringValue
            case "TachieCharacterParameter":
                character.tachieCharacterParameter = CodecSupport.preservedObject(fieldValue)
            case "MouseSmooth":
                character.mouseSmooth = CodecSupport.int(fieldValue, default: character.mouseSmooth)
            case "IsTachieLocked":
                character.isTachieLocked = CodecSupport.bool(fieldValue, default: character.isTachieLocked)
            case "TachieX":
                CodecSupport.decodeAnimation(fieldValue, into: &character.tachieX)
            case "TachieY":
                CodecSupport.decodeAnimation(fieldValue, into: &character.tachieY)
            case "TachieZ":
                CodecSupport.decodeAnimation(fieldValue, into: &character.tachieZ)
            case "TachieOpacity":
                CodecSupport.decodeAnimation(fieldValue, into: &character.tachieOpacity)
            case "TachieZoom":
                CodecSupport.decodeAnimation(fieldValue, into: &character.tachieZoom)
            case "TachieRotation":
                CodecSupport.decodeAnimation(fieldValue, into: &character.tachieRotation)
            case "TachieFadeIn":
                character.tachieFadeIn = CodecSupport.double(fieldValue, default: character.tachieFadeIn)
            case "TachieFadeOut":
                character.tachieFadeOut = CodecSupport.double(fieldValue, default: character.tachieFadeOut)
            case "TachieBlend":
                character.tachieBlend = CodecSupport.enumeration(fieldValue, default: character.tachieBlend)
            case "TachieIsInverted":
                character.tachieIsInverted = CodecSupport.bool(fieldValue, default: character.tachieIsInverted)
            case "TachieIsAlwaysOnTop":
                character.tachieIsAlwaysOnTop = CodecSupport.bool(fieldValue, default: character.tachieIsAlwaysOnTop)
            case "TachieIsZOrderEnabled":
                character.tachieIsZOrderEnabled = CodecSupport.bool(fieldValue, default: character.tachieIsZOrderEnabled)
            case "TachieIsClippingWithObjectAbove":
                character.tachieIsClippingWithObjectAbove = CodecSupport.bool(fieldValue, default: character.tachieIsClippingWithObjectAbove)
            case "TachieDefaultItemParameter":
                character.tachieDefaultItemParameter = CodecSupport.preservedObject(fieldValue)
            case "TachieItemVideoEffects":
                character.tachieItemVideoEffects = CodecSupport.preservedList(fieldValue)
            case "TachieDefaultFaceParameter":
                character.tachieDefaultFaceParameter = CodecSupport.preservedObject(fieldValue)
            case "TachieDefaultFaceEffects":
                character.tachieDefaultFaceEffects = CodecSupport.preservedList(fieldValue)
            case "AdditionalForegroundTemplateName":
                character.additionalForegroundTemplateName =
                    fieldValue == .null ? nil : fieldValue.stringValue
            case "AdditionalBackgroundTemplateName":
                character.additionalBackgroundTemplateName =
                    fieldValue == .null ? nil : fieldValue.stringValue
            case "VoiceItemLength":
                character.voiceItemLength = CodecSupport.int(fieldValue, default: character.voiceItemLength)
            case "TachieItemLength":
                character.tachieItemLength = CodecSupport.int(fieldValue, default: character.tachieItemLength)
            case "VoiceItemKeyFrames":
                if let keyFrames = CodecSupport.decodeKeyFrames(fieldValue) {
                    character.voiceItemKeyFrames = keyFrames
                }
            case "TachieItemKeyFrames":
                if let keyFrames = CodecSupport.decodeKeyFrames(fieldValue) {
                    character.tachieItemKeyFrames = keyFrames
                }
            case "LineHeight":
                // 旧互換（set 専用）: LineHeight2 の先頭値へ転送される
                character.lineHeight2.setFirstValue(
                    CodecSupport.double(fieldValue, default: character.lineHeight2.firstValue)
                )
            case "LetterSpacing":
                // 旧互換（set 専用）: LetterSpacing2 の先頭値へ転送される
                character.letterSpacing2.setFirstValue(
                    CodecSupport.double(fieldValue, default: character.letterSpacing2.firstValue)
                )
            default:
                character.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return character
    }
}
