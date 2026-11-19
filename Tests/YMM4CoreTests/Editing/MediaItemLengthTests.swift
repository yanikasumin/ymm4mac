import XCTest
@testable import YMM4Core

/// メディアアイテムの長さ決定（FE-R1-043、編集操作層）。
///
/// 本家の規則（ItemEx.ResetLength / GetContentLengthAppliedPlaybackRate、
/// FrameTime.TimeToFrame、ItemEditorViewModel の編集終了処理）を
/// 実コードで照合した結果を固定する。受け入れ条件 R2-B02 / B03 に
/// 対応する（監査 Round 2 の文面そのものは設計文書に残っていないため、
/// 設計節の要点から構成した対応付け。実装台帳 FE-FILEPATH に記録）。
final class MediaItemLengthTests: XCTestCase {

    private func seconds(_ value: Double) -> TimeSpanValue {
        TimeSpanValue(seconds: value)
    }

    // MARK: - R2-B02: 新規追加時の長さ決定（ResetLength）

    func testResetLengthUsesContentLengthAtConstantRate() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(90)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 2700)
    }

    func testResetLengthScalesByPlaybackRate() {
        let fast = AudioItem()
        fast.playbackRate = 200
        fast.recordMediaInfo(MediaFileInfo(duration: seconds(90)))
        fast.resetLength(fps: 30)
        XCTAssertEqual(fast.length, 1350)

        let slow = AudioItem()
        slow.playbackRate = 50
        slow.recordMediaInfo(MediaFileInfo(duration: seconds(90)))
        slow.resetLength(fps: 30)
        XCTAssertEqual(slow.length, 5400)

        // 負のレートは絶対値で効く（本家は Math.Abs を使う）。
        let reversed = AudioItem()
        reversed.playbackRate = -100
        reversed.recordMediaInfo(MediaFileInfo(duration: seconds(90)))
        reversed.resetLength(fps: 30)
        XCTAssertEqual(reversed.length, 2700)
    }

    func testResetLengthSubtractsContentOffset() {
        let item = AudioItem()
        item.contentOffset = seconds(10)
        item.recordMediaInfo(MediaFileInfo(duration: seconds(90)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 2400)
        XCTAssertEqual(item.contentOffset, seconds(10))
    }

    func testResetLengthWithOffsetResetUsesFullContent() {
        let item = AudioItem()
        item.contentOffset = seconds(10)
        item.recordMediaInfo(MediaFileInfo(duration: seconds(90)))
        item.resetLength(fps: 30, resetContentOffset: true)
        XCTAssertEqual(item.contentOffset, .zero)
        XCTAssertEqual(item.length, 2700)
    }

    func testResetLengthFallsBackToDefaultWhenContentIsZero() {
        let item = AudioItem()
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, BaseItem.defaultItemLength)
        XCTAssertEqual(BaseItem.defaultItemLength, 300)
    }

    func testResetLengthFallsBackToDefaultWhenConstantRateIsZero() {
        let item = AudioItem()
        item.playbackRate = 0
        item.recordMediaInfo(MediaFileInfo(duration: seconds(90)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 300)
    }

    func testResetLengthRoundsAwayFromZero() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(1.05)))
        item.resetLength(fps: 30)
        // 1.05 秒 × 30fps = 31.5 → 0 から遠い側へ丸めて 32。
        XCTAssertEqual(item.length, 32)
    }

    func testResetLengthNeverDropsBelowOneFrame() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(0.001)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 1)
    }

    func testResetLengthUsesGivenFPS() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 60)
        XCTAssertEqual(item.length, 600)
    }

    /// 非定数レートでは、先頭値が 0 でも素材が尽きる時刻から
    /// 長さが決まる（本家は非定数フラグだけで分岐に入る）。
    func testResetLengthWithNonConstantRateUsesExhaustedTime() {
        let item = AudioItem()
        item.length = 300
        item.playbackRate2 = Animation(
            defaultValue: 100, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(100), AnimationValue(100)]
        )
        item.recordMediaInfo(MediaFileInfo(duration: seconds(5)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 150)
    }

    /// 非定数レートで素材が尽きる時刻が求まらない場合（レートが
    /// 常に 0）は、適用時間が 0 になり長さは最小の 1 になる
    /// （本家も GetFrameFrom(0) を max(1, …) で受ける）。
    func testResetLengthWithNonConstantZeroRateBecomesOneFrame() {
        let item = AudioItem()
        item.length = 300
        item.playbackRate2 = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(0)]
        )
        item.recordMediaInfo(MediaFileInfo(duration: seconds(5)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 1)
    }

    // MARK: - エコー尾と素材情報の記録

    func testRecordMediaInfoAddsEchoTailToContentLength() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.echoInterval = 0.1
        item.echoAttenuation = 40
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        XCTAssertEqual(item.originalContentLength, seconds(10))
        // 繰り返し回数 = ceil(log(0.01) / log(0.4)) = 6、尾 = 0.6 秒。
        XCTAssertEqual(item.contentLength, seconds(10.6))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 318)
    }

    /// 素材長がゼロなら、エコーが有効でも尾を加えず ContentLength は
    /// ゼロのまま（FE-R15-001。本家 VideoItem.cs / AudioItem.cs の
    /// ContentLength は素材長ゼロで Zero を返す）。長さは既定の
    /// 300 フレームへ倒れる。
    func testRecordMediaInfoWithZeroDurationIgnoresEchoTail() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.echoInterval = 0.1
        item.echoAttenuation = 40
        item.recordMediaInfo(MediaFileInfo(duration: .zero))
        XCTAssertEqual(item.originalContentLength, .zero)
        XCTAssertEqual(item.contentLength, .zero)
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, BaseItem.defaultItemLength)
    }

    func testRecordMediaInfoWithoutEchoKeepsRawDuration() {
        let item = VideoItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10), width: 1920, height: 1080))
        XCTAssertEqual(item.originalContentLength, seconds(10))
        XCTAssertEqual(item.contentLength, seconds(10))
    }

    /// 画像は本家でも長さを持たない（ContentLength は常に 0）。
    func testRecordMediaInfoForImageKeepsLengthsZero() {
        let item = ImageItem()
        item.recordMediaInfo(MediaFileInfo(duration: .zero, width: 1920, height: 1080))
        XCTAssertEqual(item.originalContentLength, .zero)
        XCTAssertEqual(item.contentLength, .zero)
    }

    // MARK: - R2-B03: 既存アイテムのファイル変更時の調整

    /// 素材そのものの長さが変わらなければ、利用者のトリム
    /// （長さとオフセット）は引き継がれる。
    func testFileChangeWithSameContentLengthPreservesTrim() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.length = 100
        item.contentOffset = seconds(2)
        let previous = item.originalContentLength
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        let adjusted = item.adjustLengthAfterFileChange(
            previousOriginalContentLength: previous, fps: 30
        )
        XCTAssertFalse(adjusted)
        XCTAssertEqual(item.length, 100)
        XCTAssertEqual(item.contentOffset, seconds(2))
    }

    /// 素材そのものの長さが変われば、オフセットを 0 へ戻して
    /// 長さを決め直す（本家エディタの編集終了処理の分岐）。
    func testFileChangeWithDifferentContentLengthResetsLength() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.length = 100
        item.contentOffset = seconds(2)
        let previous = item.originalContentLength
        item.recordMediaInfo(MediaFileInfo(duration: seconds(20)))
        let adjusted = item.adjustLengthAfterFileChange(
            previousOriginalContentLength: previous, fps: 30
        )
        XCTAssertTrue(adjusted)
        XCTAssertEqual(item.length, 600)
        XCTAssertEqual(item.contentOffset, .zero)
    }

    // MARK: - FE-R16-001: 差し替え後のタイムライン長キャッシュ整合

    /// アイテムを1つ持つタイムラインを用意する。長さキャッシュは
    /// 実アイテム集合と一致した状態から始める。
    private func makeTimelineWithAudioItem(
        duration: Double
    ) -> (timeline: Timeline, item: AudioItem) {
        let timeline = Timeline()
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(duration)))
        item.resetLength(fps: 30)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        return (timeline, item)
    }

    /// アプリ層 `applyFileChange` の確定手順（記録→調整→調整が起きた
    /// 場合だけキャッシュ再計算）を Core 側で再現する。
    /// アイテム側の調整は所属タイムラインを知らないため、キャッシュの
    /// 追随はタイムラインを把握している側の責務という契約を固定する。
    private func applyFileChangeSequence(
        item: AudioItem, timeline: Timeline, newDuration: Double
    ) -> Bool {
        let previous = item.originalContentLength
        item.recordMediaInfo(MediaFileInfo(duration: seconds(newDuration)))
        let adjusted = item.adjustLengthAfterFileChange(
            previousOriginalContentLength: previous, fps: 30
        )
        if adjusted {
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        return adjusted
    }

    /// 調整だけではキャッシュは追随しない（アプリ層の再計算が必要な
    /// 根拠）。再計算後は実長と一致する。
    func testAdjustAloneLeavesTimelineLengthCacheStale() {
        let (timeline, item) = makeTimelineWithAudioItem(duration: 10)
        XCTAssertEqual(timeline.length, 300)
        let previous = item.originalContentLength
        item.recordMediaInfo(MediaFileInfo(duration: seconds(20)))
        XCTAssertTrue(item.adjustLengthAfterFileChange(
            previousOriginalContentLength: previous, fps: 30
        ))
        XCTAssertNotEqual(timeline.length, timeline.computeCurrentLength())
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, timeline.computeCurrentLength())
    }

    /// 拡大: 差し替え確定後にキャッシュが新しい実長へ追随する。
    func testTimelineLengthCacheFollowsFileChangeExpansion() {
        let (timeline, item) = makeTimelineWithAudioItem(duration: 10)
        let adjusted = applyFileChangeSequence(
            item: item, timeline: timeline, newDuration: 20
        )
        XCTAssertTrue(adjusted)
        XCTAssertEqual(item.length, 600)
        XCTAssertEqual(timeline.length, timeline.computeCurrentLength())
        XCTAssertEqual(timeline.length, 600)
    }

    /// 短縮: 伸びた状態から短い素材へ差し替えてもキャッシュが縮む。
    func testTimelineLengthCacheFollowsFileChangeShrink() {
        let (timeline, item) = makeTimelineWithAudioItem(duration: 20)
        XCTAssertEqual(timeline.length, 600)
        let adjusted = applyFileChangeSequence(
            item: item, timeline: timeline, newDuration: 10
        )
        XCTAssertTrue(adjusted)
        XCTAssertEqual(item.length, 300)
        XCTAssertEqual(timeline.length, timeline.computeCurrentLength())
        XCTAssertEqual(timeline.length, 300)
    }

    /// 同長差し替え: 調整は起きず、利用者のトリムとキャッシュの
    /// 整合はそのまま保たれる。
    func testTimelineLengthCacheStaysConsistentWhenFileChangeKeepsLength() {
        let (timeline, item) = makeTimelineWithAudioItem(duration: 10)
        item.length = 100
        timeline.refreshTimelineLengthAndMaxLayer()
        let adjusted = applyFileChangeSequence(
            item: item, timeline: timeline, newDuration: 10
        )
        XCTAssertFalse(adjusted)
        XCTAssertEqual(item.length, 100)
        XCTAssertEqual(timeline.length, timeline.computeCurrentLength())
        XCTAssertEqual(timeline.length, 100)
    }

    // MARK: - FE-R15-006: エコー設定変更時の素材長再計算

    /// エコーを後から有効にすると、記録済みの素材長へ現在の設定の
    /// 尾が付く。本家は ContentLength の取得時に計算するため即時に
    /// 反映される。長さはここでは追随しない（追随は編集終了時調整
    /// の分岐 (2) の役割で、区切りの供給が無いため未実装）。
    func testEchoEnableAfterRecordRefreshesContentLengthOnly() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.contentLength, seconds(10))
        XCTAssertEqual(item.length, 300)
        item.echoIsEnabled = true
        // 間隔 0.1 秒・減衰 40% → 繰り返し 6 回、尾 0.6 秒。
        XCTAssertEqual(item.contentLength, seconds(10.6))
        XCTAssertEqual(item.length, 300)
    }

    /// エコーの間隔・減衰を変えるたびに尾が再計算される。
    /// 無効化すると素材そのものの長さへ戻る。
    func testEchoParameterChangesRefreshContentLength() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        XCTAssertEqual(item.contentLength, seconds(10.6))
        item.echoInterval = 0.2
        // 尾 = 0.2 秒 × 6 回 = 1.2 秒。
        XCTAssertEqual(item.contentLength, seconds(11.2))
        item.echoAttenuation = 20
        // 繰り返し = ceil(log(0.01) / log(0.2)) = 3、尾 = 0.2 × 3。
        XCTAssertEqual(item.contentLength, seconds(10.6))
        item.echoIsEnabled = false
        XCTAssertEqual(item.contentLength, seconds(10))
    }

    /// 素材長が未記録（ゼロ）の間は、エコーを有効にしても素材長は
    /// ゼロのまま（FE-R15-001 の規則を再計算でも守る）。
    func testEchoRefreshKeepsZeroContentLengthAtZero() {
        let item = AudioItem()
        item.echoIsEnabled = true
        XCTAssertEqual(item.originalContentLength, .zero)
        XCTAssertEqual(item.contentLength, .zero)
    }

    /// 尾は再生速度の先頭値で比例する（GetEchoLength）。速度変更後
    /// のエコー変更でも、その時点の速度で計算し直される。
    func testEchoRefreshScalesTailWithPlaybackRate() {
        let item = AudioItem()
        item.playbackRate = 200
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        // 尾 = 0.6 秒 × (200 / 100) = 1.2 秒。
        XCTAssertEqual(item.contentLength, seconds(11.2))
        item.echoAttenuation = 20
        // 繰り返し 3 回、尾 = 0.1 × 3 × (200 / 100) = 0.6 秒。
        XCTAssertEqual(item.contentLength, seconds(10.6))
    }

    // MARK: - FE-R15-004 分岐 (3): 再生速度変更時の比率再計算

    /// 定数速度を半分にすると、消費量を保つため長さは 2 倍になる。
    func testPlaybackRateChangeRescalesLengthByRatio() {
        let item = AudioItem()
        item.length = 300
        item.playbackRate = 50
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        )
        XCTAssertTrue(adjusted)
        XCTAssertEqual(item.length, 600)
    }

    /// 定数速度を 2 倍にすると長さは半分になる。
    func testPlaybackRateChangeHalvesLengthWhenDoubled() {
        let item = AudioItem()
        item.length = 300
        item.playbackRate = 200
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        )
        XCTAssertTrue(adjusted)
        XCTAssertEqual(item.length, 150)
    }

    /// 換算結果の小数部は切り捨てる（本家は double から int への
    /// キャスト）。100 フレームを 3 倍速にすると 33 フレーム。
    func testPlaybackRateChangeTruncatesFraction() {
        let item = AudioItem()
        item.length = 100
        item.playbackRate = 300
        XCTAssertTrue(item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        ))
        XCTAssertEqual(item.length, 33)
    }

    /// 旧速度が 0 の場合は、消費量を長さそのものとして扱う
    /// （本家の特殊分岐）。300 フレームを 50% にすると 600。
    func testPlaybackRateChangeFromZeroRateUsesLengthAsConsumed() {
        let item = AudioItem()
        item.length = 300
        item.playbackRate = 0
        item.playbackRate = 50
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 0, previousIsConstant: true, fps: 30
        )
        XCTAssertTrue(adjusted)
        XCTAssertEqual(item.length, 600)
    }

    /// 新速度が 0 の場合は長さを換算しない（符号反転も起きない
    /// ため、何も変わらない）。
    func testPlaybackRateChangeToZeroKeepsLength() {
        let item = AudioItem()
        item.length = 300
        item.playbackRate = 0
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        )
        XCTAssertFalse(adjusted)
        XCTAssertEqual(item.length, 300)
    }

    /// 換算結果が 1 未満なら既定の長さ（300）へ倒す。
    func testPlaybackRateChangeFallsBackToDefaultWhenResultBelowOne() {
        let item = AudioItem()
        item.length = 10
        item.playbackRate = 2000
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        )
        XCTAssertTrue(adjusted)
        XCTAssertEqual(item.length, BaseItem.defaultItemLength)
    }

    /// 符号が反転しない速度変更ではオフセットに触らない。
    func testPlaybackRateChangeWithoutSignFlipKeepsContentOffset() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.contentOffset = seconds(2)
        item.length = 300
        item.playbackRate = 50
        XCTAssertTrue(item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        ))
        XCTAssertEqual(item.length, 600)
        XCTAssertEqual(item.contentOffset, seconds(2))
    }

    /// 符号反転時はオフセットを素材の終端側へ付け替える:
    /// ContentLength − (ContentOffset + 長さの時間 × |旧速度| / 100)。
    /// 同じ速さの反転では長さは不変で、オフセットだけが動く。
    func testPlaybackRateChangeSignFlipReanchorsContentOffset() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.contentOffset = seconds(2)
        item.length = 300
        item.playbackRate = -100
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        )
        XCTAssertTrue(adjusted)
        XCTAssertEqual(item.length, 300)
        // 10 − (2 + 10 秒 × 100 / 100) = −2 秒（本家はクランプしない）。
        XCTAssertEqual(item.contentOffset, seconds(-2))
    }

    /// 符号反転と倍率変更が同時の場合、付け替えには新しい長さと
    /// 旧速度を使う。100% → −50%: 長さ 300 → 600、オフセットは
    /// 10 − (2 + 20 秒 × 100 / 100) = −12 秒。
    func testPlaybackRateChangeSignFlipUsesNewLengthAndOldRate() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.contentOffset = seconds(2)
        item.length = 300
        item.playbackRate = -50
        XCTAssertTrue(item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        ))
        XCTAssertEqual(item.length, 600)
        XCTAssertEqual(item.contentOffset, seconds(-12))
    }

    /// 編集開始時点で定数でなければ分岐に入らない。
    func testPlaybackRateChangeRejectedWhenPreviousNotConstant() {
        let item = AudioItem()
        item.length = 300
        item.playbackRate = 50
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: false, fps: 30
        )
        XCTAssertFalse(adjusted)
        XCTAssertEqual(item.length, 300)
    }

    /// 編集後の種別が定数でなければ分岐に入らない。
    func testPlaybackRateChangeRejectedWhenCurrentNotConstant() {
        let item = AudioItem()
        item.length = 300
        item.playbackRate2 = Animation(
            defaultValue: 50, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(50), AnimationValue(50)]
        )
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        )
        XCTAssertFalse(adjusted)
        XCTAssertEqual(item.length, 300)
    }

    /// 先頭値が変わっていなければ何もしない。
    func testPlaybackRateChangeWithSameValueDoesNothing() {
        let item = AudioItem()
        item.length = 300
        let adjusted = item.adjustLengthAfterPlaybackRateChange(
            previousFirstValue: 100, previousIsConstant: true, fps: 30
        )
        XCTAssertFalse(adjusted)
        XCTAssertEqual(item.length, 300)
    }

    // MARK: - PlaybackRateMap.findContentExhaustedTime

    /// テーブルの範囲内で尽きる場合の交点計算。
    func testFindContentExhaustedTimeWithinTable() {
        let map = PlaybackRateMap(rate: Animation(
            defaultValue: 100, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(100), AnimationValue(100)]
        ))
        let exhausted = map.findContentExhaustedTime(
            itemLength: 300, fps: 30,
            contentOffset: .zero, contentLength: seconds(5)
        )
        XCTAssertNotNil(exhausted)
        XCTAssertEqual(exhausted?.seconds ?? -1, 5, accuracy: 0.001)
    }

    /// テーブルの範囲を超える場合は末尾レートで外挿する。
    func testFindContentExhaustedTimeExtrapolatesBeyondTable() {
        let map = PlaybackRateMap(rate: Animation(
            defaultValue: 100, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(100), AnimationValue(100)]
        ))
        let exhausted = map.findContentExhaustedTime(
            itemLength: 30, fps: 30,
            contentOffset: .zero, contentLength: seconds(5)
        )
        XCTAssertNotNil(exhausted)
        XCTAssertEqual(exhausted?.seconds ?? -1, 5, accuracy: 0.001)
    }

    /// 末尾レートが 0 で範囲内に尽きなければ nil。
    func testFindContentExhaustedTimeReturnsNilWhenRateEndsAtZero() {
        let map = PlaybackRateMap(rate: Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(0)]
        ))
        let exhausted = map.findContentExhaustedTime(
            itemLength: 30, fps: 30,
            contentOffset: .zero, contentLength: seconds(5)
        )
        XCTAssertNil(exhausted)
    }
}
