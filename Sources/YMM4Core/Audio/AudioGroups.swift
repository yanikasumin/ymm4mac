import Foundation

/// アイテムの区間に対するグループ適用の区切り。
/// 本家 `AudioGroupSegment` に対応する。
///
/// アイテムの範囲をグループ境界で割った各区間について、その区間を
/// 所有する音声合成グループ（`owner`、無ければ nil = トップレベルで
/// 鳴る）と、所有グループより内側で直接かかる通常グループ
/// （`directGroups`、レイヤー降順）を保持する。
public struct AudioGroupSegment {
    public var startFrame: Int
    public var endFrame: Int
    /// 所有グループより内側の通常グループ（近い順 = レイヤー降順）。
    public var directGroups: [GroupItem]
    /// 区間を所有する音声合成グループ。nil はトップレベル所有。
    public var owner: GroupItem?

    public init(startFrame: Int, endFrame: Int, directGroups: [GroupItem], owner: GroupItem?) {
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.directGroups = directGroups
        self.owner = owner
    }
}

/// 音声グループの解決。本家 `AudioGroupResolver` に対応する。
///
/// 候補グループは「非表示でなく、レイヤーが表示中で、長さが正」の
/// GroupItem。アイテムとの親子は映像側のグループ解決と同じ規則
/// （レイヤー範囲と Group 番号）で、祖先方向へ辿る。
public final class AudioGroupResolver {
    private let candidateGroups: [GroupItem]
    private let isLayerVisible: (Int) -> Bool
    private var segmentsCache: [ObjectIdentifier: [AudioGroupSegment]] = [:]

    public init(items: [BaseItem], isLayerVisible: @escaping (Int) -> Bool) {
        candidateGroups = items.compactMap { $0 as? GroupItem }.filter {
            !$0.isHidden && isLayerVisible($0.layer) && $0.length > 0
        }
        self.isLayerVisible = isLayerVisible
    }

    /// 音声グループが1つも無いか。本家 `HasNoAudioGroups`。
    ///
    /// 本家は「音声合成グループ、または有効な AudioEffects を持つ
    /// グループ」の存在で判定する。モデル層の AudioEffects は生 JSON
    /// のため、有効判定は JSON の `IsEnabled`（欠落時は有効扱い）で
    /// 代替する近似である（台帳に記録）。
    public var hasNoAudioGroups: Bool {
        !candidateGroups.contains { group in
            group.isAudioComposite
                || group.audioEffects.contains { effect in
                    effect.value.field("IsEnabled")?.boolValue ?? true
                }
        }
    }

    /// アイテムのグループ区間列（キャッシュする）。
    public func segments(for item: BaseItem) -> [AudioGroupSegment] {
        let key = ObjectIdentifier(item)
        if let cached = segmentsCache[key] { return cached }
        let computed = computeSegments(for: item)
        segmentsCache[key] = computed
        return computed
    }

    /// バスの子になるアイテム（レイヤー昇順）。本家 `GetBusChildren`。
    public func busChildren(of bus: GroupItem, items: [BaseItem]) -> [BaseItem] {
        items.filter { item in
            (item is AudioItemProperties
                || (item as? GroupItem)?.isAudioComposite == true)
                && !item.isHidden
                && isLayerVisible(item.layer)
                && segments(for: item).contains { $0.owner === bus }
        }
        .sorted { $0.layer < $1.layer }
    }

    // MARK: - 区間の算出（本家 ComputeSegments）

    private func computeSegments(for item: BaseItem) -> [AudioGroupSegment] {
        let frame = item.frame
        let endFrame = item.frame + item.length
        let relevantGroups = relevantGroups(for: item)
        var boundaries: Set<Int> = [frame, endFrame]
        for group in relevantGroups {
            if frame < group.frame && group.frame < endFrame {
                boundaries.insert(group.frame)
            }
            let groupEnd = group.frame + group.length
            if frame < groupEnd && groupEnd < endFrame {
                boundaries.insert(groupEnd)
            }
        }
        let sortedBoundaries = boundaries.sorted()
        var segments: [AudioGroupSegment] = []
        for index in 0..<(sortedBoundaries.count - 1) {
            let start = sortedBoundaries[index]
            let segmentEnd = sortedBoundaries[index + 1]
            let containing = relevantGroups.filter { $0.contains(frame: start) }
            let ordered = distinctByIdentity(parentsAndGrandparents(of: item, in: containing))
                .sorted { $0.layer > $1.layer }
            let directGroups = Array(ordered.prefix(while: { !$0.isAudioComposite }))
            let owner = ordered.first(where: { $0.isAudioComposite })
            if let last = segments.last,
               last.owner === owner,
               last.directGroups.count == directGroups.count,
               zip(last.directGroups, directGroups).allSatisfy({ pair in pair.0 === pair.1 })
            {
                segments[segments.count - 1].endFrame = segmentEnd
                continue
            }
            segments.append(
                AudioGroupSegment(
                    startFrame: start, endFrame: segmentEnd,
                    directGroups: directGroups, owner: owner
                )
            )
        }
        return segments
    }

