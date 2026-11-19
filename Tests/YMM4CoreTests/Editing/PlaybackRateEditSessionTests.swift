import XCTest
@testable import YMM4Core

/// FE-R27-129-01 / 03: 再生速度の編集が「速度の変更＋編集終了時
/// 調整」を Undo/Redo 可能な1つの確定編集として扱われることの
/// 回帰テスト（監査 Round 27 の受け入れ試験 1〜8）。
///
/// アプリ層（`AnimationRowView` の再生速度セッションと
/// `ProjectView` の終了時ハンドラ）と同じ記録手順を Core の
/// 記述子＋ `EditRecorder` で再現する: セッション開始 → 基点
/// 捕捉 → 記述子経由の書き込み（対象キー "PlaybackRate2#const"、
/// トークン提示で記録）→ 終了時調整（基点で分岐の優先を判定し、
/// 長さ・オフセットの変更を同じセッションへ記録）→ セッション
/// 確定。従来は調整が無記録で、Undo で速度だけが戻り長さが
/// 残っていた（FE-R27-129-01）。
final class PlaybackRateEditSessionTests: XCTestCase {

    private func seconds(_ value: Double) -> TimeSpanValue {
        TimeSpanValue(seconds: value)
    }

    private struct Fixture {
        let item: AudioItem
        let descriptor: PropertyDescriptor
        let recorder: EditRecorder
    }

    private func makeFixture() -> Fixture {
        let item = AudioItem()
        let descriptor = ItemPropertyMetadata.descriptors(for: item)
            .first { $0.id == "PlaybackRate2" }!
        return Fixture(
            item: item, descriptor: descriptor, recorder: EditRecorder())
    }

    /// 素材 10 秒・長さ 300 フレームの初期状態にする。
    private func prepareItem(_ fixture: Fixture) {
        fixture.item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        fixture.item.resetLength(fps: 30)
        XCTAssertEqual(fixture.item.length, 300)
    }

    /// 行の書き込み（定数化経路）と同じ手順: 入口確認 → 記述子
    /// 経由で書き込み → 実効値を読み戻してトークン提示で記録。
    private func writeRate(
        _ fixture: Fixture, _ value: Double, token: EditSessionToken?
    ) {
        let descriptor = fixture.descriptor
        XCTAssertTrue(
            fixture.recorder.canRecordValueChange(sessionToken: token))
        let old = descriptor.animationValue!.firstValue
        descriptor.setAnimationConstantValue(value)
        let new = descriptor.animationValue!.firstValue
        fixture.recorder.recordValueChange(
            target: EditTargetKey(fixture.item, key: "PlaybackRate2#const"),
            oldValue: old, newValue: new,
            apply: { descriptor.setAnimationConstantValue($0) },
            sessionToken: token)
    }

    /// `ProjectView` の終了時ハンドラと同じ手順: トークンの
    /// 有効性を確認 → Core の適用層で調整 → 長さ・オフセットの
    /// 変更を同じセッションへ記録する。
    private func finishSession(
        _ fixture: Fixture, baseline: PlaybackRateEditBaseline,
        token: EditSessionToken?
    ) {
        let item = fixture.item
        XCTAssertTrue(
            fixture.recorder.canRecordValueChange(sessionToken: token))
        let oldLength = item.length
        let oldOffset = item.contentOffset
        guard item.finishPlaybackRateEdit(baseline: baseline, fps: 30)
        else { return }
        if item.length != oldLength {
            fixture.recorder.recordValueChange(
                target: EditTargetKey(item, key: "Length"),
                oldValue: oldLength, newValue: item.length,
                apply: { item.length = $0 },
                sessionToken: token)
        }
        if item.contentOffset != oldOffset {
            fixture.recorder.recordValueChange(
                target: EditTargetKey(item, key: "ContentOffset"),
                oldValue: oldOffset, newValue: item.contentOffset,
                apply: { item.contentOffset = $0 },
                sessionToken: token)
        }
    }

    /// テキスト確定と同じく、開始から確定までを1セッションで
    /// 同期的に完結させる。
    private func commitRateEdit(_ fixture: Fixture, _ value: Double) {
        let token = fixture.recorder.beginSession()
        XCTAssertNotNil(token)
        let baseline = fixture.item.capturePlaybackRateEditBaseline()
        writeRate(fixture, value, token: token)
        finishSession(fixture, baseline: baseline, token: token)
        fixture.recorder.commitSession(token: token!)
    }

