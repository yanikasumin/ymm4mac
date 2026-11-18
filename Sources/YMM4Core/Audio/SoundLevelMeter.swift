import Foundation

/// サウンドレベルメーターの測定値（1/60 秒区間ごと）。
/// 本家 `SoundLevelMeter.LevelMeterFrameValue` に対応する。
public struct LevelMeterFrameValue: Equatable, Sendable {
    /// バッファ位置（インターリーブ済みサンプル数）。
    public var bufferPosition: Int64
    /// ピーク値（dB、−60 が下限）。
    public var peak: Double
    /// 平均値（dB、−60 が下限）。ピークメーターでは RMS、
    /// ラウドネスメーターでは ShortTerm が入る。
    public var rms: Double

    public init(bufferPosition: Int64, peak: Double, rms: Double) {
        self.bufferPosition = bufferPosition
        self.peak = peak
        self.rms = rms
    }

    /// 無信号（本家 `LevelMeterFrameValue.Silent`）。
    public static let silent = LevelMeterFrameValue(bufferPosition: 0, peak: -60, rms: -60)
}

/// ピークホールド値。本家 `SoundLevelMeter.LevelMeterHoldValue`。
public struct LevelMeterHoldValue: Equatable, Sendable {
    /// バッファ位置（インターリーブ済みサンプル数）。
    public var bufferPosition: Int64
    /// ホールド中のピーク値（dB）。
    public var peak: Double

    public init(bufferPosition: Int64, peak: Double) {
        self.bufferPosition = bufferPosition
        self.peak = peak
    }

    /// 無信号（本家 `LevelMeterHoldValue.Silent`）。
    public static let silent = LevelMeterHoldValue(bufferPosition: 0, peak: -60)
}

/// メーター1本分の現在値とホールド値。
/// 本家 `SoundLevelMeter.LevelMeterValue` に対応する。
public struct LevelMeterValue: Equatable, Sendable {
    /// 現在値（減衰適用後）。
    public var current: LevelMeterFrameValue
    /// ピークホールド値。
    public var hold: LevelMeterHoldValue

    public init(current: LevelMeterFrameValue, hold: LevelMeterHoldValue) {
        self.current = current
        self.hold = hold
    }

    /// 無信号（本家 `LevelMeterValue.Silent`）。
    public static let silent = LevelMeterValue(current: .silent, hold: .silent)
}

/// サウンドレベルメーター（ピーク L/R ＋ BS.1770 ラウドネス）。
/// 本家 `SoundLevelMeter`（YukkuriMovieMaker.Player.Audio）の再現。
///
/// 意味論（本家どおり）:
/// - `process` は 1 秒分のサンプル列を受け取り、1/60 秒区間ごとに
///   ピーク（区間の最大絶対値）と RMS を計算して位置付きで蓄える。
///   RMS は前回呼び出しの末尾 5 区間分と連結した列の、区間開始から
///   6 区間分の窓で計算する（本家の実装そのまま）。
/// - ピークが 0.001 未満の区間は −60 dB に丸める。
/// - ラウドネスは BS.1770-3 の 400ms ブロック（75% オーバーラップ）で
///   測り、区間値の Peak 欄に Momentary、Rms 欄に ShortTerm
///   （直近 30 ブロックの平均二乗から再計算）が入る。
/// - `setCurrentPosition` は指定位置以前の最新区間値を現在値として
///   取り出し、それより前の蓄積を捨てる。表示ピークは減衰指定時に
///   1 回あたり 0.5 dB ずつ下げる。ホールドは新しいピークが上回るか、
///   保持位置から 10 秒を超えたときに更新される。
/// - シーク時は現在値を保持したままホールドだけをリセットする。
///
/// 本家は .NET の Lock で全操作を保護する。ここでも NSLock で保護し、
/// 供給側（読み取り）と表示側（ポーリング）が別スレッドから触れる
/// 前提に合わせる。
public final class SoundLevelMeter: @unchecked Sendable {
    /// RMS 窓に使う前区間の保持数（本家 `StockFrameCount`）。
    public static let stockFrameCount = 5

