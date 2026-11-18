import Foundation

/// テキスト制御タグの解析器。本家 `ControlTagParser` の仕様を再現する。
///
/// タグは `<...>` 形式で、本文中に埋め込む。先頭文字で種別が決まる:
/// - `<#前景色[,装飾色]>`: 色（16進数または色名。空で解除）
/// - `<s サイズ[,フォント[,スタイル]]>`: フォントサイズ・名前・スタイル
/// - `<@フォント[,スタイル]>` / `<@+B>` 等: フォント名とスタイルの増減
/// - `<p X,Y>`: 位置ずらし（Y は符号反転して保持）。`<pp X,Y>` は
///   フォントサイズの百分率で指定する比例版
/// - `<rb 親文字,ルビ[,サイズ%[,X[,Y[,フォント[,スタイル[,前景色[,装飾色]]]]]]]>`: ルビ
/// - `<rot 角度>`: 回転
/// - `<r 秒あたり文字数>`: 表示速度（タイミングタグ）
/// - `<w 秒数>` / `<w*倍率>`: 待ち（タイミングタグ）
/// - `<c 秒数>`: それまでの区間を隠す（タイミングタグ）
/// - `<ls 字間>`: 字間
/// 数値には `+=` 等の演算子接頭辞が使える。タグの直前に `\` を置くと
/// タグとして解釈されず、バックスラッシュだけが消えて文字として残る。
/// 解釈できないタグは文字として残り、状態はタグの前に戻る。
///
/// 位置はすべてルーン（Unicode スカラ）単位で扱う。本家は UTF-16 単位
/// であり、サロゲートペアを含むテキストでは位置がずれる（移植側の
/// 装飾の扱いに合わせた内部差分）。
public enum ControlTagParser {

    public struct ParseResult {
        /// タグを取り除いたテキスト（ルビは親文字が残る）。
        public var text: String
        /// 既存装飾へタグ装飾を統合した結果。
        public var decorations: [TextDecoration]
        public var timingTags: [TimingTag]
        public var rubyInfos: [RubyInfo]
    }

    // MARK: - 状態

    private struct TagState {
        var color: Color? = nil
        var decorationColor: Color? = nil
        var fontSize: Double? = nil
        var font: String? = nil
        var bold: Bool? = nil
        var italic: Bool? = nil
        var strikethrough: Bool? = nil
        var underline: Bool? = nil
        var offsetX: Double = 0
        var offsetY: Double = 0
        var isAbsoluteX: Bool = false
        var isAbsoluteY: Bool = false
        var rotationZ: Double = 0
        var characterSpacing: Double? = nil
        var styleType: Int? = nil

        /// 本家 `HasActiveState`。太字等は true のときだけ有効と数える。
        var hasActive: Bool {
            color != nil || decorationColor != nil || fontSize != nil
                || font != nil || bold == true || italic == true
                || strikethrough == true || underline == true
                || offsetX != 0 || offsetY != 0
                || isAbsoluteX || isAbsoluteY || rotationZ != 0
                || characterSpacing != nil || styleType != nil
        }
    }

    private struct SegmentInfo {
        var start: Int
        var length: Int
        var state: TagState
        var rotationGroupId: Int
        var positionGroupId: Int
    }

    private struct PendingRuby {
        var baseText: String
        var baseTextLength: Int
        var rawBaseLength: Int
        var rubyText: String
        var rawRubyLength: Int
        var fontSizePercent: Double
        var offsetX: Double
        var offsetY: Double
        var font: String?
        var bold: Bool?
        var italic: Bool?
        var foreground: Color?
        var decorationColor: Color?
    }

    // MARK: - 解析

