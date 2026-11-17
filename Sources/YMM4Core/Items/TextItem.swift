import Foundation

/// テキストの一部への装飾。本家 `TextDecoration`（レコード）に対応する。
///
/// `IsAbsolutePosition` と `HasDecoration` は計算プロパティだが本家は
/// 保存時に書き出すため、エンコード時に計算して含める（読み込み時は捨てる）。
public struct TextDecoration: Equatable, Sendable {
    public var start: Int
    public var length: Int
    public var isBold: Bool
    public var isItalic: Bool
    public var scale: Double
    public var font: String?
    public var foreground: Color?
    public var isLineBreak: Bool
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var isAbsoluteX: Bool = false
    public var isAbsoluteY: Bool = false
    public var decorationColor: Color? = nil
    public var rotationZ: Double = 0
    public var isStrikethrough: Bool = false
    public var isUnderline: Bool = false
    public var rotationGroupId: Int = 0
    public var positionGroupId: Int = 0
    public var characterSpacing: Double? = nil
    public var styleType: Int? = nil

    public init(
        start: Int, length: Int, isBold: Bool = false, isItalic: Bool = false,
        scale: Double = 1, font: String? = nil, foreground: Color? = nil,
        isLineBreak: Bool = false
    ) {
        self.start = start
        self.length = length
        self.isBold = isBold
        self.isItalic = isItalic
        self.scale = scale
        self.font = font
        self.foreground = foreground
        self.isLineBreak = isLineBreak
    }

    /// 絶対配置かどうか。本家 `IsAbsolutePosition`。
    public var isAbsolutePosition: Bool {
        isAbsoluteX || isAbsoluteY
    }

    /// 装飾が有効かどうか。本家 `HasDecoration` の条件そのまま。
    public var hasDecoration: Bool {
        if isLineBreak { return false }
        if !isBold && !isItalic && !isStrikethrough && !isUnderline && scale == 1.0
            && font == nil && foreground == nil && decorationColor == nil
            && offsetX == 0 && offsetY == 0 && !isAbsoluteX && !isAbsoluteY
            && rotationZ == 0 && characterSpacing == nil {
            return styleType != nil
        }
        return true
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "Start", value: .number(start)),
            (key: "Length", value: .number(length)),
            (key: "IsBold", value: .bool(isBold)),
            (key: "IsItalic", value: .bool(isItalic)),
            (key: "Scale", value: .number(scale)),
            (key: "Font", value: font.map(JSONValue.string) ?? .null),
            (key: "Foreground", value: foreground.map { .string($0.honkeString) } ?? .null),
            (key: "IsLineBreak", value: .bool(isLineBreak)),
            (key: "OffsetX", value: .number(offsetX)),
            (key: "OffsetY", value: .number(offsetY)),
            (key: "IsAbsoluteX", value: .bool(isAbsoluteX)),
            (key: "IsAbsoluteY", value: .bool(isAbsoluteY)),
            (key: "DecorationColor", value: decorationColor.map { .string($0.honkeString) } ?? .null),
            (key: "RotationZ", value: .number(rotationZ)),
            (key: "IsStrikethrough", value: .bool(isStrikethrough)),
            (key: "IsUnderline", value: .bool(isUnderline)),
            (key: "RotationGroupId", value: .number(rotationGroupId)),
            (key: "PositionGroupId", value: .number(positionGroupId)),
            (key: "CharacterSpacing", value: characterSpacing.map(JSONValue.number) ?? .null),
            (key: "StyleType", value: styleType.map(JSONValue.number) ?? .null),
            (key: "IsAbsolutePosition", value: .bool(isAbsolutePosition)),
            (key: "HasDecoration", value: .bool(hasDecoration)),
        ])
    }

    static func decode(from value: JSONValue) -> TextDecoration? {
        guard value.objectFields != nil else { return nil }
        var decoration = TextDecoration(start: 0, length: 0, scale: 0)
        decoration.start = CodecSupport.int(value.field("Start"), default: 0)
        decoration.length = CodecSupport.int(value.field("Length"), default: 0)
        decoration.isBold = CodecSupport.bool(value.field("IsBold"), default: false)
        decoration.isItalic = CodecSupport.bool(value.field("IsItalic"), default: false)
        decoration.scale = CodecSupport.double(value.field("Scale"), default: 0)
        if let fontValue = value.field("Font"), fontValue != .null {
            decoration.font = fontValue.stringValue
        }
        if let foregroundValue = value.field("Foreground"), foregroundValue != .null {
            decoration.foreground = CodecSupport.color(foregroundValue, default: .white)
        }
        decoration.isLineBreak = CodecSupport.bool(value.field("IsLineBreak"), default: false)
        decoration.offsetX = CodecSupport.double(value.field("OffsetX"), default: 0)
        decoration.offsetY = CodecSupport.double(value.field("OffsetY"), default: 0)
        decoration.isAbsoluteX = CodecSupport.bool(value.field("IsAbsoluteX"), default: false)
        decoration.isAbsoluteY = CodecSupport.bool(value.field("IsAbsoluteY"), default: false)
        if let colorValue = value.field("DecorationColor"), colorValue != .null {
            decoration.decorationColor = CodecSupport.color(colorValue, default: .white)
        }
        decoration.rotationZ = CodecSupport.double(value.field("RotationZ"), default: 0)
        decoration.isStrikethrough = CodecSupport.bool(value.field("IsStrikethrough"), default: false)
        decoration.isUnderline = CodecSupport.bool(value.field("IsUnderline"), default: false)
        decoration.rotationGroupId = CodecSupport.int(value.field("RotationGroupId"), default: 0)
        decoration.positionGroupId = CodecSupport.int(value.field("PositionGroupId"), default: 0)
        if let spacingValue = value.field("CharacterSpacing"), spacingValue != .null {
            decoration.characterSpacing = spacingValue.doubleValue
        }
        if let styleValue = value.field("StyleType"), styleValue != .null {
            decoration.styleType = styleValue.intValue
        }
        return decoration
    }
}

