import Foundation

/// テキストの前処理。本家の `TextHelper.ApplyAsterisk` と、読み変換
/// （`KanjiToYomiBase.ConvertAsync`）の辞書適用順を再現する。
///
/// 処理順は本家の描画経路に合わせる: アスタリスク辞書 → 正規化
/// （呼び出し側）→ 制御タグ解析。読み上げ側は単語辞書 → 正規化 →
/// 読み変換本体 → 発音辞書の順で、本体変換は合成音声エンジン側の
/// 責務のため、ここでは辞書適用の部品だけを提供する。
public enum TextPreprocessor {

    /// アスタリスク辞書（伏せ字置換）を適用する。装飾が無い場合は
    /// 辞書順に単純置換し、装飾がある場合は置換で伸びた範囲へ装飾を
    /// 追従させる（本家 `TextHelper.ApplyAsterisk`）。
    public static func applyAsterisk(
        text: String,
        decorations: [TextDecoration],
        wordSets: [WordSet]
    ) -> (text: String, decorations: [TextDecoration]) {
        let enabled = wordSets.filter { $0.isEnabled && !$0.from.isEmpty }
        guard !enabled.isEmpty else { return (text, decorations) }
        if decorations.isEmpty {
            var result = text
            for wordSet in enabled {
                result = wordSet.convert(result)
            }
            return (result, decorations)
        }
        var currentText = text
        var currentDecorations = decorations
        for wordSet in enabled {
            (currentText, currentDecorations) = applyAsteriskWordSet(
                wordSet, text: currentText, decorations: currentDecorations
            )
        }
        return (currentText, currentDecorations)
    }

    /// 読み上げ用の単語辞書を適用する。本家はカスタム形式の話者では
    /// セリフへ直接適用し、それ以外は読み変換の中で適用する。どちらも
    /// 実質はこの順序適用になる。
    public static func applyWordSets(_ text: String, wordSets: [WordSet]) -> String {
        var result = text
        for wordSet in wordSets where wordSet.isEnabled && !wordSet.from.isEmpty {
            result = wordSet.convert(result)
        }
        return result
    }

    /// 読み変換の後に発音辞書を適用する。
    public static func applyPronouncingSets(
        _ text: String, pronouncingSets: [WordSet]
    ) -> String {
        applyWordSets(text, wordSets: pronouncingSets)
    }

    // MARK: - 装飾つきアスタリスク置換

    /// 1 件の辞書を装飾つきテキストへ適用する。本家
    /// `TextHelper.ApplyAsterisk` の装飾あり経路の再現: 正規表現の
    /// マッチごとに、置換文字列の長さの差分を使って装飾を調整する。
    /// マッチ開始位置を含む装飾は長さが差分だけ変わり、それより
    /// 後ろの装飾は開始位置が差分だけずれる。
    private static func applyAsteriskWordSet(
        _ wordSet: WordSet, text: String, decorations: [TextDecoration]
    ) -> (text: String, decorations: [TextDecoration]) {
        let regex: NSRegularExpression?
        if wordSet.isRegex {
            regex = wordSet.makeRegex()
        } else {
            regex = try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: wordSet.from),
                options: wordSet.ignoreCase ? [.caseInsensitive] : []
            )
        }
        guard let regex else { return (text, decorations) }

        let runes = Array(text.unicodeScalars)
        let nsText = text as NSString
        // ICU のマッチ位置（UTF-16）→ ルーン位置の対応表。
        var runeIndexByUTF16 = [Int](repeating: 0, count: nsText.length + 1)
        var utf16Cursor = 0
        for (runeIndex, scalar) in runes.enumerated() {
            for _ in 0..<scalar.utf16.count {
                runeIndexByUTF16[utf16Cursor] = runeIndex
                utf16Cursor += 1
            }
        }
        runeIndexByUTF16[nsText.length] = runes.count
        func runePosition(ofUTF16 offset: Int) -> Int {
            runeIndexByUTF16[max(0, min(offset, nsText.length))]
        }

        let matches = regex.matches(
            in: text, range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return (text, decorations) }

        var resultRunes: [Unicode.Scalar] = []
        var resultDecorations = decorations
        var matchOffset = 0
        var searchFrom = 0
        for match in matches {
            let matchStart = runePosition(ofUTF16: match.range.location)
            let matchEnd = runePosition(
                ofUTF16: match.range.location + match.range.length
            )
            guard matchStart >= searchFrom else { continue }
            resultRunes.append(contentsOf: runes[searchFrom..<matchStart])
            // 置換文字列の展開は本家の手作業方式（正規表現のときだけ、
            // $番号 / ${番号} / $& を文字どおり置き換える）。
            var replacement = wordSet.to
            if wordSet.isRegex {
                replacement = expandAsteriskReplacement(
                    wordSet.to, match: match, in: nsText
                )
            }
            let replacementRunes = Array(replacement.unicodeScalars)
            resultRunes.append(contentsOf: replacementRunes)
            let delta = replacementRunes.count - (matchEnd - matchStart)
            let adjustedStart = matchStart + matchOffset
            for index in resultDecorations.indices {
                var decoration = resultDecorations[index]
                if decoration.start <= adjustedStart,
                   adjustedStart < decoration.start + decoration.length {
                    decoration.length += delta
                } else if matchStart < decoration.start + matchOffset {
                    decoration.start += delta
                }
                resultDecorations[index] = decoration
            }
            matchOffset += delta
            searchFrom = matchEnd
        }
        resultRunes.append(contentsOf: runes[searchFrom...])
        return (
            String(String.UnicodeScalarView(resultRunes)),
            cleanupDecorations(resultDecorations)
        )
    }

    /// 本家 ApplyAsterisk の置換文字列展開。グループ番号と $& を
    /// 文字列置換で差し込む（.NET のテンプレート展開とは別方式）。
    /// 名前つきグループの ${名前} は ICU から名前が取れないため
    /// 番号形式のみ対応する。
    private static func expandAsteriskReplacement(
        _ template: String, match: NSTextCheckingResult, in text: NSString
    ) -> String {
        var result = template
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            let value = range.location == NSNotFound
                ? "" : text.substring(with: range)
            result = result.replacingOccurrences(of: "$\(index)", with: value)
            result = result.replacingOccurrences(of: "${\(index)}", with: value)
        }
        result = result.replacingOccurrences(
            of: "$&", with: text.substring(with: match.range)
        )
        return result
    }

    /// 本家の後処理: 長さ 0 以下の装飾を取り除き、隣り合う装飾の
    /// 重なりを後続側を切り詰めて解消する。変化が無くなるまで繰り返す。
    private static func cleanupDecorations(
        _ decorations: [TextDecoration]
    ) -> [TextDecoration] {
        var result = decorations
        var changed = true
        while changed {
            changed = false
            var index = 0
            while index < result.count {
                if result[index].length <= 0 {
                    result.remove(at: index)
                    changed = true
                } else {
                    index += 1
                }
            }
            if result.count > 1 {
                for pair in 0..<(result.count - 1) {
                    let current = result[pair]
                    var next = result[pair + 1]
                    if next.start < current.start + current.length {
                        let overlap = current.start + current.length - next.start
                        next.start += overlap
                        next.length -= overlap
                        result[pair + 1] = next
                        changed = true
                    }
                }
            }
        }
        return result
    }
}
