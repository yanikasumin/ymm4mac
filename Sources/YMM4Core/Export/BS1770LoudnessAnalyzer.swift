import Foundation

// MARK: - BS.1770-3 アナライザ（本家 ItuRBs1770v3LoudnessAnalyzer）

/// ITU-R BS.1770-3 ラウドネスアナライザ。
///
/// K 特性フィルタ（ハイシェルフ 1500 Hz / +4 dB → ハイパス 37.5 Hz の
/// Biquad 直列）を左右別に通し、400 ms ブロック・75% オーバーラップで
/// ブロック平均二乗を積む。ゲーティングは絶対ゲート（−70 LKFS）と
/// 相対ゲート（絶対ゲート後の統合値 −10 LU）の二段（W6-6.2）。
/// フィルタ係数と処理は float32 で行い、本家の float 演算に合わせる。
public final class BS1770LoudnessAnalyzer {
    /// Biquad フィルタ（本家 BiQuadFilter）。直接形 I、float32 演算。
    private struct Biquad {
        var a1: Float = 0
        var a2: Float = 0
        var b0: Float = 0
        var b1: Float = 0
        var b2: Float = 0
        private var x1: Float = 0
        private var x2: Float = 0
        private var y1: Float = 0
        private var y2: Float = 0

        mutating func process(_ sample: Float) -> Float {
            let result = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = sample
            y2 = y1
            y1 = result
            return result
        }
    }

    /// K 特性フィルタ1段分（本家 HighShelfFilter）。
    /// RBJ ハイシェルフ: 中心 1500 Hz、Q = 0.707、ゲイン +4 dB。
    private static func highShelf(frequency: Int) -> Biquad {
        let f0: Float = 1500
        let q: Float = 0.707
        let gainDb: Float = 4
        let x = Float.pi * 2 * f0 / Float(frequency)
        let amp = sqrtf(powf(10, gainDb / 20))
        let alpha = sinf(x) / (q * 2)
        let cosX = cosf(x)
        let twoSqrtAAlpha = 2 * sqrtf(amp) * alpha
        var filter = Biquad()
        let a0 = amp + 1 - (amp - 1) * cosX + twoSqrtAAlpha
        filter.a1 = 2 * (amp - 1 - (amp + 1) * cosX) / a0
        filter.a2 = (amp + 1 - (amp - 1) * cosX - twoSqrtAAlpha) / a0
        filter.b0 = amp * (amp + 1 + (amp - 1) * cosX + twoSqrtAAlpha) / a0
        filter.b1 = -2 * amp * (amp - 1 + (amp + 1) * cosX) / a0
        filter.b2 = amp * (amp + 1 + (amp - 1) * cosX - twoSqrtAAlpha) / a0
        return filter
    }

    /// K 特性フィルタ2段分（本家 HighPassFilter）。
    /// RBJ ハイパス: 37.5 Hz、Q = 0.86。
    private static func highPass(frequency: Int) -> Biquad {
        let f0: Float = 37.5
        let q: Float = 0.86
        let x = Float.pi * 2 * f0 / Float(frequency)
        let alpha = sinf(x) / (q * 2)
        let cosX = cosf(x)
        var filter = Biquad()
        let a0 = 1 + alpha
        filter.a1 = -2 * cosX / a0
        filter.a2 = (1 - alpha) / a0
        filter.b0 = (1 + cosX) * 0.5 / a0
        filter.b1 = (1 + cosX) * -1 / a0
        filter.b2 = (1 + cosX) * 0.5 / a0
        return filter
    }

    /// チャンネル分の K 特性フィルタ（シェルフ→ハイパスの直列）。
    private struct KWeightFilter {
        var shelf: Biquad
        var pass: Biquad

        init(frequency: Int) {
            shelf = BS1770LoudnessAnalyzer.highShelf(frequency: frequency)
            pass = BS1770LoudnessAnalyzer.highPass(frequency: frequency)
        }

        mutating func process(_ sample: Float) -> Float {
            pass.process(shelf.process(sample))
        }
    }

    private var filterLeft: KWeightFilter
    private var filterRight: KWeightFilter
    private let blockSize: Int
    private let overlapSize: Int
    private var leftBuffer: [Float] = []
    private var rightBuffer: [Float] = []
    private var bufferPosition = 0
    private var bufferLength = 0
    private var isComputingLongTerm = false
    private var gatedBlocks: [(meanSquare: Float, loudness: Float)] = []

