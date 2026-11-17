import Foundation

/// ラウドネス解析（書き出し前の音量測定パス）の純粋計算。
///
/// 本家 `VideoFileWriter.CreateFileAsync` の解析パスと
/// `ItuRBs1770v3LoudnessAnalyzer` の意味論を再現する（仕様第6章 §6 /
/// W6-6.1〜W6-6.4）。実ファイルや実ストリームには触れず、
/// 「フレーム単位の固定長配列＋実際に読めた件数」の列を入力として
/// 音量倍率とコンプレッサ倍率を返す。
///
/// 本家の癖として再現するもの:
/// - アナライザへは Read の戻り値ではなく固定長配列そのものが渡され、
///   最終フレーム等の読み不足分はゼロ埋めのまま測定に入る（W6-6.3）。
///   ピーク測定だけは実際に読めた件数の範囲を見る。
/// - モード 3 / 4（最大音量系）では BS.1770-3 アナライザ自体が
///   生成されない（W6-6.2）。
/// - モード 3 / 4 ではコンプレッサ Auto の計算分岐に到達せず、
///   compressorRate は初期値 1 のまま残る（W6-6.2 の if / else-if 構造）。
/// - DownMaximumVolume はピーク dB を max(peakDb, 0) として扱うため、
///   ピークが 0 dBFS 以下なら倍率は 1（下げる方向にしか働かない）。

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

// MARK: - 倍率計算（本家 VideoFileWriter の解析パス）

/// 解析パスの結果。
public struct LoudnessAnalysisResult: Equatable, Sendable {
    /// 解析パス（読み直し）が実行されたかどうか。
    /// モード Disabled かつ RatioMode Custom の場合は実行されず、
    /// compressorRate に設定値がそのまま入る（W6-6.1）。
    public var analysisPerformed: Bool
    /// 音量倍率（DynamicsProcessor の入力音量として適用される）。
    public var volumeRate: Float
    /// コンプレッサ倍率。
    public var compressorRate: Float
    /// ラウドネス補正量（dB）。ピーク系モードでは表示用の副産物。
    public var loudnessFix: Float
    /// 測定された長期ラウドネス（LKFS）。アナライザが無い場合は −60。
    public var averageLoudness: Float
    /// 測定されたピーク（dB）。初期値 −60。
    public var peakDb: Float
}

public enum LoudnessAnalysis {
    /// 解析1フレーム分の入力。`samples` は固定長配列の全体、
    /// `readCount` はそのうち実際に読めた件数。
    public struct FrameChunk {
        public var samples: [Float]
        public var readCount: Int

        public init(samples: [Float], readCount: Int) {
            self.samples = samples
            self.readCount = readCount
        }
    }

    // MARK: - 解析計画（本家 VideoFileWriter の分岐 W6-6.1）

    /// 解析計画。音声を読み直す解析が必要かどうかと、不要な場合に
    /// そのまま確定する倍率を表す。
    ///
    /// 本家 `VideoFileWriter.CreateFileAsync` は、Loudness=Disabled かつ
    /// Compressor=Disabled では解析ブロック自体に入らず、
    /// Loudness=Disabled かつ Compressor=Custom（固定 Ratio）では
    /// 倍率を設定するだけで音声を読み直さない。呼び出し側は音声を
    /// 読む前にこの計画で判定すること（EX17-05 の是正）。
    public struct Plan: Equatable, Sendable {
        /// 音声を読み直す解析が必要かどうか。
        public var requiresReading: Bool
        /// 解析が不要な場合にそのまま確定する音量倍率。
        public var volumeRate: Float
        /// 解析が不要な場合にそのまま確定するコンプレッサ倍率。
        public var compressorRate: Float

        public init(requiresReading: Bool, volumeRate: Float, compressorRate: Float) {
            self.requiresReading = requiresReading
            self.volumeRate = volumeRate
            self.compressorRate = compressorRate
        }
    }

    /// 設定から解析計画を立てる（本家 W6-6.1 の分岐）。
    public static func plan(
        loudness: LoudnessNormalizationSettings,
        compressor: CompressorSettings
    ) -> Plan {
        if loudness.mode == .disabled, compressor.ratioMode == .custom {
            return Plan(requiresReading: false, volumeRate: 1, compressorRate: compressor.ratio)
        }
        let requiresReading =
            loudness.mode != .disabled || compressor.ratioMode != .disabled
        return Plan(requiresReading: requiresReading, volumeRate: 1, compressorRate: 1)
    }

