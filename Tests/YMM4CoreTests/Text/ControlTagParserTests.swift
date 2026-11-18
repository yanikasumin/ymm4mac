import XCTest
@testable import YMM4Core

/// 制御タグ解析（Issue #60）。期待値は本家 ControlTagParser の仕様
/// （逆コンパイル済みコードから確定）に基づく。
final class ControlTagParserTests: XCTestCase {

    private func parse(
        _ text: String, decorations: [TextDecoration] = [],
        baseFontSize: Double = 20
    ) -> ControlTagParser.ParseResult {
        ControlTagParser.parse(
            text: text, existingDecorations: decorations,
            baseFontSize: baseFontSize, baseFont: "TestFont",
            baseBold: false, baseItalic: false
        )
    }

    // MARK: - 色タグ

    func testHexColorTag() {
        let result = parse("AB<#FF0000>CD")
        XCTAssertEqual(result.text, "ABCD")
        XCTAssertEqual(result.decorations.count, 1)
        let decoration = result.decorations[0]
        XCTAssertEqual(decoration.start, 2)
        XCTAssertEqual(decoration.length, 2)
        XCTAssertEqual(
            decoration.foreground,
            Color(alpha: 255, red: 255, green: 0, blue: 0)
        )
    }

    func testNamedColorAndGreyNormalization() {
        let result = parse("<#grey>X")
        XCTAssertEqual(
            result.decorations.first?.foreground,
            Color(alpha: 255, red: 128, green: 128, blue: 128)
        )
        let purple = parse("<#rebeccapurple>X")
        XCTAssertEqual(
            purple.decorations.first?.foreground,
            Color(alpha: 255, red: 102, green: 51, blue: 153)
        )
    }

    func testEightDigitHexIsRRGGBBAA() {
        let result = parse("<#FF000080>X")
        XCTAssertEqual(
            result.decorations.first?.foreground,
            Color(alpha: 128, red: 255, green: 0, blue: 0)
        )
    }

    func testShortHexExpansion() {
        // 3桁は各桁を繰り返す: F00 → FF0000。
        let result = parse("<#F00>X")
        XCTAssertEqual(
            result.decorations.first?.foreground,
            Color(alpha: 255, red: 255, green: 0, blue: 0)
        )
    }

    func testColorReset() {
        let result = parse("A<#FF0000>B<#>C")
        XCTAssertEqual(result.text, "ABC")
        XCTAssertEqual(result.decorations.count, 1)
        XCTAssertEqual(result.decorations[0].start, 1)
        XCTAssertEqual(result.decorations[0].length, 1)
    }

    func testDecorationColorPair() {
        let result = parse("<#FF0000,00FF00>X")
        XCTAssertEqual(
            result.decorations.first?.decorationColor,
            Color(alpha: 255, red: 0, green: 255, blue: 0)
        )
    }

    // MARK: - フォントタグ

    func testFontSizeBecomesScale() {
        let result = parse("<s 40>AB")
        XCTAssertEqual(result.decorations.count, 1)
        XCTAssertEqual(result.decorations[0].scale, 2.0, accuracy: 1e-9)
        XCTAssertEqual(result.decorations[0].start, 0)
        XCTAssertEqual(result.decorations[0].length, 2)
    }

    func testFontSizeArithmetic() {
        let result = parse("<s +=10>AB")
        XCTAssertEqual(result.decorations[0].scale, 1.5, accuracy: 1e-9)
    }

    func testFontTagWithNameAndStyle() {
        let result = parse("<s ,Meiryo,B>X")
        let decoration = result.decorations[0]
        XCTAssertEqual(decoration.font, "Meiryo")
        XCTAssertTrue(decoration.isBold)
        XCTAssertFalse(decoration.isItalic)
    }

    func testFontFamilyTagAndDeltaStyle() {
        let result = parse("<@Yu Gothic>X")
        XCTAssertEqual(result.decorations[0].font, "Yu Gothic")

        let delta = parse("<@+B>X")
        XCTAssertTrue(delta.decorations[0].isBold)
        XCTAssertNil(delta.decorations[0].font)
    }