    /// 受け入れ試験 1: 速度 100% → 50% で長さが 300 → 600 へ
    /// 追随し、履歴は1エントリ。Undo で速度と長さが一緒に
    /// 戻り、Redo で一緒に再適用される。
    func testRateHalvingAdjustsLengthInSameHistoryEntry() {
        let fixture = makeFixture()
        prepareItem(fixture)

        commitRateEdit(fixture, 50)
        XCTAssertEqual(fixture.item.playbackRate, 50)
        XCTAssertEqual(fixture.item.length, 600)
        XCTAssertEqual(fixture.recorder.coordinator.history.undoCount, 1)

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(fixture.item.playbackRate, 100)
        XCTAssertEqual(fixture.item.length, 300)

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(fixture.item.playbackRate, 50)
        XCTAssertEqual(fixture.item.length, 600)
    }

    /// 受け入れ試験 2: 符号反転（100% → −50%）では長さと
    /// オフセットが一緒に付け替わり、Undo/Redo で3値が一緒に
    /// 往復する。
    func testSignFlipAdjustsLengthAndOffsetInSameEntry() {
        let fixture = makeFixture()
        prepareItem(fixture)
        fixture.item.contentOffset = seconds(2)

        commitRateEdit(fixture, -50)
        XCTAssertEqual(fixture.item.playbackRate, -50)
        XCTAssertEqual(fixture.item.length, 600)
        // オフセット = 10 − (2 + 20 秒 × 100 / 100) = −12 秒。
        XCTAssertEqual(fixture.item.contentOffset, seconds(-12))
        XCTAssertEqual(fixture.recorder.coordinator.history.undoCount, 1)

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(fixture.item.playbackRate, 100)
        XCTAssertEqual(fixture.item.length, 300)
        XCTAssertEqual(fixture.item.contentOffset, seconds(2))

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(fixture.item.playbackRate, -50)
        XCTAssertEqual(fixture.item.length, 600)
        XCTAssertEqual(fixture.item.contentOffset, seconds(-12))
    }

    /// 受け入れ試験 3: スライダの連続ドラッグ（逐次書き込み）
    /// は調整込みで履歴1エントリへまとまり、1回の Undo で
    /// 原状へ戻る。
    func testSliderDragCoalescesIntoOneEntry() {
        let fixture = makeFixture()
        prepareItem(fixture)

        let token = fixture.recorder.beginSession()
        XCTAssertNotNil(token)
        let baseline = fixture.item.capturePlaybackRateEditBaseline()
        writeRate(fixture, 80, token: token)
        writeRate(fixture, 60, token: token)
        writeRate(fixture, 50, token: token)
        finishSession(fixture, baseline: baseline, token: token)
        fixture.recorder.commitSession(token: token!)

        XCTAssertEqual(fixture.item.playbackRate, 50)
        XCTAssertEqual(fixture.item.length, 600)
        XCTAssertEqual(fixture.recorder.coordinator.history.undoCount, 1)

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(fixture.item.playbackRate, 100)
        XCTAssertEqual(fixture.item.length, 300)
    }

    /// 受け入れ試験 4: 他人のセッションが有効な間は再生速度の
    /// セッションを開始できず、速度・長さ・オフセットのいずれ
    /// も変わらない（アプリ層は開始拒否で書き込み自体を行わず、
    /// 基点も捕捉しない）。
    func testSessionRefusalLeavesRateLengthOffsetUntouched() {
        let fixture = makeFixture()
        prepareItem(fixture)
        fixture.item.contentOffset = seconds(2)

        let foreign = fixture.recorder.beginSession()
        XCTAssertNotNil(foreign)
        // 行側の開始は拒否される（トークンが得られない）。
        XCTAssertNil(fixture.recorder.beginSession())
        XCTAssertFalse(fixture.recorder.canRecordValueChange())

        fixture.recorder.cancelSession(token: foreign!)
        XCTAssertEqual(fixture.item.playbackRate, 100)
        XCTAssertEqual(fixture.item.length, 300)
        XCTAssertEqual(fixture.item.contentOffset, seconds(2))
        XCTAssertFalse(fixture.recorder.coordinator.canUndo)
    }

    /// 受け入れ試験 5（記述子・Undo 経由）: エコー有効中の速度
    /// 変更では素材長がその場で再計算され、Undo/Redo の適用
    /// でも追随する（FE-R27-129-02。追随点は `playbackRate2`
    /// の書き込みへの集約）。
    func testEchoContentLengthFollowsRateThroughDescriptorAndUndo() {
        let fixture = makeFixture()
        fixture.item.echoIsEnabled = true
        // エコー有効時は素材長が尾込み（10.6 秒）になり、長さも
        // 318 フレームになるため、prepareItem の前提（300）と
        // 分けて初期化する。
        fixture.item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        fixture.item.resetLength(fps: 30)
        XCTAssertEqual(fixture.item.contentLength, seconds(10.6))

        commitRateEdit(fixture, 200)
        // 尾 = 0.6 秒 × (200 / 100) = 1.2 秒。
        XCTAssertEqual(fixture.item.contentLength, seconds(11.2))

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(fixture.item.playbackRate, 100)
        XCTAssertEqual(fixture.item.contentLength, seconds(10.6))

        XCTAssertTrue(fixture.recorder.coordinator.redo())
        XCTAssertEqual(fixture.item.contentLength, seconds(11.2))
    }

