import XCTest
@testable import YMM4Core

/// FE-SNAP-SEPARATIONS: タイムラインの吸着への素材内部の区切り
/// （ContentSeparations）の供給の回帰テスト。
///
/// 本家の規則（逆コンパイル済みコードで確認）:
/// - 追加の吸着先（extraSnapPoints）は、他のアイテムの区切りでは
///   なくドラッグ中アイテム自身の区切りから組み立てる。使うのは
///   後端トリム（TimelineItemViewModel.ResizeFootCommand）と
///   キーフレームのドラッグ（TimelineItemKeyFrameViewModel.
///   DragDeltaCommand）だけで、移動と前端トリムは使わない。
/// - 組み立ては「正の時刻のみ → VideoInfo.GetFrameFrom でフレーム
///   換算 → アイテム内フレームが Length + delta + snapDistance
///   未満の間だけ（TakeWhile）→ Frame を加えて絶対位置」。
///
/// 数値の前提: タイムラインの FPS は既定 30。素材 10 秒・速度
/// 100%・オフセットなしの音声アイテムの区切りは [10 秒] で、
/// アイテム内フレームは 300。
final class ContentSeparationSnapPointsTests: XCTestCase {

    private func seconds(_ value: Double) -> TimeSpanValue {
        TimeSpanValue(seconds: value)
    }

    /// 素材 10 秒を持つ音声アイテム（区切りは 10 秒 = 300 フレーム）。
    private func makeAudioItem(frame: Int, length: Int) -> AudioItem {
        let item = AudioItem()
        item.recordMediaInfo(MediaFileInfo(duration: seconds(10)))
        item.frame = frame
        item.length = length
        return item
    }

    // MARK: - 供給計算

    /// 自身の区切りが、開始フレームを加えた絶対位置で候補に入る。
    func testSupplyIncludesOwnSeparationAsAbsolutePoint() {
        let timeline = Timeline()
        let item = makeAudioItem(frame: 100, length: 150)
        // 上限 = 150 + 160 + 10 = 320 > 300 なので区切りが入る
        let points = timeline.contentSeparationSnapPoints(
            for: item, frameDelta: 160, snapDistance: 10)
        XCTAssertEqual(points, [400])
    }

    /// 上限（Length + delta + snapDistance）に届かない区切りは
    /// 入らない。上限ちょうど（未満でない）も入らない。
    func testSupplyCutOffAtBound() {
        let timeline = Timeline()
        let item = makeAudioItem(frame: 100, length: 150)
        // 上限 260 < 300
        XCTAssertEqual(
            timeline.contentSeparationSnapPoints(
                for: item, frameDelta: 100, snapDistance: 10),
            [])
        // 上限 300 ちょうど: 区切りのフレーム 300 は未満でない
        XCTAssertEqual(
            timeline.contentSeparationSnapPoints(
                for: item, frameDelta: 140, snapDistance: 10),
            [])
        // 上限 301 で入る
        XCTAssertEqual(
            timeline.contentSeparationSnapPoints(
                for: item, frameDelta: 141, snapDistance: 10),
            [400])
    }

    /// ループ素材では区切りが繰り返し現れ、上限までの分だけが
    /// 入る（遅延列挙が打ち切られることの確認を兼ねる）。
    func testSupplyLoopedRepeatsUpToBound() {
        let timeline = Timeline()
        let item = makeAudioItem(frame: 0, length: 150)
        item.isLooped = true
        // 区切りは 300 / 600 / 900 / … フレーム。上限 = 150 + 500 + 10 = 660
        let points = timeline.contentSeparationSnapPoints(
            for: item, frameDelta: 500, snapDistance: 10)
        XCTAssertEqual(points, [300, 600])
    }

    /// 時刻が 0 以下になる区切りは入らない（本家の
    /// `TimeSpan.Zero < time` の絞り込み）。オフセットが素材長と
    /// 等しいと区切りは 0 秒、超えると負になる。
    func testSupplyExcludesNonPositiveTimes() {
        let timeline = Timeline()
        let item = makeAudioItem(frame: 100, length: 150)
        item.contentOffset = seconds(10)
        XCTAssertEqual(
            timeline.contentSeparationSnapPoints(
                for: item, frameDelta: 500, snapDistance: 10),
            [])
        item.contentOffset = seconds(12)
        XCTAssertEqual(
            timeline.contentSeparationSnapPoints(
                for: item, frameDelta: 500, snapDistance: 10),
            [])
        // オフセット 2 秒なら区切りは 8 秒 = 240 フレーム
        item.contentOffset = seconds(2)
        XCTAssertEqual(
            timeline.contentSeparationSnapPoints(
                for: item, frameDelta: 500, snapDistance: 10),
            [340])
    }