    /// アイテムに関係するグループ（親→祖先へ辿って到達できるもの）。
    /// 本家 `GetRelevantGroups` の frontier 展開。
    private func relevantGroups(for item: BaseItem) -> [GroupItem] {
        var remaining = candidateGroups.filter {
            $0.intersectsWith(frame: item.frame, length: item.length)
        }
        var relevant: [GroupItem] = []
        var frontier: [BaseItem] = [item]
        while !frontier.isEmpty && !remaining.isEmpty {
            let parents = remaining.filter { group in
                frontier.contains { AudioGroupResolver.canBeParent(group, of: $0) }
            }
            if parents.isEmpty { break }
            remaining.removeAll { candidate in parents.contains { $0 === candidate } }
            relevant += parents
            frontier = parents
        }
        return relevant
    }

    /// 親と祖先を列挙する。本家 `GetParentsAndGrandparents`。
    private func parentsAndGrandparents(
        of item: BaseItem, in groups: [GroupItem]
    ) -> [GroupItem] {
        let parents = groups.filter { AudioGroupResolver.canBeParent($0, of: item) }
        var result = parents
        let rest = groups.filter { candidate in !parents.contains { $0 === candidate } }
        for parent in parents {
            result += parentsAndGrandparents(of: parent, in: rest)
        }
        return result
    }

    /// グループがアイテムの親になれるか。本家 `CanBeParent`。
    static func canBeParent(_ group: GroupItem, of item: BaseItem) -> Bool {
        if group === item { return false }
        if group.isGroupOnly && !(group.group != 0 && group.group == item.group) {
            return false
        }
        return group.layer < item.layer && item.layer <= group.layer + group.groupRange
    }

    private func distinctByIdentity(_ groups: [GroupItem]) -> [GroupItem] {
        var seen: Set<ObjectIdentifier> = []
        return groups.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}

/// グループ適用の組み立て。本家 `AudioGroupStreamBuilder` に対応する。
public enum AudioGroupStreamBuilder {
    /// フレーム差をサンプル位置へ換算する。本家 `FrameDeltaToPosition`。
    /// 符号は絶対値で換算してから付ける。位置は偶数へ切り捨てる。
    public static func frameDeltaToPosition(_ frames: Int, fps: Int, hz: Int) -> Int {
        let sign = frames >= 0 ? 1 : -1
        let ticks = AudioStream.frameToTicks(frame: abs(frames), fps: fps)
        var position = ticks * Int64(AudioStream.channelCount * hz) / 10_000_000
        position -= position % 2
        return sign * Int(position)
    }

    /// アイテムのストリームへグループ適用を被せる。本家 `Wrap`。
    ///
    /// - 他の所有者に属する区間がある場合、その所有者の文脈で鳴るべき
    ///   区間だけを通す SegmentGate を被せる。
    /// - この文脈（`ownerContext`）に属する区間では、直接グループ
    ///   （レイヤー降順）ごとに、そのグループが直接かかる窓だけへ
    ///   グループの AudioEffects チェーン（+ Resampler）を適用する。
    ///   グループに有効なエフェクトが無ければチェーン自体を挿入しない
    ///   （本家どおり）。
    public static func wrap(
        _ source: AudioStream,
        item: BaseItem,
        segments: [AudioGroupSegment],
        ownerContext: GroupItem?,
        hz: Int,
        fps: Int,
        effectProvider: any AudioEffectProvider
    ) -> AudioStream {
        var result = source
        if segments.contains(where: { $0.owner !== ownerContext }) {
            let allowed = mergeRanges(
                segments
                    .filter { $0.owner === ownerContext }
                    .map {
                        (
                            start: frameDeltaToPosition(
                                $0.startFrame - item.frame, fps: fps, hz: hz
                            ),
                            end: frameDeltaToPosition(
                                $0.endFrame - item.frame, fps: fps, hz: hz
                            )
                        )
                    }
            )
            result = SegmentGateStream(input: result, allowedRanges: allowed)
        }
        var directGroups: [GroupItem] = []
        for segment in segments where segment.owner === ownerContext {
            for group in segment.directGroups
            where !directGroups.contains(where: { $0 === group }) {
                directGroups.append(group)
            }
        }
        directGroups.sort { $0.layer > $1.layer }
        for group in directGroups {
            let windows = mergeRanges(
                segments
                    .filter {
                        $0.owner === ownerContext
                            && $0.directGroups.contains { $0 === group }
                    }
                    .map {
                        (
                            start: frameDeltaToPosition(
                                $0.startFrame - item.frame, fps: fps, hz: hz
                            ),
                            end: frameDeltaToPosition(
                                $0.endFrame - item.frame, fps: fps, hz: hz
                            )
                        )
                    }
            )
            if windows.isEmpty { continue }
            let groupDuration = TimeSpanValue(
                ticks: AudioStream.frameToTicks(frame: group.length, fps: fps)
            )
            var processors = effectProvider.processors(
                for: group.audioEffects, duration: groupDuration, fps: fps
            )
            if processors.isEmpty { continue }
            if hz != 0 {
                processors.append(ResamplerStream(toHz: hz))
            }
            let positionOffset = frameDeltaToPosition(
                item.frame - group.frame, fps: fps, hz: hz
            )
            result = GroupEffectChainStream(
                input: result,
                processors: processors,
                windows: windows,
                positionOffset: positionOffset
            )
        }
        return result
    }

    /// 区間列をソートし、重なり・隣接を結合する。本家 `MergeRanges`。
    static func mergeRanges(
        _ ranges: [(start: Int, end: Int)]
    ) -> [(start: Int, end: Int)] {
        var merged: [(start: Int, end: Int)] = []
        for range in ranges.filter({ $0.start < $0.end }).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, last.end >= range.start {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
