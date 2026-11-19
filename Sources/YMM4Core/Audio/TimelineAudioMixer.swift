import Foundation

/// タイムライン全体の音声ミックス。本家 `TimelineSource`
/// （Player.Audio）に対応する。
///
/// 意味論（本家どおり）:
/// - `hz` はタイムラインの `VideoInfo.Hz`。長さはタイムライン長を
///   サンプルへ換算したもの。
/// - 読み取りのたびに、読み取り区間と交差するアイテムの資源を開閉
///   する。対象は音声アイテムと音声合成グループで、非表示アイテム・
///   非表示レイヤーは除外する。グループに全区間を所有されている
///   アイテムはトップレベルでは開かない（バス側で鳴る）。
/// - 各資源を個別に読み、レイヤー音量（LayerSettings の Volume / 100）
///   を掛けて出力へ **float 加算**する。ミックス段にリミッターは無い。
/// - 読み取り数はタイムライン長で打ち切られる。出力バッファへの
///   加算先は呼び出し側が 0 初期化している前提（本家の慣行）。
/// - シークは全資源を破棄して作り直す（本家どおり）。
///
/// 本家との内部差: 本家は資源の読み取りを Parallel.ForEach で並列化し
/// Interlocked で加算するが、ここでは逐次に加算する（結果は同じ）。
/// 資源ごとの読み取りバッファも本家は使い回すが、ここでは読み取り
/// ごとに確保する（意味論に影響しない内部差）。
///
/// モデルの所有（Issue #106）: 読み取り対象のタイムラインは
/// `retarget(to:sceneTimelines:)` で差し替えられる。実時間再生では
/// 編集モデルではなく、映像プレビューと同じスナップショット
/// （`Project.makeExportSnapshot` の専有複製）を渡す運用とし、生成側
/// （チャンク生成キュー）が編集中のモデルを直接読まない構造にする。
/// 差し替えは読み取り・シークと直列化された状態で呼ぶこと（再生側は
/// 供給ロックの保持中に行う）。差し替え前のタイムラインから開いた
/// 資源は全て破棄され、読み取り位置は保持される。
public final class TimelineAudioMixer: AudioStream {
    /// 対象タイムライン。`retarget` で差し替わる。
    public private(set) var timeline: Timeline
    private let factory: AudioSourceFactory
    private var resources: [(item: BaseItem, stream: AudioStream)] = []
    private var groupResolver: AudioGroupResolver?

    public init(timeline: Timeline, factory: AudioSourceFactory) {
        self.timeline = timeline
        self.factory = factory
        super.init()
    }

    /// 読み取り対象のタイムラインを差し替える（Issue #106）。
    ///
    /// 開いている資源とグループ解決は旧タイムライン前提のため全て
    /// 破棄し、次の読み取りで新しいタイムラインから開き直す。工場の
    /// シーン解決も、差し替え先と同じモデル集合（スナップショットの
    /// タイムライン群）へ向け直す — 解決が編集モデルへ戻ると、
    /// SceneItem の音声だけが生モデルを読み続けてしまうためである。
    /// 読み取り位置（`position`）は保持する。シークではないので、
    /// 呼び出し側が蓄積側（リングバッファ等）の破棄を担う。
    public func retarget(to newTimeline: Timeline, sceneTimelines: [Timeline]) {
        timeline = newTimeline
        factory.sceneTimelineResolver = { id in
            sceneTimelines.first { $0.id == id }
        }
        resources.removeAll()
        groupResolver = nil
    }

    private var fps: Int { timeline.videoInfo.fps }

    public override var hz: Int { timeline.videoInfo.hz }

    public override var duration: Int {
        timeToPosition(AudioStream.frameToTicks(frame: timeline.length, fps: fps))
    }

    override func seekImpl(_ position: Int) {
        resources.removeAll()
        groupResolver = nil
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        let start = positionToTimeTicks(position)
        let end = positionToTimeTicks(position + count)
        openCloseResources(start: start, end: end)
        return readResources(&buffer, offset: offset, count: count)
    }

    private func resolver() -> AudioGroupResolver {
        if let groupResolver { return groupResolver }
        let created = AudioGroupResolver(items: timeline.items) { layer in
            !self.timeline.layerSettings.setting(forLayer: layer).isHidden
        }
        groupResolver = created
        return created
    }

    private func intersects(_ item: BaseItem, start: Int64, end: Int64) -> Bool {
        let itemStart = AudioStream.frameToTicks(frame: item.frame, fps: fps)
        let itemEnd = AudioStream.frameToTicks(frame: item.frame + item.length, fps: fps)
        return itemStart < end && start < itemEnd
    }

    private func openCloseResources(start: Int64, end: Int64) {
        let resolver = resolver()
        resources.removeAll { entry in
            !timeline.items.contains { $0 === entry.item }
                || !intersects(entry.item, start: start, end: end)
                || entry.item.isHidden
                || timeline.layerSettings.setting(forLayer: entry.item.layer).isHidden
        }
        for item in timeline.items {
            let isAudioItem = item is AudioItemProperties
            let isBus = (item as? GroupItem)?.isAudioComposite == true
            if !isAudioItem && !isBus { continue }
            if item.isHidden
                || timeline.layerSettings.setting(forLayer: item.layer).isHidden
            {
                continue
            }
            if !intersects(item, start: start, end: end) { continue }
            let segments = resolver.segments(for: item)
            if !segments.isEmpty && !segments.contains(where: { $0.owner == nil }) {
                continue
            }
            if resources.contains(where: { $0.item === item }) { continue }
            let stream = createResource(for: item, resolver: resolver)
            let itemStart = AudioStream.frameToTicks(frame: item.frame, fps: fps)
            stream.seek(to: timeToPosition(start - itemStart))
            resources.append((item: item, stream: stream))
        }
    }

    private func createResource(for item: BaseItem, resolver: AudioGroupResolver) -> AudioStream {
        let base: AudioStream
        if let group = item as? GroupItem {
            base = GroupAudioBusSource(
                group: group, timeline: timeline, hz: hz, fps: fps,
                resolver: resolver, factory: factory
            )
        } else if let effected = factory.effectedStream(for: item, hz: hz, fps: fps) {
            base = effected
        } else {
            return FileAudioStream(provider: nil)
        }
        if resolver.hasNoAudioGroups { return base }
        return AudioGroupStreamBuilder.wrap(
            base,
            item: item,
            segments: resolver.segments(for: item),
            ownerContext: nil,
            hz: hz,
            fps: fps,
            effectProvider: factory.effectProvider
        )
    }

    private func readResources(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        let clamped = max(0, min(duration - position, count))
        for entry in resources {
            var itemBuffer = [Float](repeating: 0, count: clamped)
            let readCount = entry.stream.read(into: &itemBuffer, offset: 0, count: clamped)
            let volume = Float(
                timeline.layerSettings.setting(forLayer: entry.item.layer).volume / 100
            )
            for index in 0..<readCount {
                buffer[offset + index] += itemBuffer[index] * volume
            }
        }
        return clamped
    }
}
