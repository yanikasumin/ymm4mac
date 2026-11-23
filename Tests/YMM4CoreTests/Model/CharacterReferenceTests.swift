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

    func testTachieFaceItemResolvesAndSavesByName() throws {
        // TachieFaceItem も同じ契約: CharacterName から解決され、
        // 保存は CharacterName のみ（R15-03 で追加）。
        let json = """
        {"FilePath":null,"SelectedTimelineIndex":0,"Timelines":[{"ID":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","Name":"メイン","VideoInfo":{"FPS":30,"Hz":48000,"Width":640,"Height":360},"Items":[{"$type":"\(TachieFaceItem.typeName)","Frame":0,"Layer":0,"Length":90,"CharacterName":"テストキャラ"}],"CurrentFrame":0,"Length":200,"MaxLayer":1}],"Characters":[{"Name":"テストキャラ"}],"CollapsedGroups":[],"LayoutXml":"","ToolStates":null}
        """
        let (project, diagnostics) = try YmmpCodec.decode(json)
        XCTAssertEqual(diagnostics.skippedItems.count, 0)
        let character = try XCTUnwrap(project.characters.first)
        let face = try XCTUnwrap(
            project.timelines.first?.items.compactMap { $0 as? TachieFaceItem }.first
        )
        XCTAssertTrue(face.character === character)
        XCTAssertEqual(face.characterName, "テストキャラ")
        let encoded = YmmpCodec.encode(project)
        XCTAssertFalse(encoded.contains("\"Character\":"))
        XCTAssertTrue(encoded.contains("\"CharacterName\":\"テストキャラ\""))
        // 再読込でも名前解決が保たれる。
        let (reloaded, _) = try YmmpCodec.decode(encoded)
        let reloadedFace = try XCTUnwrap(
            reloaded.timelines.first?.items.compactMap { $0 as? TachieFaceItem }.first
        )
        XCTAssertTrue(reloadedFace.character === reloaded.characters.first)
    }

    func testLegacyEmbeddedNameYieldsToResolvedCharacter() throws {
        // 旧形式で埋込 Character の Name が CharacterName と異なる場合、
        // 読み込み完了時の名前解決（CharacterName 側）が優先され、
        // 埋込名は破棄される。保存名も解決先の名前になる（R15-03）。
        var json = honkeStyleJSON()
        json = json.replacingOccurrences(
            of: "\"CharacterName\":\"テストキャラ\",\"Serif\"",
            with: "\"Character\":{\"Name\":\"埋込名\"},\"CharacterName\":\"テストキャラ\",\"Serif\""
        )
        let (project, _) = try YmmpCodec.decode(json)
        let character = try XCTUnwrap(project.characters.first)
        let voice = try XCTUnwrap(
            project.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertTrue(voice.character === character)
        XCTAssertEqual(voice.character?.name, "テストキャラ")
        let encoded = YmmpCodec.encode(project)
        XCTAssertTrue(encoded.contains("\"CharacterName\":\"テストキャラ\""))
        XCTAssertFalse(encoded.contains("埋込名"))
    }

    /// 複製（cloned）は全フィールドを保持した独立インスタンスを返す
    /// （FE-UNIT6: キャラクター編集画面の「複製」の土台）。
    func testClonedCharacterIsIndependentCopy() {
        let original = Character()
        original.name = "元キャラ"
        original.groupName = "グループ"
        original.layer = 3
        original.remark = "備考"
        original.voice = VoiceDescription(api: "エンジン", arg: "話者1")
        original.volume.setFirstValue(75)
        original.additionalFields = [(key: "UnknownKey", value: .string("保持値"))]

        let copy = original.cloned()
        XCTAssertFalse(copy === original)
        XCTAssertEqual(copy.name, "元キャラ")
        XCTAssertEqual(copy.groupName, "グループ")
        XCTAssertEqual(copy.layer, 3)
        XCTAssertEqual(copy.remark, "備考")
        XCTAssertEqual(copy.voice, VoiceDescription(api: "エンジン", arg: "話者1"))
        XCTAssertEqual(copy.volume.firstValue, 75)
        XCTAssertEqual(copy.additionalFields.count, 1)
        XCTAssertEqual(copy.additionalFields.first?.key, "UnknownKey")

        // 書き出し結果が元と同一になる（往復で欠落しない）。
        XCTAssertEqual(
            copy.encodeToJSONValue().serialized(),
            original.encodeToJSONValue().serialized()
        )

        // 複製側の変更が元へ漏れない（アニメーションも独立）。
        copy.name = "複製側"
        copy.volume.setFirstValue(10)
        XCTAssertEqual(original.name, "元キャラ")
        XCTAssertEqual(original.volume.firstValue, 75)
    }

    func testLegacyEmbeddedCharacterSurvivesWhenNameUnresolved() throws {
        // CharacterName がプロジェクトのキャラクターに一致しない場合、
        // 埋込 Character（分離インスタンス）が残り、保存時の
        // CharacterName は本家 getter 規則（Character?.Name ??
        // characterName）どおり埋込名へ追随する（R15-03）。
        var json = honkeStyleJSON()
        json = json.replacingOccurrences(
            of: "\"CharacterName\":\"テストキャラ\",\"Serif\"",
            with: "\"Character\":{\"Name\":\"埋込名\"},\"CharacterName\":\"未登録名\",\"Serif\""
        )
        let (project, _) = try YmmpCodec.decode(json)
        let voice = try XCTUnwrap(
            project.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertNotNil(voice.character)
        XCTAssertFalse(voice.character === project.characters.first)
        XCTAssertEqual(voice.character?.name, "埋込名")
        // 保持している名前文字列自体は書き換わらない。
        XCTAssertEqual(voice.characterName, "未登録名")
        let encoded = YmmpCodec.encode(project)
        XCTAssertTrue(encoded.contains("\"CharacterName\":\"埋込名\""))
    }

    // MARK: - FE-R39-133-01 / 03: 編集後の参照整合

    /// 未解決の保持名を持つ3型のアイテムだけが入ったプロジェクト。
    private func projectWithUnresolvedItems(
        name: String
    ) -> (project: Project, voice: VoiceItem, tachie: TachieItem, face: TachieFaceItem) {
        let project = Project()
        let timeline = Timeline()
        let voice = VoiceItem()
        voice.characterName = name
        let tachie = TachieItem()
        tachie.characterName = name
        let face = TachieFaceItem()
        face.characterName = name
        timeline.items = [voice, tachie, face]
        project.timelines = [timeline]
        return (project, voice, tachie, face)
    }

    func testReresolveBindsUnresolvedItemsAfterRegistration() throws {
        // 未解決名「後から登録」を保持するアイテムがある状態で同名
        // キャラクターを登録すると、再解決で即座に結び付き、
        // 保存・再読込後の状態と一致する（FE-R39-133-03）。
        let (project, voice, tachie, face) =
            projectWithUnresolvedItems(name: "後から登録")
        let character = Character()
        character.name = "後から登録"
        project.characters.append(character)
        project.reresolveUnresolvedCharacterReferences()
        XCTAssertTrue(voice.character === character)
        XCTAssertTrue(tachie.character === character)
        XCTAssertTrue(face.character === character)

        let (reloaded, _) = try YmmpCodec.decode(YmmpCodec.encode(project))
        let reloadedCharacter = try XCTUnwrap(reloaded.characters.first)
        let items = try XCTUnwrap(reloaded.timelines.first).items
        XCTAssertTrue(
            items.compactMap { $0 as? VoiceItem }.first?.character === reloadedCharacter
        )
        XCTAssertTrue(
            items.compactMap { $0 as? TachieItem }.first?.character === reloadedCharacter
        )
        XCTAssertTrue(
            items.compactMap { $0 as? TachieFaceItem }.first?.character === reloadedCharacter
        )
    }

    func testRemoveFirstOfDuplicatedNamesMatchesReload() throws {
        // 読み込み由来の同名データで先頭個体を削除すると、参照は
        // 残存個体へ即座に再接続され、保存・再読込後と一致する
        // （FE-R39-133-01）。
        let json = """
        {"FilePath":null,"SelectedTimelineIndex":0,"Timelines":[{"ID":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","Name":"メイン","VideoInfo":{"FPS":30,"Hz":48000,"Width":640,"Height":360},"Items":[{"$type":"\(VoiceItem.typeName)","Frame":0,"Layer":0,"Length":90,"CharacterName":"重複名","Serif":"セリフです"}],"CurrentFrame":0,"Length":200,"MaxLayer":1}],"Characters":[{"Name":"重複名","Remark":"先頭"},{"Name":"重複名","Remark":"2番目"}],"CollapsedGroups":[],"LayoutXml":"","ToolStates":null}
        """
        let (project, _) = try YmmpCodec.decode(json)
        XCTAssertEqual(project.characters.count, 2)
        let first = project.characters[0]
        let second = project.characters[1]
        let voice = try XCTUnwrap(
            project.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        // 読み込みは先頭一致。
        XCTAssertTrue(voice.character === first)

        project.removeCharacter(first)
        XCTAssertEqual(project.characters.count, 1)
        XCTAssertTrue(project.characters.first === second)
        // 切り離された参照は、同名の残存個体へ即時に再接続される。
        XCTAssertTrue(voice.character === second)
        XCTAssertEqual(voice.characterName, "重複名")

        // 保存・再読込後も同じ個体（備考「2番目」）へ解決される。
        let (reloaded, _) = try YmmpCodec.decode(YmmpCodec.encode(project))
        let reloadedVoice = try XCTUnwrap(
            reloaded.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertTrue(reloadedVoice.character === reloaded.characters.first)
        XCTAssertEqual(reloadedVoice.character?.remark, "2番目")
    }

    func testRemoveOnlyCharacterLeavesUnresolvedNamePreserved() throws {
        // 同名の残存個体が無い削除では、参照は外れて名前だけが残り、
        // 保存・再読込後もその状態が保たれる（FE-R39-133-01）。
        let (project, _) = try YmmpCodec.decode(honkeStyleJSON())
        let character = try XCTUnwrap(project.characters.first)
        project.removeCharacter(character)
        XCTAssertTrue(project.characters.isEmpty)
        let voice = try XCTUnwrap(
            project.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertNil(voice.character)
        XCTAssertEqual(voice.characterName, "テストキャラ")

        let (reloaded, _) = try YmmpCodec.decode(YmmpCodec.encode(project))
        let reloadedVoice = try XCTUnwrap(
            reloaded.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertNil(reloadedVoice.character)
        XCTAssertEqual(reloadedVoice.characterName, "テストキャラ")
    }

    func testReresolveDoesNotRebindResolvedReference() throws {
        // 一覧のインスタンスへ解決済みの参照は、再解決で名前一致だけ
        // を理由に付け替えない（FE-R39-133-03 の条件）。
        let (project, voice, _, _) = projectWithUnresolvedItems(name: "同名")
        let first = Character()
        first.name = "同名"
        let second = Character()
        second.name = "同名"
        project.characters = [first, second]
        // ピッカーで2番目を選んだ状態（解決済み）。
        voice.character = second
        project.reresolveUnresolvedCharacterReferences()
        XCTAssertTrue(voice.character === second)
    }

    func testReresolveKeepsDetachedInstanceWhileNameUnmatched() throws {
        // 一覧に無いインスタンス（埋め込み複製）を指す参照は、保持名が
        // 一覧に一致しない間は読み込み規則どおり残り、一致する
        // キャラクターが登録されるとそちらへ寄る。
        let (project, voice, _, _) = projectWithUnresolvedItems(name: "未登録名")
        let detached = Character()
        detached.name = "埋込名"
        voice.character = detached
        project.reresolveUnresolvedCharacterReferences()
        XCTAssertTrue(voice.character === detached)

        let registered = Character()
        registered.name = "未登録名"
        project.characters.append(registered)
        project.reresolveUnresolvedCharacterReferences()
        XCTAssertTrue(voice.character === registered)
    }

    func testRenameAndReresolveMatchesReload() throws {
        // 改名: 解決済みアイテムはインスタンス経由で追随し、改名後の
        // 名前を保持していた未解決アイテムは再解決で結び付く。
        let project = Project()
        let timeline = Timeline()
        let character = Character()
        character.name = "旧名"
        project.characters = [character]
        let resolved = VoiceItem()
        resolved.characterName = "旧名"
        resolved.character = character
        let unresolved = VoiceItem()
        unresolved.characterName = "新名"
        timeline.items = [resolved, unresolved]
        project.timelines = [timeline]

        character.name = "新名"
        project.reresolveUnresolvedCharacterReferences()
        XCTAssertTrue(resolved.character === character)
        XCTAssertTrue(unresolved.character === character)

        let encoded = YmmpCodec.encode(project)
        XCTAssertTrue(encoded.contains("\"CharacterName\":\"新名\""))
        XCTAssertFalse(encoded.contains("旧名"))
        let (reloaded, _) = try YmmpCodec.decode(encoded)
        let reloadedCharacter = try XCTUnwrap(reloaded.characters.first)
        let voices = try XCTUnwrap(reloaded.timelines.first).items
            .compactMap { $0 as? VoiceItem }
        XCTAssertEqual(voices.count, 2)
        XCTAssertTrue(voices.allSatisfy { $0.character === reloadedCharacter })
    }

    func testCharacterNameValidation() {
        // 編集時の不変条件: 空名と他キャラクターとの重複を拒否し、
        // 自分自身の現在名は許す（FE-R39-133-01）。
        let project = Project()
        let a = Character()
        a.name = "A"
        let b = Character()
        b.name = "B"
        project.characters = [a, b]
        XCTAssertFalse(project.isUsableCharacterName(""))
        XCTAssertFalse(project.isUsableCharacterName("A"))
        XCTAssertFalse(project.isUsableCharacterName("", excluding: a))
        XCTAssertTrue(project.isUsableCharacterName("A", excluding: a))
        XCTAssertFalse(project.isUsableCharacterName("B", excluding: a))
        XCTAssertTrue(project.isUsableCharacterName("C", excluding: a))
        XCTAssertTrue(project.isUsableCharacterName("C"))
    }
}