    private let lock = NSLock()
    private var hz: Int = 0
    private var previousSamples: [Float] = []
    private var leftValues: [LevelMeterFrameValue] = []
    private var rightValues: [LevelMeterFrameValue] = []
    private var loudnessValues: [LevelMeterFrameValue] = []
    private var leftStorage: LevelMeterValue = .silent
    private var rightStorage: LevelMeterValue = .silent
    private var loudnessStorage: LevelMeterValue = .silent
    private var bufferOffset: Int64 = 0
    private var loudnessAnalyzer = MomentaryLoudnessAnalyzer(hz: 48_000)

    /// ピークメーター（L/R）の測定が有効か。
    public var isSoundLevelMeterEnabled = true
    /// ラウドネスメーターの測定が有効か。
    public var isLoudnessMeterEnabled = true

    public init() {}

    /// 左チャンネルの現在値とホールド値。
    public var left: LevelMeterValue {
        lock.lock()
        defer { lock.unlock() }
        return leftStorage
    }

    /// 右チャンネルの現在値とホールド値。
    public var right: LevelMeterValue {
        lock.lock()
        defer { lock.unlock() }
        return rightStorage
    }

    /// ラウドネスの現在値とホールド値。
    public var loudness: LevelMeterValue {
        lock.lock()
        defer { lock.unlock() }
        return loudnessStorage
    }

    /// シークに合わせて内部状態をリセットする。本家 `Seek`。
    /// 現在値は保持し、ホールドと蓄積だけを破棄する。
    public func seek(to time: TimeSpanValue, hz: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.hz = hz
        let stockCount = hz * 2 * Self.stockFrameCount / 60
        if previousSamples.count != stockCount {
            previousSamples = [Float](repeating: 0, count: stockCount)
        } else {
            for index in previousSamples.indices { previousSamples[index] = 0 }
        }
        loudnessAnalyzer = MomentaryLoudnessAnalyzer(hz: hz)
        bufferOffset = Int64(time.seconds * Double(hz) * 2)
        leftValues.removeAll()
        rightValues.removeAll()
        loudnessValues.removeAll()
        leftStorage = LevelMeterValue(current: leftStorage.current, hold: .silent)
        rightStorage = LevelMeterValue(current: rightStorage.current, hold: .silent)
        loudnessStorage = LevelMeterValue(current: loudnessStorage.current, hold: .silent)
    }