    func testFontResetKeepsSize() {
        // <s> のリセットはフォントとスタイルだけを戻し、サイズは戻さない。
        let result = parse("<s 40,Meiryo>A<s>B")
        XCTAssertEqual(result.text, "AB")
        let second = result.decorations.first { $0.start == 1 }
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.scale ?? 0, 2.0, accuracy: 1e-9)
        XCTAssertNil(second?.font)
    }

    // MARK: - 位置・回転・字間

    func testPositionTagAbsoluteAndYInverted() {
        let result = parse("<p 10,20>X")
        let decoration = result.decorations[0]
        XCTAssertEqual(decoration.offsetX, 10, accuracy: 1e-9)
        XCTAssertEqual(decoration.offsetY, -20, accuracy: 1e-9)
        XCTAssertTrue(decoration.isAbsoluteX)
        XCTAssertTrue(decoration.isAbsoluteY)
    }

    func testPositionTagSignedIsRelative() {
        let result = parse("<p 10,0>A<p +5,0>B")
        let second = result.decorations.first { $0.start == 1 }
        XCTAssertEqual(second?.offsetX ?? 0, 15, accuracy: 1e-9)
        XCTAssertEqual(second?.isAbsoluteX, false)
    }

    func testProportionalPositionTag() {
        // 基準サイズ 20 の 50% = 10。
        let result = parse("<pp 50,0>X")
        XCTAssertEqual(result.decorations[0].offsetX, 10, accuracy: 1e-9)
        XCTAssertTrue(result.decorations[0].isAbsoluteX)
    }

    func testRotationTag() {
        let result = parse("<rot 45>X")
        XCTAssertEqual(result.decorations[0].rotationZ, 45, accuracy: 1e-9)
    }

    func testLetterSpacingTag() {
        let result = parse("<ls 5>X")
        XCTAssertEqual(result.decorations[0].characterSpacing ?? 0, 5, accuracy: 1e-9)
        let reset = parse("<ls 5>A<ls>B")
        XCTAssertEqual(reset.decorations.count, 1)
        XCTAssertEqual(reset.decorations[0].length, 1)
    }

    func testNewlineResetsInlineOffset() {
        // 改行で進行方向のオフセット値が 0 へ戻る（絶対配置の
        // フラグは残るため、B の区間も装飾として出る）。改行前の
        // 区間は本家どおり改行文字を含む。
        let result = parse("<p 10,0>A\nB")
        XCTAssertEqual(result.decorations.count, 2)
        XCTAssertEqual(result.decorations[0].start, 0)
        XCTAssertEqual(result.decorations[0].length, 2)
        XCTAssertEqual(result.decorations[0].offsetX, 10, accuracy: 1e-9)
        XCTAssertEqual(result.decorations[1].start, 2)
        XCTAssertEqual(result.decorations[1].length, 1)
        XCTAssertEqual(result.decorations[1].offsetX, 0, accuracy: 1e-9)
        XCTAssertTrue(result.decorations[1].isAbsoluteX)
    }

    // MARK: - エスケープと無効タグ

    func testEscapedTagStaysLiteral() {
        let result = parse("A\\<#FF0000>B")
        XCTAssertEqual(result.text, "A<#FF0000>B")
        XCTAssertTrue(result.decorations.isEmpty)
    }

    func testInvalidTagStaysLiteralAndStateRollsBack() {
        let bad = parse("<#ZZZ>X")
        XCTAssertEqual(bad.text, "<#ZZZ>X")
        XCTAssertTrue(bad.decorations.isEmpty)

        let badSize = parse("<s abc>X")
        XCTAssertEqual(badSize.text, "<s abc>X")
        XCTAssertTrue(badSize.decorations.isEmpty)
    }

    func testNonTagAngleBracketsUntouched() {
        let result = parse("a<b>c <x>1")
        XCTAssertEqual(result.text, "a<b>c <x>1")
        XCTAssertTrue(result.decorations.isEmpty)
    }

    // MARK: - ルビ

    func testRubyBasic() {
        let result = parse("<rb 漢字,かんじ>です")
        XCTAssertEqual(result.text, "漢字です")
        XCTAssertEqual(result.rubyInfos.count, 1)
        let info = result.rubyInfos[0]
        XCTAssertEqual(info.start, 0)
        XCTAssertEqual(info.length, 2)
        XCTAssertEqual(info.rubyText, "かんじ")
        XCTAssertEqual(info.fontSizePercent, 50, accuracy: 1e-9)
    }

    func testRubyPlainTextUsesRubyText() {
        XCTAssertEqual(
            ControlTagParser.plainText("<rb 漢字,かんじ>です"), "かんじです"
        )
        XCTAssertEqual(ControlTagParser.plainText("<#FF0000>通常"), "通常")
    }

    func testRubySizeAndEscapedComma() {
        let sized = parse("<rb 漢字,かんじ,100>")
        XCTAssertEqual(sized.rubyInfos[0].fontSizePercent, 100, accuracy: 1e-9)

        let escaped = parse("<rb a\\,b,c>")
        XCTAssertEqual(escaped.text, "a,b")
        XCTAssertEqual(escaped.rubyInfos[0].rubyText, "c")
    }

    func testRubyInvalidStaysLiteral() {
        let result = parse("<rb 漢字>X")
        XCTAssertEqual(result.text, "<rb 漢字>X")
        XCTAssertTrue(result.rubyInfos.isEmpty)
    }

    // MARK: - 既存装飾との統合

    func testExistingDecorationAdjustedAndMerged() {
        // 生テキスト全体を覆う既存装飾は、タグ除去に合わせて詰まり、
        // タグの色と重なる部分では色が統合される。
        let raw = "X<#FF0000>Y"
        let existing = [TextDecoration(
            start: 0, length: raw.unicodeScalars.count, isBold: true
        )]
        let result = parse(raw, decorations: existing)
        XCTAssertEqual(result.text, "XY")
        XCTAssertEqual(result.decorations.count, 2)
        XCTAssertEqual(result.decorations[0].start, 0)
        XCTAssertEqual(result.decorations[0].length, 1)
        XCTAssertTrue(result.decorations[0].isBold)
        XCTAssertNil(result.decorations[0].foreground)
        XCTAssertEqual(result.decorations[1].start, 1)
        XCTAssertTrue(result.decorations[1].isBold)
        XCTAssertEqual(
            result.decorations[1].foreground,
            Color(alpha: 255, red: 255, green: 0, blue: 0)
        )
    }

    // MARK: - タイミング

    private func timings(
        _ text: String, baseInterval: Double = 100
    ) -> CharacterTimingInfo? {
        let parsed = parse(text)
        return ControlTagParser.calculateCharacterTimings(
            textLength: parsed.text.unicodeScalars.count,
            timingTags: parsed.timingTags,
            baseDisplayIntervalMs: baseInterval,
            displayDirection: .fromFirst, hideDirection: .fromFirst,
            randomSeed: 0
        )
    }

    func testNoTimingTagsReturnsNil() {
        XCTAssertNil(timings("ABC"))
    }

    func testDisplaySpeedTag() {
        let timing = timings("AB<r 2>CD")
        XCTAssertNotNil(timing)
        // 基準 100ms/字 → 2字/秒 = 500ms/字へ切り替わる。
        XCTAssertEqual(timing?.displayTimesMs ?? [], [0, 100, 200, 700])
    }

    func testDisplaySpeedReset() {
        let timing = timings("A<r 2>B<r>C")
        XCTAssertEqual(timing?.displayTimesMs ?? [], [0, 100, 600])
    }

    func testWaitTag() {
        let timing = timings("A<w 1>B")
        XCTAssertEqual(timing?.displayTimesMs ?? [], [0, 1100])
    }

    func testWaitFactorTag() {
        // 直前の Wait/Clear 位置（0）から 2 文字分 × 倍率 2 = 4 秒。
        let timing = timings("AB<w*2>C")
        XCTAssertEqual(timing?.displayTimesMs ?? [], [0, 100, 4200])
    }

    func testClearTagSections() {
        let timing = timings("AB<c>CD")
        XCTAssertNotNil(timing)
        XCTAssertEqual(timing?.hideTimesMs[0] ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(timing?.hideTimesMs[1] ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(
            timing?.hideTimesMs[2] ?? 0, Double.greatestFiniteMagnitude
        )
        XCTAssertEqual(timing?.sections.count, 2)
        XCTAssertEqual(timing?.sections[0].hideTimeMs ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(timing?.sections[1].displayStartMs ?? 0, 200, accuracy: 1e-9)
    }

    func testFromLastPermutation() {
        let parsed = parse("AB<r 2>CD")
        let timing = ControlTagParser.calculateCharacterTimings(
            textLength: 4, timingTags: parsed.timingTags,
            baseDisplayIntervalMs: 100,
            displayDirection: .fromLast, hideDirection: .fromFirst,
            randomSeed: 0
        )
        XCTAssertEqual(timing?.displayTimesMs ?? [], [700, 200, 100, 0])
    }

    func testFilterActiveSectionsDropsHiddenSection() {
        let parsed = parse("AB<c>CD")
        let timing = ControlTagParser.calculateCharacterTimings(
            textLength: 4, timingTags: parsed.timingTags,
            baseDisplayIntervalMs: 100,
            displayDirection: .fromFirst, hideDirection: .fromFirst,
            randomSeed: 0
        )
        let filtered = ControlTagParser.filterActiveSections(
            text: parsed.text, fullDecorations: parsed.decorations,
            fullTiming: timing, fullRubyInfos: [], currentTimeMs: 250
        )
        XCTAssertEqual(filtered.text, "CD")
        XCTAssertEqual(filtered.timing?.displayTimesMs ?? [], [200, 300])
    }

    func testFilterDropsLeadingNewlineOfFollowingSection() {
        let parsed = parse("AB<c>\nCD")
        let timing = ControlTagParser.calculateCharacterTimings(
            textLength: parsed.text.unicodeScalars.count,
            timingTags: parsed.timingTags,
            baseDisplayIntervalMs: 100,
            displayDirection: .fromFirst, hideDirection: .fromFirst,
            randomSeed: 0
        )
        let filtered = ControlTagParser.filterActiveSections(
            text: parsed.text, fullDecorations: parsed.decorations,
            fullTiming: timing, fullRubyInfos: [], currentTimeMs: 250
        )
        XCTAssertEqual(filtered.text, "CD")
    }

    func testFilterAllActiveReturnsInput() {
        // クリアが無い単一区間は、全区間が有効な間は入力そのまま。
        let parsed = parse("AB<r 2>CD")
        let timing = ControlTagParser.calculateCharacterTimings(
            textLength: 4, timingTags: parsed.timingTags,
            baseDisplayIntervalMs: 100,
            displayDirection: .fromFirst, hideDirection: .fromFirst,
            randomSeed: 0
        )
        let filtered = ControlTagParser.filterActiveSections(
            text: parsed.text, fullDecorations: parsed.decorations,
            fullTiming: timing, fullRubyInfos: [], currentTimeMs: 0
        )
        XCTAssertEqual(filtered.text, "ABCD")
    }

    func testFilterDropsNotYetDisplayedSection() {
        // クリアで区切られた後段は、表示開始時刻までは落ちる。
        let parsed = parse("AB<c>CD")
        let timing = ControlTagParser.calculateCharacterTimings(
            textLength: 4, timingTags: parsed.timingTags,
            baseDisplayIntervalMs: 100,
            displayDirection: .fromFirst, hideDirection: .fromFirst,
            randomSeed: 0
        )
        let filtered = ControlTagParser.filterActiveSections(
            text: parsed.text, fullDecorations: parsed.decorations,
            fullTiming: timing, fullRubyInfos: [], currentTimeMs: 50
        )
        XCTAssertEqual(filtered.text, "AB")
    }
}
