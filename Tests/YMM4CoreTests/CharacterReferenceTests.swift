import XCTest
@testable import YMM4Core

/// MAC-0015: キャラクター参照の保存・解決契約。
///
/// 本家ではアイテムの実行時参照 `Character` は [JsonIgnore] で、保存される
/// のは `CharacterName` のみ（VoiceItem.cs L173–195、TachieItem.cs、
/// TachieFaceItem.cs で確認）。読み込み時は CharacterName から
/// Project.Characters へ再解決する。以前の実装は "Character" オブジェクト
/// 自体を書き出しており、本家ファイルを読むと参照が未解決のままだった。
final class CharacterReferenceTests: XCTestCase {

    /// 本家形式（"Character" キーなし、CharacterName のみ）の最小プロジェクト。
    private func honkeStyleJSON() -> String {
        """
        {"FilePath":null,"SelectedTimelineIndex":0,"Timelines":[{"ID":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","Name":"メイン","VideoInfo":{"FPS":30,"Hz":48000,"Width":640,"Height":360},"Items":[{"$type":"\(VoiceItem.typeName)","Frame":0,"Layer":0,"Length":90,"CharacterName":"テストキャラ","Serif":"セリフです"},{"$type":"\(TachieItem.typeName)","Frame":100,"Layer":1,"Length":90,"CharacterName":"テストキャラ"}],"CurrentFrame":0,"Length":200,"MaxLayer":1}],"Characters":[{"Name":"テストキャラ"}],"CollapsedGroups":[],"LayoutXml":"","ToolStates":null}
        """
    }

    func testHonkeFileResolvesCharacterByName() throws {
        let (project, diagnostics) = try YmmpCodec.decode(honkeStyleJSON())
        XCTAssertEqual(diagnostics.skippedItems.count, 0)
        let character = try XCTUnwrap(project.characters.first)
        XCTAssertEqual(character.name, "テストキャラ")
        let items = try XCTUnwrap(project.timelines.first).items
        let voice = try XCTUnwrap(items.compactMap { $0 as? VoiceItem }.first)
        let tachie = try XCTUnwrap(items.compactMap { $0 as? TachieItem }.first)
        // 参照は Project.Characters の同一インスタンスへ解決される。
        XCTAssertTrue(voice.character === character)
        XCTAssertTrue(tachie.character === character)
        XCTAssertEqual(voice.characterName, "テストキャラ")
        XCTAssertEqual(tachie.characterName, "テストキャラ")
    }

    func testSaveDoesNotWriteCharacterObject() throws {
        let (project, _) = try YmmpCodec.decode(honkeStyleJSON())
        let encoded = YmmpCodec.encode(project)
        // アイテム側に "Character" オブジェクトキーが存在しないこと
        // （ルートの "Characters" は別物で、こちらは残る）。
        XCTAssertFalse(encoded.contains("\"Character\":"))
        XCTAssertTrue(encoded.contains("\"Characters\":"))
        XCTAssertTrue(encoded.contains("\"CharacterName\":\"テストキャラ\""))
    }

    func testHonkeRoundTripReachesFixedPoint() throws {
        let (project, _) = try YmmpCodec.decode(honkeStyleJSON())
        let first = YmmpCodec.encode(project)
        let (reloaded, _) = try YmmpCodec.decode(first)
        // 再読込でも参照が名前解決され、実効値の入力が保たれる。
        let voice = try XCTUnwrap(
            reloaded.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertTrue(voice.character === reloaded.characters.first)
        XCTAssertEqual(YmmpCodec.encode(reloaded), first)
    }

    func testLegacyEmbeddedCharacterStillLoadsAndNormalizes() throws {
        // 旧形式（"Character" オブジェクトを埋め込んだ自前保存ファイル）も
        // 読み込め、保存時に本家形式へ正規化される。
        var json = honkeStyleJSON()
        json = json.replacingOccurrences(
            of: "\"CharacterName\":\"テストキャラ\",\"Serif\"",
            with: "\"Character\":{\"Name\":\"テストキャラ\"},\"CharacterName\":\"テストキャラ\",\"Serif\""
        )
        let (project, _) = try YmmpCodec.decode(json)
        let voice = try XCTUnwrap(
            project.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertNotNil(voice.character)
        let encoded = YmmpCodec.encode(project)
        XCTAssertFalse(encoded.contains("\"Character\":"))
        XCTAssertTrue(encoded.contains("\"CharacterName\":\"テストキャラ\""))
    }
}