    /// 解析を行わない場合の結果。計画の倍率がそのまま確定値になり、
    /// 測定値は初期値（ピーク・ラウドネスとも −60）のままになる。
    public static func skippedResult(for plan: Plan) -> LoudnessAnalysisResult {
        LoudnessAnalysisResult(
            analysisPerformed: false,
            volumeRate: plan.volumeRate,
            compressorRate: plan.compressorRate,
            loudnessFix: 0, averageLoudness: -60, peakDb: -60
        )
    }

    /// 本家の解析ループを、チャンク列に対する純粋計算として再現する。
    ///
    /// 中間経過（約5秒ごとの再計算）は本家では壁時計依存だが、
    /// 最終値はループ後の確定計算で上書きされるため結果に影響しない。
    /// ここでは最終値のみを計算する。
    public static func analyze(
        chunks: [FrameChunk],
        loudness: LoudnessNormalizationSettings,
        compressor: CompressorSettings,
        hz: Int
    ) -> LoudnessAnalysisResult {
        let plan = plan(loudness: loudness, compressor: compressor)
        guard plan.requiresReading else { return skippedResult(for: plan) }
        var accumulator = Accumulator(loudness: loudness, compressor: compressor, hz: hz)
        for chunk in chunks {
            accumulator.consume(chunk)
        }
        return accumulator.finish()
    }

    /// ストリームからフレーム単位で読みながら解析する（本番経路）。
    ///
    /// 本家どおり固定長の1配列を使い回し、全区間をメモリに保持しない
    /// （EX17-06 の是正。チャンク列版はテスト補助として残す）。
    /// 解析計画が読み取り不要を示す場合はストリームへ一切触れない。
    /// 読み方は `makeChunks` と同じ（固定長・ゼロ埋め・読み件数の保持）。
    public static func analyze(
        stream: AudioStream,
        frameCount: Int,
        loudness: LoudnessNormalizationSettings,
        compressor: CompressorSettings,
        hz: Int,
        fps: Int
    ) -> LoudnessAnalysisResult {
        let plan = plan(loudness: loudness, compressor: compressor)
        guard plan.requiresReading else { return skippedResult(for: plan) }
        var accumulator = Accumulator(loudness: loudness, compressor: compressor, hz: hz)
        let rawLength = hz * 2 / fps
        let frameLength = rawLength - rawLength % 2
        guard frameLength > 0, frameCount > 0 else { return accumulator.finish() }
        var buffer = [Float](repeating: 0, count: frameLength)
        for _ in 0..<frameCount {
            for index in buffer.indices { buffer[index] = 0 }
            let readCount = stream.read(into: &buffer, offset: 0, count: frameLength)
            accumulator.consume(FrameChunk(samples: buffer, readCount: readCount))
        }
        return accumulator.finish()
    }

    /// 解析の累積器。チャンク列版とストリーミング版で、1チャンク分の
    /// 取り込みと最終値の確定計算を共有する。
    private struct Accumulator {
        private var result: LoudnessAnalysisResult
        private let loudness: LoudnessNormalizationSettings
        private let compressor: CompressorSettings
        private let analyzer: BS1770LoudnessAnalyzer?

        init(
            loudness: LoudnessNormalizationSettings,
            compressor: CompressorSettings,
            hz: Int
        ) {
            self.loudness = loudness
            self.compressor = compressor
            result = LoudnessAnalysisResult(
                analysisPerformed: true, volumeRate: 1, compressorRate: 1,
                loudnessFix: 0, averageLoudness: -60, peakDb: -60
            )
            let mode = loudness.mode
            analyzer = (mode == .downOnly || mode == .both)
                ? BS1770LoudnessAnalyzer(hz: hz) : nil
            analyzer?.beginLongTermLoudness()
        }

        mutating func consume(_ chunk: FrameChunk) {
            let mode = loudness.mode
            analyzer?.process(chunk.samples)
            if mode == .downMaximumVolume || mode == .upDownMaximumVolume {
                updatePeak(chunk: chunk, result: &result)
                let effectivePeak = mode == .downMaximumVolume
                    ? max(result.peakDb, 0) : result.peakDb
                result.volumeRate = fixLoudnessVolume(
                    target: 0, average: effectivePeak, mode: mode
                ).volumeRate
            } else if compressor.ratioMode == .auto {
                updatePeak(chunk: chunk, result: &result)
                result.compressorRate = compressorRate(
                    peakDb: result.peakDb + result.loudnessFix, settings: compressor
                )
            }
        }