    public static func parse(
        text: String,
        existingDecorations: [TextDecoration],
        baseFontSize: Double,
        baseFont: String,
        baseBold: Bool,
        baseItalic: Bool,
        isVertical: Bool = false,
        baseLetterSpacing: Double = 0
    ) -> ParseResult {
        let runes = Array(text.unicodeScalars)
        let matches = scanTags(runes)
        guard !runes.isEmpty, !matches.isEmpty else {
            return ParseResult(
                text: text, decorations: existingDecorations,
                timingTags: [], rubyInfos: []
            )
        }

        var adjusted = existingDecorations
        var clean: [Unicode.Scalar] = []
        var cleanPos = 0
        var rawPos = 0
        var removedCount = 0
        var segmentStart = 0
        var segmentActive = false
        var state = TagState()
        var rotationGroupId = 0
        var positionGroupId = 0
        var timingCollector: [TimingTag] = []
        var rubyInfos: [RubyInfo] = []
        var segments: [SegmentInfo] = []

        /// 通常テキストをクリーン側へ追加する。改行のたびに区間を切り、
        /// 進行方向と直交するオフセットを 0 へ戻す（本家の規則）。
        func appendPlain(_ range: Range<Int>) {
            var chunkStart = range.lowerBound
            var i = range.lowerBound
            while i < range.upperBound {
                if runes[i] == "\n" {
                    clean.append(contentsOf: runes[chunkStart...i])
                    cleanPos += i - chunkStart + 1
                    if segmentActive, cleanPos > segmentStart {
                        segments.append(SegmentInfo(
                            start: segmentStart,
                            length: cleanPos - segmentStart,
                            state: state,
                            rotationGroupId: rotationGroupId,
                            positionGroupId: positionGroupId
                        ))
                    }
                    if isVertical { state.offsetY = 0 } else { state.offsetX = 0 }
                    segmentStart = cleanPos
                    segmentActive = state.hasActive
                    i += 1
                    chunkStart = i
                } else {
                    i += 1
                }
            }
            clean.append(contentsOf: runes[chunkStart..<range.upperBound])
            cleanPos += range.upperBound - chunkStart
        }

        for match in matches {
            appendPlain(rawPos..<match.start)
            if match.escaped {
                // バックスラッシュだけを取り除き、タグ文字列を残す。
                let tagRange = (match.start + 1)..<(match.start + match.length)
                clean.append(contentsOf: runes[tagRange])
                cleanPos += match.length - 1
                removedCount += 1
                adjustExistingDecorations(
                    &adjusted, removedAt: match.start - (removedCount - 1),
                    removedLength: 1
                )
            } else {
                let snapshot = state
                let snapshotRotationGroup = rotationGroupId
                let snapshotPositionGroup = positionGroupId
                var pendingRuby: PendingRuby? = nil
                let tagRunes = Array(runes[match.start..<(match.start + match.length)])
                let success = dispatchTag(
                    tagRunes: tagRunes, cleanPos: cleanPos,
                    baseFontSize: baseFontSize, baseLetterSpacing: baseLetterSpacing,
                    state: &state,
                    rotationGroupId: &rotationGroupId,
                    positionGroupId: &positionGroupId,
                    timingCollector: &timingCollector,
                    pendingRuby: &pendingRuby
                )
                if success, let ruby = pendingRuby {
                    if segmentActive, cleanPos > segmentStart {
                        segments.append(SegmentInfo(
                            start: segmentStart, length: cleanPos - segmentStart,
                            state: snapshot,
                            rotationGroupId: snapshotRotationGroup,
                            positionGroupId: snapshotPositionGroup
                        ))
                    }
                    let rubyRawStartAdjusted =
                        (match.start + 3 + ruby.rawBaseLength + 1) - removedCount
                    let rubyDecorations = extractRubyTextDecorations(
                        adjusted, rubyRawStartAdjusted: rubyRawStartAdjusted,
                        rawRubyLength: ruby.rawRubyLength,
                        rubyCleanLength: ruby.rubyText.unicodeScalars.count
                    )
                    var info = RubyInfo(
                        start: cleanPos, length: ruby.baseTextLength,
                        rubyText: ruby.rubyText,
                        fontSizePercent: ruby.fontSizePercent
                    )
                    info.offsetX = ruby.offsetX
                    info.offsetY = ruby.offsetY
                    info.font = ruby.font
                    info.bold = ruby.bold
                    info.italic = ruby.italic
                    info.foreground = ruby.foreground
                    info.decorationColor = ruby.decorationColor
                    info.rubyDecorations = rubyDecorations
                    clean.append(contentsOf: ruby.baseText.unicodeScalars)
                    rubyInfos.append(info)
                    if state.hasActive {
                        segments.append(SegmentInfo(
                            start: cleanPos, length: ruby.baseTextLength,
                            state: state,
                            rotationGroupId: rotationGroupId,
                            positionGroupId: positionGroupId
                        ))
                    }
                    let removedBefore = removedCount
                    removedCount += match.length - ruby.baseTextLength
                    adjustExistingDecorationsForRuby(
                        &adjusted, tagStartAdjusted: match.start - removedBefore,
                        tagLength: match.length, baseTextOffsetInTag: 3,
                        rawBaseTextLength: ruby.rawBaseLength,
                        baseTextCleanStart: cleanPos,
                        baseTextCleanLength: ruby.baseTextLength
                    )
                    cleanPos += ruby.baseTextLength
                    segmentStart = cleanPos
                    segmentActive = state.hasActive
                } else if success {
                    if segmentActive, cleanPos > segmentStart {
                        segments.append(SegmentInfo(
                            start: segmentStart, length: cleanPos - segmentStart,
                            state: snapshot,
                            rotationGroupId: snapshotRotationGroup,
                            positionGroupId: snapshotPositionGroup
                        ))
                    }
                    segmentStart = cleanPos
                    segmentActive = state.hasActive
                    let removedBefore = removedCount
                    removedCount += match.length
                    adjustExistingDecorations(
                        &adjusted, removedAt: match.start - removedBefore,
                        removedLength: match.length
                    )
                } else {
                    // 解釈できないタグは状態を戻し、文字として残す。
                    state = snapshot
                    clean.append(contentsOf: runes[match.start..<(match.start + match.length)])
                    cleanPos += match.length
                }
            }
            rawPos = match.start + match.length
        }
        appendPlain(rawPos..<runes.count)
        if segmentActive, cleanPos > segmentStart {
            segments.append(SegmentInfo(
                start: segmentStart, length: cleanPos - segmentStart,
                state: state,
                rotationGroupId: rotationGroupId,
                positionGroupId: positionGroupId
            ))
        }

        let decorations = mergeDecorations(
            existing: adjusted, tagInfos: segments, baseFontSize: baseFontSize
        )
        return ParseResult(
            text: String(String.UnicodeScalarView(clean)),
            decorations: decorations,
            timingTags: timingCollector,
            rubyInfos: rubyInfos
        )
    }

    /// タグを取り除いた読み上げ用テキスト。ルビは親文字ではなく
    /// ルビ文字列へ置き換わる。本家 `GetPlainText`。
    public static func plainText(_ text: String) -> String {
        let parsed = parse(
            text: text, existingDecorations: [], baseFontSize: 20,
            baseFont: "", baseBold: false, baseItalic: false
        )
        guard !parsed.rubyInfos.isEmpty else { return parsed.text }
        let runes = Array(parsed.text.unicodeScalars)
        var result: [Unicode.Scalar] = []
        var cursor = 0
        for info in parsed.rubyInfos.sorted(by: { $0.start < $1.start }) {
            if cursor < info.start {
                result.append(contentsOf: runes[cursor..<info.start])
            }
            result.append(contentsOf: info.rubyText.unicodeScalars)
            cursor = info.start + info.length
        }
        if cursor < runes.count {
            result.append(contentsOf: runes[cursor...])
        }
        return String(String.UnicodeScalarView(result))
    }

    // MARK: - タグ走査

    private struct TagMatch {
        var start: Int
        var length: Int
        var escaped: Bool
    }

    /// 本家のタグ正規表現 `\\?<(?:#[^<>]*|s[^<>]*|p[^<>]*|r[^<>]*|w[^<>]*|c[^<>]*|l[^<>]*|@[^<>]*)>`
    /// （大文字小文字を区別しない）と等価な走査。
    private static func scanTags(_ runes: [Unicode.Scalar]) -> [TagMatch] {
        func isFamily(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar {
            case "#", "@", "s", "S", "p", "P", "r", "R", "w", "W", "c", "C", "l", "L":
                return true
            default:
                return false
            }
        }
        var matches: [TagMatch] = []
        var i = 0
        while i < runes.count {
            var start = i
            var escaped = false
            var lt: Int? = nil
            if runes[i] == "\\", i + 1 < runes.count, runes[i + 1] == "<" {
                escaped = true
                lt = i + 1
            } else if runes[i] == "<" {
                lt = i
            }
            guard let ltIndex = lt else {
                i += 1
                continue
            }
            start = escaped ? i : ltIndex
            guard ltIndex + 1 < runes.count, isFamily(runes[ltIndex + 1]) else {
                i += 1
                continue
            }
            var j = ltIndex + 2
            var close: Int? = nil
            while j < runes.count {
                if runes[j] == ">" {
                    close = j
                    break
                }
                if runes[j] == "<" { break }
                j += 1
            }
            guard let end = close else {
                i += 1
                continue
            }
            matches.append(TagMatch(
                start: start, length: end - start + 1, escaped: escaped
            ))
            i = end + 1
        }
        return matches
    }

