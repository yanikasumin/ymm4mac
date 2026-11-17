import Foundation

/// 音量係数の適用段（本家 `DynamicsProcessor`、書き出しでは
/// コンプレッサ固定で常時生成される — W6-6.4）。
///
/// 書き出し側の役割は2つ: (1) 解析パスで決まった音量倍率 `volume` を
/// 全サンプルへ掛ける。(2) コンプレッサ倍率 `ratio` が 1 でない場合に、
/// ルックアヘッド付きのピーク追従で利得を下げる。
/// Ratio == 1 の場合は高速経路で、読み取り→倍率乗算のみを行う
/// （この経路は本家と完全一致する）。
///
/// 未検証の注記: 利得追従に使うエンベロープフォロワ（NWaves の
/// `EnvelopeFollower`）の係数法則は逆コンパイル集合にソースが無く、
/// 本家の `DynamicsProcessor` から読み取れるのは
/// Attack / Release の換算定数 T = 1 / ln(9) と入出力の接続だけである。
/// 本実装のフォロワは「整流入力に対する1極スムーザ
/// （係数 = exp(−1 / (time × fs))、入力が現在値を上回れば attack、
/// そうでなければ release）」として再構成したもので、
/// 係数の厳密な一致は主張しない。Ratio ≠ 1 の経路は構造の再現であり、
/// 波形レベルの一致は本家実機での検証待ち。

/// 本家 `DynamicsProcessor` の AudioStream 化。
public final class DynamicsProcessorStream: AudioStream {
    /// Attack / Release 換算定数（本家 `T = 1 / ln(9)`）。
    private static let timeConstant = 1.0 / log(9.0)

    private let input: AudioStream
    /// 入力音量（ラウドネスの音量倍率がここに入る）。
    public var volume: Float
    /// スレッショルド（dB）。
    public var threshold: Float
    /// コンプレッサ倍率。1 の場合は高速経路になる。
    public var ratio: Float
    /// メイクアップゲイン（dB）。書き出しでは 0。
    public var makeupGain: Float
    /// ルックアヘッドの有効化。
    public var isLookAheadEnabled: Bool

    private let attackSeconds: Float
    private let follower: EnvelopeFollower
    private var ring = FloatRingBuffer()
    private var scratch: [Float] = []
    private var lookAheadSize = 0

    public init(
        input: AudioStream,
        volume: Float,
        threshold: Float,
        ratio: Float,
        makeupGain: Float = 0,
        attack: Float,
        release: Float,
        isLookAheadEnabled: Bool
    ) {
        self.input = input
        self.volume = volume
        self.threshold = threshold
        self.ratio = ratio
        self.makeupGain = makeupGain
        self.isLookAheadEnabled = isLookAheadEnabled
        self.attackSeconds = attack
        follower = EnvelopeFollower(sampleRate: input.hz)
        follower.attackTime = Float(Double(attack) * Self.timeConstant)
        follower.releaseTime = Float(Double(release) * Self.timeConstant)
        super.init()
    }

    public override var hz: Int { input.hz }

    public override var duration: Int { input.duration }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        if ratio == 1 {
            // 高速経路: 読んで倍率を掛けるだけ（本家と完全一致）。
            let readCount = input.read(into: &buffer, offset: offset, count: count)
            for index in offset..<(offset + readCount) {
                buffer[index] *= volume
            }
            return readCount
        }
        var needed = count + lookAheadSize - ring.readableLength
        if needed % 2 != 0 { needed += 1 }
        if needed < 0 { needed = 0 }
        if scratch.count < needed {
            scratch = [Float](repeating: 0, count: needed)
        } else {
            for index in scratch.indices { scratch[index] = 0 }
        }
        if needed > 0 {
            let obtained = input.read(into: &scratch, offset: 0, count: needed)
            ring.write(scratch, count: obtained)
        }
        let result = ring.read(into: &buffer, offset: offset, count: count)
        var position = 0
        while position < result {
            let peak = aheadPeak(buffer: buffer, offset: offset + position, remaining: result - position)
            let gain = processGain(peak) * volume
            buffer[offset + position] *= gain
            if position + 1 < result {
                buffer[offset + position + 1] *= gain
            }
            position += 2
        }
        return result
    }

    override func seekImpl(_ position: Int) {
        follower.reset()
        input.seek(to: position)
        ring.clear()
        if ratio != 1 {
            lookAheadSize = isLookAheadEnabled
                ? Int(attackSeconds * Float(input.hz) * 2)
                : 0
        }
    }

    /// 本家 `GetAheadPeak`。出力先の現在位置から
    /// `2 + lookAheadSize` サンプルと、リングバッファの続きを見て最大絶対値。
    private func aheadPeak(buffer: [Float], offset: Int, remaining: Int) -> Float {
        var peak: Float = 0
        let window = 2 + lookAheadSize
        let fromBuffer = min(window, remaining)
        for index in 0..<fromBuffer {
            peak = max(peak, abs(buffer[offset + index]))
        }
        let fromRing = min(window - fromBuffer, ring.readableLength)
        for index in 0..<fromRing {
            peak = max(peak, abs(ring.peek(index)))
        }
        return peak
    }

    /// 本家 `ProcessGain`（コンプレッサ分岐）。
    private func processGain(_ sample: Float) -> Float {
        let minimumAmplitudeDb: Float = -120
        let level = abs(sample * volume)
        let decibel = level > 1e-6 ? 20 * log10f(level) : minimumAmplitudeDb
        let target = decibel < threshold
            ? decibel
            : threshold + (decibel - threshold) / ratio
        let reduction = follower.process(target - decibel)
        return powf(10, (makeupGain - reduction) / 20)
    }
}