        mutating func finish() -> LoudnessAnalysisResult {
            let mode = loudness.mode
            result.averageLoudness = analyzer?.endLongTermLoudness() ?? -60
            if mode == .downOnly || mode == .both {
                let fixed = fixLoudnessVolume(
                    target: loudness.target, average: result.averageLoudness, mode: mode
                )
                result.loudnessFix = fixed.loudnessFix
                result.volumeRate = fixed.volumeRate
            }
            if mode == .downMaximumVolume || mode == .upDownMaximumVolume {
                let effectivePeak = mode == .downMaximumVolume
                    ? max(result.peakDb, 0) : result.peakDb
                result.volumeRate = fixLoudnessVolume(
                    target: 0, average: effectivePeak, mode: mode
                ).volumeRate
            } else if compressor.ratioMode == .auto {
                result.compressorRate = compressorRate(
                    peakDb: result.peakDb + result.loudnessFix, settings: compressor
                )
            } else if compressor.ratioMode == .custom {
                result.compressorRate = compressor.ratio
            }
            return result
        }
    }

    /// ストリームから本家の読み方でチャンク列を組み立てる（テスト補助）。
    ///
    /// 全フレーム分の配列を蓄積するため、本番経路では使わない
    /// （本番は `analyze(stream:...)` のストリーミング版。EX17-06）。
    /// 1フレームの配列長は `Hz * 2 / FPS`（整数除算）を偶数へ切り捨てた
    /// 固定長で、毎回ゼロ初期化してから読み、読み切れなかった尾部は
    /// ゼロ埋めのままチャンクに入る（W6-6.3）。
    public static func makeChunks(
        from stream: AudioStream, frameCount: Int, hz: Int, fps: Int
    ) -> [FrameChunk] {
        let rawLength = hz * 2 / fps
        let frameLength = rawLength - rawLength % 2
        guard frameLength > 0, frameCount > 0 else { return [] }
        var chunks: [FrameChunk] = []
        chunks.reserveCapacity(frameCount)
        var array = [Float](repeating: 0, count: frameLength)
        for _ in 0..<frameCount {
            for index in array.indices { array[index] = 0 }
            let readCount = stream.read(into: &array, offset: 0, count: frameLength)
            chunks.append(FrameChunk(samples: array, readCount: readCount))
        }
        return chunks
    }

    // MARK: - 本家の補助計算

    /// ピークは実際に読めた範囲だけを見る（W6-6.3）。
    private static func updatePeak(chunk: FrameChunk, result: inout LoudnessAnalysisResult) {
        var peak: Float = 0
        let count = min(chunk.readCount, chunk.samples.count)
        for index in 0..<count {
            peak = max(peak, abs(chunk.samples[index]))
        }
        result.peakDb = max(result.peakDb, decibel(fromAmplitude: peak))
    }

    /// 本家 `GetDb`。振幅 0 以下は −60。
    static func decibel(fromAmplitude amplitude: Float) -> Float {
        amplitude > 0 ? 20 * log10f(amplitude) : -60
    }

    /// 本家 `GetVolume`。dB 差から倍率へ。差が 0 なら 1。
    static func volume(fromDecibelDelta delta: Float) -> Float {
        delta != 0 ? powf(10, delta / 20) : 1
    }

    /// 本家 `FixLoudnessVolume`。DownOnly では上げる方向を 0 dB で止める。
    static func fixLoudnessVolume(
        target: Float, average: Float, mode: LoudnessFixMode
    ) -> (loudnessFix: Float, volumeRate: Float) {
        var fix = target - average
        if mode == .downOnly {
            fix = min(0, fix)
        }
        return (fix, volume(fromDecibelDelta: fix))
    }

    /// 本家 `GetCompressorRate`。上限は max(PeakLimit, Threshold) で、
    /// ピークがそれ未満なら 1、以上なら超過分と余裕分の比。
    static func compressorRate(peakDb: Float, settings: CompressorSettings) -> Float {
        let limit = max(settings.peakLimit, settings.threshold)
        if peakDb < limit { return 1 }
        return (peakDb - settings.threshold) / (limit - settings.threshold)
    }
}
