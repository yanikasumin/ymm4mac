import XCTest
@testable import YMM4Core

/// ユーザー辞書とアスタリスク置換（Issue #60）。期待値は本家
/// UserDictionary / WordSet / TextHelper の仕様に基づく。
final class UserDictionaryTests: XCTestCase {

    // MARK: - 既定値と JSON 往復

    func testDefaultCounts() {
        let dictionary = UserDictionary.default
        XCTAssertEqual(dictionary.asteriskWordSets.count, 2)
        XCTAssertEqual(dictionary.wordSets.count, 107)
        XCTAssertEqual(dictionary.pronouncingSets.count, 1)
        // 既定のアスタリスク辞書は全件無効（本家の初期状態）。
        XCTAssertTrue(dictionary.asteriskWordSets.allSatisfy { !$0.isEnabled })
    }

    func testDefaultsSortedByFromLengthDescending() {
        let froms = UserDictionary.default.wordSets.map { $0.from }
        let lengths = froms.map { $0.count }
        XCTAssertEqual(lengths, lengths.sorted(by: >))
    }

    func testJSONRoundTrip() {
        let dictionary = UserDictionary.default
        let parsed = UserDictionary.parse(json: dictionary.serializedJSON())
        XCTAssertEqual(parsed, dictionary)
    }

    func testPartialJSONFallsBackToDefaults() {
        let json = """
        {"WordSets":[{"IsEnabled":true,"From":"a","To":"b","IsRegex":false,"IgnoreCase":true,"Description":null}]}
        """
        let parsed = UserDictionary.parse(json: json)
        XCTAssertEqual(parsed?.wordSets.count, 1)
        XCTAssertEqual(parsed?.wordSets[0].from, "a")
        XCTAssertEqual(
            parsed?.asteriskWordSets.count,
            UserDictionary.default.asteriskWordSets.count
        )
        XCTAssertEqual(
            parsed?.pronouncingSets.count,
            UserDictionary.default.pronouncingSets.count
        )
    }

    // MARK: - WordSet の置換

    func testPlainConvertCaseInsensitive() {
        let wordSet = WordSet(from: "abc", to: "X")
        XCTAssertEqual(wordSet.convert("aBc abc"), "X X")
    }

    func testPlainConvertCaseSensitive() {
        let wordSet = WordSet(from: "abc", to: "X", ignoreCase: false)
        XCTAssertEqual(wordSet.convert("aBc abc"), "aBc X")
    }

    func testRegexConvertWithGroupReference() {
        let wordSet = WordSet(from: "([0-9]+)円", to: "$1えん", isRegex: true)
        XCTAssertEqual(wordSet.convert("100円と50円"), "100えんと50えん")
    }

    func testInvalidRegexReturnsOriginal() {
        let wordSet = WordSet(from: "([", to: "X", isRegex: true)
        XCTAssertEqual(wordSet.convert("対象([テキスト"), "対象([テキスト")
    }

    func testDisabledWordSetDoesNotConvert() {
        let wordSet = WordSet(from: "abc", to: "X", isEnabled: false)
        XCTAssertEqual(wordSet.convert("abc"), "abc")
        // 辞書適用のヘルパも無効な項目を飛ばす。
        XCTAssertEqual(
            TextPreprocessor.applyWordSets("abc", wordSets: [wordSet]), "abc"
        )
    }

    // MARK: - アスタリスク置換

    func testAsteriskWithoutDecorations() {
        let dictionary = [WordSet(from: "秘密", to: "◯◯")]
        let result = TextPreprocessor.applyAsterisk(
            text: "これは秘密です", decorations: [], wordSets: dictionary
        )
        XCTAssertEqual(result.text, "これは◯◯です")
        XCTAssertTrue(result.decorations.isEmpty)
    }

    func testAsteriskDefaultDictionaryIsNoOp() {
        // 既定のアスタリスク辞書は全件無効のため無変換。
        let result = TextPreprocessor.applyAsterisk(
            text: "Twitterとうんち", decorations: [],
            wordSets: UserDictionary.default.asteriskWordSets
        )
        XCTAssertEqual(result.text, "Twitterとうんち")
    }

    func testAsteriskWithDecorationsExtendsCoveringDecoration() {
        // 置換範囲を完全に含む装飾は、置換後の長さへ伸びる。
        let dictionary = [WordSet(from: "秘密", to: "◯◯◯")]
        let decorations = [TextDecoration(start: 2, length: 2, isBold: true)]
        let result = TextPreprocessor.applyAsterisk(
            text: "AB秘密CD", decorations: decorations, wordSets: dictionary
        )
        XCTAssertEqual(result.text, "AB◯◯◯CD")
        XCTAssertEqual(result.decorations.count, 1)
        XCTAssertEqual(result.decorations[0].start, 2)
        XCTAssertEqual(result.decorations[0].length, 3)
    }

    func testAsteriskWithDecorationsShiftsFollowing() {
        // 置換より後ろの装飾は差分だけ移動する。
        let dictionary = [WordSet(from: "秘密", to: "◯")]
        let decorations = [TextDecoration(start: 5, length: 1, isBold: true)]
        let result = TextPreprocessor.applyAsterisk(
            text: "AB秘密CDE", decorations: decorations, wordSets: dictionary
        )
        XCTAssertEqual(result.text, "AB◯CDE")
        XCTAssertEqual(result.decorations[0].start, 4)
        XCTAssertEqual(result.decorations[0].length, 1)
    }

    func testAsteriskRegexTemplateWithDecorations() {
        // マッチ開始位置を含む装飾は、置換後の文字列全体を覆うよう
        // 長さが差分だけ伸びる（本家の規則）。
        let dictionary = [WordSet(from: "([0-9]+)", to: "[$1]", isRegex: true)]
        let decorations = [TextDecoration(start: 1, length: 2, isBold: true)]
        let result = TextPreprocessor.applyAsterisk(
            text: "A12B", decorations: decorations, wordSets: dictionary
        )
        XCTAssertEqual(result.text, "A[12]B")
        XCTAssertEqual(result.decorations[0].start, 1)
        XCTAssertEqual(result.decorations[0].length, 4)
    }

    // MARK: - プロジェクト往復でタグ文字列が失われないこと

    func testYmmpRoundTripPreservesTagTextAndDecorations() throws {
        let text = TextItem()
        text.frame = 0
        text.length = 90
        text.layer = 0
        text.text = "<#FF0000>赤い<rb 漢字,かんじ><r 5>速い"
        text.decorations = [TextDecoration(start: 0, length: 3, isBold: true)]

        let timeline = Timeline()
        timeline.items = [text]
        let project = Project()
        project.timelines = [timeline]

        let encoded = YmmpCodec.encode(project)
        let (loaded, _) = try YmmpCodec.decode(encoded)
        let loadedText = loaded.timelines[0].items.compactMap { $0 as? TextItem }.first
        XCTAssertEqual(loadedText?.text, text.text)
        XCTAssertEqual(loadedText?.decorations.count, 1)
        XCTAssertEqual(loadedText?.decorations[0].isBold, true)
        // 再エンコードでもタグ文字列はそのまま残る。
        let reencoded = YmmpCodec.encode(loaded)
        let (reloaded, _) = try YmmpCodec.decode(reencoded)
        let reloadedText = reloaded.timelines[0].items
            .compactMap { $0 as? TextItem }.first
        XCTAssertEqual(reloadedText?.text, text.text)
    }
}