    /// 1 秒分のサンプル列を測定する。本家 `Process`。
    ///
    /// 入力は「1 秒分」（hz × 2 サンプル）を前提とする。区間数は
    /// 本家どおり入力長から導く（60 区間に満たない入力では区間が
    /// その分だけ少なくなる）。
    public func process(_ samplesPerSecond: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard isSoundLevelMeterEnabled || isLoudnessMeterEnabled else { return }
        guard !samplesPerSecond.isEmpty else { return }
        let segmentCount = samplesPerSecond.count / 60
        guard segmentCount > 0 else { return }
        let segmentTotal = samplesPerSecond.count / segmentCount
        // RMS 窓の連結列（前回末尾＋今回全体）はピーク測定が有効な
        // ときだけ必要になる。
        let joined: [Float] = isSoundLevelMeterEnabled
            ? previousSamples + samplesPerSecond
            : []
        for index in 0..<segmentTotal {
            let start = segmentCount * index
            let count = min(segmentCount, samplesPerSecond.count - start)
            guard count > 0 else { break }
            let bufferPosition = bufferOffset + Int64(segmentCount * index)
            if isSoundLevelMeterEnabled {
                var leftPeak: Float = 0
                var rightPeak: Float = 0
                for offset in 0..<count {
                    let sample = samplesPerSecond[start + offset]
                    if offset % 2 == 0 {
                        leftPeak = max(leftPeak, abs(sample))
                    } else {
                        rightPeak = max(rightPeak, abs(sample))
                    }
                }
                let peakLeft = leftPeak < 0.001
                    ? -60.0 : 20 * log10(Double(leftPeak))
                let peakRight = rightPeak < 0.001
                    ? -60.0 : 20 * log10(Double(rightPeak))
                // RMS は連結列の区間開始（前回分からの通し位置）から
                // 6 区間分の窓で取る（本家の Skip / Take そのまま）。
                let windowStart = segmentCount * index
                let windowCount = min(segmentCount * 6, joined.count - windowStart)
                var leftSquareSum = 0.0
                var rightSquareSum = 0.0
                var leftCount = 0
                var rightCount = 0
                for offset in 0..<max(windowCount, 0) {
                    let sample = Double(joined[windowStart + offset])
                    if offset % 2 == 0 {
                        leftSquareSum += sample * sample
                        leftCount += 1
                    } else {
                        rightSquareSum += sample * sample
                        rightCount += 1
                    }
                }
                let rmsLeftRaw = leftCount > 0
                    ? (leftSquareSum / Double(leftCount)).squareRoot() : 0
                let rmsRightRaw = rightCount > 0
                    ? (rightSquareSum / Double(rightCount)).squareRoot() : 0
                let rmsLeft = rmsLeftRaw < 0.0010000000474974513
                    ? -60.0 : 20 * log10(rmsLeftRaw)
                let rmsRight = rmsRightRaw < 0.0010000000474974513
                    ? -60.0 : 20 * log10(rmsRightRaw)
                leftValues.append(LevelMeterFrameValue(
                    bufferPosition: bufferPosition, peak: peakLeft, rms: rmsLeft
                ))
                rightValues.append(LevelMeterFrameValue(
                    bufferPosition: bufferPosition, peak: peakRight, rms: rmsRight
                ))
            }
            if isLoudnessMeterEnabled {
                loudnessAnalyzer.process(
                    Array(samplesPerSecond[start..<(start + count)])
                )
                loudnessValues.append(LevelMeterFrameValue(
                    bufferPosition: bufferPosition,
                    peak: Double(loudnessAnalyzer.momentary),
                    rms: Double(loudnessAnalyzer.shortTerm)
                ))
            }
        }
        if isSoundLevelMeterEnabled, previousSamples.count <= samplesPerSecond.count {
            let tailStart = samplesPerSecond.count - previousSamples.count
            for index in previousSamples.indices {
                previousSamples[index] = samplesPerSecond[tailStart + index]
            }
        }
        bufferOffset += Int64(samplesPerSecond.count)
    }

    /// 現在位置の値を取り出す。本家 `SetCurrentPosition`。
    /// 指定位置以前の最新区間値を現在値にし、それより前の蓄積を捨てる。
    public func setCurrentPosition(_ time: TimeSpanValue, isDecayed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let position = Int64(time.seconds * Double(hz) * 2)
        if let value = leftValues.last(where: { $0.bufferPosition <= position }) {
            leftStorage = makeValue(old: leftStorage, new: value, isDecayed: isDecayed)
            leftValues.removeAll { $0.bufferPosition < value.bufferPosition }
        }
        if let value = rightValues.last(where: { $0.bufferPosition <= position }) {
            rightStorage = makeValue(old: rightStorage, new: value, isDecayed: isDecayed)
            rightValues.removeAll { $0.bufferPosition < value.bufferPosition }
        }
        if let value = loudnessValues.last(where: { $0.bufferPosition <= position }) {
            loudnessStorage = makeValue(old: loudnessStorage, new: value, isDecayed: isDecayed)
            loudnessValues.removeAll { $0.bufferPosition < value.bufferPosition }
        }
    }

    /// 本家 `CreateLevelMeterValue`。ホールドの更新条件と減衰の適用。
    private func makeValue(
        old: LevelMeterValue, new: LevelMeterFrameValue, isDecayed: Bool
    ) -> LevelMeterValue {
        let exceeded = old.hold.peak <= new.peak
        let expired = old.hold.bufferPosition + Int64(hz * 2 * 10) < new.bufferPosition
        let hold = (exceeded || expired)
            ? LevelMeterHoldValue(bufferPosition: new.bufferPosition, peak: new.peak)
            : old.hold
        let currentPeak = isDecayed
            ? max(new.peak, old.current.peak - 0.5)
            : new.peak
        return LevelMeterValue(
            current: LevelMeterFrameValue(
                bufferPosition: new.bufferPosition, peak: currentPeak, rms: new.rms
            ),
            hold: hold
        )
    }
}