    public init(hz: Int) {
        filterLeft = KWeightFilter(frequency: hz)
        filterRight = KWeightFilter(frequency: hz)
        blockSize = Int(Double(hz) * 0.4)
        overlapSize = Int(Double(hz) * 0.4 * 0.75)
    }

    /// 長期ラウドネス測定の開始（本家 `BeginLongTermLoudness`）。
    public func beginLongTermLoudness() {
        isComputingLongTerm = true
    }

    /// 長期ラウドネスの確定（本家 `EndLongTermLoudness`）。
    /// ゲート済みブロックを破棄して統合値を返す。
    public func endLongTermLoudness() -> Float {
        let result = computeLongTermLoudness()
        isComputingLongTerm = false
        gatedBlocks.removeAll()
        return result
    }

    /// 本家 `ComputeLongTermLoudness`。絶対ゲート通過ブロックの
    /// 平均二乗から相対ゲート（−10 LU）を決め、通過分だけで再平均する。
    public func computeLongTermLoudness() -> Float {
        let firstAverage: Float = gatedBlocks.isEmpty
            ? 0
            : Float(gatedBlocks.reduce(0.0) { $0 + Double($1.meanSquare) } / Double(gatedBlocks.count))
        let relativeGate = -0.691 + 10 * log10f(firstAverage) - 10
        let passing = gatedBlocks.filter { $0.loudness > relativeGate }
        let secondAverage: Float = passing.isEmpty
            ? 0
            : Float(passing.reduce(0.0) { $0 + Double($1.meanSquare) } / Double(passing.count))
        return max(-60, -0.691 + 10 * log10f(secondAverage))
    }

    /// 本家 `Reset`。バッファとブロック列を捨てる。
    /// K フィルタの内部状態は本家でもリセットされないため、ここでも保持する。
    public func reset() {
        leftBuffer = []
        rightBuffer = []
        bufferPosition = 0
        bufferLength = 0
        isComputingLongTerm = false
        gatedBlocks.removeAll()
    }

    /// インターリーブ済みサンプル列を取り込む（本家 `Process`）。
    /// 入力は「渡された配列の全体」が対象で、呼び出し側の都合で
    /// ゼロ埋めされた尾部もそのまま測定に入る。
    public func process(_ input: [Float]) {
        writeBuffer(input)
        guard bufferLength >= blockSize else { return }
        while bufferLength > blockSize {
            processBlock()
        }
        if bufferPosition > 0 {
            for index in 0..<bufferLength {
                leftBuffer[index] = leftBuffer[bufferPosition + index]
                rightBuffer[index] = rightBuffer[bufferPosition + index]
            }
            bufferPosition = 0
        }
    }

    private func writeBuffer(_ input: [Float]) {
        let required = bufferPosition + bufferLength + input.count / 2
        if leftBuffer.count < required {
            leftBuffer.append(contentsOf: [Float](repeating: 0, count: required - leftBuffer.count))
            rightBuffer.append(contentsOf: [Float](repeating: 0, count: required - rightBuffer.count))
        }
        for index in 0..<(input.count / 2) {
            leftBuffer[bufferPosition + bufferLength + index] = filterLeft.process(input[index * 2])
            rightBuffer[bufferPosition + bufferLength + index] = filterRight.process(input[index * 2 + 1])
        }
        bufferLength += input.count / 2
    }

    private func processBlock() {
        var sumLeft = 0.0
        var sumRight = 0.0
        for index in 0..<blockSize {
            let left = leftBuffer[bufferPosition + index]
            let right = rightBuffer[bufferPosition + index]
            sumLeft += Double(left) * Double(left)
            sumRight += Double(right) * Double(right)
        }
        let meanSquareLeft = Float(sumLeft / Double(blockSize))
        let meanSquareRight = Float(sumRight / Double(blockSize))
        let meanSquare = (meanSquareLeft + meanSquareRight) / 2
        let loudness = max(-60, -0.691 + 10 * log10f(meanSquare))
        if loudness > -70, isComputingLongTerm {
            gatedBlocks.append((meanSquare, loudness))
        }
        let step = blockSize - overlapSize
        bufferPosition += step
        bufferLength -= step
    }
}
