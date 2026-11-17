import Foundation

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
