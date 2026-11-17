import Foundation

/// エンベロープフォロワ（再構成。上の注記を参照）。
final class EnvelopeFollower {
    /// サンプリング周波数。
    let sampleRate: Int
    /// アタック時間（秒）。係数は設定時に再計算される。
    var attackTime: Float = 0 {
        didSet { attackCoefficient = Self.coefficient(time: attackTime, sampleRate: sampleRate) }
    }
    /// リリース時間（秒）。
    var releaseTime: Float = 0 {
        didSet { releaseCoefficient = Self.coefficient(time: releaseTime, sampleRate: sampleRate) }
    }
    private var attackCoefficient: Float = 0
    private var releaseCoefficient: Float = 0
    private var envelope: Float = 0

    init(sampleRate: Int) {
        self.sampleRate = sampleRate
    }

    private static func coefficient(time: Float, sampleRate: Int) -> Float {
        expf(-1 / (time * Float(sampleRate)))
    }

    /// 整流した入力に対して1極で追従する。
    func process(_ sample: Float) -> Float {
        let rectified = abs(sample)
        if rectified > envelope {
            envelope = attackCoefficient * envelope + (1 - attackCoefficient) * rectified
        } else {
            envelope = releaseCoefficient * envelope + (1 - releaseCoefficient) * rectified
        }
        return envelope
    }

    func reset() {
        envelope = 0
    }
}

/// 読み取り専用のリングバッファ（本家 NWaves `RingBuffer` 相当の最小実装）。
struct FloatRingBuffer {
    private var storage: [Float] = []
    private var head = 0
    private(set) var readableLength = 0

    mutating func write(_ source: [Float], count: Int) {
        guard count > 0 else { return }
        if storage.count < readableLength + count {
            // 保持中の要素を先頭へ寄せてから容量を確保する
            var compacted: [Float] = []
            compacted.reserveCapacity(readableLength + count)
            for index in 0..<readableLength {
                compacted.append(storage[(head + index) % storage.count])
            }
            storage = compacted
            head = 0
            storage.append(contentsOf: [Float](repeating: 0, count: count))
        }
        for index in 0..<count {
            storage[(head + readableLength + index) % storage.count] = source[index]
        }
        readableLength += count
    }

    mutating func read(into destination: inout [Float], offset: Int, count: Int) -> Int {
        let amount = min(count, readableLength)
        guard amount > 0 else { return 0 }
        for index in 0..<amount {
            destination[offset + index] = storage[(head + index) % storage.count]
        }
        head = (head + amount) % storage.count
        readableLength -= amount
        return amount
    }

    /// 消費せずに i 番目（0 = 最も古い未読要素）を見る。
    func peek(_ index: Int) -> Float {
        storage[(head + index) % storage.count]
    }

    mutating func clear() {
        head = 0
        readableLength = 0
    }
}
