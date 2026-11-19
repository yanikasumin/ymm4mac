import Foundation

/// 音声エフェクト処理器の基底。本家 `AudioEffectProcessorBase` /
/// `EffectBase` に対応する。
///
/// 処理器は `input` への代入で前段と直列に接続されるデコレータであり、
/// 自身も `AudioStream` として振る舞う（本家 `IAudioEffectProcessor :
/// IAudioStream`）。`hz` / `duration` の既定は入力への委譲で、変換を
/// 伴う処理器（リサンプラ等）が上書きする。
public class AudioEffectProcessorBase: AudioStream {
    /// 前段のストリーム。所有はこの処理器が持つ（チェーンの保持）。
    public var input: AudioStream?

    public override var hz: Int { input?.hz ?? 0 }
    public override var duration: Int { input?.duration ?? 0 }
}

/// 入力を読み取ってから同じバッファへ加工を適用する処理器の基底。
/// 本家 `SimpleEffectBase` に対応する。
///
/// 本家の意味論: `read` は入力の読み取りを先に行い、その戻り値に
/// かかわらず要求 `count` 全体へ `Process` を適用する（末尾の無音部も
/// 加工対象）。`seek` は入力へそのまま転送する。`Process` から見た
/// `position` はこの処理器自身の読み取り開始位置。
public class SimpleAudioEffectProcessorBase: AudioEffectProcessorBase {
    override func seekImpl(_ position: Int) {
        input?.seek(to: position)
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        let readCount = input?.read(into: &buffer, offset: offset, count: count) ?? 0
        process(&buffer, offset: offset, count: count)
        return readCount
    }

    /// 読み取り済みバッファへの加工。サブクラスが上書きする。
    func process(_ buffer: inout [Float], offset: Int, count: Int) {}
}

/// 負位置へのシークを可能にする処理器。本家
/// `NegativeSeekableAudioStreamEffect` に対応する。チェーンの先頭に
/// 常時挿入される。
///
/// 意味論（本家どおり）: シーク時は入力へ `max(0, position)` を転送し、
/// 負の分は読み取り時に「読み飛ばし」として数える（バッファには
/// 書かない。呼び出し側の 0 初期化が無音になる）。負分の消費は
/// この処理器が自前の仮想位置で数える。
public final class NegativeSeekableAudioStream: AudioEffectProcessorBase {
    private var virtualPosition: Int = 0

    override func seekImpl(_ position: Int) {
        virtualPosition = position
        input?.seek(to: max(0, position))
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        var skipped = 0
        if virtualPosition < 0 {
            skipped = min(count, -virtualPosition)
            virtualPosition += skipped
        }
        let readCount = input?.read(
            into: &buffer, offset: offset + skipped, count: count - skipped
        ) ?? 0
        return readCount + skipped
    }
}

/// 素材の開始位置オフセット。本家 `ContentOffsetEffect` に対応する。
///
/// シーク位置へオフセット分を加えて入力へ転送し、長さからオフセット
/// 分を引く（0 未満にはならない）。読み取り自体は素通し。
public final class ContentOffsetAudioStream: SimpleAudioEffectProcessorBase {
    /// オフセット（素材側の時刻）。
    public let contentOffset: TimeSpanValue

    public init(contentOffset: TimeSpanValue) {
        self.contentOffset = contentOffset
        super.init()
    }

    public override var duration: Int {
        max((input?.duration ?? 0) - timeToPosition(contentOffset.ticks), 0)
    }

    override func seekImpl(_ position: Int) {
        input?.seek(to: timeToPosition(contentOffset.ticks) + position)
    }
}

/// ループ再生。本家 `LoopEffect` に対応する。
///
/// 有効時は長さが無制限になり、入力が尽きるたび先頭へ戻って読み続ける。
/// シーク位置は入力の長さで剰余を取る。入力の長さが 0 の場合は常に 0 を
/// 返す。本家の `read` は巻き戻しに自身の `Seek(0)` を使うため、巻き戻し
/// を含む読み取りの後はこの処理器の `position` が「戻り値の累積」と
/// 一致する（開始位置を含まない）。本家どおりの挙動として再現する。
public final class LoopAudioStream: SimpleAudioEffectProcessorBase {
    /// ループが有効か。
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        super.init()
    }

    public override var duration: Int {
        if !isEnabled { return input?.duration ?? 0 }
        return Int.max
    }

    override func seekImpl(_ position: Int) {
        var target = position
        if isEnabled, let input, input.duration > 0 {
            target = position % input.duration
        }
        input?.seek(to: target)
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input, input.duration != 0 else { return 0 }
        var total = 0
        var previousTotal = 0
        var hasWrapped = false
        while true {
            // SimpleEffectBase 経由の読み取り（Process は無加工）。
            let readCount = input.read(
                into: &buffer, offset: offset + total, count: count - total
            )
            process(&buffer, offset: offset + total, count: count - total)
            total += readCount
            if !isEnabled { return total }
            if total == count { return total }
            if hasWrapped && total == previousTotal { break }
            previousTotal = total
            hasWrapped = true
            seek(to: 0)
        }
        return total
    }
}

/// 逆再生。本家 `ReverseStreamEffect` に対応する。
///
/// 1 秒分のブロック単位で入力を後方へ読み、各ブロック内を
/// フレーム単位で反転して供給する（チャンネルは入れ替えない）。
/// シーク時は「末尾から position だけ手前」が読み取り開始点になる。
public final class ReverseAudioStream: AudioEffectProcessorBase {
    private var buffer: [Float] = []
    private var bufferIndex: Int = 0
    private var bufferLength: Int = 0
    private var currentPosition: Int = 0