    /// 供給はドラッグ中アイテム自身の区切りだけであり、タイムライン
    /// 上の他アイテムの区切りは入らない。素材情報が無いアイテム
    /// （区切りが空）では供給も空になる。
    func testSupplyUsesOnlyOwnSeparations() {
        let timeline = Timeline()
        let dragged = AudioItem()
        dragged.frame = 0
        dragged.length = 150
        let other = makeAudioItem(frame: 500, length: 150)
        timeline.items = [dragged, other]
        XCTAssertEqual(
            timeline.contentSeparationSnapPoints(
                for: dragged, frameDelta: 500, snapDistance: 10),
            [])
    }

    // MARK: - 吸着計算との結合

    /// 後端トリムの形: 後端の代表点が自身の区切り位置へ吸着する。
    /// 供給が無ければ吸着しない（現在フレームは遠方に置く）。
    func testFootSnapsToOwnSeparation() {
        let timeline = Timeline()
        let item = makeAudioItem(frame: 100, length: 150)
        timeline.items = [item]
        timeline.currentFrame = 0
        let points = timeline.contentSeparationSnapPoints(
            for: item, frameDelta: 158, snapDistance: 10)
        XCTAssertEqual(points, [400])
        // 代表点 250 に +158 した 408 が、区切り 400 へ吸着する
        let delta = timeline.getSnappedDelta(
            snapTargetFrames: [250], baseLayer: 0, frameDelta: 158,
            frameDistance: 10, layerDistance: 3,
            ignoreItems: [item], extraSnapPoints: points)
        XCTAssertEqual(delta, 150)
        XCTAssertEqual(250 + delta, 400)
        // 供給が無ければ同じ移動量は吸着しない
        let unsnapped = timeline.getSnappedDelta(
            snapTargetFrames: [250], baseLayer: 0, frameDelta: 158,
            frameDistance: 10, layerDistance: 3,
            ignoreItems: [item])
        XCTAssertEqual(unsnapped, 158)
    }

    /// 区切りが候補にあっても、代表点との距離が frameDistance の
    /// 範囲外なら吸着しない。
    func testFootDoesNotSnapBeyondFrameDistance() {
        let timeline = Timeline()
        let item = makeAudioItem(frame: 100, length: 150)
        timeline.items = [item]
        timeline.currentFrame = 0
        let points = timeline.contentSeparationSnapPoints(
            for: item, frameDelta: 170, snapDistance: 10)
        XCTAssertEqual(points, [400])
        // 代表点 250 + 170 = 420 と区切り 400 の距離は 20 > 10
        let delta = timeline.getSnappedDelta(
            snapTargetFrames: [250], baseLayer: 0, frameDelta: 170,
            frameDistance: 10, layerDistance: 3,
            ignoreItems: [item], extraSnapPoints: points)
        XCTAssertEqual(delta, 170)
    }

    /// キーフレームドラッグの形: キーフレームの代表点が自身の
    /// 区切り位置へ吸着する。
    func testKeyFrameSnapsToOwnSeparation() {
        let timeline = Timeline()
        let item = makeAudioItem(frame: 100, length: 150)
        item.keyFrames = KeyFrames(frames: [100])
        timeline.items = [item]
        timeline.currentFrame = 0
        let points = timeline.contentSeparationSnapPoints(
            for: item, frameDelta: 195, snapDistance: 10)
        XCTAssertEqual(points, [400])
        // 代表点（キーフレーム絶対位置 200）に +195 した 395 が
        // 区切り 400 へ吸着する
        let delta = timeline.getSnappedDelta(
            snapTargetFrames: [200], baseLayer: 0, frameDelta: 195,
            frameDistance: 10, layerDistance: 3,
            ignoreItems: [item], extraSnapPoints: points)
        XCTAssertEqual(delta, 200)
        XCTAssertEqual(200 + delta, 400)
    }
}
