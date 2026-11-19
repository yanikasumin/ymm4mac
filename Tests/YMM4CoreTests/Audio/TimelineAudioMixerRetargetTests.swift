import XCTest
@testable import YMM4Core

/// Issue #106: ミキサーの読み取り対象の差し替え（retarget）の検証。
///
/// 実時間再生では、ミキサーは編集モデルではなく映像プレビューと
/// 同じスナップショットを読む。ここでは差し替えの契約 — 内容の
/// 切り替わり、位置の保持、旧モデルへの変更の不達、シーン解決の
/// 向け直し — と、生成側が編集モデルと分離していることの構造を
/// 固定する。
final class TimelineAudioMixerRetargetTests: XCTestCase {

    private func makeMixerTimeline(items: [BaseItem]) -> Timeline {
        let timeline = Timeline()
        var info = VideoInfo()
        info.fps = 30
        info.hz = 48_000
        timeline.videoInfo = info
        timeline.items = items
        timeline.refreshTimelineLengthAndMaxLayer()
        return timeline
    }

    /// 定数音声だけのミキサーと、その供給元ファクトリ。
    private func makeFactory(_ values: [String: Float]) -> MapPCMProviderFactory {
        let factory = MapPCMProviderFactory()
        for (path, value) in values {
            factory.providers[path] = constantProvider(value, frames: 96_000)
        }
        return factory
    }

