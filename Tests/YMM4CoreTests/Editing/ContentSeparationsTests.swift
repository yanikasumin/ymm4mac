import XCTest
@testable import YMM4Core

/// FE-CONTENTSEP: コンテンツの区切り（本家 `ContentSeparations`）の
/// 供給と、それを使う編集終了時調整の分岐 (2)・エコー変更時の
/// 長さ追随の回帰テスト。
///
/// 数値の期待値は本家の実コードから導いた:
/// - 基底形（BaseItem.cs の ContentSeparations）: 定数時は
///   `-ContentOffset + ContentLength × 先頭値`（先頭値は % の数値
///   そのもの）、非定数時は素材が尽きる時刻のみ。
/// - 動画・音声形（VideoItem.cs / AudioItem.cs の上書き）: 定数時は
///   `(素材長 × (i+1) − オフセット) / |速度| × 100` の繰り返し＋
///   エコー分、非定数時は境界の横切列挙（ループ）または素材が
///   尽きる時刻＋エコー分。本体は尾なしの素材長で計算する。
/// - 境界の横切（PlaybackRateMap.EnumerateContentBoundaryCrossings）:
///   フレーム区間内の線形補間＋ティック切り捨て。
/// - 分岐 (2)（ItemEditorViewModel.EditingValue.EndEdit）: 素材長が
///   変わり、かつ編集開始時点で長さの終端が区切りの ±1 フレーム
///   以内にあれば `ResetLength`（オフセット付け替えなし）。
///   分岐 (1)（素材本来の長さの変化）が優先し、分岐 (3)（比率
///   再計算）には分岐 (2) が優先する。
final class ContentSeparationsTests: XCTestCase {

    private func seconds(_ value: Double) -> TimeSpanValue {
        TimeSpanValue(seconds: value)
    }

