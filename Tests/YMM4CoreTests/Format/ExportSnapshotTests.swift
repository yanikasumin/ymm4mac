import XCTest
@testable import YMM4Core

/// AUD-07: 書き出し用スナップショット（`Project.makeExportSnapshot(of:)`）の独立性。
///
/// 書き出しは全フレームを通じてモデルを読み続けるため、編集中の
/// プロジェクトをそのまま渡すと UI 側の変更と競合する（配列の並行変更は
/// クラッシュ級）。スナップショットはコーデック往復で作った専有
/// インスタンス群であり、生成後に元のモデルをどう変更しても、書き出し側
/// が読む値（アイテムのプロパティ・動画設定・レイヤー設定・アイテム集合）
/// は変わらないことをここで固定する。
final class ExportSnapshotTests: XCTestCase {

    /// 2タイムライン（メイン＋シーン）とキャラクター参照を持つプロジェクト。
    private func makeProject() -> (
        project: Project, main: Timeline, scene: Timeline,
        text: TextItem, voice: VoiceItem, character: Character
    ) {
        let character = Character()
        character.name = "テストキャラ"

        let scene = Timeline()
        scene.name = "シーン"

        let text = TextItem()
        text.frame = 0
        text.layer = 0
        text.length = 90
        text.text = "元のテキスト"

        let voice = VoiceItem()
        voice.frame = 100
        voice.layer = 1
        voice.length = 90
        voice.characterName = "テストキャラ"
        voice.serif = "元のセリフ"
        voice.character = character

        let main = Timeline()
        main.name = "メイン"
        main.videoInfo = VideoInfo(fps: 60, hz: 48_000, width: 1920, height: 1080)
        main.items = [text, voice]
        main.layerSettings.items = [
            LayerSetting(layer: 0, label: "元ラベル", volume: 80)
        ]
        main.refreshTimelineLengthAndMaxLayer()

        let project = Project()
        project.characters = [character]
        project.timelines = [main, scene]
        return (project, main, scene, text, voice, character)
    }

    /// 生成時点では、スナップショットは元の内容をそのまま写している。
    func testSnapshotMatchesOriginalAtStart() throws {
        let fixture = makeProject()
        let snapshot = try fixture.project.makeExportSnapshot(of: fixture.main)

        // 対象はスナップショット側の別インスタンスで、timelines 内の
        // 同一オブジェクトを指す（SceneItem 解決が引く配列と同一性が一致）。
        XCTAssertTrue(snapshot.timeline !== fixture.main)
        XCTAssertTrue(snapshot.timeline === snapshot.timelines[0])
        XCTAssertEqual(snapshot.timelines.count, 2)
        XCTAssertEqual(snapshot.timelines[1].id, fixture.scene.id)
        XCTAssertEqual(snapshot.timelines[1].name, "シーン")

        // 内容は開始時点の元と一致する（タイムライン単位の符号化が同一）。
        XCTAssertEqual(
            YmmpCodec.encodeTimeline(snapshot.timeline).serialized(),
            YmmpCodec.encodeTimeline(fixture.main).serialized()
        )
        XCTAssertEqual(snapshot.timeline.videoInfo, fixture.main.videoInfo)
        XCTAssertEqual(snapshot.timeline.length, 190)

        // キャラクター参照はスナップショット内のキャラクターへ解決される。
        let snapshotVoice = try XCTUnwrap(
            snapshot.timeline.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertEqual(snapshotVoice.character?.name, "テストキャラ")
        XCTAssertTrue(snapshotVoice.character !== fixture.character)
    }

    /// 生成後に元のモデルを変更しても、書き出し側が読む値は変わらない。
    func testSnapshotIsIndependentOfLaterEdits() throws {
        let fixture = makeProject()
        let snapshot = try fixture.project.makeExportSnapshot(of: fixture.main)

        // 書き出し中の UI 変更経路を再現する:
        // デスクリプタ経由のアイテム値、動画設定の差し替え、アイテム配列の
        // 追加・削除（並行変更でクラッシュ級の経路）、レイヤー設定の
        // 下付き代入と追加、キャラクターと他タイムラインの変更。
        fixture.text.text = "編集後のテキスト"
        fixture.text.frame = 500
        fixture.voice.serif = "編集後のセリフ"
        fixture.character.name = "改名キャラ"
        fixture.main.videoInfo = VideoInfo(fps: 30, hz: 44_100, width: 640, height: 360)
        fixture.main.items.append(TextItem())
        fixture.main.items.removeAll { $0 === fixture.voice }
        fixture.main.layerSettings.items[0].label = "変更ラベル"
        fixture.main.layerSettings.items.append(LayerSetting(layer: 5))
        fixture.scene.name = "改名シーン"

        // アイテムのプロパティは開始時点のまま。
        let snapshotText = try XCTUnwrap(
            snapshot.timeline.items.compactMap { $0 as? TextItem }.first
        )
        XCTAssertEqual(snapshotText.text, "元のテキスト")
        XCTAssertEqual(snapshotText.frame, 0)
        let snapshotVoice = try XCTUnwrap(
            snapshot.timeline.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertEqual(snapshotVoice.serif, "元のセリフ")
        XCTAssertEqual(snapshotVoice.character?.name, "テストキャラ")

        // 動画設定・長さ・アイテム集合も開始時点のまま。
        XCTAssertEqual(snapshot.timeline.videoInfo.fps, 60)
        XCTAssertEqual(snapshot.timeline.videoInfo.width, 1920)
        XCTAssertEqual(snapshot.timeline.videoInfo.hz, 48_000)
        XCTAssertEqual(snapshot.timeline.items.count, 2)
        XCTAssertEqual(snapshot.timeline.length, 190)

        // レイヤー設定と他タイムラインも開始時点のまま。
        XCTAssertEqual(snapshot.timeline.layerSettings.items.count, 1)
        XCTAssertEqual(snapshot.timeline.layerSettings.items.first?.label, "元ラベル")
        XCTAssertEqual(snapshot.timeline.layerSettings.items.first?.volume, 80)
        XCTAssertEqual(snapshot.timelines[1].name, "シーン")
    }

    /// プロジェクトに属さないタイムラインはスナップショット対象にできない。
    func testSnapshotRejectsTimelineOutsideProject() {
        let project = Project()
        project.timelines = [Timeline()]
        let outsider = Timeline()
        XCTAssertThrowsError(try project.makeExportSnapshot(of: outsider)) { error in
            XCTAssertEqual(error as? YmmpError, .timelineNotInProject)
        }
    }
}
