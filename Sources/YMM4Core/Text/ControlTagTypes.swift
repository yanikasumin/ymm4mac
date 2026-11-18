import Foundation

/// 制御タグの数値指定に使う演算子。本家 `ArithmeticOperator` に対応する。
/// タグ中では接頭辞 `*=` `/=` `+=` `-=` `=`（または無印＝代入）で表す。
public enum ArithmeticOperator: Equatable, Sendable {
    case set
    case add
    case subtract
    case multiply
    case divide
}

/// タイミングタグの種別。本家 `TimingTagType` に対応する。
public enum TimingTagType: Equatable, Sendable {
    /// 表示速度の変更（`<r 秒あたり文字数>`）。
    case displaySpeed
    /// 指定秒数だけ表示を止める（`<w 秒数>` / `<w*倍率>`）。
    case wait
    /// それまでの区間を隠す（`<c 秒数>`）。
    case clear
}

/// タイミングタグ1件。本家 `TimingTag` に対応する。
/// `position` はタグ除去後のテキスト（クリーンテキスト）での位置。
public struct TimingTag: Equatable, Sendable {
    public var position: Int
    public var type: TimingTagType
    public var value: Double
    public var arithmeticOperator: ArithmeticOperator

    public init(
        position: Int, type: TimingTagType, value: Double,
        arithmeticOperator: ArithmeticOperator = .set
    ) {
        self.position = position
        self.type = type
        self.value = value
        self.arithmeticOperator = arithmeticOperator
    }
}

/// ルビ（ふりがな）1件。本家 `RubyInfo` に対応する。
/// `start` / `length` はクリーンテキストでの親文字の範囲。
/// `fontSizePercent` は基準フォントサイズに対する百分率（既定50）。
public struct RubyInfo: Equatable, Sendable {
    public var start: Int
    public var length: Int
    public var rubyText: String
    public var fontSizePercent: Double
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var font: String? = nil
    public var bold: Bool? = nil
    public var italic: Bool? = nil
    public var foreground: Color? = nil
    public var decorationColor: Color? = nil
    /// ルビ文字列自体にかかる装飾（親テキストの装飾から切り出したもの）。
    public var rubyDecorations: [TextDecoration]? = nil

    public init(
        start: Int, length: Int, rubyText: String, fontSizePercent: Double
    ) {
        self.start = start
        self.length = length
        self.rubyText = rubyText
        self.fontSizePercent = fontSizePercent
    }
}

/// タイミング区間（クリアタグで区切られた範囲）1件。
/// 本家 `CharacterTimingSection` に対応する。
public struct CharacterTimingSection: Equatable, Sendable {
    public var start: Int
    public var length: Int
    /// 区間内の最小の表示開始時刻（ミリ秒）。
    public var displayStartMs: Double
    /// 区間の消去時刻（ミリ秒）。消去が無ければ `Double.greatestFiniteMagnitude`。
    public var hideTimeMs: Double

    public init(start: Int, length: Int, displayStartMs: Double, hideTimeMs: Double) {
        self.start = start
        self.length = length
        self.displayStartMs = displayStartMs
        self.hideTimeMs = hideTimeMs
    }
}

/// 文字ごとの表示・消去時刻。本家 `CharacterTimingInfo` に対応する。
/// 添字はクリーンテキストの文字位置。
public struct CharacterTimingInfo: Equatable, Sendable {
    public var displayTimesMs: [Double]
    public var hideTimesMs: [Double]
    public var sections: [CharacterTimingSection]

    public init(
        displayTimesMs: [Double], hideTimesMs: [Double],
        sections: [CharacterTimingSection]
    ) {
        self.displayTimesMs = displayTimesMs
        self.hideTimesMs = hideTimesMs
        self.sections = sections
    }
}
