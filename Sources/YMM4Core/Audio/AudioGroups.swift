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

/// 区間が属する窓を探す（本家 SegmentGate / GroupEffectChain の FindWindow）。
func findWindow(in windows: [(start: Int, end: Int)], at position: Int) -> (start: Int, end: Int)? {
    for window in windows {
        if position < window.start { return nil }
        if position < window.end { return window }
    }
    return nil
}

/// 次の窓の開始位置（無ければ Int.max）。本家 `NextRangeStart`。
func nextWindowStart(in windows: [(start: Int, end: Int)], after position: Int) -> Int {
    for window in windows where position < window.start {
        return window.start
    }
    return Int.max
}

/// 許可区間以外を無音化するゲート。本家 `SegmentGateEffect` に対応する。
///
/// 許可区間内は入力を読み、区間外は 0 で埋めて読み進める（この処理器は
/// 自前で 0 埋めする）。入力が区間途中で枯れた場合は残りを 0 で埋める。
/// シークは、許可区間内なら入力へ転送し、外なら「未同期」として
/// 次の読み取りで区間開始へ合わせる。
public final class SegmentGateStream: AudioEffectProcessorBase {
    /// 許可区間（サンプル位置、ソート済み・重なりなし）。
    public let allowedRanges: [(start: Int, end: Int)]
    private var isInputSynced = false

    public init(input: AudioStream, allowedRanges: [(start: Int, end: Int)]) {
        self.allowedRanges = allowedRanges
            .filter { $0.start < $0.end }
            .sorted { $0.start < $1.start }
        super.init()
        self.input = input
    }

    override func seekImpl(_ position: Int) {
        if findWindow(in: allowedRanges, at: position) != nil {
            input?.seek(to: position)
            isInputSynced = true
        } else {
            isInputSynced = false
        }
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input else {
            for index in 0..<count { buffer[offset + index] = 0 }
            return count
        }
        var written = 0
        while written < count {
            let currentPosition = position + written
            let remaining = count - written
            if let range = findWindow(in: allowedRanges, at: currentPosition) {
                let chunk = min(remaining, range.end - currentPosition)
                if !isInputSynced {
                    input.seek(to: currentPosition)
                    isInputSynced = true
                }
                let readCount = readFully(
                    input, into: &buffer, offset: offset + written, count: chunk
                )
                written += readCount
                if readCount < chunk {
                    let silence = chunk - readCount
                    for index in 0..<silence { buffer[offset + written + index] = 0 }
                    written += silence
                    isInputSynced = false
                }
            } else {
                let next = nextWindowStart(in: allowedRanges, after: currentPosition)
                let gap = next == Int.max ? remaining : min(remaining, next - currentPosition)
                for index in 0..<gap { buffer[offset + written + index] = 0 }
                written += gap
                isInputSynced = false
            }
        }
        return written
    }
}

/// グループのエフェクトを、そのグループが直接かかる区間だけに適用する
/// チェーン。本家 `GroupEffectChainEffect` に対応する。
///
/// 窓の外は入力を素通しし、窓の中は「位置オフセット分ずらした入力を
/// エフェクトチェーンへ通したもの」を読む。オフセットは
/// アイテム位置 − グループ位置で、エフェクト側の評価位置が
/// グループ基準になる（本家の PositionShiftStream の役割）。
public final class GroupEffectChainStream: AudioEffectProcessorBase {
    /// 入力位置をずらすだけの内部ストリーム。本家 `PositionShiftStream`。
    private final class PositionShiftStream: AudioEffectProcessorBase {
        let positionOffset: Int

        init(positionOffset: Int) {
            self.positionOffset = positionOffset
            super.init()
        }

        override var duration: Int {
            guard let input else { return 0 }
            if input.duration == Int.max { return Int.max }
            return input.duration + positionOffset
        }

        override func seekImpl(_ position: Int) {
            input?.seek(to: position - positionOffset)
        }

        override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
            input?.read(into: &buffer, offset: offset, count: count) ?? 0
        }
    }

    /// 適用窓（サンプル位置、ソート済み）。
    public let windows: [(start: Int, end: Int)]
    /// 位置オフセット（アイテム位置 − グループ位置、サンプル）。
    public let positionOffset: Int
    private let chain: AudioStream
    private let shiftedInput: PositionShiftStream
    private var isChainSynced = false
    private var isInputSynced = false

    public init(
        input: AudioStream,
        processors: [AudioEffectProcessorBase],
        windows: [(start: Int, end: Int)],
        positionOffset: Int
    ) {
        self.windows = windows
            .filter { $0.start < $0.end }
            .sorted { $0.start < $1.start }
        self.positionOffset = positionOffset
        let shifted = PositionShiftStream(positionOffset: positionOffset)
        shiftedInput = shifted
        var current: AudioStream = shifted
        for processor in processors {
            processor.input = current
            current = processor
        }
        chain = current
        super.init()
        self.input = input
        shifted.input = input
    }

    override func seekImpl(_ position: Int) {
        if findWindow(in: windows, at: position) != nil {
            chain.seek(to: position + positionOffset)
            isChainSynced = true
            isInputSynced = false
        } else {
            input?.seek(to: position)
            isInputSynced = true
            isChainSynced = false
        }
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input else {
            for index in 0..<count { buffer[offset + index] = 0 }
            return count
        }
        var written = 0
        while written < count {
            let currentPosition = position + written
            let remaining = count - written
            if let window = findWindow(in: windows, at: currentPosition) {
                let chunk = min(remaining, window.end - currentPosition)
                if !isChainSynced {
                    chain.seek(to: currentPosition + positionOffset)
                    isChainSynced = true
                    isInputSynced = false
                }
                let readCount = readFully(
                    chain, into: &buffer, offset: offset + written, count: chunk
                )
                written += readCount
                if readCount < chunk {
                    let silence = chunk - readCount
                    for index in 0..<silence { buffer[offset + written + index] = 0 }
                    written += silence
                    isChainSynced = false
                }
            } else {
                let next = nextWindowStart(in: windows, after: currentPosition)
                let span = next == Int.max ? remaining : min(remaining, next - currentPosition)
                if !isInputSynced {
                    input.seek(to: currentPosition)
                    isInputSynced = true
                    isChainSynced = false
                }
                let readCount = readFully(
                    input, into: &buffer, offset: offset + written, count: span
                )
                written += readCount
                if readCount < span {
                    let silence = span - readCount
                    for index in 0..<silence { buffer[offset + written + index] = 0 }
                    written += silence
                    isInputSynced = false
                }
            }
        }
        return written
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
