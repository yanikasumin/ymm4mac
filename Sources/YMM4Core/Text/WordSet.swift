import Foundation

/// ユーザー辞書の置換エントリ1件。本家 `WordSet`（KanjiToYomi）に対応する。
///
/// 置換は `From` → `To` の単純置換、または正規表現置換（`IsRegex`）。
/// 正規表現の置換文字列では本家（.NET）と同じく `$1` 等のグループ参照が
/// 使える。無効な正規表現や置換の失敗時は原文をそのまま返す（本家の
/// 例外時の契約どおり）。
public struct WordSet: Equatable, Sendable {
    public var isEnabled: Bool
    public var from: String
    public var to: String
    public var isRegex: Bool
    public var ignoreCase: Bool
    public var description: String?

    public init(
        from: String, to: String, description: String? = nil,
        isRegex: Bool = false, ignoreCase: Bool = true, isEnabled: Bool = true
    ) {
        self.from = from
        self.to = to
        self.description = description
        self.isRegex = isRegex
        self.ignoreCase = ignoreCase
        self.isEnabled = isEnabled
    }

    /// 本家 `Convert`。この項目の置換をテキストへ適用する。
    public func convert(_ text: String) -> String {
        guard isEnabled, !from.isEmpty, !text.isEmpty else { return text }
        if isRegex {
            guard let regex = makeRegex() else { return text }
            return Self.regexReplace(text, regex: regex, template: to)
        }
        // 本家は OrdinalIgnoreCase（または Ordinal）の全置換。
        return text.replacingOccurrences(
            of: from, with: to,
            options: ignoreCase ? [.caseInsensitive] : []
        )
    }

    /// この項目の正規表現（アスタリスク置換の装飾連動経路と共有する）。
    func makeRegex() -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: from, options: ignoreCase ? [.caseInsensitive] : []
        )
    }

    /// .NET の `Regex.Replace(text, To)` と同じ置換文字列展開で全置換する。
    static func regexReplace(
        _ text: String, regex: NSRegularExpression, template: String
    ) -> String {
        let nsText = text as NSString
        let matches = regex.matches(
            in: text, range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result += nsText.substring(
                    with: NSRange(
                        location: cursor,
                        length: match.range.location - cursor
                    )
                )
            }
            result += expandTemplate(template, match: match, in: nsText)
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            result += nsText.substring(
                with: NSRange(location: cursor, length: nsText.length - cursor)
            )
        }
        return result
    }

    /// .NET の置換文字列展開（`Match.Result`）の再現。
    ///
    /// 対応する記法: `$$`（$ そのもの）、`$&`（一致全体）、`$``（一致より前）、
    /// `$'`（一致より後）、`$+`（最後に捕捉したグループ）、`$n` / `${n}`
    /// （番号グループ）。名前付きグループ `${name}` は番号として解釈できる
    /// 場合のみ扱う。無効なグループ番号はリテラルのまま残す。
    static func expandTemplate(
        _ template: String, match: NSTextCheckingResult, in text: NSString
    ) -> String {
        func groupText(_ index: Int) -> String? {
            guard index < match.numberOfRanges else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return "" }
            return text.substring(with: range)
        }
        let chars = Array(template)
        var output = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            guard ch == "$", i + 1 < chars.count else {
                output.append(ch)
                i += 1
                continue
            }
            let next = chars[i + 1]
            switch next {
            case "$":
                output.append("$")
                i += 2
            case "&":
                output += groupText(0) ?? ""
                i += 2
            case "`":
                output += text.substring(
                    with: NSRange(location: 0, length: match.range.location)
                )
                i += 2
            case "'":
                let end = match.range.location + match.range.length
                output += text.substring(
                    with: NSRange(location: end, length: text.length - end)
                )
                i += 2
            case "+":
                var last = ""
                for index in 1..<match.numberOfRanges {
                    let range = match.range(at: index)
                    if range.location != NSNotFound {
                        last = text.substring(with: range)
                    }
                }
                output += last
                i += 2
            case "{":
                var j = i + 2
                var name = ""
                while j < chars.count, chars[j] != "}" {
                    name.append(chars[j])
                    j += 1
                }
                if j < chars.count, let number = Int(name),
                   let value = groupText(number) {
                    output += value
                    i = j + 1
                } else {
                    output.append(ch)
                    i += 1
                }
            default:
                if next.isNumber {
                    // 2桁→1桁の順に有効なグループ番号を探す（.NET の規則）。
                    var consumed = 0
                    if i + 2 < chars.count, chars[i + 2].isNumber,
                       let two = Int(String(chars[(i + 1)...(i + 2)])),
                       two < match.numberOfRanges {
                        output += groupText(two) ?? ""
                        consumed = 3
                    } else if let one = Int(String(next)),
                              one < match.numberOfRanges {
                        output += groupText(one) ?? ""
                        consumed = 2
                    }
                    if consumed > 0 {
                        i += consumed
                    } else {
                        output.append(ch)
                        i += 1
                    }
                } else {
                    output.append(ch)
                    i += 1
                }
            }
        }
        return output
    }
}
