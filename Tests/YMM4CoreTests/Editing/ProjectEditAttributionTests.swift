import XCTest
@testable import YMM4Core

/// FE-R30-130-02: トークンなし離散編集イベントのプロジェクト帰属。
///
/// アプリ層の配線（ProjectView のスタンプ捕捉とガード）が守る不変条件を、
/// アプリ層が使う形そのままに Core 側で固定する:
/// - 帰属チェックはモデル変更と Undo 記録の双方より前に行う（条件 B）。
/// - 陳腐化したイベントはモデルも履歴も変えない（条件 C）。
/// - 現行プロジェクトの離散編集は従来どおり記録・Undo できる（条件 D）。
/// - 連続編集のトークン契約は帰属の導入で変わらない（条件 E）。
final class ProjectEditAttributionTests: XCTestCase {
    private final class Target {}

    /// アプリ層の入口確認と同じ形のガード付き書き込み。
    /// 帰属が陳腐化していればモデル変更にも記録にも進まない。
    private func guardedWrite(
        attribution: ProjectEditAttribution,
        stamp: EditProjectStamp,
        recorder: EditRecorder,
        target: AnyObject,
        key: String,
        oldValue: Double,
        newValue: Double,
        apply: @escaping (Double) -> Void
    ) -> Bool {
        guard attribution.isCurrent(stamp) else { return false }
        guard recorder.canRecordValueChange() else { return false }
        apply(newValue)
        recorder.recordValueChange(
            target: EditTargetKey(object: ObjectIdentifier(target), key: key),
            oldValue: oldValue,
            newValue: newValue,
            apply: apply
        )
        return true
    }

    func testStampIsCurrentUntilAdvance() {
        let attribution = ProjectEditAttribution()
        let stamp = attribution.currentStamp()
        XCTAssertTrue(attribution.isCurrent(stamp))
        // 同じ世代では何度取得しても同じスタンプが現行のまま。
        XCTAssertEqual(attribution.currentStamp(), stamp)
        XCTAssertTrue(attribution.isCurrent(attribution.currentStamp()))
    }

    func testAdvanceStalesPreviousStamps() {
        let attribution = ProjectEditAttribution()
        let first = attribution.currentStamp()
        attribution.advance()
        XCTAssertFalse(attribution.isCurrent(first))
        let second = attribution.currentStamp()
        XCTAssertTrue(attribution.isCurrent(second))
        XCTAssertNotEqual(first, second)
        attribution.advance()
        XCTAssertFalse(attribution.isCurrent(first))
        XCTAssertFalse(attribution.isCurrent(second))
        XCTAssertTrue(attribution.isCurrent(attribution.currentStamp()))
    }

    /// 条件 B・C: 切り替え後に遅れて届いた旧プロジェクト向けの離散編集は、
    /// モデル変更も履歴の増加も起こさない。
    func testStaleDiscreteEditIsRejectedBeforeModelChangeAndRecording() {
        let attribution = ProjectEditAttribution()
        let recorder = EditRecorder()
        let target = Target()
        var value = 1.0
        let stampAtViewCreation = attribution.currentStamp()

        // プロジェクト切り替え: 世代を進め、履歴は差し替え側で消去される。
        attribution.advance()
        recorder.resetForProjectSwitch()

        let written = guardedWrite(
            attribution: attribution,
            stamp: stampAtViewCreation,
            recorder: recorder,
            target: target,
            key: "X",
            oldValue: 1,
            newValue: 42,
            apply: { value = $0 }
        )
        XCTAssertFalse(written)
        XCTAssertEqual(value, 1, "陳腐化したイベントはモデルを変更しない")
        XCTAssertFalse(recorder.coordinator.canUndo, "新プロジェクトの履歴は増えない")
        XCTAssertFalse(recorder.coordinator.canRedo)
    }

    /// 条件 D: 現行プロジェクトの離散編集は従来どおり実行・記録され、Undo できる。
    func testCurrentDiscreteEditRecordsAndUndoes() {
        let attribution = ProjectEditAttribution()
        let recorder = EditRecorder()
        let target = Target()
        var value = 1.0

        let written = guardedWrite(
            attribution: attribution,
            stamp: attribution.currentStamp(),
            recorder: recorder,
            target: target,
            key: "X",
            oldValue: 1,
            newValue: 42,
            apply: { value = $0 }
        )
        XCTAssertTrue(written)
        XCTAssertEqual(value, 42)
        XCTAssertTrue(recorder.coordinator.canUndo)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(value, 1)
        XCTAssertTrue(recorder.coordinator.redo())
        XCTAssertEqual(value, 42)
    }

    /// 条件 E: 帰属を導入しても、連続編集のトークン契約（所有者の蓄積・
    /// 失効トークンの拒否）は従来どおりである。切り替えで破棄された
    /// セッションのトークンは、切り替え後の新しいセッションを妨げない。
    func testTokenContractUnaffectedByAttribution() {
        let attribution = ProjectEditAttribution()
        let recorder = EditRecorder()
        let target = Target()
        var value = 0.0
        let key = EditTargetKey(object: ObjectIdentifier(target), key: "X")

        // 旧プロジェクトのセッション。
        guard let oldToken = recorder.beginSession() else {
            return XCTFail("セッションを開始できる")
        }
        XCTAssertTrue(recorder.canRecordValueChange(sessionToken: oldToken))

        // 切り替え: 世代を進めるとセッションは巻き戻されて破棄される。
        attribution.advance()
        recorder.resetForProjectSwitch()
        XCTAssertFalse(recorder.canRecordValueChange(sessionToken: oldToken))

        // 新プロジェクトでは新しいセッションが通常どおり使える。
        guard let newToken = recorder.beginSession() else {
            return XCTFail("切り替え後もセッションを開始できる")
        }
        recorder.recordValueChange(
            target: key, oldValue: 0, newValue: 5,
            apply: { value = $0 }, sessionToken: newToken
        )
        value = 5
        recorder.commitSession(token: newToken)
        XCTAssertTrue(recorder.coordinator.canUndo)
        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(value, 0)
    }
}
