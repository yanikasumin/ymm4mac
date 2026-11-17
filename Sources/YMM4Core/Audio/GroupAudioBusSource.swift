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