/// BS.1770-3 の Momentary / ShortTerm を供給するアナライザ。
/// 本家 `ItuRBs1770v3LoudnessAnalyzer` の、メーター表示に必要な部分
/// （400ms ブロック・75% オーバーラップ、直近 30 ブロックの保持）の再現。
///
/// K 特性フィルタの係数式は書き出し側の `BS1770LoudnessAnalyzer`
/// （統合ラウドネス用）と同一の RBJ 式だが、あちらはブロック値を
/// 保持しないため、ここではブロック列を持つ別実装として置く。
/// 統合ラウドネス（ゲーティング付き）は書き出し側の責務であり、
/// ここには持ち込まない。
final class MomentaryLoudnessAnalyzer {
    /// Biquad フィルタ（直接形 I、float32 演算）。
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

    /// K 特性フィルタ（ハイシェルフ 1500 Hz / +4 dB → ハイパス 37.5 Hz）。
    private struct KWeightFilter {
        var shelf: Biquad
        var pass: Biquad

        init(frequency: Int) {
            shelf = Self.highShelf(frequency: frequency)
            pass = Self.highPass(frequency: frequency)
        }

        mutating func process(_ sample: Float) -> Float {
            pass.process(shelf.process(sample))
        }

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
    }

    private var filterLeft: KWeightFilter
    private var filterRight: KWeightFilter
    private let blockSize: Int
    private let overlapSize: Int
    private var leftBuffer: [Float] = []
    private var rightBuffer: [Float] = []
    private var bufferPosition = 0
    private var bufferLength = 0
    /// 直近ブロックの（平均二乗, ラウドネス）。最大 30 件（本家どおり）。
    private var recentBlocks: [(meanSquare: Float, loudness: Float)] = []

    init(hz: Int) {
        filterLeft = KWeightFilter(frequency: hz)
        filterRight = KWeightFilter(frequency: hz)
        blockSize = Int(Double(hz) * 0.4)
        overlapSize = Int(Double(hz) * 0.4 * 0.75)
    }

    /// 最新ブロックのラウドネス（本家 `Momentary`、下限 −60）。
    var momentary: Float {
        guard let last = recentBlocks.last else { return -60 }
        return max(-60, last.loudness)
    }

    /// 直近ブロックの平均二乗から再計算したラウドネス
    /// （本家 `ShortTerm`、下限 −60）。
    var shortTerm: Float {
        guard !recentBlocks.isEmpty else { return -60 }
        let average = recentBlocks.reduce(Float(0)) { $0 + $1.meanSquare }
            / Float(recentBlocks.count)
        return max(-60, -0.691 + 10 * log10f(average))
    }

    /// インターリーブ済みサンプル列を取り込む。本家 `Process`。
    func process(_ input: [Float]) {
        writeBuffer(input)
        guard bufferLength >= blockSize, blockSize > 0 else { return }
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
        let frameCount = input.count / 2
        let required = bufferPosition + bufferLength + frameCount
        if leftBuffer.count < required {
            leftBuffer.append(contentsOf: [Float](
                repeating: 0, count: required - leftBuffer.count
            ))
            rightBuffer.append(contentsOf: [Float](
                repeating: 0, count: required - rightBuffer.count
            ))
        }
        for index in 0..<frameCount {
            leftBuffer[bufferPosition + bufferLength + index] =
                filterLeft.process(input[index * 2])
            rightBuffer[bufferPosition + bufferLength + index] =
                filterRight.process(input[index * 2 + 1])
        }
        bufferLength += frameCount
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
        let meanSquare = Float((sumLeft / Double(blockSize)
            + sumRight / Double(blockSize)) / 2)
        let loudness = max(-60, -0.691 + 10 * log10f(meanSquare))
        recentBlocks.append((meanSquare: meanSquare, loudness: loudness))
        if recentBlocks.count > 30 {
            recentBlocks.removeFirst()
        }
        let step = blockSize - overlapSize
        bufferPosition += step
        bufferLength -= step
    }
}
