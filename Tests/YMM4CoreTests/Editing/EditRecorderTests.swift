import XCTest
@testable import YMM4Core

/// FE-UNDO-WIRING の記録集約点 `EditRecorder` の検証。
///
/// 受け入れ観点:
/// - FE-R20-126-02: トランザクション開始が拒否された場合、
///   `recordTimelineChange` は変更本体を実行せず、モデルにも履歴にも
///   変更を残さない。実行できる場合は変更と記録が行われる。
final class EditRecorderTests: XCTestCase {

    private func makeItem(frame: Int, length: Int) -> TextItem {
        let item = TextItem()
        item.frame = frame
        item.length = length
        return item
    }

    /// 開始できる場合は本体が実行され、差分が履歴へ記録される。
    func testRecordTimelineChangeExecutesAndRecordsWhenIdle() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 30)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()

        let recorder = EditRecorder()
        var executed = false
        let result = recorder.recordTimelineChange(timeline: timeline) {
            executed = true
            item.frame = 45
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertTrue(result)
        XCTAssertTrue(executed)
        XCTAssertEqual(item.frame, 45)
        XCTAssertTrue(recorder.coordinator.canUndo)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(item.frame, 0)
    }

    /// セッションが有効な間に開始を拒否された場合、本体は実行されず、
    /// モデルにも履歴にも変更が残らない（FE-R20-126-02）。
    func testRecordTimelineChangeRefusedWhileSessionActive() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, length: 30)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()

        let recorder = EditRecorder()
        XCTAssertTrue(recorder.beginSession())

        var executed = false
        let result = recorder.recordTimelineChange(timeline: timeline) {
            executed = true
            item.frame = 45
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertFalse(result)
        XCTAssertFalse(executed)
        XCTAssertEqual(item.frame, 0)
        XCTAssertEqual(timeline.length, 30)

        // セッションを確定しても、拒否された変更は履歴に現れない
        // （セッション自体は空のためエントリ自体が作られない）。
        recorder.commitSession()
        XCTAssertFalse(recorder.coordinator.canUndo)
    }
}
