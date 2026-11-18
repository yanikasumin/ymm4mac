#if os(macOS)
import Foundation
import YMM4Core

/// 再生用の音声供給（ミキサー＋レベルメーター）。
/// 本家 `TimelineSourceSampleProviderWithLevelMeter`
/// （YukkuriMovieMaker.Player.Audio）に対応する。
///
/// 意味論（本家どおり）:
/// - 内部に 2 秒分のリングバッファを持ち、1 秒窓（Hz × 2 サンプル）
///   単位でミキサーから読み、その窓をレベルメーターへ通してから
///   蓄える。読み出しは蓄積から要求分だけ返す。
/// - ミキサーの読み取りが窓に満たない場合は終端とみなし、残りを
///   無音で埋める（終端以降は無音を返し続ける）。
/// - レベルメーターの測定は、ピーク／ラウドネスのどちらかが有効な
///   ときだけ行う（本家は設定の IsEnabled で判定する。ここでは
///   メーター側の有効フラグがそのまま効く）。
/// - シークはミキサーとメーターの双方を同じ位置へ合わせ、蓄積を
///   破棄する。
///
/// 所有権: ミキサー（とその先の工場・プロバイダ）はこの供給元が
/// 強参照で保持する。再生エンジンがこの供給元を保持し、破棄時に
/// まとめて解放される。
public final class PlaybackAudioSource {
    /// ミキサー本体。
    public let mixer: TimelineAudioMixer
    /// レベルメーター。読み取り（供給側）と表示側の双方から触れる
    /// ため、メーター自体がロックで保護する。
    public let levelMeter: SoundLevelMeter

    private var ringBuffer: [Float]
    private var bufferIndex = 0
    private var bufferLength = 0
    private var windowSize: Int
    private var isEndOfStream = false

    /// サンプリングレート（タイムラインの Hz）。
    public var hz: Int { mixer.hz }

    public init(mixer: TimelineAudioMixer, levelMeter: SoundLevelMeter) {
        self.mixer = mixer
        self.levelMeter = levelMeter
        let window = mixer.hz * AudioStream.channelCount
        self.windowSize = window
        self.ringBuffer = [Float](repeating: 0, count: window * 2)
    }

    /// 指定位置へシークする。本家 `Seek`。
    public func seek(toTime time: TimeSpanValue) {
        mixer.seek(toTime: time)
        levelMeter.seek(to: time, hz: hz)
        if ringBuffer.count != hz * AudioStream.channelCount * 2 {
            ringBuffer = [Float](
                repeating: 0, count: hz * AudioStream.channelCount * 2
            )
        } else {
            for index in ringBuffer.indices { ringBuffer[index] = 0 }
        }
        bufferIndex = 0
        bufferLength = 0
        windowSize = hz * AudioStream.channelCount
        isEndOfStream = false
    }

    /// バッファへ読み取る。本家 `Read`。
    ///
    /// 出力の対象区間は先に 0 埋めされ、蓄積からコピーした分だけが
    /// 上書きされる。戻り値は実際に返したサンプル数。
    @discardableResult
    public func read(into buffer: inout [Float], offset: Int, count: Int) -> Int {
        for index in 0..<count where offset + index < buffer.count {
            buffer[offset + index] = 0
        }
        while bufferLength <= windowSize {
            let writePosition = (bufferIndex + bufferLength) % ringBuffer.count
            let wasEndOfStream = isEndOfStream
            var readCount = 0
            if !wasEndOfStream {
                // 窓全体を先に 0 埋めする。ミキサーの読み取りは
                // 「0 初期化されたバッファへの加算」が契約であり、
                // 読み取りが窓に満たない分はそのまま無音になる
                // （本家は終端時に残りを明示的に消すが、結果は同じ）。
                clearWindow(at: writePosition, count: windowSize)
                readCount = readWindow(at: writePosition, count: windowSize)
            }
            if readCount != windowSize {
                isEndOfStream = true
            }
            bufferLength += windowSize
            // メーター測定はソースから読んだ窓に対してだけ行う
            // （終端以降の無音窓は測定しない。本家の分岐構造どおり）。
            let meterEnabled = levelMeter.isSoundLevelMeterEnabled
                || levelMeter.isLoudnessMeterEnabled
            if !wasEndOfStream, meterEnabled {
                levelMeter.process(windowSamples(at: writePosition, count: windowSize))
            }
        }
        let copied = min(count, bufferLength)
        var remaining = copied
        var written = 0
        while remaining > 0 {
            let chunk = min(remaining, ringBuffer.count - bufferIndex)
            if chunk == 0 { break }
            for index in 0..<chunk {
                buffer[offset + written + index] = ringBuffer[bufferIndex + index]
            }
            written += chunk
            remaining -= chunk
            bufferIndex = (bufferIndex + chunk) % ringBuffer.count
            bufferLength -= chunk
        }
        return written
    }

    /// リングバッファ上の区間を 0 埋めする（境界跨ぎ対応）。
    private func clearWindow(at position: Int, count: Int) {
        for index in 0..<count {
            ringBuffer[(position + index) % ringBuffer.count] = 0
        }
    }

    /// リングバッファの絶対位置へミキサーから 1 窓分を読む。
    /// 書き込み位置は読み出し量によって窓境界からずれるため、
    /// リングの末尾を跨ぐ場合は一時バッファ経由で 2 区間に分ける。
    private func readWindow(at position: Int, count: Int) -> Int {
        if position + count <= ringBuffer.count {
            var total = 0
            while total < count {
                let readCount = mixer.read(
                    into: &ringBuffer, offset: position + total, count: count - total
                )
                if readCount <= 0 { break }
                total += readCount
            }
            return total
        }
        var temporary = [Float](repeating: 0, count: count)
        var total = 0
        while total < count {
            let readCount = mixer.read(
                into: &temporary, offset: total, count: count - total
            )
            if readCount <= 0 { break }
            total += readCount
        }
        for index in 0..<count {
            ringBuffer[(position + index) % ringBuffer.count] = temporary[index]
        }
        return total
    }

    /// リングバッファ上の 1 窓分を配列として取り出す（メーター用）。
    private func windowSamples(at position: Int, count: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            samples[index] = ringBuffer[(position + index) % ringBuffer.count]
        }
        return samples
    }
}
#endif