    // MARK: - タグ振り分け

    // swiftlint:disable:next function_parameter_count
    private static func dispatchTag(
        tagRunes: [Unicode.Scalar],
        cleanPos: Int,
        baseFontSize: Double,
        baseLetterSpacing: Double,
        state: inout TagState,
        rotationGroupId: inout Int,
        positionGroupId: inout Int,
        timingCollector: inout [TimingTag],
        pendingRuby: inout PendingRuby?
    ) -> Bool {
        guard tagRunes.count >= 3 else { return false }
        let family = tagRunes[1]
        let lower = String(family).lowercased()
        /// `<>` を除いた中身の文字列。
        func content(from runeIndex: Int) -> String {
            guard runeIndex < tagRunes.count - 1 else { return "" }
            return String(String.UnicodeScalarView(tagRunes[runeIndex..<(tagRunes.count - 1)]))
        }
        switch lower {
        case "#":
            return parseColorTag(content(from: 2), state: &state)
        case "s":
            return parseFontTag(
                content(from: 2), baseFontSize: baseFontSize, state: &state
            )
        case "@":
            return parseFontFamilyTag(content(from: 2), state: &state)
        case "p":
            let proportional = tagRunes.count >= 4
                && String(tagRunes[2]).lowercased() == "p"
            let ok = proportional
                ? parseProportionalPositionTag(
                    content(from: 3), baseFontSize: baseFontSize, state: &state
                  )
                : parsePositionTag(content(from: 2), state: &state)
            if ok { positionGroupId += 1 }
            return ok
        case "r":
            if tagRunes.count >= 4, String(tagRunes[2]).lowercased() == "b" {
                guard let ruby = parseRubyTag(content(from: 3)) else { return false }
                pendingRuby = ruby
                return true
            }
            if tagRunes.count >= 5,
               String(tagRunes[2]).lowercased() == "o",
               String(tagRunes[3]).lowercased() == "t" {
                let ok = parseRotationTag(content(from: 4), state: &state)
                if ok { rotationGroupId += 1 }
                return ok
            }
            return parseDisplaySpeedTag(
                content(from: 2), cleanPos: cleanPos,
                timingCollector: &timingCollector
            )
        case "w":
            return parseWaitTag(
                content(from: 2), cleanPos: cleanPos,
                timingCollector: &timingCollector
            )
        case "c":
            return parseClearTag(
                content(from: 2), cleanPos: cleanPos,
                timingCollector: &timingCollector
            )
        case "l":
            guard tagRunes.count >= 4,
                  String(tagRunes[2]).lowercased() == "s" else { return false }
            return parseLetterSpacingTag(
                content(from: 3), baseLetterSpacing: baseLetterSpacing,
                state: &state
            )
        default:
            return false
        }
    }

    // MARK: - 値の解析

    /// 本家 `ApplyArithmetic`。
    private static func applyArithmetic(
        _ op: ArithmeticOperator, _ current: Double, _ operand: Double
    ) -> Double {
        switch op {
        case .set: return operand
        case .add: return current + operand
        case .subtract: return current - operand
        case .multiply: return current * operand
        case .divide: return current / operand
        }
    }

    /// 本家 `TryParseArithmeticValue`。接頭辞の演算子と数値へ分解する。
    /// 数値は .NET の `double.TryParse`（不変カルチャ）に近い範囲を許す。
    private static func parseArithmeticValue(
        _ raw: String
    ) -> (op: ArithmeticOperator, value: Double)? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var op: ArithmeticOperator = .set
        for (prefix, candidate) in [
            ("*=", ArithmeticOperator.multiply),
            ("/=", ArithmeticOperator.divide),
            ("+=", ArithmeticOperator.add),
            ("-=", ArithmeticOperator.subtract),
            ("=", ArithmeticOperator.set),
        ] {
            if text.hasPrefix(prefix) {
                op = candidate
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        guard let value = parseDotNetDouble(text) else { return nil }
        return (op, value)
    }

    /// .NET の不変カルチャ数値解析の近似。千区切りのカンマを無視し、
    /// 符号・小数点・指数を許す。
    private static func parseDotNetDouble(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
        guard !text.isEmpty else { return nil }
        return Double(text)
    }

    /// 本家 `ParseColor`。16 進数（桁数 1/2/3/4 は各桁を繰り返して
    /// 展開、6 は RRGGBB、8 は RRGGBBAA）または色名。
    private static func parseColor(_ raw: String) -> Color? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("#") { text.removeFirst() }
        guard !text.isEmpty else { return nil }
        if let hex = parseHexColor(text) { return hex }
        let key = text
            .replacingOccurrences(
                of: "grey", with: "gray", options: .caseInsensitive
            )
            .lowercased()
        return NamedColorTable.colors[key]
    }

    private static func parseHexColor(_ text: String) -> Color? {
        var digits = text
        switch digits.count {
        case 1:
            digits = String(repeating: digits, count: 6)
        case 2:
            digits = digits + digits + digits
        case 3, 4:
            digits = digits.map { "\($0)\($0)" }.joined()
        default:
            break
        }
        guard digits.count == 6 || digits.count == 8 else { return nil }
        var bytes: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        if bytes.count == 3 {
            return Color(alpha: 255, red: bytes[0], green: bytes[1], blue: bytes[2])
        }
        // 8 桁は RRGGBBAA（本家 FromArgb の引数順による）。
        return Color(alpha: bytes[3], red: bytes[0], green: bytes[1], blue: bytes[2])
    }