    /// 非定数（線形・平坦）レートの PlaybackRateMap。
    private func flatMap(_ value: Double) -> PlaybackRateMap {
        PlaybackRateMap(rate: Animation(
            defaultValue: value, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(value), AnimationValue(value)]
        ))
    }

    /// 非定数（線形・平坦）レートをアイテムへ設定する。
    private func setFlatNonConstantRate(_ item: BaseItem, _ value: Double) {
        item.playbackRate2 = Animation(
            defaultValue: value, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(value), AnimationValue(value)]
        )
    }

    // MARK: - (b) PlaybackRateMap.enumerateContentBoundaryCrossings

    /// 前進: 素材 5 秒を 100% で消費すると、境界は 5 秒間隔で
    /// アイテム時刻 5 秒・10 秒に現れる。アイテム長は境界が末端
    /// にちょうど一致しない 330 フレームにする（末端一致では
    /// 累積誤差で検出フレームが前後する。本家の累積も同じ
    /// double 演算であり、補間時刻は変わらない）。
    func testCrossingsForwardAtConstantRate() {
        let crossings = Array(flatMap(100).enumerateContentBoundaryCrossings(
            itemLength: 330, fps: 30,
            contentOffset: .zero, contentLength: seconds(5)))
        XCTAssertEqual(crossings.count, 2)
        guard crossings.count == 2 else { return }
        XCTAssertEqual(crossings[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(crossings[1].seconds, 10, accuracy: 0.001)
    }

    /// オフセットがある場合は消費の起点がずれ、境界の現れる
    /// アイテム時刻もその分ずれる（起点 2 秒 → 境界は 3 秒・8 秒）。
    func testCrossingsRespectContentOffset() {
        let crossings = Array(flatMap(100).enumerateContentBoundaryCrossings(
            itemLength: 300, fps: 30,
            contentOffset: seconds(2), contentLength: seconds(5)))
        XCTAssertEqual(crossings.count, 2)
        guard crossings.count == 2 else { return }
        XCTAssertEqual(crossings[0].seconds, 3, accuracy: 0.001)
        XCTAssertEqual(crossings[1].seconds, 8, accuracy: 0.001)
    }

    /// 逆行: 先頭レートが負なら素材末尾側から消費が始まり、
    /// 境界 0 と −素材長を横切る時刻が列挙される。
    /// アイテム長は境界が末端にちょうど一致しない 330 フレーム
    /// にする（末端一致では累積誤差で検出フレームが前後するが、
    /// 補間時刻は変わらない。本家の累積も同じ double 演算）。
    func testCrossingsBackwardAtNegativeRate() {
        let crossings = Array(flatMap(-100).enumerateContentBoundaryCrossings(
            itemLength: 330, fps: 30,
            contentOffset: .zero, contentLength: seconds(5)))
        XCTAssertEqual(crossings.count, 2)
        guard crossings.count == 2 else { return }
        XCTAssertEqual(crossings[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(crossings[1].seconds, 10, accuracy: 0.001)
    }

    /// 1フレームで複数の境界を横切る場合もすべて列挙される
    /// （100,000% では1フレームで素材 1 秒を約33回消費する。
    /// 31フレームで境界は 1,033 回）。
    func testCrossingsMultiplePerFrame() {
        let crossings = Array(flatMap(100_000).enumerateContentBoundaryCrossings(
            itemLength: 31, fps: 30,
            contentOffset: .zero, contentLength: seconds(1)))
        XCTAssertEqual(crossings.count, 1_033)
        XCTAssertEqual(crossings.first?.seconds ?? -1, 0.001, accuracy: 0.01)
        XCTAssertEqual(crossings.last?.seconds ?? -1, 1.033, accuracy: 0.01)
    }

    /// 素材長がゼロ以下、またはレートが常に 0（消費が進まない）
    /// 場合は空。
    func testCrossingsEmptyForZeroContentOrZeroRate() {
        XCTAssertTrue(Array(flatMap(100).enumerateContentBoundaryCrossings(
            itemLength: 300, fps: 30,
            contentOffset: .zero, contentLength: .zero)).isEmpty)
        XCTAssertTrue(Array(flatMap(0).enumerateContentBoundaryCrossings(
            itemLength: 300, fps: 30,
            contentOffset: .zero, contentLength: seconds(5))).isEmpty)
    }

    /// 列挙は遅延であり、先頭だけを取り出せる（長いアイテムでも
    /// 表の構築分だけで打ち切れる）。
    func testCrossingsEnumerationIsLazy() {
        let crossings = flatMap(100).enumerateContentBoundaryCrossings(
            itemLength: 1_000_000, fps: 30,
            contentOffset: .zero, contentLength: seconds(1))
        let head = Array(crossings.prefix(3))
        XCTAssertEqual(head.count, 3)
        XCTAssertEqual(head[0].seconds, 1, accuracy: 0.001)
        XCTAssertEqual(head[1].seconds, 2, accuracy: 0.001)
        XCTAssertEqual(head[2].seconds, 3, accuracy: 0.001)
    }

    // MARK: - (a) 基底形（BaseItem）

    /// 基底の定数形は本家どおり、先頭値（% の数値そのもの）を
    /// 素材長へ掛ける: −1 秒 + 2 秒 × 100 = 199 秒。
    /// 動画・音声形（|速度| で割り戻す）とは次元が異なる形を、
    /// 本家の実コードに合わせて意図的に固定する。
    func testBaseSeparationsConstantMultipliesRawPercent() {
        let item = TextItem()
        item.contentLength = seconds(2)
        item.contentOffset = seconds(1)
        XCTAssertEqual(Array(item.contentSeparations), [seconds(199)])
    }

    /// 基底の定数形は符号つきの先頭値をそのまま使う
    /// （−100% なら −200 秒）。
    func testBaseSeparationsConstantNegativeRate() {
        let item = TextItem()
        item.contentLength = seconds(2)
        item.playbackRate = -100
        XCTAssertEqual(Array(item.contentSeparations), [seconds(-200)])
    }

    /// 基底の非定数形は素材が尽きる時刻のみ。素材長がゼロなら空。
    func testBaseSeparationsNonConstantUsesExhaustedTime() {
        let item = TextItem()
        setFlatNonConstantRate(item, 100)
        item.contentLength = seconds(5)
        item.length = 300
        let separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 1)
        XCTAssertEqual(separations[0].seconds, 5, accuracy: 0.001)

        let empty = TextItem()
        setFlatNonConstantRate(empty, 100)
        XCTAssertTrue(Array(empty.contentSeparations).isEmpty)
    }

    // MARK: - (a) 動画・音声形

    /// 定数形の本体: (素材長 − オフセット) / |速度| × 100。
    func testMediaSeparationsConstantBody() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        XCTAssertEqual(Array(item.contentSeparations), [seconds(10)])
        item.playbackRate = 200
        XCTAssertEqual(Array(item.contentSeparations), [seconds(5)])
        item.playbackRate = 50
        XCTAssertEqual(Array(item.contentSeparations), [seconds(20)])
        item.playbackRate = -100
        XCTAssertEqual(Array(item.contentSeparations), [seconds(10)])
        item.playbackRate = 100
        item.contentOffset = seconds(2)
        XCTAssertEqual(Array(item.contentSeparations), [seconds(8)])
    }

    /// 定数形で速度 0 の場合は区切りが生まれない。
    func testMediaSeparationsConstantZeroRateIsEmpty() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.playbackRate = 0
        XCTAssertTrue(Array(item.contentSeparations).isEmpty)
    }

    /// 定数形・ループ時は素材長の整数倍が繰り返し現れる。
    func testMediaSeparationsConstantLoopedRepeats() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.isLooped = true
        XCTAssertEqual(
            Array(item.contentSeparations.prefix(3)),
            [seconds(10), seconds(20), seconds(30)])
    }

    /// 定数形のエコー分: 本体の後に `GetEchoLength / |速度| × 100`
    /// を加えた位置。速度 200% では尾が 1.2 秒に伸び、割り戻して
    /// 0.6 秒分になる。逆再生（−100%）では符号つきの比例で負に
    /// なり、生まれない。
    func testMediaSeparationsConstantEcho() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        // 間隔 0.1 秒・減衰 40% → 追加時間 0.6 秒。
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(10), seconds(10.6)])
        item.playbackRate = 200
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(5), seconds(5.6)])
        item.playbackRate = -100
        XCTAssertEqual(Array(item.contentSeparations), [seconds(10)])
    }

    /// 非定数形・非ループは素材が尽きる時刻のみ。エコー有効時は
    /// その後に追加時間（割り戻しなし）が付く。
    func testMediaSeparationsNonConstantExhaustedAndEcho() {
        let item = AudioItem()
        setFlatNonConstantRate(item, 100)
        item.recordMediaInfo(MediaFileInfo(duration: seconds(5)))
        item.length = 300
        var separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 1)
        guard separations.count == 1 else { return }
        XCTAssertEqual(separations[0].seconds, 5, accuracy: 0.001)

        item.echoIsEnabled = true
        separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 2)
        guard separations.count == 2 else { return }
        XCTAssertEqual(separations[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(separations[1].seconds, 5.6, accuracy: 0.001)
    }

    /// 非定数形・ループ時は境界の横切列挙が本体になる。
    /// アイテム長は境界が末端に一致しない 330 フレームにする
    /// （横切列挙の末端一致の注意は testCrossingsForwardAtConstantRate
    /// と同じ）。
    func testMediaSeparationsNonConstantLoopedUsesCrossings() {
        let item = AudioItem()
        setFlatNonConstantRate(item, 100)
        item.recordMediaInfo(MediaFileInfo(duration: seconds(5)))
        item.length = 330
        item.isLooped = true
        let separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 2)
        guard separations.count == 2 else { return }
        XCTAssertEqual(separations[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(separations[1].seconds, 10, accuracy: 0.001)
    }

    /// 素材長（尾込み）がゼロの間は、エコー設定にかかわらず
    /// 区切りは生まれない（入口ガードは尾込みの素材長）。
    func testMediaSeparationsEmptyWithoutContent() {
        let item = AudioItem()
        item.echoIsEnabled = true
        XCTAssertTrue(Array(item.contentSeparations).isEmpty)
        let video = VideoItem()
        XCTAssertTrue(Array(video.contentSeparations).isEmpty)
    }

    /// 動画アイテムも音声と同じ上書き形を使う。
    func testVideoSeparationsMatchAudioForm() {
        let item = VideoItem()
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(10), seconds(10.6)])
    }

    // MARK: - (c) 終端判定と基点の捕捉

    /// 終端判定は ±1 フレームの許容つき（本家
    /// `isLengthOnSeparator`）。区切りは 300 フレーム。
    func testLengthEndOnSeparatorTolerance() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        for (length, expected) in [(298, false), (299, true), (300, true),
                                   (301, true), (302, false)] {
            item.length = length
            XCTAssertEqual(
                item.isLengthEndOnContentSeparator(fps: 30), expected,
                "length \(length)")
        }
    }

    /// ループ時は2回目以降の区切り上でも終端と判定される。
    func testLengthEndOnSeparatorForLoopedSecondRepeat() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.isLooped = true
        item.length = 600
        XCTAssertTrue(item.isLengthEndOnContentSeparator(fps: 30))
    }

    /// 基点は編集開始時点の終端判定を保持する。
    func testBaselineCapturesSeparatorState() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        XCTAssertTrue(
            item.capturePlaybackRateEditBaseline().isLengthEndOnSeparator)
        item.length = 200
        XCTAssertFalse(
            item.capturePlaybackRateEditBaseline().isLengthEndOnSeparator)
    }

    // MARK: - 分岐 (2) の配線（finishPlaybackRateEdit）

    /// エコー有効中の速度変更では素材長が尾の再計算で変わる。
    /// 終端が区切り上にあれば分岐 (2) が発火し、分岐 (3) の
    /// 比率換算（318 × 100 / 200 = 159）ではなく、素材長の
    /// 決め直し（11.2 秒を 200% で適用 = 5.6 秒 = 168）が優先する。
    func testBranch2FiresAndPreemptsRatio() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 318)
        let baseline = item.capturePlaybackRateEditBaseline()
        item.playbackRate = 200
        XCTAssertEqual(item.contentLength, seconds(11.2))
        XCTAssertTrue(item.finishPlaybackRateEdit(baseline: baseline, fps: 30))
        XCTAssertEqual(item.length, 168)
    }

    /// 終端が区切り上に無ければ分岐 (2) は発火せず、分岐 (3) の
    /// 比率換算が走る（長さ 200 → 消費量 200 のまま 100）。
    func testBranch2SkippedWhenEndOffSeparator() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        item.length = 200
        let baseline = item.capturePlaybackRateEditBaseline()
        XCTAssertFalse(baseline.isLengthEndOnSeparator)
        item.playbackRate = 200
        XCTAssertTrue(item.finishPlaybackRateEdit(baseline: baseline, fps: 30))
        XCTAssertEqual(item.length, 100)
    }

    /// 素材長が変わらなければ（エコー無効時の速度変更）、終端が
    /// 区切り上にあっても分岐 (2) は発火せず、分岐 (3) が走る。
    func testBranch2SkippedWhenContentLengthUnchanged() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        let baseline = item.capturePlaybackRateEditBaseline()
        XCTAssertTrue(baseline.isLengthEndOnSeparator)
        item.playbackRate = 50
        XCTAssertEqual(item.contentLength, seconds(10))
        XCTAssertTrue(item.finishPlaybackRateEdit(baseline: baseline, fps: 30))
        XCTAssertEqual(item.length, 600)
    }

    /// 分岐 (1) が優先する: 編集途中でファイルが差し替われば、
    /// 分岐 (2) の条件（素材長の変化＋区切り上の終端）を満たして
    /// いても分岐 (2) は走らず、ファイル変更経路の結果が残る。
    func testBranch1PreemptsBranch2() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        let baseline = item.capturePlaybackRateEditBaseline()
        // ファイル差し替え（分岐 (1)）: 20 秒＋尾 0.6 秒 → 618。
        item.recordMediaInfo(MediaFileInfo(duration: seconds(20)))
        XCTAssertTrue(item.adjustLengthAfterFileChange(
            previousOriginalContentLength: seconds(10), fps: 30))
        XCTAssertEqual(item.length, 618)
        item.playbackRate = 200
        XCTAssertFalse(item.finishPlaybackRateEdit(baseline: baseline, fps: 30))
        XCTAssertEqual(item.length, 618)
    }

    /// 終端が区切りから +1 フレームの位置でも分岐 (2) は発火し、
    /// +2 フレームでは発火しない（±1 フレームの許容）。
    func testBranch2ToleranceOneFrame() {
        let plusOne = AudioItem()
        plusOne.echoIsEnabled = true
        plusOne.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        plusOne.resetLength(fps: 30)
        plusOne.length = 319
        let baselinePlusOne = plusOne.capturePlaybackRateEditBaseline()
        XCTAssertTrue(baselinePlusOne.isLengthEndOnSeparator)
        plusOne.playbackRate = 200
        XCTAssertTrue(plusOne.finishPlaybackRateEdit(
            baseline: baselinePlusOne, fps: 30))
        XCTAssertEqual(plusOne.length, 168)

        let plusTwo = AudioItem()
        plusTwo.echoIsEnabled = true
        plusTwo.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        plusTwo.resetLength(fps: 30)
        plusTwo.length = 320
        let baselinePlusTwo = plusTwo.capturePlaybackRateEditBaseline()
        XCTAssertFalse(baselinePlusTwo.isLengthEndOnSeparator)
        plusTwo.playbackRate = 200
        XCTAssertTrue(plusTwo.finishPlaybackRateEdit(
            baseline: baselinePlusTwo, fps: 30))
        // 分岐 (3): 320 × 100 / 200 = 160。
        XCTAssertEqual(plusTwo.length, 160)
    }

    // MARK: - エコー設定変更時の長さ追随（FE-R15-006 残件）

    /// 終端が区切り上に無ければ、エコーを有効にしても素材長だけ
    /// が変わり、長さは追随しない。
    func testEchoChangeDoesNotFollowWhenEndOffSeparator() {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        item.length = 200
        item.echoIsEnabled = true
        XCTAssertEqual(item.contentLength, seconds(10.6))
        XCTAssertEqual(item.length, 200)
    }

    /// エコー間隔の変更でも追随する（尾 0.6 秒 → 1.2 秒で
    /// 318 → 336 フレーム）。変更前のエコー値で構成した区切りで
    /// 判定するため、有効化直後の状態からでも追随が成立する。
    func testEchoIntervalChangeFollowsLength() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 318)
        item.echoInterval = 0.2
        XCTAssertEqual(item.contentLength, seconds(11.2))
        XCTAssertEqual(item.length, 336)
    }

    /// エコーを無効化すると素材長が戻り、長さも追随して戻る。
    func testEchoDisableFollowsLengthBack() {
        let item = AudioItem()
        item.echoIsEnabled = true
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        XCTAssertEqual(item.length, 318)
        item.echoIsEnabled = false
        XCTAssertEqual(item.contentLength, seconds(10))
        XCTAssertEqual(item.length, 300)
    }

    /// 動画アイテムでも同じ追随が働く。
    func testEchoChangeFollowsLengthForVideo() {
        let item = VideoItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.resetLength(fps: 30)
        item.echoIsEnabled = true
        XCTAssertEqual(item.contentLength, seconds(10.6))
        XCTAssertEqual(item.length, 318)
    }

    /// 素材が未記録（素材長ゼロ）の間は、エコーを切り替えても
    /// 長さは変わらない。
    func testEchoChangeWithoutContentDoesNotFollow() {
        let item = AudioItem()
        item.length = 300
        item.echoIsEnabled = true
        XCTAssertEqual(item.contentLength, .zero)
        XCTAssertEqual(item.length, 300)
    }
}
