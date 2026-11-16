import XCTest
@testable import YMM4Core

final class YmmpCodecTests: XCTestCase {
    // MARK: - 正規化比較のヘルパ

    /// キー順序と数値表記を正規化した JSON 文字列。
    /// 往復テストの「正規化した JSON 同士の差分ゼロ」の判定に使う。
    private func canonical(_ text: String) throws -> String {
        var parser = JSONParser(text: text)
        return canonical(try parser.parse())
    }

    private func canonical(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let flag):
            return flag ? "true" : "false"
        case .numberLiteral(let literal):
            if let integer = Int64(literal) {
                return String(integer)
            }
            return newtonsoftDoubleLiteral(Double(literal) ?? 0)
        case .string(let string):
            return JSONValue.string(string).serialized()
        case .array(let elements):
            return "[" + elements.map { canonical($0) }.joined(separator: ",") + "]"
        case .object(let fields):
            let sorted = fields.sorted { $0.key < $1.key }
            return "{" + sorted.map {
                JSONValue.string($0.key).serialized() + ":" + canonical($0.value)
            }.joined(separator: ",") + "}"
        }
    }

    // MARK: - JSON 基盤

    /// 数値リテラルは原文のまま保持される（往復保全の基盤）。
    func testJSONValuePreservesNumberLiterals() throws {
        let text = "{\"a\":1.50,\"b\":[true,null,\"x\"]}"
        var parser = JSONParser(text: text)
        let value = try parser.parse()
        XCTAssertEqual(value.serialized(), text)
    }

    // MARK: - 往復（固定点）

    /// 複数種のアイテムを含む Project を構築→保存→再読込→再保存し、
    /// 正規化した JSON の差分がゼロであること（P0-16 の固定点パターン）。
    func testRoundTripFixedPoint() throws {
        let project = Project()
        project.filePath = "/tmp/sample.ymmp"
        let character = Character()
        character.name = "テストキャラ"
        character.additionalFields.append((
            key: "Voice",
            value: .object([(key: "SpeakerName", value: .string("speaker"))])
        ))
        project.characters = [character]
        project.collapsedGroups = ["グループ"]
        project.toolStates = [
            (key: "Tool1", value: SerializableToolState(title: "ツール", savedState: "state")),
        ]

        let timeline = Timeline()
        timeline.name = "メイン"
        timeline.videoInfo = VideoInfo(fps: 30, hz: 48_000, width: 640, height: 360)
        timeline.currentFrame = 12

        let text = TextItem()
        text.frame = 0
        text.length = 90
        text.layer = 0
        text.text = "こんにちは、世界"
        text.keyFrames = KeyFrames(frames: [30])
        text.x.animationType = .linear
        text.x.values = [AnimationValue(0), AnimationValue(50), AnimationValue(100)]
        text.videoEffects = [
            PreservedObject(.object([
                (key: "$type", value: .string("YukkuriMovieMaker.Project.Effects.WaveEffect, YukkuriMovieMaker")),
                (key: "IsEnabled", value: .bool(true)),
            ])),
            PreservedObject(.object([
                (key: "$type", value: .string("Some.Plugin.Effect, SomePlugin")),
                (key: "Custom", value: .number(1.5)),
            ])),
        ]

        let audio = AudioItem()
        audio.frame = 100
        audio.length = 60
        audio.layer = 1
        audio.filePath = "/tmp/voice.wav"
        audio.volume.values = [AnimationValue(80)]

        let voice = VoiceItem()
        voice.frame = 200
        voice.length = 120
        voice.layer = 2
        voice.character = character
        voice.characterName = "テストキャラ"
        voice.serif = "セリフです"
        voice.voiceCache = Data([1, 2, 3, 4])

        let shape = ShapeItem()
        shape.frame = 0
        shape.length = 30
        shape.layer = 3

        let transition = TransitionItem()
        transition.frame = 300
        transition.length = 15
        transition.layer = 0
        transition.transitionType = "YukkuriMovieMaker.Transition.PushTransition, YukkuriMovieMaker"

        let group = GroupItem()
        group.frame = 0
        group.length = 400
        group.layer = 4
        group.groupRange = 3

        timeline.items = [text, audio, voice, shape, transition, group]
        timeline.refreshTimelineLengthAndMaxLayer()
        timeline.layerSettings.items = [
            LayerSetting(layer: 1, label: "音声", color: .red, isHidden: false, volume: 80),
        ]
        project.timelines = [timeline]

        let first = YmmpCodec.encode(project)
        let (loaded, diagnostics) = try YmmpCodec.decode(first)
        XCTAssertEqual(diagnostics.skippedItems.count, 0)
        let second = YmmpCodec.encode(loaded)
        // 1回目の読み込みでは本家同様に型移行（WaveEffect のコミュニティ
        // 移行）が $type へ適用されるため、固定点は2回目の往復で判定する
        let (reloaded, _) = try YmmpCodec.decode(second)
        let third = YmmpCodec.encode(reloaded)
        XCTAssertEqual(try canonical(second), try canonical(third))

        // 読み戻した値のスポットチェック
        let loadedTimeline = try XCTUnwrap(loaded.timelines.first)
        XCTAssertEqual(loadedTimeline.items.count, 6)
        let loadedText = try XCTUnwrap(loadedTimeline.items[0] as? TextItem)
        XCTAssertEqual(loadedText.text, "こんにちは、世界")
        XCTAssertEqual(loadedText.keyFrames.frames, [30])
        // 移行先の $type で保持されている
        XCTAssertEqual(
            loadedText.videoEffects[0].typeName,
            "YukkuriMovieMaker.Plugin.Community.Effect.Video.Wave.WaveEffect, YukkuriMovieMaker.Plugin.Community"
        )
        // 未知プラグインのエフェクトはそのまま保持される
        XCTAssertEqual(loadedText.videoEffects[1].typeName, "Some.Plugin.Effect, SomePlugin")
        let loadedVoice = try XCTUnwrap(loadedTimeline.items[2] as? VoiceItem)
        XCTAssertEqual(loadedVoice.serif, "セリフです")
        XCTAssertEqual(loadedVoice.character?.name, "テストキャラ")
        XCTAssertEqual(loadedVoice.voiceCache, Data([1, 2, 3, 4]))
    }

    /// ファイル保存（本家の手順: 一時ファイル→再読込検証→コピー）でも
    /// 往復が保たれる。
    func testSaveAndLoadFile() throws {
        let project = Project()
        let timeline = Timeline()
        timeline.name = "保存テスト"
        let item = TextItem()
        item.text = "保存されるテキスト"
        item.length = 45
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        project.timelines = [timeline]

        let directory = NSTemporaryDirectory() + "ymm4mac-codec-test-\(UUID().uuidString)"
        let path = directory + "/sub/project.ymmp"
        try YmmpCodec.save(project, toFile: path)
        let (loaded, _) = try YmmpCodec.load(fromFile: path)
        XCTAssertEqual(
            try canonical(YmmpCodec.encode(project)),
            try canonical(YmmpCodec.encode(loaded))
        )
        try? FileManager.default.removeItem(atPath: directory)
    }

    // MARK: - 本家形式の読み込み

    /// 本家形式を模した手書きの最小 .ymmp（$type 付き、1行 JSON）。
    func testLoadHonkeStyleJSON() throws {
        let json = """
        {"FilePath":null,"SelectedTimelineIndex":0,"Timelines":[{"ID":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","Name":"メイン","VideoInfo":{"FPS":30,"Hz":48000,"Width":640,"Height":360,"BackgroundColor":"#FF000000"},"VerticalLine":{"IsEnabled":true,"StartFrame":5,"LineType":"BPM","Line":{"$type":"YukkuriMovieMaker.Project.VerticalBPMLine, YukkuriMovieMaker.Plugin","BPM":120.0},"Group":4},"Items":[{"$type":"YukkuriMovieMaker.Project.Items.TextItem, YukkuriMovieMaker","Group":0,"Frame":10,"Layer":2,"KeyFrames":{"Frames":[15]},"Length":90,"PlaybackRate":100.0,"PlaybackRate2":{"Values":[{"Value":100.0}],"Span":0.0,"AnimationType":"なし","Bezier":{"Points":[],"IsQuadratic":false}},"ContentOffset":"00:00:01.5000000","Remark":"メモ","IsLocked":false,"IsHidden":false,"Text":"テスト"}],"LayerSettings":{"Items":[{"Layer":2,"Label":"ラベル","Color":"#00FFFFFF","IsHidden":true,"Volume":80.0}]},"CurrentFrame":12,"Length":100,"MaxLayer":2}],"Characters":[],"CollapsedGroups":[],"LayoutXml":"","ToolStates":null}
        """
        let (project, diagnostics) = try YmmpCodec.decode(json)
        XCTAssertEqual(diagnostics.skippedItems.count, 0)
        let timeline = try XCTUnwrap(project.timelines.first)
        XCTAssertEqual(timeline.name, "メイン")
        XCTAssertEqual(timeline.currentFrame, 12)
        // Length / MaxLayer はファイルの値が復元される（再計算値ではない）
        XCTAssertEqual(timeline.length, 100)
        XCTAssertEqual(timeline.maxLayer, 2)
        XCTAssertEqual(timeline.videoInfo.width, 640)
        XCTAssertEqual(timeline.verticalLine.isEnabled, true)
        XCTAssertEqual(timeline.verticalLine.startFrame, 5)
        XCTAssertEqual(timeline.layerSettings.items.first?.label, "ラベル")
        XCTAssertEqual(timeline.layerSettings.items.first?.volume, 80)

        let item = try XCTUnwrap(timeline.items.first as? TextItem)
        XCTAssertEqual(item.frame, 10)
        XCTAssertEqual(item.layer, 2)
        XCTAssertEqual(item.keyFrames.frames, [15])
        XCTAssertEqual(item.contentOffset.ticks, 15_000_000)
        XCTAssertEqual(item.remark, "メモ")
        XCTAssertEqual(item.text, "テスト")
    }

    /// 未知の $type の要素は読み飛ばされ、既知要素は保たれ、記録が残る。
    func testUnknownItemTypeSkippedAndRecorded() throws {
        let json = """
        {"Timelines":[{"ID":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","Name":"","VideoInfo":{"FPS":30,"Hz":48000,"Width":1920,"Height":1080,"BackgroundColor":"#00FFFFFF"},"Items":[{"$type":"YukkuriMovieMaker.Project.Items.TextItem, YukkuriMovieMaker","Frame":0,"Layer":0,"Length":30,"Text":"残る"},{"$type":"YukkuriMovieMaker.Project.Items.FutureItem, YukkuriMovieMaker","Frame":40,"Layer":0,"Length":30},{"$type":"YukkuriMovieMaker.Project.Items.AudioItem, YukkuriMovieMaker","Frame":80,"Layer":1,"Length":30,"FilePath":"/tmp/a.wav"}],"CurrentFrame":0,"Length":110,"MaxLayer":1}]}
        """
        let (project, diagnostics) = try YmmpCodec.decode(json)
        let timeline = try XCTUnwrap(project.timelines.first)
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertTrue(timeline.items[0] is TextItem)
        XCTAssertTrue(timeline.items[1] is AudioItem)
        XCTAssertEqual(diagnostics.skippedItems.count, 1)
        XCTAssertEqual(
            diagnostics.skippedItems.first?.typeName,
            "YukkuriMovieMaker.Project.Items.FutureItem, YukkuriMovieMaker"
        )
        XCTAssertEqual(diagnostics.skippedItems.first?.itemIndex, 1)
    }

    /// モデル化していないプロパティは追加フィールドとして保持され、
    /// 保存時にそのまま書き戻される。
    func testUnknownPropertyPreserved() throws {
        let json = """
        {"Timelines":[{"Name":"","Items":[{"$type":"YukkuriMovieMaker.Project.Items.TextItem, YukkuriMovieMaker","Frame":0,"Layer":0,"Length":30,"Text":"x","FutureProperty":{"Nested":[1,2,3]},"FutureFlag":true}]}]}
        """
        let (project, _) = try YmmpCodec.decode(json)
        let item = try XCTUnwrap(project.timelines.first?.items.first)
        XCTAssertEqual(
            item.additionalFields.first(where: { $0.key == "FutureProperty" })?.value,
            .object([(key: "Nested", value: .array([.number(1), .number(2), .number(3)]))])
        )
        XCTAssertEqual(
            item.additionalFields.first(where: { $0.key == "FutureFlag" })?.value,
            .bool(true)
        )
        // 再保存した JSON にも残っている
        let encoded = YmmpCodec.encode(project)
        XCTAssertTrue(encoded.contains("\"FutureProperty\":{\"Nested\":[1,2,3]}"))
    }

    /// 本家リネーム（OutlineLiteEffect → OutlineEffect）が $type に適用される。
    func testRenamedTypeResolverAppliedToEffects() throws {
        let json = """
        {"Timelines":[{"Name":"","Items":[{"$type":"YukkuriMovieMaker.Project.Items.TextItem, YukkuriMovieMaker","Frame":0,"Layer":0,"Length":30,"VideoEffects":[{"$type":"YukkuriMovieMaker.Project.Effects.OutlineLiteEffect, YukkuriMovieMaker","IsEnabled":true}]}]}]}
        """
        let (project, diagnostics) = try YmmpCodec.decode(json)
        let item = try XCTUnwrap(project.timelines.first?.items.first as? TextItem)
        XCTAssertEqual(
            item.videoEffects.first?.typeName,
            "YukkuriMovieMaker.Project.Effects.OutlineEffect, YukkuriMovieMaker"
        )
        _ = diagnostics
    }

    /// 旧形式（単一 Timeline プロパティ）は Timelines へ取り込まれる。
    func testOldTimelineMigration() throws {
        let json = """
        {"Timeline":{"Name":"旧","Items":[],"CurrentFrame":0,"Length":1,"MaxLayer":0}}
        """
        let (project, _) = try YmmpCodec.decode(json)
        XCTAssertEqual(project.timelines.count, 1)
        XCTAssertEqual(project.timelines.first?.name, "旧")
    }

    /// YMM3 の XML は弾く。
    func testLegacyXMLRejected() {
        XCTAssertThrowsError(try YmmpCodec.decode("<YukkuriMovieMaker></YukkuriMovieMaker>")) { error in
            XCTAssertEqual(error as? YmmpError, .legacyXMLFormat)
        }
    }

    // MARK: - 形式変換

    func testTimeSpanFormats() {
        XCTAssertEqual(TimeSpanValue(honkeString: "00:00:00")?.ticks, 0)
        XCTAssertEqual(TimeSpanValue(honkeString: "00:00:05.5000000")?.ticks, 55_000_000)
        XCTAssertEqual(TimeSpanValue(honkeString: "1.12:00:00")?.ticks, 1_296_000_000_000)
        XCTAssertEqual(TimeSpanValue(honkeString: "-00:00:01.2500000")?.ticks, -12_500_000)
        XCTAssertEqual(TimeSpanValue(ticks: 55_000_000).honkeString, "00:00:05.5000000")
        XCTAssertEqual(TimeSpanValue(ticks: 1_296_000_000_000).honkeString, "1.12:00:00")
        XCTAssertEqual(TimeSpanValue(ticks: 0).honkeString, "00:00:00")
        XCTAssertEqual(TimeSpanValue(ticks: -12_500_000).honkeString, "-00:00:01.2500000")
    }

    func testAnimationTypeHonkeNames() {
        XCTAssertEqual(AnimationType(honkeName: "なし"), AnimationType.none)
        XCTAssertEqual(AnimationType(honkeName: "加減速移動"), .accelerationDeceleration)
        XCTAssertEqual(AnimationType(honkeName: "Quad_InOut_Int"), .quadInOutInt)
        XCTAssertEqual(AnimationType(honkeName: "Bounce_OutIn_Int"), .bounceOutInInt)
        XCTAssertEqual(AnimationType(honkeName: "Linear_Bezier"), .linearBezier)
        XCTAssertEqual(AnimationType.quadInOutInt.honkeName, "Quad_InOut_Int")
        XCTAssertEqual(AnimationType.interpolation.honkeName, "補間移動")
        XCTAssertNil(AnimationType(honkeName: "存在しない型"))
    }

    func testColorHonkeString() {
        XCTAssertEqual(Color.white.honkeString, "#FFFFFFFF")
        XCTAssertEqual(Color.transparent.honkeString, "#00FFFFFF")
        XCTAssertEqual(Color(honkeString: "#FF112233"), Color(alpha: 255, red: 0x11, green: 0x22, blue: 0x33))
        XCTAssertNil(Color(honkeString: "red"))
    }
}
