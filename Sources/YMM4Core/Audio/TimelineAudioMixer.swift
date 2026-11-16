import Foundation

/// 音声合成グループのバス。本家 `GroupAudioBusSource` に対応する。
///
/// 内部の BusMixStream が「このバスを所有者とする区間を持つ子アイテム」
/// を開閉しながらミックスし、その後段にグループ自身の AudioEffects と
/// Resampler（Hz）が直列に掛かる。読み取りはグループの長さで
/// 打ち切られ、負位置の分は無音として数える（EffectedItemSource と同じ
/// 外周の意味論）。
public final class GroupAudioBusSource: AudioStream {
    /// 子アイテムをミックスする内部ストリーム。本家 `BusMixStream`。
    private final class BusMixStream: AudioStream {
        let group: GroupItem
        let timeline: Timeline
        let hzValue: Int
        let fps: Int
        let resolver: AudioGroupResolver
        let factory: AudioSourceFactory
        let children: [BaseItem]
        let groupStartTicks: Int64
        var resources: [(item: BaseItem, stream: AudioStream)] = []
        var mixBuffer: [Float] = []

        override var hz: Int { hzValue }
        override var duration: Int {
            AudioGroupStreamBuilder.frameDeltaToPosition(group.length, fps: fps, hz: hzValue)
        }

        init(
            group: GroupItem, timeline: Timeline, hz: Int, fps: Int,
            resolver: AudioGroupResolver, factory: AudioSourceFactory
        ) {
            self.group = group
            self.timeline = timeline
            hzValue = hz
            self.fps = fps
            self.resolver = resolver
            self.factory = factory
            children = resolver.busChildren(of: group, items: timeline.items)
            groupStartTicks = AudioStream.frameToTicks(frame: group.frame, fps: fps)
            super.init()
        }

        override func seekImpl(_ position: Int) {
            resources.removeAll()
        }

        override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
            for index in 0..<count { buffer[offset + index] = 0 }
            let start = groupStartTicks + positionToTimeTicks(position)
            let end = groupStartTicks + positionToTimeTicks(position + count)
            openCloseResources(start: start, end: end)
            if mixBuffer.count < count {
                mixBuffer = [Float](repeating: 0, count: count)
            }
            for entry in resources {
                for index in 0..<count { mixBuffer[index] = 0 }
                let readCount = entry.stream.read(into: &mixBuffer, offset: 0, count: count)
                let volume = Float(
                    timeline.layerSettings.setting(forLayer: entry.item.layer).volume / 100
                )
                for index in 0..<readCount {
                    buffer[offset + index] += mixBuffer[index] * volume
                }
            }
            return count
        }

        private func intersects(_ item: BaseItem, start: Int64, end: Int64) -> Bool {
            let itemStart = AudioStream.frameToTicks(frame: item.frame, fps: fps)
            let itemEnd = AudioStream.frameToTicks(frame: item.frame + item.length, fps: fps)
            return itemStart < end && start < itemEnd
        }

        private func openCloseResources(start: Int64, end: Int64) {
            resources.removeAll { entry in
                !timeline.items.contains { $0 === entry.item }
                    || !intersects(entry.item, start: start, end: end)
                    || entry.item.isHidden
                    || timeline.layerSettings.setting(forLayer: entry.item.layer).isHidden
            }
            for item in children {
                if item.isHidden
                    || timeline.layerSettings.setting(forLayer: item.layer).isHidden
                {
                    continue
                }
                if !intersects(item, start: start, end: end) { continue }
                if resources.contains(where: { $0.item === item }) { continue }
                let source: AudioStream
                if let childGroup = item as? GroupItem {
                    source = GroupAudioBusSource(
                        group: childGroup, timeline: timeline, hz: hzValue, fps: fps,
                        resolver: resolver, factory: factory
                    )
                } else if let effected = factory.effectedStream(
                    for: item, hz: hzValue, fps: fps
                ) {
                    source = effected
                } else {
                    continue
                }
                let wrapped = AudioGroupStreamBuilder.wrap(
                    source,
                    item: item,
                    segments: resolver.segments(for: item),
                    ownerContext: group,
                    hz: hzValue,
                    fps: fps,
                    effectProvider: factory.effectProvider
                )
                let itemStart = AudioStream.frameToTicks(frame: item.frame, fps: fps)
                wrapped.seek(to: timeToPosition(start - itemStart))
                resources.append((item: item, stream: wrapped))
            }
        }
    }

    private let effected: AudioStream
    private let busDuration: Int

    public override var hz: Int { effected.hz }
    public override var duration: Int { busDuration }

    public init(
        group: GroupItem, timeline: Timeline, hz: Int, fps: Int,
        resolver: AudioGroupResolver, factory: AudioSourceFactory
    ) {
        let busMix = BusMixStream(
            group: group, timeline: timeline, hz: hz, fps: fps,
            resolver: resolver, factory: factory
        )
        let groupDuration = TimeSpanValue(
            ticks: AudioStream.frameToTicks(frame: group.length, fps: fps)
        )
        var processors = factory.effectProvider.processors(
            for: group.audioEffects, duration: groupDuration, fps: fps
        )
        if hz != 0 {
            processors.append(ResamplerStream(toHz: hz))
        }
        var current: AudioStream = busMix
        for processor in processors {
            processor.input = current
            current = processor
        }
        effected = current
        busDuration = Int(Double(current.hz) * groupDuration.seconds) * 2
        super.init()
    }

    override func seekImpl(_ position: Int) {
        effected.seek(to: max(0, position))
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        var skipped = 0
        var readOffset = offset
        var readCount = count
        if position < 0 {
            skipped = min(count, -position)
            readCount -= skipped
            readOffset += skipped
        }
        var remaining = busDuration - position - skipped
        remaining -= remaining % 2
        readCount = max(0, min(remaining, readCount))
        return effected.read(into: &buffer, offset: readOffset, count: readCount) + skipped
    }
}

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
public final class TimelineAudioMixer: AudioStream {
    /// 対象タイムライン。
    public let timeline: Timeline
    private let factory: AudioSourceFactory
    private var resources: [(item: BaseItem, stream: AudioStream)] = []
    private var groupResolver: AudioGroupResolver?

    public init(timeline: Timeline, factory: AudioSourceFactory) {
        self.timeline = timeline
        self.factory = factory
        super.init()
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