/// テキスト・字幕に共通するフォント外観の一式。
///
/// 本家では TextItem と VoiceItem（字幕部分）が同じプロパティ群を個別に
/// 持つ。ここでは値の組としてまとめ、各アイテムが保持する。
/// フォント名の既定値は本家ではリソース文字列 `Texts.DefaultFont` で、
/// 逆コンパイル済みコードからは実文字列を特定できない（未解決事項）。
public struct TextAppearance: Sendable {
    public var font: String = ""
    public var fontSize: Animation = Animation(defaultValue: 34, minValue: 1, maxValue: 100_000)
    public var lineHeight2: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    public var letterSpacing2: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    public var wordWrap: WordWrap = .noWrap
    public var maxWidth: Animation = Animation(defaultValue: 1920, minValue: 0, maxValue: 100_000)
    public var basePoint: BasePoint = .leftTop
    public var fontColor: Color = .white
    public var style: TextStyle = .normal
    public var styleColor: Color = .black
    public var bold: Bool = false
    public var italic: Bool = false
    public var underline: Bool = false
    public var strikethrough: Bool = false
    public var isTrimEndSpace: Bool = false
    public var isDevidedPerCharacter: Bool = false
    public var displayInterval: Double = 0
    public var displayDirection: TypewriterAnimationDirection = .fromFirst
    public var hideInterval: Double = 0
    public var hideDirection: TypewriterAnimationDirection = .fromFirst

    public init() {}

    public mutating func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&fontSize)
        body(&lineHeight2)
        body(&letterSpacing2)
        body(&maxWidth)
    }

    func encodeFields() -> [(key: String, value: JSONValue)] {
        [
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
        ]
    }

    mutating func decodeField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Font":
            font = CodecSupport.string(value, default: font)
        case "FontSize":
            CodecSupport.decodeAnimation(value, into: &fontSize)
        case "LineHeight2":
            CodecSupport.decodeAnimation(value, into: &lineHeight2)
        case "LetterSpacing2":
            CodecSupport.decodeAnimation(value, into: &letterSpacing2)
        case "WordWrap":
            wordWrap = CodecSupport.enumeration(value, default: wordWrap)
        case "MaxWidth":
            CodecSupport.decodeAnimation(value, into: &maxWidth)
        case "BasePoint":
            basePoint = CodecSupport.enumeration(value, default: basePoint)
        case "FontColor":
            fontColor = CodecSupport.color(value, default: fontColor)
        case "Style":
            style = CodecSupport.enumeration(value, default: style)
        case "StyleColor":
            styleColor = CodecSupport.color(value, default: styleColor)
        case "Bold":
            bold = CodecSupport.bool(value, default: bold)
        case "Italic":
            italic = CodecSupport.bool(value, default: italic)
        case "Underline":
            underline = CodecSupport.bool(value, default: underline)
        case "Strikethrough":
            strikethrough = CodecSupport.bool(value, default: strikethrough)
        case "IsTrimEndSpace":
            isTrimEndSpace = CodecSupport.bool(value, default: isTrimEndSpace)
        case "IsDevidedPerCharacter":
            isDevidedPerCharacter = CodecSupport.bool(value, default: isDevidedPerCharacter)
        case "DisplayInterval":
            displayInterval = CodecSupport.double(value, default: displayInterval)
        case "DisplayDirection":
            displayDirection = CodecSupport.enumeration(value, default: displayDirection)
        case "HideInterval":
            hideInterval = CodecSupport.double(value, default: hideInterval)
        case "HideDirection":
            hideDirection = CodecSupport.enumeration(value, default: hideDirection)
        case "LineHeight":
            // 旧互換（set 専用）: LineHeight2 の先頭値へ転送される
            lineHeight2.setFirstValue(CodecSupport.double(value, default: lineHeight2.firstValue))
        case "LetterSpacing":
            // 旧互換（set 専用）: LetterSpacing2 の先頭値へ転送される
            letterSpacing2.setFirstValue(CodecSupport.double(value, default: letterSpacing2.firstValue))
        default:
            return false
        }
        return true
    }
}

/// テキストアイテム。本家 `TextItem` に対応する。
public final class TextItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.TextItem, YukkuriMovieMaker"
    }

    /// テキスト本文。
    public var text: String = ""
    /// 部分装飾。
    public var decorations: [TextDecoration] = []
    /// フォント外観。
    public var appearance = TextAppearance()

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        appearance.forEachAnimation(body)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "Text", value: .string(text)),
            (key: "Decorations", value: .array(decorations.map { $0.encodeToJSONValue() })),
        ] + appearance.encodeFields()
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Text":
            text = CodecSupport.string(value, default: text)
            return true
        case "Decorations":
            if let elements = value.arrayValue {
                decorations = elements.compactMap { TextDecoration.decode(from: $0) }
            }
            return true
        default:
            if appearance.decodeField(key, value) {
                return true
            }
            return super.decodeKnownField(key, value)
        }
    }
}