    /// 本家 `ParseStyleString`。B/I/S/U の有無でスタイルを絶対指定する。
    private static func parseStyleString(
        _ styleText: String, state: inout TagState
    ) -> Bool {
        let upper = styleText.uppercased()
        if upper.contains("B") || upper.contains("I")
            || upper.contains("S") || upper.contains("U") {
            state.bold = upper.contains("B")
            state.italic = upper.contains("I")
            state.strikethrough = upper.contains("S")
            state.underline = upper.contains("U")
        }
        for character in styleText where character.isNumber {
            guard let digit = Int(String(character)), (0...6).contains(digit)
            else { return false }
            state.styleType = digit
            break
        }
        return true
    }

    /// 本家 `ParseStyleDeltaString`。`+`/`-` と文字で増減を指定する。
    private static func parseStyleDelta(_ styleText: String, state: inout TagState) {
        var isPlus = true
        for character in styleText {
            switch character {
            case "+": isPlus = true
            case "-": isPlus = false
            default:
                switch String(character).uppercased() {
                case "B": state.bold = isPlus
                case "I": state.italic = isPlus
                case "S": state.strikethrough = isPlus
                case "U": state.underline = isPlus
                default: break
                }
            }
        }
    }

    // MARK: - 各タグの解析

    private static func parseColorTag(_ content: String, state: inout TagState) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            state.color = nil
            state.decorationColor = nil
            return true
        }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 2 else { return false }
        let foreground = parts[0].trimmingCharacters(in: .whitespaces)
        if foreground.isEmpty {
            state.color = nil
        } else if let color = parseColor(foreground) {
            state.color = color
        } else {
            return false
        }
        if parts.count == 2 {
            let decoration = parts[1].trimmingCharacters(in: .whitespaces)
            if decoration.isEmpty {
                state.decorationColor = nil
            } else if let color = parseColor(decoration) {
                state.decorationColor = color
            } else {
                return false
            }
        }
        return true
    }

    private static func parseFontTag(
        _ content: String, baseFontSize: Double, state: inout TagState
    ) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            // 本家はフォントとスタイルだけを戻し、サイズは戻さない。
            state.font = nil
            state.bold = nil
            state.italic = nil
            state.strikethrough = nil
            state.underline = nil
            state.styleType = nil
            return true
        }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 3 else { return false }
        let sizeText = parts[0].trimmingCharacters(in: .whitespaces)
        if !sizeText.isEmpty {
            guard let parsed = parseArithmeticValue(sizeText) else { return false }
            let current = state.fontSize ?? baseFontSize
            let newSize = parsed.op == .set
                ? parsed.value
                : applyArithmetic(parsed.op, current, parsed.value)
            guard newSize > 0 else { return false }
            state.fontSize = newSize
        }
        if parts.count >= 2 {
            let fontText = parts[1].trimmingCharacters(in: .whitespaces)
            if !fontText.isEmpty { state.font = fontText }
        }
        if parts.count == 3 {
            let styleText = parts[2].trimmingCharacters(in: .whitespaces)
            if !styleText.isEmpty {
                // + か - を含む場合は増減指定として解釈する。
                if styleText.contains("+") || styleText.contains("-") {
                    state.bold = state.bold ?? false
                    state.italic = state.italic ?? false
                    state.strikethrough = state.strikethrough ?? false
                    state.underline = state.underline ?? false
                    parseStyleDelta(styleText, state: &state)
                } else if !parseStyleString(styleText, state: &state) {
                    return false
                }
            }
        }
        return true
    }

    private static func parseFontFamilyTag(
        _ content: String, state: inout TagState
    ) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            state.font = nil
            state.bold = nil
            state.italic = nil
            state.strikethrough = nil
            state.underline = nil
            state.styleType = nil
            return true
        }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 2 else { return false }
        let first = parts[0].trimmingCharacters(in: .whitespaces)
        if first.hasPrefix("+") || first.hasPrefix("-") {
            // 先頭要素が増減指定ならフォントは変えずスタイルだけを動かす。
            parseStyleDelta(first, state: &state)
        } else {
            if !first.isEmpty { state.font = first }
            if parts.count == 2 {
                let styleText = parts[1].trimmingCharacters(in: .whitespaces)
                if styleText.contains("+") || styleText.contains("-") {
                    parseStyleDelta(styleText, state: &state)
                } else if !parseStyleString(styleText, state: &state) {
                    return false
                }
            }
        }
        return true
    }

    private static func parsePositionTag(_ content: String, state: inout TagState) -> Bool {
        let parts = content.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let xText = parts[0].trimmingCharacters(in: .whitespaces)
        let yText = parts[1].trimmingCharacters(in: .whitespaces)
        guard let x = parseArithmeticValue(xText),
              let y = parseArithmeticValue(yText) else { return false }
        // 符号なしの代入は絶対指定、符号つきの代入は相対加算として
        // 扱う（本家の判定）。Y は結果の符号を反転して保持する。
        let resolvedX = resolvePositionComponent(x, text: xText, current: state.offsetX)
        let resolvedY = resolvePositionComponent(y, text: yText, current: state.offsetY)
        state.offsetX = resolvedX.value
        state.offsetY = -resolvedY.value
        state.isAbsoluteX = resolvedX.isAbsolute
        state.isAbsoluteY = resolvedY.isAbsolute
        return true
    }

    private static func resolvePositionComponent(
        _ parsed: (op: ArithmeticOperator, value: Double),
        text: String, current: Double
    ) -> (value: Double, isAbsolute: Bool) {
        let hasSign = text.hasPrefix("+") || text.hasPrefix("-")
        let isAbsolute = parsed.op == .set && !hasSign
        if isAbsolute { return (parsed.value, true) }
        if parsed.op == .set { return (current + parsed.value, false) }
        return (applyArithmetic(parsed.op, current, parsed.value), false)
    }

    private static func parseProportionalPositionTag(
        _ content: String, baseFontSize: Double, state: inout TagState
    ) -> Bool {
        let parts = content.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let xText = parts[0].trimmingCharacters(in: .whitespaces)
        let yText = parts[1].trimmingCharacters(in: .whitespaces)
        guard let x = parseArithmeticValue(xText),
              let y = parseArithmeticValue(yText) else { return false }
        let scale = (state.fontSize ?? baseFontSize) / 100
        state.offsetX = applyArithmetic(x.op, state.offsetX, x.value * scale)
        state.offsetY = applyArithmetic(y.op, state.offsetY, -y.value * scale)
        state.isAbsoluteX = x.op == .set
        state.isAbsoluteY = y.op == .set
        return true
    }

    private static func parseRotationTag(_ content: String, state: inout TagState) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            state.rotationZ = 0
            return true
        }
        guard let parsed = parseArithmeticValue(text) else { return false }
        state.rotationZ = parsed.op == .set
            ? parsed.value
            : applyArithmetic(parsed.op, state.rotationZ, parsed.value)
        return true
    }

    private static func parseLetterSpacingTag(
        _ content: String, baseLetterSpacing: Double, state: inout TagState
    ) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            state.characterSpacing = nil
            return true
        }
        guard let parsed = parseArithmeticValue(text) else { return false }
        state.characterSpacing = parsed.op == .set
            ? parsed.value
            : applyArithmetic(
                parsed.op, state.characterSpacing ?? baseLetterSpacing, parsed.value
              )
        return true
    }

    private static func parseDisplaySpeedTag(
        _ content: String, cleanPos: Int, timingCollector: inout [TimingTag]
    ) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            timingCollector.append(TimingTag(
                position: cleanPos, type: .displaySpeed, value: -1
            ))
            return true
        }
        guard let parsed = parseArithmeticValue(text) else { return false }
        if parsed.op == .set {
            guard parsed.value >= 0 else { return false }
            timingCollector.append(TimingTag(
                position: cleanPos, type: .displaySpeed, value: parsed.value
            ))
        } else {
            timingCollector.append(TimingTag(
                position: cleanPos, type: .displaySpeed,
                value: parsed.value, arithmeticOperator: parsed.op
            ))
        }
        return true
    }

    private static func parseWaitTag(
        _ content: String, cleanPos: Int, timingCollector: inout [TimingTag]
    ) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("*") {
            guard let factor = parseDotNetDouble(String(text.dropFirst()))
            else { return false }
            // 直前の Wait / Clear タグ位置からの経過文字数に倍率を掛ける。
            var lastPosition = 0
            for tag in timingCollector
            where tag.type == .wait || tag.type == .clear {
                lastPosition = tag.position
            }
            timingCollector.append(TimingTag(
                position: cleanPos, type: .wait,
                value: factor * Double(cleanPos - lastPosition)
            ))
            return true
        }
        guard let seconds = parseDotNetDouble(text) else { return false }
        timingCollector.append(TimingTag(
            position: cleanPos, type: .wait, value: seconds
        ))
        return true
    }

    private static func parseClearTag(
        _ content: String, cleanPos: Int, timingCollector: inout [TimingTag]
    ) -> Bool {
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            timingCollector.append(TimingTag(
                position: cleanPos, type: .clear, value: 0
            ))
            return true
        }
        guard let delay = parseDotNetDouble(text) else { return false }
        timingCollector.append(TimingTag(
            position: cleanPos, type: .clear, value: delay
        ))
        return true
    }

    // MARK: - ルビタグ

    /// `<rb ...>` の中身を解析する。カンマ区切りは `\,` のエスケープを
    /// 尊重し、要素内の `\,` は後でカンマへ戻す。
    private static func parseRubyTag(_ content: String) -> PendingRuby? {
        let parts = splitByUnescapedComma(content)
        guard parts.count >= 2 else { return nil }
        func element(_ index: Int) -> String? {
            guard index < parts.count else { return nil }
            return parts[index]
        }
        func unescaped(_ raw: String) -> String {
            raw.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\,", with: ",")
        }
        let rawBaseLength = parts[0].unicodeScalars.count
        let rawRubyLength = parts[1].unicodeScalars.count
        let baseText = unescaped(parts[0])
        let rubyText = unescaped(parts[1])
        var fontSizePercent = 50.0
        if let raw = element(2) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                guard let parsed = parseArithmeticValue(text) else { return nil }
                fontSizePercent = parsed.op == .set
                    ? parsed.value
                    : applyArithmetic(parsed.op, 50, parsed.value)
            }
        }
        var offsetX = 0.0
        if let raw = element(3) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                guard let value = parseDotNetDouble(text) else { return nil }
                offsetX = value
            }
        }
        var offsetY = 0.0
        if let raw = element(4) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                guard let value = parseDotNetDouble(text) else { return nil }
                offsetY = value
            }
        }
        var font: String? = nil
        if let raw = element(5) {
            let text = unescaped(raw)
            if !text.isEmpty { font = text }
        }
        var bold: Bool? = nil
        var italic: Bool? = nil
        if let raw = element(6) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                let upper = text.uppercased()
                bold = upper.contains("B")
                italic = upper.contains("I")
            }
        }
        var foreground: Color? = nil
        if let raw = element(7) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                guard let color = parseColor(text) else { return nil }
                foreground = color
            }
        }
        var decorationColor: Color? = nil
        if let raw = element(8) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                guard let color = parseColor(text) else { return nil }
                decorationColor = color
            }
        }
        guard !baseText.isEmpty, !rubyText.isEmpty else { return nil }
        return PendingRuby(
            baseText: baseText,
            baseTextLength: baseText.unicodeScalars.count,
            rawBaseLength: rawBaseLength,
            rubyText: rubyText,
            rawRubyLength: rawRubyLength,
            fontSizePercent: fontSizePercent,
            offsetX: offsetX, offsetY: offsetY,
            font: font, bold: bold, italic: italic,
            foreground: foreground, decorationColor: decorationColor
        )
    }

    /// `\,` を区切りとして数えないカンマ分割。要素にはエスケープが
    /// 残ったまま入る（本家の `SplitByUnescapedComma`）。
    private static func splitByUnescapedComma(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previousWasBackslash = false
        for character in text {
            if character == "\\", !previousWasBackslash {
                previousWasBackslash = true
                current.append(character)
            } else if character == ",", !previousWasBackslash {
                parts.append(current)
                current = ""
                previousWasBackslash = false
            } else {
                current.append(character)
                previousWasBackslash = false
            }
        }
        parts.append(current)
        return parts
    }

    // MARK: - 既存装飾の調整

    /// タグの除去に合わせて既存装飾の範囲を詰める。本家
    /// `AdjustExistingDecorations`。
    private static func adjustExistingDecorations(
        _ decorations: inout [TextDecoration],
        removedAt: Int, removedLength: Int
    ) {
        let removedEnd = removedAt + removedLength
        for index in decorations.indices where !decorations[index].isLineBreak {
            var decoration = decorations[index]
            let start = decoration.start
            let end = decoration.start + decoration.length
            if end <= removedAt { continue }
            if start >= removedEnd {
                decoration.start = start - removedLength
            } else if start >= removedAt {
                decoration.length = max(0, decoration.length - (removedEnd - start))
                decoration.start = removedAt
            } else {
                decoration.length = max(
                    0, decoration.length - (min(end, removedEnd) - removedAt)
                )
            }
            decorations[index] = decoration
        }
    }

    /// ルビタグの除去に合わせた調整。タグ内の親文字部分はクリーン側の
    /// 親文字へ対応づけ、それ以外は詰める。本家
    /// `AdjustExistingDecorationsForRuby`。
    // swiftlint:disable:next function_parameter_count
    private static func adjustExistingDecorationsForRuby(
        _ decorations: inout [TextDecoration],
        tagStartAdjusted: Int, tagLength: Int,
        baseTextOffsetInTag: Int, rawBaseTextLength: Int,
        baseTextCleanStart: Int, baseTextCleanLength: Int
    ) {
        let tagEnd = tagStartAdjusted + tagLength
        let baseStartInRaw = tagStartAdjusted + baseTextOffsetInTag
        let baseEndInRaw = baseStartInRaw + rawBaseTextLength
        func mapPosition(_ position: Int) -> Int {
            if position <= tagStartAdjusted { return position }
            if position >= tagEnd { return position - (tagLength - baseTextCleanLength) }
            if position <= baseStartInRaw { return baseTextCleanStart }
            if position >= baseEndInRaw { return baseTextCleanStart + baseTextCleanLength }
            let ratio = Double(position - baseStartInRaw)
                / Double(max(1, rawBaseTextLength))
            return baseTextCleanStart
                + Int((Double(baseTextCleanLength) * ratio).rounded(.down))
        }
        for index in decorations.indices where !decorations[index].isLineBreak {
            var decoration = decorations[index]
            let start = decoration.start
            let end = decoration.start + decoration.length
            if end <= tagStartAdjusted || start >= tagEnd { continue }
            let newStart = mapPosition(start)
            let newEnd = mapPosition(end)
            if start >= tagStartAdjusted, start < baseStartInRaw {
                decoration.start = newStart
                decoration.length = max(0, newEnd - newStart)
            } else if end > baseEndInRaw, end <= tagEnd {
                decoration.start = newStart
                decoration.length = max(0, newEnd - newStart)
            } else if start < tagStartAdjusted {
                decoration.length = max(
                    0, decoration.length - (tagLength - baseTextCleanLength)
                )
            } else {
                decoration.start = newStart
                decoration.length = max(0, newEnd - newStart)
            }
            decorations[index] = decoration
        }
    }

    /// ルビ文字列の範囲にかかる既存装飾を、ルビ側の装飾として切り出す。
    /// 本家 `ExtractRubyTextDecorations`。
    private static func extractRubyTextDecorations(
        _ decorations: [TextDecoration],
        rubyRawStartAdjusted: Int, rawRubyLength: Int, rubyCleanLength: Int
    ) -> [TextDecoration] {
        let rubyEnd = rubyRawStartAdjusted + rawRubyLength
        var result: [TextDecoration] = []
        for decoration in decorations where !decoration.isLineBreak {
            let start = decoration.start
            let end = decoration.start + decoration.length
            let overlapStart = max(start, rubyRawStartAdjusted)
            let overlapEnd = min(end, rubyEnd)
            guard overlapEnd > overlapStart else { continue }
            let ratio = rawRubyLength > 0
                ? Double(rubyCleanLength) / Double(rawRubyLength) : 1
            var copy = decoration
            copy.start = Int((Double(overlapStart - rubyRawStartAdjusted) * ratio)
                .rounded(.down))
            copy.length = max(
                1,
                Int((Double(overlapEnd - overlapStart) * ratio).rounded(.down))
            )
            copy.isLineBreak = false
            result.append(copy)
        }
        return result
    }

    // MARK: - 装飾の統合

    private static func mergeDecorations(
        existing: [TextDecoration], tagInfos: [SegmentInfo], baseFontSize: Double
    ) -> [TextDecoration] {
        if tagInfos.isEmpty { return existing }
        if existing.isEmpty {
            return tagInfos.compactMap { info in
                guard let decoration = tagInfoToDecoration(
                    info, start: info.start, length: info.length,
                    baseFontSize: baseFontSize
                ), decoration.hasDecoration else { return nil }
                return decoration
            }
        }
        var result: [TextDecoration] = []
        for existingDecoration in existing {
            if existingDecoration.isLineBreak {
                result.append(existingDecoration)
                continue
            }
            var remaining: [(start: Int, length: Int)] = [
                (existingDecoration.start, existingDecoration.length)
            ]
            for tag in tagInfos {
                var next: [(start: Int, length: Int)] = []
                for (start, length) in remaining {
                    let end = start + length
                    let tagStart = tag.start
                    let tagEnd = tag.start + tag.length
                    if end <= tagStart || start >= tagEnd {
                        next.append((start, length))
                        continue
                    }
                    let overlapStart = max(start, tagStart)
                    let overlapEnd = min(end, tagEnd)
                    let merged = mergeProperties(
                        tag, existingDecoration,
                        start: overlapStart, length: overlapEnd - overlapStart,
                        baseFontSize: baseFontSize
                    )
                    if merged.hasDecoration { result.append(merged) }
                    if start < tagStart { next.append((start, tagStart - start)) }
                    if end > tagEnd { next.append((tagEnd, end - tagEnd)) }
                }
                remaining = next
            }
            for (start, length) in remaining where length > 0 {
                var copy = existingDecoration
                copy.start = start
                copy.length = length
                result.append(copy)
            }
        }
        for tag in tagInfos {
            var remaining: [(start: Int, length: Int)] = [(tag.start, tag.length)]
            for existingDecoration in existing where !existingDecoration.isLineBreak {
                var next: [(start: Int, length: Int)] = []
                for (start, length) in remaining {
                    let end = start + length
                    let existingStart = existingDecoration.start
                    let existingEnd = existingStart + existingDecoration.length
                    if end <= existingStart || start >= existingEnd {
                        next.append((start, length))
                        continue
                    }
                    if start < existingStart {
                        next.append((start, existingStart - start))
                    }
                    if end > existingEnd {
                        next.append((existingEnd, end - existingEnd))
                    }
                }
                remaining = next
            }
            for (start, length) in remaining where length > 0 {
                if let decoration = tagInfoToDecoration(
                    tag, start: start, length: length, baseFontSize: baseFontSize
                ), decoration.hasDecoration {
                    result.append(decoration)
                }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    private static func tagInfoToDecoration(
        _ info: SegmentInfo, start: Int, length: Int, baseFontSize: Double
    ) -> TextDecoration? {
        let state = info.state
        guard state.hasActive else { return nil }
        var decoration = TextDecoration(
            start: start, length: length,
            isBold: state.bold ?? false,
            isItalic: state.italic ?? false,
            scale: state.fontSize.map { $0 / baseFontSize } ?? 1,
            font: state.font,
            foreground: state.color,
            isLineBreak: false
        )
        decoration.isStrikethrough = state.strikethrough ?? false
        decoration.isUnderline = state.underline ?? false
        decoration.decorationColor = state.decorationColor
        decoration.offsetX = state.offsetX
        decoration.offsetY = state.offsetY
        decoration.isAbsoluteX = state.isAbsoluteX
        decoration.isAbsoluteY = state.isAbsoluteY
        decoration.rotationZ = state.rotationZ
        decoration.rotationGroupId = info.rotationGroupId
        decoration.positionGroupId = info.positionGroupId
        decoration.characterSpacing = state.characterSpacing
        decoration.styleType = state.styleType
        return decoration
    }

    private static func mergeProperties(
        _ tag: SegmentInfo, _ existing: TextDecoration,
        start: Int, length: Int, baseFontSize: Double
    ) -> TextDecoration {
        let state = tag.state
        var decoration = TextDecoration(
            start: start, length: length,
            isBold: state.bold ?? existing.isBold,
            isItalic: state.italic ?? existing.isItalic,
            scale: state.fontSize.map { $0 / baseFontSize } ?? existing.scale,
            font: state.font ?? existing.font,
            foreground: state.color ?? existing.foreground,
            isLineBreak: false
        )
        decoration.isStrikethrough = state.strikethrough ?? existing.isStrikethrough
        decoration.isUnderline = state.underline ?? existing.isUnderline
        decoration.decorationColor = state.decorationColor ?? existing.decorationColor
        decoration.isAbsoluteX = state.isAbsoluteX || existing.isAbsoluteX
        decoration.isAbsoluteY = state.isAbsoluteY || existing.isAbsoluteY
        decoration.offsetX = state.isAbsoluteX
            ? state.offsetX
            : (state.offsetX != 0 ? state.offsetX : existing.offsetX)
        decoration.offsetY = state.isAbsoluteY
            ? state.offsetY
            : (state.offsetY != 0 ? state.offsetY : existing.offsetY)
        decoration.rotationZ = state.rotationZ != 0
            ? state.rotationZ : existing.rotationZ
        decoration.rotationGroupId = state.rotationZ != 0
            ? tag.rotationGroupId : existing.rotationGroupId
        decoration.positionGroupId =
            (state.offsetX != 0 || state.offsetY != 0
                || state.isAbsoluteX || state.isAbsoluteY)
            ? tag.positionGroupId : existing.positionGroupId
        decoration.characterSpacing = state.characterSpacing ?? existing.characterSpacing
        decoration.styleType = state.styleType ?? existing.styleType
        return decoration
    }

    // MARK: - 文字タイミング

    /// タイミングタグから文字ごとの表示・非表示時刻を計算する。本家
    /// `CalculateCharacterTimings`。タイミングタグが無い場合は nil。
    /// 本家は `hideDirection` 引数を計算に使っていない（同じ挙動にする）。
    /// ランダム表示の乱数列は .NET の `System.Random` と一致しない。
    public static func calculateCharacterTimings(
        textLength: Int,
        timingTags: [TimingTag],
        baseDisplayIntervalMs: Double,
        displayDirection: TypewriterAnimationDirection,
        hideDirection: TypewriterAnimationDirection,
        randomSeed: Int
    ) -> CharacterTimingInfo? {
        guard !timingTags.isEmpty, textLength > 0 else { return nil }

        // Clear の位置で区間を分ける。
        var clearPositions: [Int] = []
        for tag in timingTags where tag.type == .clear {
            if !clearPositions.contains(tag.position) {
                clearPositions.append(tag.position)
            }
        }
        clearPositions.sort()
        var ranges: [(start: Int, length: Int)] = []
        var cursor = 0
        for position in clearPositions {
            if position > cursor {
                ranges.append((cursor, position - cursor))
            }
            cursor = position
        }
        if cursor < textLength {
            ranges.append((cursor, textLength - cursor))
        }
        if ranges.isEmpty {
            ranges.append((0, textLength))
        }

        var tagsByPosition: [Int: [TimingTag]] = [:]
        for tag in timingTags {
            tagsByPosition[tag.position, default: []].append(tag)
        }

        var displayTimes = [Double](repeating: 0, count: textLength)
        var hideTimes = [Double](
            repeating: Double.greatestFiniteMagnitude, count: textLength
        )
        var interval = baseDisplayIntervalMs
        var clock = 0.0
        for index in 0..<textLength {
            if let tags = tagsByPosition[index] {
                for tag in tags {
                    switch tag.type {
                    case .displaySpeed:
                        if tag.arithmeticOperator != .set {
                            let charsPerSecond = interval > 0 ? 1000 / interval : 0
                            let newSpeed = applyArithmetic(
                                tag.arithmeticOperator, charsPerSecond, tag.value
                            )
                            interval = newSpeed > 0 ? 1000 / newSpeed : 0
                        } else if tag.value < 0 {
                            interval = baseDisplayIntervalMs
                        } else {
                            interval = tag.value != 0 ? 1000 / tag.value : 0
                        }
                    case .wait:
                        clock += tag.value * 1000
                    case .clear:
                        let hideAt = clock + tag.value * 1000
                        for prior in 0..<index {
                            hideTimes[prior] = min(hideTimes[prior], hideAt)
                        }
                        clock = hideAt
                    }
                }
            }
            displayTimes[index] = clock
            clock += interval
        }

        // 区間ごとに表示順を並べ替える。
        var permuted = displayTimes
        for range in ranges where range.length > 0 {
            let slice = Array(displayTimes[range.start..<(range.start + range.length)])
            var order = Array(0..<range.length)
            switch displayDirection {
            case .fromLast:
                order = Array((0..<range.length).reversed())
            case .random:
                shuffle(&order, seed: randomSeed + range.start)
            case .fromFirst, .unknown(_):
                break
            }
            for offset in 0..<range.length {
                permuted[range.start + offset] = slice[order[offset]]
            }
        }

        var sections: [CharacterTimingSection] = []
        for range in ranges where range.length > 0 {
            var minDisplay = Double.greatestFiniteMagnitude
            var minHide = Double.greatestFiniteMagnitude
            for index in range.start..<(range.start + range.length) {
                minDisplay = min(minDisplay, permuted[index])
                minHide = min(minHide, hideTimes[index])
            }
            sections.append(CharacterTimingSection(
                start: range.start, length: range.length,
                displayStartMs: minDisplay, hideTimeMs: minHide
            ))
        }
        return CharacterTimingInfo(
            displayTimesMs: permuted, hideTimesMs: hideTimes, sections: sections
        )
    }

    /// 決定的な Fisher–Yates シャッフル（SplitMix64）。
    private static func shuffle(_ array: inout [Int], seed: Int) {
        guard array.count > 1 else { return }
        var state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15
        func nextRandom() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
        var index = array.count - 1
        while index > 0 {
            let swapIndex = Int(nextRandom() % UInt64(index + 1))
            array.swapAt(index, swapIndex)
            index -= 1
        }
    }

    // MARK: - 区間フィルタ

    /// 指定時刻に表示されていない区間をテキストから取り除き、装飾・
    /// ルビ・タイミングを新しい位置へ写し直す。本家
    /// `FilterActiveSections`。タイミング情報が無い場合は入力を
    /// そのまま返す。
    public static func filterActiveSections(
        text: String,
        fullDecorations: [TextDecoration],
        fullTiming: CharacterTimingInfo?,
        fullRubyInfos: [RubyInfo],
        currentTimeMs: Double
    ) -> (text: String, decorations: [TextDecoration],
          timing: CharacterTimingInfo?, rubyInfos: [RubyInfo]) {
        guard let fullTiming else {
            return (text, fullDecorations, nil, fullRubyInfos)
        }
        let runes = Array(text.unicodeScalars)
        let infinity = Double.greatestFiniteMagnitude
        func isActive(_ section: CharacterTimingSection) -> Bool {
            currentTimeMs >= section.displayStartMs
                && (section.hideTimeMs >= infinity || currentTimeMs < section.hideTimeMs)
        }
        if fullTiming.sections.allSatisfy(isActive) {
            return (text, fullDecorations, fullTiming, fullRubyInfos)
        }

        // 残る文字の旧位置→新位置の対応を作る。
        var indexMap = [Int](repeating: -1, count: runes.count)
        var newRunes: [Unicode.Scalar] = []
        var droppedPrevious = false
        for section in fullTiming.sections {
            let start = max(0, section.start)
            let end = min(runes.count, section.start + section.length)
            guard end > start else { continue }
            if !isActive(section) {
                droppedPrevious = true
                continue
            }
            var effectiveStart = start
            if droppedPrevious {
                // 直前の区間が落ちた場合、次の区間の先頭改行を落とす。
                if effectiveStart + 1 < end,
                   runes[effectiveStart] == "\r", runes[effectiveStart + 1] == "\n" {
                    effectiveStart += 2
                } else if runes[effectiveStart] == "\n" {
                    effectiveStart += 1
                }
            }
            for index in effectiveStart..<end {
                indexMap[index] = newRunes.count
                newRunes.append(runes[index])
            }
            droppedPrevious = false
        }

        var newDecorations: [TextDecoration] = []
        for decoration in fullDecorations {
            let end = decoration.start + decoration.length
            var segmentStart = -1
            for position in decoration.start...end {
                let isMapped = position < end && position < runes.count
                    && indexMap[position] >= 0
                if isMapped, segmentStart < 0 {
                    segmentStart = position
                } else if !isMapped, segmentStart >= 0 {
                    var copy = decoration
                    copy.start = indexMap[segmentStart]
                    copy.length = indexMap[position - 1] + 1 - indexMap[segmentStart]
                    newDecorations.append(copy)
                    segmentStart = -1
                }
            }
        }

        var oldIndices: [Int] = []
        for index in 0..<runes.count where indexMap[index] >= 0 {
            oldIndices.append(index)
        }
        var newDisplay = [Double](repeating: 0, count: newRunes.count)
        var newHide = [Double](repeating: infinity, count: newRunes.count)
        for newIndex in 0..<newRunes.count {
            let oldIndex = oldIndices[newIndex]
            if oldIndex < fullTiming.displayTimesMs.count {
                newDisplay[newIndex] = fullTiming.displayTimesMs[oldIndex]
            }
            if oldIndex < fullTiming.hideTimesMs.count {
                newHide[newIndex] = fullTiming.hideTimesMs[oldIndex]
            }
        }
        var newSections: [CharacterTimingSection] = []
        for section in fullTiming.sections where isActive(section) {
            let start = max(0, section.start)
            let end = min(runes.count, section.start + section.length)
            var newStart = -1
            var count = 0
            for index in start..<end where indexMap[index] >= 0 {
                if newStart < 0 { newStart = indexMap[index] }
                count += 1
            }
            if count > 0 {
                newSections.append(CharacterTimingSection(
                    start: newStart, length: count,
                    displayStartMs: section.displayStartMs,
                    hideTimeMs: section.hideTimeMs
                ))
            }
        }
        let newTiming = CharacterTimingInfo(
            displayTimesMs: newDisplay, hideTimesMs: newHide, sections: newSections
        )

        var newRubyInfos: [RubyInfo] = []
        for info in fullRubyInfos {
            guard info.start >= 0, info.length > 0,
                  info.start + info.length <= runes.count else { continue }
            let mappedStart = indexMap[info.start]
            let mappedEnd = indexMap[info.start + info.length - 1]
            guard mappedStart >= 0, mappedEnd >= 0 else { continue }
            var copy = info
            copy.start = mappedStart
            copy.length = mappedEnd - mappedStart + 1
            newRubyInfos.append(copy)
        }

        return (
            String(String.UnicodeScalarView(newRunes)),
            newDecorations, newTiming, newRubyInfos
        )
    }
}