    func testRetargetSwitchesContent() {
        let factory = makeFactory(["a": 0.5, "b": 0.25])
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let timelineA = makeMixerTimeline(items: [makeAudioItem(filePath: "a", length: 60)])
        let timelineB = makeMixerTimeline(items: [makeAudioItem(filePath: "b", length: 60)])
        let mixer = TimelineAudioMixer(timeline: timelineA, factory: sourceFactory)

        var buffer = [Float](repeating: 0, count: 9_600)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 9_600), 9_600)
        XCTAssertEqual(buffer[0], 0.5, accuracy: 1e-6)

        mixer.retarget(to: timelineB, sceneTimelines: [timelineB])
        XCTAssertTrue(mixer.timeline === timelineB)
        mixer.seek(to: 0)
        // ミキサーの読み取りはバッファへの加算が契約のため、読み直し
        // の前に 0 へ戻す（本番経路の PlaybackAudioSource も窓ごとに
        // 0 埋めしてから読む）。
        buffer = [Float](repeating: 0, count: 9_600)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 9_600), 9_600)
        XCTAssertEqual(buffer[0], 0.25, accuracy: 1e-6)
        XCTAssertEqual(buffer[9_599], 0.25, accuracy: 1e-6)
    }

    func testRetargetPreservesPosition() {
        let factory = makeFactory(["a": 0.5, "b": 0.25])
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        // A は全区間 0.5。B は前半（1 秒）無音、後半 0.25。
        let timelineA = makeMixerTimeline(items: [makeAudioItem(filePath: "a", length: 60)])
        let timelineB = makeMixerTimeline(items: [
            makeAudioItem(filePath: "b", frame: 30, length: 30)
        ])
        let mixer = TimelineAudioMixer(timeline: timelineA, factory: sourceFactory)

        // A を 1 秒分読む（位置は 1 秒地点）。
        var first = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &first, offset: 0, count: 96_000), 96_000)
        XCTAssertEqual(first[0], 0.5, accuracy: 1e-6)

        mixer.retarget(to: timelineB, sceneTimelines: [timelineB])
        // 位置が保持されていれば、B の後半（0.25）が返る。位置が
        // 0 へ戻っていれば B の前半の無音が返るため区別できる。
        var second = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(mixer.read(into: &second, offset: 0, count: 96_000), 96_000)
        XCTAssertEqual(second[0], 0.25, accuracy: 1e-6)
        XCTAssertEqual(second[95_999], 0.25, accuracy: 1e-6)
    }

    func testMutatingOldTimelineAfterRetargetDoesNotAffectOutput() {
        let factory = makeFactory(["a": 0.5, "b": 0.25])
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let timelineA = makeMixerTimeline(items: [makeAudioItem(filePath: "a", length: 60)])
        let timelineB = makeMixerTimeline(items: [makeAudioItem(filePath: "b", length: 60)])
        let mixer = TimelineAudioMixer(timeline: timelineA, factory: sourceFactory)
        mixer.retarget(to: timelineB, sceneTimelines: [timelineB])

        // 差し替え後に旧タイムライン（編集モデル側に相当）をどう
        // 変更しても、生成側の出力へは届かない。
        timelineA.items = [makeAudioItem(filePath: "a", length: 60, volume: 100)]
        timelineA.layerSettings.items = [LayerSetting(layer: 0, volume: 0)]
        timelineA.items.removeAll()

        mixer.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 9_600)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 9_600), 9_600)
        XCTAssertEqual(buffer[0], 0.25, accuracy: 1e-6)
    }

    func testRetargetRepointsSceneResolution() {
        let factory = makeFactory(["a": 0.4, "b": 0.7])
        let sceneId = UUID()
        // 旧モデル集合: シーン先は 0.4 のタイムライン。
        let nestedOld = makeMixerTimeline(items: [makeAudioItem(filePath: "a", length: 30)])
        nestedOld.id = sceneId
        let sceneItemOld = SceneItem()
        sceneItemOld.sceneId = sceneId
        sceneItemOld.frame = 0
        sceneItemOld.length = 30
        sceneItemOld.volume = constantAnimation(100)
        let parentOld = makeMixerTimeline(items: [sceneItemOld])
        // 新モデル集合: 同じシーン ID で中身は 0.7。
        let nestedNew = makeMixerTimeline(items: [makeAudioItem(filePath: "b", length: 30)])
        nestedNew.id = sceneId
        let sceneItemNew = SceneItem()
        sceneItemNew.sceneId = sceneId
        sceneItemNew.frame = 0
        sceneItemNew.length = 30
        sceneItemNew.volume = constantAnimation(100)
        let parentNew = makeMixerTimeline(items: [sceneItemNew])

        let oldSet = [parentOld, nestedOld]
        let sourceFactory = AudioSourceFactory(
            providerFactory: factory,
            sceneTimelineResolver: { id in oldSet.first { $0.id == id } }
        )
        let mixer = TimelineAudioMixer(timeline: parentOld, factory: sourceFactory)
        var buffer = [Float](repeating: 0, count: 9_600)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 9_600), 9_600)
        XCTAssertEqual(buffer[0], 0.4, accuracy: 1e-6)

        // 差し替えでシーン解決も新しいモデル集合へ向く。向け直しが
        // 無ければ旧集合の 0.4 が返り続けるため区別できる。
        mixer.retarget(to: parentNew, sceneTimelines: [parentNew, nestedNew])
        mixer.seek(to: 0)
        buffer = [Float](repeating: 0, count: 9_600)
        XCTAssertEqual(mixer.read(into: &buffer, offset: 0, count: 9_600), 9_600)
        XCTAssertEqual(buffer[0], 0.7, accuracy: 1e-6)
    }

    /// 生成側（ミキサー）がスナップショットを読み続けている間に、
    /// 編集モデル側を並行して変更しても、生成が壊れず出力も
    /// スナップショットの内容のままであること。ミキサーが編集
    /// モデルを保持する形では、配列の並行変更で異常終了しうる
    /// 形状そのものである（Issue #106 の競合の再現条件）。
    func testConcurrentReadsWhileEditingSeparateLiveModel() {
        let factory = makeFactory(["a": 0.5, "b": 0.9])
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let snapshot = makeMixerTimeline(items: [makeAudioItem(filePath: "a", length: 300)])
        let liveModel = makeMixerTimeline(items: [makeAudioItem(filePath: "b", length: 300)])
        let mixer = TimelineAudioMixer(timeline: snapshot, factory: sourceFactory)

        let finished = expectation(description: "読み取りループの完了")
        let lock = NSLock()
        var mismatchedSamples = 0
        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = [Float](repeating: 0, count: 8_192)
            for _ in 0..<100 {
                mixer.seek(to: 0)
                var read = 0
                while read < 96_000 {
                    // 加算契約のため、チャンクごとに 0 へ戻してから読む。
                    for index in buffer.indices { buffer[index] = 0 }
                    let count = mixer.read(
                        into: &buffer, offset: 0, count: min(8_192, 96_000 - read)
                    )
                    if count <= 0 { break }
                    for index in 0..<count where abs(buffer[index] - 0.5) > 1e-6 {
                        lock.lock()
                        mismatchedSamples += 1
                        lock.unlock()
                    }
                    read += count
                }
            }
            finished.fulfill()
        }

        // 読み取りの裏で編集モデル側を繰り返し変更する。
        for iteration in 0..<100 {
            if iteration % 2 == 0 {
                liveModel.items = [makeAudioItem(filePath: "b", length: 300)]
            } else {
                liveModel.items = []
            }
            liveModel.layerSettings.items = [
                LayerSetting(layer: 0, volume: Double(iteration % 100))
            ]
            liveModel.refreshTimelineLengthAndMaxLayer()
        }

        wait(for: [finished], timeout: 60)
        XCTAssertEqual(mismatchedSamples, 0)
        XCTAssertTrue(mixer.timeline === snapshot)
    }
}
