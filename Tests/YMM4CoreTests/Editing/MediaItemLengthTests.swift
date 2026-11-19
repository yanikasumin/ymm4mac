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
