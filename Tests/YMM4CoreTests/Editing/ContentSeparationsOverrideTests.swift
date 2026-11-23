import XCTest
@testable import YMM4Core

/// シーン・ボイスアイテムの `contentSeparations` 上書き形
/// （本家 `SceneItem.cs:67` / `VoiceItem.cs:365`）のテスト。
/// 基底形・動画音声形は `ContentSeparationsTests` が担う。
final class ContentSeparationsOverrideTests: XCTestCase {

    private func seconds(_ value: Double) -> TimeSpanValue {
        TimeSpanValue(seconds: value)
    }

    /// 非定数形にするための平坦な線形速度。
    /// `ContentSeparationsTests.setFlatNonConstantRate` と同じ形。
    private func setFlatNonConstantRate(_ item: BaseItem, _ value: Double) {
        item.playbackRate2 = Animation(
            defaultValue: value, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(value), AnimationValue(value)]
        )
    }

    private func makeVoice(voiceLength: Double) -> VoiceItem {
        let item = VoiceItem()
        item.voiceLength = seconds(voiceLength)
        return item
    }

    private func makeScene(sceneLength: TimeSpanValue?) -> SceneItem {
        let item = SceneItem()
        item.sceneLengthProvider = { _ in sceneLength }
        return item
    }

    // MARK: - ボイス形: 定数

    /// 定数形の本体は (voiceLength − オフセット) / |速度| × 100。
    /// その後に追加時間（速度で割り戻さない）が付く。
    func testVoiceSeparationsConstantBodyAndAdditionalTime() {
        let item = makeVoice(voiceLength: 4)
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(4), seconds(4.3)])
        item.playbackRate = 200
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(2), seconds(2.3)])
        item.playbackRate = 100
        item.contentOffset = seconds(1)
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(3), seconds(3.3)])
        item.additionalTime = 0
        XCTAssertEqual(Array(item.contentSeparations), [seconds(3)])
    }

    /// 定数形のエコー分は本体と追加時間の間に入る。逆再生では
    /// 符号つきの尾が負になり、エコー分だけが生まれない。
    func testVoiceSeparationsConstantEcho() {
        let item = makeVoice(voiceLength: 4)
        item.echoIsEnabled = true
        // 間隔 0.1 秒・減衰 40% → 追加時間 0.6 秒。
        XCTAssertEqual(
            Array(item.contentSeparations),
            [seconds(4), seconds(4.6), seconds(4.9)])
        item.playbackRate = -100
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(4), seconds(4.3)])
    }

    /// 定数形で速度 0 の場合は区切りが生まれない。
    func testVoiceSeparationsConstantZeroRateIsEmpty() {
        let item = makeVoice(voiceLength: 4)
        item.playbackRate = 0
        XCTAssertTrue(Array(item.contentSeparations).isEmpty)
    }

    /// voiceLength が 0 でも入口ガードは本家 ContentLength の
    /// 5 秒フォールバックで通り、本体（0 秒位置）と追加時間の
    /// 区切りが生まれる。
    func testVoiceSeparationsZeroVoiceLengthUsesFiveSecondGuard() {
        let item = makeVoice(voiceLength: 0)
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(0), seconds(0.3)])
    }

    /// 入口ガードの打ち切りは実効素材長がちょうど 0 のとき
    /// だけ（本家は `ContentLength == TimeSpan.Zero` のみで
    /// yield break する）。追加時間の負値で実効素材長が負に
    /// なっても列挙は進み、本体は素材の生値から生まれる。
    func testVoiceSeparationsNegativeEffectiveContentLengthStillEnumerates() {
        let item = makeVoice(voiceLength: 4)
        item.additionalTime = -5
        XCTAssertEqual(Array(item.contentSeparations), [seconds(4)])
    }

    /// 実効素材長がちょうど 0 になる場合は打ち切る。
    func testVoiceSeparationsZeroEffectiveContentLengthIsEmpty() {
        let item = makeVoice(voiceLength: 4)
        item.additionalTime = -4
        XCTAssertTrue(Array(item.contentSeparations).isEmpty)
    }

    // MARK: - ボイス形: 非定数

    /// 非定数形は素材が尽きる時刻 → エコー分（割り戻しなし）→
    /// 追加時間の順。
    func testVoiceSeparationsNonConstantExhaustedEchoAdditional() {
        let item = makeVoice(voiceLength: 5)
        setFlatNonConstantRate(item, 100)
        item.length = 300
        item.echoIsEnabled = true
        let separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 3)
        guard separations.count == 3 else { return }
        XCTAssertEqual(separations[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(separations[1].seconds, 5.6, accuracy: 0.001)
        XCTAssertEqual(separations[2].seconds, 5.9, accuracy: 0.001)
    }

    /// 非定数形で素材がアイテム長の中で尽きない場合、本家
    /// `FindContentExhaustedTime` は末尾レートで外挿した時刻を
    /// 返すため、区切りはアイテム長の外側に生まれる（消費側が
    /// 範囲で打ち切る前提）。エコー・追加時間もその後に続く。
    func testVoiceSeparationsNonConstantExtrapolatesBeyondItemLength() {
        let item = makeVoice(voiceLength: 5)
        setFlatNonConstantRate(item, 100)
        item.length = 60
        item.echoIsEnabled = true
        let separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 3)
        guard separations.count == 3 else { return }
        XCTAssertEqual(separations[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(separations[1].seconds, 5.6, accuracy: 0.001)
        XCTAssertEqual(separations[2].seconds, 5.9, accuracy: 0.001)
    }

    /// 非定数形で尽きる時刻が得られない場合（末尾レート 0 で
    /// 外挿できない）、エコー・追加時間の区切りも生まれない
    /// （本家は尽きる時刻が有る場合の分岐内に両方を含む）。
    func testVoiceSeparationsNonConstantNoExhaustedTimeIsEmpty() {
        let item = makeVoice(voiceLength: 5)
        setFlatNonConstantRate(item, 0)
        item.length = 60
        item.echoIsEnabled = true
        XCTAssertTrue(Array(item.contentSeparations).isEmpty)
    }

    // MARK: - シーン形: 定数

    /// 定数形の本体は参照先シーンの長さで構成される
    /// （動画・音声形と同じ割り戻し）。
    func testSceneSeparationsConstantBody() {
        let item = makeScene(sceneLength: seconds(6))
        XCTAssertEqual(Array(item.contentSeparations), [seconds(6)])
        item.playbackRate = 200
        XCTAssertEqual(Array(item.contentSeparations), [seconds(3)])
        item.playbackRate = 100
        item.contentOffset = seconds(2)
        XCTAssertEqual(Array(item.contentSeparations), [seconds(4)])
    }

    /// 定数形・ループ時はシーン長の整数倍が繰り返し現れる。
    func testSceneSeparationsConstantLoopedRepeats() {
        let item = makeScene(sceneLength: seconds(6))
        item.isLooped = true
        XCTAssertEqual(
            Array(item.contentSeparations.prefix(3)),
            [seconds(6), seconds(12), seconds(18)])
    }

    /// 定数形で速度が正でなければ、エコー分も含めて区切りは
    /// 一切生まれない（動画・音声形との差。本家は符号つきで
    /// 割り戻し、速度 ≤ 0 で yield break する）。
    func testSceneSeparationsConstantNonPositiveRateIsEmpty() {
        let item = makeScene(sceneLength: seconds(6))
        item.echoIsEnabled = true
        item.playbackRate = -100
        XCTAssertTrue(Array(item.contentSeparations).isEmpty)
        item.playbackRate = 0
        XCTAssertTrue(Array(item.contentSeparations).isEmpty)
    }

    /// 定数形のエコー分は本体の後に付く。シーン長が 0 でも
    /// エコーの区切りだけは生まれる（入口ガードが本家にも無い）。
    func testSceneSeparationsConstantEchoAndZeroSceneLength() {
        let item = makeScene(sceneLength: seconds(6))
        item.echoIsEnabled = true
        XCTAssertEqual(
            Array(item.contentSeparations), [seconds(6), seconds(6.6)])

        let emptyScene = makeScene(sceneLength: nil)
        emptyScene.echoIsEnabled = true
        XCTAssertEqual(
            Array(emptyScene.contentSeparations), [seconds(0.6)])
    }

    /// 供給が無い場合はシーン長 0 として振る舞う（本家の
    /// 未登録シーンと同じ）。エコー無効なら区切りは生まれない。
    func testSceneSeparationsNoProviderDegradesToUnregistered() {
        let item = SceneItem()
        XCTAssertTrue(Array(item.contentSeparations).isEmpty)
        item.echoIsEnabled = true
        XCTAssertEqual(Array(item.contentSeparations), [seconds(0.6)])
    }

    // MARK: - シーン形: 非定数

    /// 非定数形・非ループはシーンの素材が尽きる時刻のみ。
    /// エコー有効時はその後に追加時間が付く。
    func testSceneSeparationsNonConstantExhaustedAndEcho() {
        let item = makeScene(sceneLength: seconds(5))
        setFlatNonConstantRate(item, 100)
        item.length = 300
        var separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 1)
        guard separations.count == 1 else { return }
        XCTAssertEqual(separations[0].seconds, 5, accuracy: 0.001)

        item.echoIsEnabled = true
        separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 2)
        guard separations.count == 2 else { return }
        XCTAssertEqual(separations[1].seconds, 5.6, accuracy: 0.001)
    }

    /// 非定数形・ループ時はシーン長に対する境界の横切列挙が
    /// 本体になる。アイテム長は境界が末端に一致しない 330
    /// フレームにする（動画・音声形の横切テストと同じ条件）。
    func testSceneSeparationsNonConstantLoopedUsesCrossings() {
        let item = makeScene(sceneLength: seconds(5))
        setFlatNonConstantRate(item, 100)
        item.isLooped = true
        item.length = 330
        let separations = Array(item.contentSeparations)
        XCTAssertEqual(separations.count, 2)
        guard separations.count == 2 else { return }
        XCTAssertEqual(separations[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(separations[1].seconds, 10, accuracy: 0.001)
    }

    /// 非定数形でシーン長が 0 の場合もエコーの区切りだけは
    /// 生まれる（本家は本体が無くても最後尾へ追加時間を付ける）。
    func testSceneSeparationsNonConstantZeroSceneLengthEchoOnly() {
        let item = makeScene(sceneLength: nil)
        setFlatNonConstantRate(item, 100)
        item.echoIsEnabled = true
        XCTAssertEqual(Array(item.contentSeparations), [seconds(0.6)])
    }

    /// 終端が区切り上かの判定がシーン形の区切りで働くこと
    /// （再生速度の編集終了時調整の消費先）。
    func testSceneSeparationsEndOnSeparatorJudgment() {
        let item = makeScene(sceneLength: seconds(6))
        item.length = 180
        XCTAssertTrue(item.isLengthEndOnContentSeparator(fps: 30))
        item.length = 150
        XCTAssertFalse(item.isLengthEndOnContentSeparator(fps: 30))
    }

    // MARK: - 供給継ぎ目（プロジェクト注入）

    /// プロジェクトが2つのタイムラインを持ち、一方のシーン
    /// アイテムが他方を参照する構成。長さは参照先タイムラインの
    /// キャッシュ長をその FPS で換算した値。
    private func makeProjectWithSceneItem() -> (Project, SceneItem, Timeline) {
        let sceneTimeline = Timeline()
        sceneTimeline.videoInfo.fps = 30
        let content = TextItem()
        content.frame = 0
        content.length = 180
        sceneTimeline.items = [content]
        sceneTimeline.refreshTimelineLengthAndMaxLayer()

        let sceneItem = SceneItem()
        sceneItem.sceneId = sceneTimeline.id
        let mainTimeline = Timeline()
        mainTimeline.items = [sceneItem]

        let project = Project()
        project.timelines = [mainTimeline, sceneTimeline]
        return (project, sceneItem, sceneTimeline)
    }

    /// 注入された供給はライブ参照であり、参照先シーンの長さの
    /// 変化は再注入なしで区切りへ反映される。
    func testProjectInjectionResolvesSceneLengthLive() {
        let (project, sceneItem, sceneTimeline) = makeProjectWithSceneItem()
        project.injectSceneLengthProviders()
        XCTAssertEqual(sceneItem.sceneContentLength, seconds(6))
        XCTAssertEqual(Array(sceneItem.contentSeparations), [seconds(6)])

        sceneTimeline.items[0].length = 240
        sceneTimeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(Array(sceneItem.contentSeparations), [seconds(8)])
    }

    /// アプリ層の追加経路の再現（FE-SEP-RESIDUALS）:
    /// tryAddItems で後から入ったシーンアイテムは、追加時点では
    /// 供給を持たず（未登録形）、アプリ層が確定の直後に呼ぶ
    /// 再注入で供給が行き渡る。再注入は冪等で、既存アイテムの
    /// 解決結果は変わらない。
    func testInjectionAfterAddCoversNewSceneItem() {
        let (project, sceneItem, _) = makeProjectWithSceneItem()
        let mainTimeline = project.timelines[0]
        let added = SceneItem()
        added.sceneId = sceneItem.sceneId
        XCTAssertTrue(mainTimeline.tryAddItems([added], frame: 600, layer: 0))
        // 注入前は未登録形（シーン長 0。エコー無効のため空）。
        XCTAssertTrue(Array(added.contentSeparations).isEmpty)

        project.injectSceneLengthProviders()
        XCTAssertEqual(Array(added.contentSeparations), [seconds(6)])
        XCTAssertEqual(Array(sceneItem.contentSeparations), [seconds(6)])

        // 再注入は冪等（同じ結果を返す）。
        project.injectSceneLengthProviders()
        XCTAssertEqual(Array(added.contentSeparations), [seconds(6)])
    }

    /// 分割で生まれた断片は左右とも複製（cloned）であり供給を
    /// 持たない。再注入で行き渡り、右半分の区切りはオフセット
    /// （分割位置 3 秒）を引いた 3 秒になる。
    func testInjectionAfterSplitCoversBothHalves() {
        let (project, sceneItem, _) = makeProjectWithSceneItem()
        project.injectSceneLengthProviders()
        sceneItem.length = 180
        let mainTimeline = project.timelines[0]
        mainTimeline.splitItems([sceneItem], frame: 90, mode: .both)
        let halves = mainTimeline.items.compactMap { $0 as? SceneItem }
        XCTAssertEqual(halves.count, 2)
        guard halves.count == 2 else { return }
        // 再注入までは両断片とも未登録形。
        for half in halves {
            XCTAssertTrue(Array(half.contentSeparations).isEmpty)
        }
        project.injectSceneLengthProviders()
        let left = halves.first { $0.frame == 0 }
        let right = halves.first { $0.frame == 90 }
        XCTAssertEqual(left.map { Array($0.contentSeparations) }, [seconds(6)])
        XCTAssertEqual(right.map { Array($0.contentSeparations) }, [seconds(3)])
    }

    /// 読み込み（デコード）が供給を注入すること。エンコード→
    /// デコードの往復で、デコード側のシーンアイテムの区切りが
    /// 参照先シーンの長さで構成される。
    func testCodecDecodeInjectsSceneLengthProvider() throws {
        let (project, _, _) = makeProjectWithSceneItem()
        let json = YmmpCodec.encode(project)
        let (decoded, _) = try YmmpCodec.decode(json)
        let decodedSceneItem = try XCTUnwrap(
            decoded.timelines.flatMap(\.items)
                .compactMap { $0 as? SceneItem }.first)
        XCTAssertEqual(
            Array(decodedSceneItem.contentSeparations), [seconds(6)])
    }
}