    /// 受け入れ試験 6: 速度の編集中に別素材へ差し替えると
    /// 分岐 (1) が優先し、比率換算が二重に走らない。
    func testFileChangeDuringRateEditTakesPriority() {
        let fixture = makeFixture()
        prepareItem(fixture)

        let token = fixture.recorder.beginSession()
        XCTAssertNotNil(token)
        let baseline = fixture.item.capturePlaybackRateEditBaseline()
        // 編集中のファイル差し替え（非同期の完了を同期で再現）:
        // 分岐 (1) で長さが決め直される（20 秒 → 600 フレーム）。
        fixture.item.recordMediaInfo(MediaFileInfo(duration: seconds(20)))
        XCTAssertTrue(fixture.item.adjustLengthAfterFileChange(
            previousOriginalContentLength: seconds(10), fps: 30))
        XCTAssertEqual(fixture.item.length, 600)
        writeRate(fixture, 50, token: token)
        finishSession(fixture, baseline: baseline, token: token)
        fixture.recorder.commitSession(token: token!)
        // 分岐 (3) が重なれば 1,200 になる。二重換算されていない。
        XCTAssertEqual(fixture.item.length, 600)
    }

    /// 受け入れ試験 7: 編集途中で選択が変わって行が作り直され
    /// ても、古い基点が後続セッションへ再利用されない。各
    /// セッションはその開始時点の基点で確定し、符号反転を
    /// 挟んでも合成結果が誤らない。
    func testSequentialSessionsDoNotComposeStaleBaseline() {
        let fixture = makeFixture()
        prepareItem(fixture)
        fixture.item.contentOffset = seconds(2)

        // セッション A: 100% → −100%（行の破棄で確定する想定）。
        commitRateEdit(fixture, -100)
        // 符号反転の付け替え: 10 − (2 + 10 秒 × 100 / 100) = −2 秒。
        XCTAssertEqual(fixture.item.contentOffset, seconds(-2))
        XCTAssertEqual(fixture.item.length, 300)

        // セッション B: −100% → −50%。基点は B の開始時点
        // （−100%）であり、A の基点（100%）ではない。
        commitRateEdit(fixture, -50)
        XCTAssertEqual(fixture.item.length, 600)
        // 符号は反転していないためオフセットは維持される。
        // A の基点で一括調整すると −12 秒へ誤る。
        XCTAssertEqual(fixture.item.contentOffset, seconds(-2))
    }

    /// 受け入れ試験 8: 移動量指定の第2値だけの編集では、定数
    /// 速度用の長さ調整は発火せず、第2値の Undo（状態一体の
    /// 記録）が維持される。
    func testMovementSecondValueEditDoesNotTriggerRateAdjustment() {
        let fixture = makeFixture()
        prepareItem(fixture)
        // 種別を移動量指定へ（値列は本家の規則で [100, 0] へ
        // 再構成される。FE-R14-001）。
        XCTAssertTrue(fixture.descriptor.setAnimationType(.movementAmount))
        let lengthBefore = fixture.item.length

        // 第2値の書き込み（アプリ層の第2値行と同じ手順: 変更
        // 前後の状態を一体で記録する。FE-R25-128-01）。
        let animation = fixture.descriptor.animationValue!
        let oldState = animation.recordedState
        let radius = max(abs(animation.minValue), abs(animation.maxValue))
        XCTAssertTrue(fixture.descriptor.setAnimationValue(
            25, atValueIndex: 1, clampRange: (-radius)...radius))
        let newState = fixture.descriptor.animationValue!.recordedState
        fixture.recorder.recordValueChange(
            target: EditTargetKey(fixture.item, key: "PlaybackRate2#movement"),
            oldValue: oldState, newValue: newState,
            apply: { fixture.descriptor.restoreAnimationRecordedState($0) })
        XCTAssertEqual(fixture.item.length, lengthBefore)

        // 終了時調整の適用層でも、定数でない基点では分岐 (3)
        // は発火しない（多層防御）。
        let baseline = fixture.item.capturePlaybackRateEditBaseline()
        XCTAssertFalse(baseline.isConstant)
        XCTAssertFalse(fixture.item.finishPlaybackRateEdit(
            baseline: baseline, fps: 30))
        XCTAssertEqual(fixture.item.length, lengthBefore)

        XCTAssertTrue(fixture.recorder.coordinator.undo())
        XCTAssertEqual(
            fixture.descriptor.animationValue!.values.map(\.value),
            [100, 0])
    }
}