    override func seekImpl(_ position: Int) {
        currentPosition = position >= duration ? 0 : duration - position
        bufferIndex = 0
        bufferLength = 0
    }

    override func readImpl(_ destBuffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input else { return 0 }
        var total = 0
        while total < count {
            if buffer.count != input.hz * 2 {
                buffer = [Float](repeating: 0, count: max(input.hz * 2, 0))
            }
            if bufferIndex == bufferLength {
                bufferIndex = 0
                let blockStart = max(0, currentPosition - buffer.count)
                let blockCount = min(buffer.count, max(0, currentPosition - blockStart))
                input.seek(to: blockStart)
                bufferLength = input.read(into: &buffer, offset: 0, count: blockCount)
                currentPosition -= bufferLength
                if bufferLength == 0 { break }
            }
            let copyCount = min(count - total, bufferLength - bufferIndex)
            for index in 0..<copyCount {
                if index % 2 == 0 {
                    destBuffer[offset + total + index] =
                        buffer[bufferLength - (bufferIndex + index) - 2]
                } else {
                    destBuffer[offset + total + index] =
                        buffer[bufferLength - (bufferIndex + index)]
                }
            }
            total += copyCount
            bufferIndex += copyCount
        }
        return total
    }
}

/// エコー。本家 `EchoEffect` に対応する。
///
/// 間隔分のリングバッファを持ち、「入力 + 前バッファ × 減衰」を次の
/// バッファとして繰り返すフィードバック型。繰り返し回数は減衰後の
/// 振幅が 1% を切る回数（上限 50）で、長さはその分だけ延びる。
/// シーク時は経過分のバッファを先行生成して状態を再現する。
public final class EchoAudioStream: AudioEffectProcessorBase {
    /// エコーの間隔。
    public let interval: TimeSpanValue
    /// 減衰率（0..1 の倍率）。
    public let attenuation: Double
    /// 繰り返し回数。本家: `min(50, ceil(log(0.01) / log(attenuation)))`。
    public let repeatCount: Int

    private var cachedBufferLength: Int?
    private var currentBuffer: [Float]?
    private var currentBufferIndex: Int = 0

    public init(interval: TimeSpanValue, attenuation: Double) {
        self.interval = interval
        self.attenuation = attenuation
        repeatCount = Self.repeatCount(attenuation: attenuation)
        super.init()
    }

    /// 繰り返し回数。本家 `EchoEffect` のコンストラクタの式。
    /// 減衰 0 以下では繰り返さず、1 以上では上限へ倒す（本家の式は
    /// 対数の定義域外で不定になるため、境界はこの形で確定させている）。
    public static func repeatCount(attenuation: Double) -> Int {
        if attenuation <= 0 {
            return 0
        } else if attenuation >= 1 {
            return 50
        }
        return min(50, Int(ceil(log(0.01) / log(attenuation))))
    }

    /// エコーで延びる時間。本家 `EchoEffect.AdditionalDuration`
    /// （間隔 × 繰り返し回数）。素材の長さ（ContentLength）の尾の
    /// 計算でも使う。
    public static func additionalDuration(
        interval: TimeSpanValue, attenuation: Double
    ) -> TimeSpanValue {
        TimeSpanValue(ticks: interval.ticks * Int64(repeatCount(attenuation: attenuation)))
    }

    /// 間隔分のサンプル数。本家 `BufferLength`（遅延評価）。
    private var bufferLength: Int {
        if let cachedBufferLength { return cachedBufferLength }
        let length = max(timeToPosition(interval.ticks), 1)
        cachedBufferLength = length
        return length
    }

    /// エコーで延びる長さ。本家 `EffectLength`。
    private var effectLength: Int { bufferLength * repeatCount }

    public override var duration: Int {
        (input?.duration ?? 0) + effectLength
    }

    override func seekImpl(_ position: Int) {
        let primed = min(position, effectLength)
        input?.seek(to: position - primed)
        currentBuffer = nil
        currentBufferIndex = 0
        if bufferLength > 0 {
            for _ in 0..<(primed / bufferLength) {
                createCurrentBuffer()
            }
        }
        createCurrentBuffer()
        currentBufferIndex = primed < 0 ? primed : primed % bufferLength
    }

    override func readImpl(_ destBuffer: inout [Float], offset: Int, count: Int) -> Int {
        if currentBuffer == nil {
            // 本家はシーク前の読み取りでは状態が無く失敗する経路だが、
            // 実際の呼び出しは必ずシークを先行させる。ここでは先行生成で
            // 代替する（到達しない経路の防御として記録）。
            createCurrentBuffer()
        }
        var total = 0
        while total < count {
            total += readCurrentBuffer(&destBuffer, offset: offset + total, count: count - total)
            if currentBufferIndex == bufferLength {
                createCurrentBuffer()
            }
        }
        return total
    }

    private func createCurrentBuffer() {
        var next = [Float](repeating: 0, count: bufferLength)
        _ = input?.read(into: &next, offset: 0, count: bufferLength)
        if let currentBuffer {
            let factor = Float(attenuation)
            for index in 0..<bufferLength {
                next[index] += currentBuffer[index] * factor
            }
        }
        currentBuffer = next
        currentBufferIndex = 0
    }

    private func readCurrentBuffer(
        _ destBuffer: inout [Float], offset: Int, count: Int
    ) -> Int {
        guard let currentBuffer else { return 0 }
        var readCount = min(count, bufferLength - currentBufferIndex)
        readCount = min(readCount, destBuffer.count - offset)
        if readCount <= 0 { return 0 }
        for index in 0..<readCount {
            if currentBufferIndex + index >= 0 {
                destBuffer[offset + index] = currentBuffer[currentBufferIndex + index]
            }
        }
        currentBufferIndex += readCount
        return readCount
    }
}
