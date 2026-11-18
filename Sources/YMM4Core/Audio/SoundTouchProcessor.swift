import Foundation

/// SoundTouch 互換の時間伸縮・音程変換の処理芯。
///
/// 本家は音高補正に SoundTouch.Net 2.3.2（SoundTouch の C# 移植）を
/// 同梱し、パラメータは Tempo / Pitch / Channels / SampleRate のみを
/// 設定して残りはライブラリ既定で使う。本家の利用箇所は
/// `SolaTimeStretchSampleProvider`（プレビュー再生）、
/// `SolaTimeStretchEffect`（アイテム速度の SOLA 方式）、
/// `VariableSolaPitchCorrectionEffect`（可変速度のピッチ補正）。
///
/// ここでは同梱 DLL から抽出した仕様（自動パラメータ式・相互相関に
/// よる重なり位置探索・線形クロスフェード・3 次補間のレート変換・
/// アンチエイリアス FIR の係数生成式）に基づき、ステレオ専用として
/// 再実装する。逆コンパイルコードの複写ではなく仕様の再実装であり、
/// 数値の丸め順序まで仕様どおりに合わせる。
///
/// パラメータ仕様（抽出結果）:
/// - シーケンス長（ms）= clamp(106.667 − 33.333 × tempo, 40, 90) を
///   四捨五入した整数。探索窓（ms）= clamp(21.667 − 3.333 × tempo,
///   15, 20) を四捨五入した整数。重なりは 8ms 固定。
/// - 重なり長 = サンプルレート × 8 / 1000（最低 16、8 の倍数へ切り捨て）。
/// - シーケンス窓長 = レート × シーケンス長 / 1000（最低で重なり長の
///   2 倍）。公称スキップ = tempo × (シーケンス窓長 − 重なり長)。
/// - 有効テンポ = tempo / pitch、有効レート = pitch × rate。
///   有効レート ≦ 1 なら「レート変換 → 時間伸縮」の順、> 1 なら
///   「時間伸縮 → レート変換」の順に接続し、切替時は処理済み出力と
///   未処理入力を新しい側へ移送する（本家の接続替え仕様どおり）。

/// フレーム単位の FIFO バッファ（ステレオ・インターリーブ固定）。
/// 本家 SoundTouch.Net の `FifoSampleBuffer` に対応する位置づけ。
final class SoundTouchFIFOBuffer {
    private var storage: [Float] = []
    /// 先頭フレームのサンプル位置。
    private var head: Int = 0
    /// 蓄積フレーム数。
    private(set) var availableFrames: Int = 0

    /// バッファ先頭から数えたサンプル（負・範囲外は呼び出し側が保証）。
    func sample(atSampleIndex index: Int) -> Float {
        storage[head + index]
    }

    /// フレーム・チャンネル指定のサンプル。
    func sample(frame: Int, channel: Int) -> Float {
        storage[head + frame * 2 + channel]
    }

    /// 末尾へフレーム列を追加する。
    func append(_ samples: [Float], frameCount: Int) {
        guard frameCount > 0 else { return }
        compactIfNeeded()
        storage.append(contentsOf: samples[0..<(frameCount * 2)])
        availableFrames += frameCount
    }

    /// 他バッファの範囲を末尾へ複写する。
    func append(framesFrom other: SoundTouchFIFOBuffer, start: Int, count: Int) {
        guard count > 0 else { return }
        append(other.copyFrames(start: start, count: count), frameCount: count)
    }

    /// 範囲の複写を取り出す。
    func copyFrames(start: Int, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        return Array(storage[(head + start * 2)..<(head + (start + count) * 2)])
    }

    /// 末尾へ無音フレームを追加する。
    func appendSilence(frames: Int) {
        guard frames > 0 else { return }
        compactIfNeeded()
        storage.append(contentsOf: [Float](repeating: 0, count: frames * 2))
        availableFrames += frames
    }

    /// 先頭から最大 `maxFrames` フレームを取り出して消費する。
    @discardableResult
    func receive(into buffer: inout [Float], offset: Int, maxFrames: Int) -> Int {
        let count = min(maxFrames, availableFrames)
        guard count > 0 else { return 0 }
        for index in 0..<(count * 2) {
            buffer[offset + index] = storage[head + index]
        }
        discard(frames: count)
        return count
    }

    /// 全フレームを取り出して空にする。
    func receiveAll() -> [Float] {
        let result = copyFrames(start: 0, count: availableFrames)
        clear()
        return result
    }

    /// 先頭からフレームを捨てる。捨てた数を返す。
    @discardableResult
    func discard(frames: Int) -> Int {
        let count = min(frames, availableFrames)
        head += count * 2
        availableFrames -= count
        if availableFrames == 0 {
            storage.removeAll(keepingCapacity: true)
            head = 0
        }
        return count
    }

    /// 蓄積量を指定フレーム数へ切り詰める（増やすことはしない）。
    /// 本家 `AdjustAmountOfSamples`。
    func adjustAmountOfSamples(_ frames: Int) {
        if frames < availableFrames {
            availableFrames = frames
            if frames == 0 {
                storage.removeAll(keepingCapacity: true)
                head = 0
            }
        }
    }

    func clear() {
        storage.removeAll(keepingCapacity: true)
        head = 0
        availableFrames = 0
    }

    private func compactIfNeeded() {
        if head > 65_536 {
            storage.removeFirst(head)
            head = 0
        }
    }
}

/// 時間伸縮段。本家 SoundTouch.Net の `TimeStretch`（TDStretch 系）に対応。
final class SoundTouchTimeStretch {
    private let inputBuffer = SoundTouchFIFOBuffer()
    private let outputBuffer = SoundTouchFIFOBuffer()
    /// 前回シーケンス末尾の重なり区間（次回のクロスフェード相手）。
    private var midBuffer: [Float] = []
    private var overlapLength: Int = 0
    private var seekLength: Int = 0
    private var seekWindowLength: Int = 0
    private var sampleRate: Int = 44_100
    private var tempo: Double = 1.0
    private var nominalSkip: Double = 0
    private var skipFract: Double = 0
    private var sampleReq: Int = 0
    private var isBeginning: Bool = true

    /// 重なり長（ms）。本家は設定変更しないため既定の 8 で固定。
    private let overlapMs: Int = 8

    init() {
        setParameters(sampleRate: 44_100)
        setTempo(1.0)
        clear()
    }

    var availableFrames: Int { outputBuffer.availableFrames }

    /// サンプルレートを設定する（シーケンス長・探索窓は自動のまま）。
    func setParameters(sampleRate: Int) {
        if sampleRate > 0 {
            self.sampleRate = sampleRate
        }
        calcSeqParameters()
        calculateOverlapLength()
        setTempo(tempo)
    }

    func setTempo(_ newTempo: Double) {
        tempo = newTempo
        calcSeqParameters()
        nominalSkip = tempo * Double(seekWindowLength - overlapLength)
        sampleReq = max(Int(nominalSkip + 0.5) + overlapLength, seekWindowLength) + seekLength
    }

    func clear() {
        outputBuffer.clear()
        clearInput()
    }

    func clearInput() {
        inputBuffer.clear()
        for index in midBuffer.indices { midBuffer[index] = 0 }
        isBeginning = true
        skipFract = 0
    }

    func putSamples(_ samples: [Float], frameCount: Int) {
        inputBuffer.append(samples, frameCount: frameCount)
        processSamples()
    }

    @discardableResult
    func receiveSamples(into buffer: inout [Float], offset: Int, maxFrames: Int) -> Int {
        outputBuffer.receive(into: &buffer, offset: offset, maxFrames: maxFrames)
    }

    /// 処理済み出力をすべて取り出す（段の接続替え用）。
    func receiveAllOutput() -> [Float] {
        outputBuffer.receiveAll()
    }

    /// 未処理入力をすべて取り出す（段の接続替え用）。
    func receiveAllInput() -> [Float] {
        inputBuffer.receiveAll()
    }

    /// 出力バッファへ直接追加する（段の接続替えで処理済み出力を移す用）。
    func appendToOutput(_ samples: [Float], frameCount: Int) {
        outputBuffer.append(samples, frameCount: frameCount)
    }

    func adjustAmountOfSamples(_ frames: Int) {
        outputBuffer.adjustAmountOfSamples(frames)
    }

    // MARK: - パラメータ計算

    private func calcSeqParameters() {
        let sequenceMs = Int(
            min(max(106.66666666666667 - 33.333333333333336 * tempo, 40.0), 90.0) + 0.5
        )
        let seekWindowMs = Int(
            min(max(21.666666666666668 - 3.3333333333333335 * tempo, 15.0), 20.0) + 0.5
        )
        seekWindowLength = sampleRate * sequenceMs / 1000
        if seekWindowLength < 2 * overlapLength {
            seekWindowLength = 2 * overlapLength
        }
        seekLength = sampleRate * seekWindowMs / 1000
    }

    private func calculateOverlapLength() {
        var length = sampleRate * overlapMs / 1000
        if length < 16 { length = 16 }
        length -= length % 8
        if length > overlapLength {
            midBuffer = [Float](repeating: 0, count: length * 2)
        }
        overlapLength = length
    }

    // MARK: - 本体処理

    private func processSamples() {
        while inputBuffer.availableFrames >= sampleReq {
            var skip = 0
            if !isBeginning {
                let overlapPosition = seekBestOverlapPosition()
                overlapAppend(inputStartFrame: overlapPosition)
                skip = overlapPosition + overlapLength
            } else {
                isBeginning = false
                let adjustment = Int(
                    tempo * Double(overlapLength) + 0.5 * Double(seekLength) + 0.5
                )
                skipFract -= Double(adjustment)
                if skipFract <= -nominalSkip {
                    skipFract = -nominalSkip
                }
            }
            if inputBuffer.availableFrames >= skip + seekWindowLength - overlapLength {
                let copyCount = seekWindowLength - 2 * overlapLength
                outputBuffer.append(framesFrom: inputBuffer, start: skip, count: copyCount)
                midBuffer = inputBuffer.copyFrames(
                    start: skip + copyCount, count: overlapLength
                )
                skipFract += nominalSkip
                let consume = Int(skipFract)
                skipFract -= Double(consume)
                inputBuffer.discard(frames: consume)
            }
        }
    }

    /// 前回末尾（midBuffer）と線形クロスフェードして出力へ追加する。
    private func overlapAppend(inputStartFrame: Int) {
        var output = [Float](repeating: 0, count: overlapLength * 2)
        let step = 1.0 / Float(overlapLength)
        var inputWeight: Float = 0
        var midWeight: Float = 1
        for frame in 0..<overlapLength {
            output[frame * 2] =
                inputBuffer.sample(frame: inputStartFrame + frame, channel: 0) * inputWeight
                + midBuffer[frame * 2] * midWeight
            output[frame * 2 + 1] =
                inputBuffer.sample(frame: inputStartFrame + frame, channel: 1) * inputWeight
                + midBuffer[frame * 2 + 1] * midWeight
            inputWeight += step
            midWeight -= step
        }
        outputBuffer.append(output, frameCount: overlapLength)
    }

    // MARK: - 相互相関による重なり位置探索

    /// midBuffer と最も相関の高い位置を探索窓内から探す（全探索）。
    private func seekBestOverlapPosition() -> Int {
        let corrLength = (2 * overlapLength) & ~7
        var anorm: Double = 0
        var bestScore = (crossCorr(frame: 0, corrLength: corrLength, anorm: &anorm) + 0.1) * 0.75
        var best = 0
        for position in 1..<seekLength {
            let corr = crossCorrAccumulate(frame: position, corrLength: corrLength, anorm: &anorm)
            let weight = Double(2 * position - seekLength) / Double(seekLength)
            let score = (corr + 0.1) * (1.0 - 0.25 * weight * weight)
            if score > bestScore {
                bestScore = score
                best = position
            }
        }
        return best
    }

    /// 正規化相互相関。`anorm` へ対象区間の二乗和を設定する。
    private func crossCorr(frame: Int, corrLength: Int, anorm: inout Double) -> Double {
        var corr: Double = 0
        var norm: Double = 0
        let base = frame * 2
        for index in 0..<corrLength {
            let value = Double(inputBuffer.sample(atSampleIndex: base + index))
            corr += value * Double(midBuffer[index])
            norm += value * value
        }
        anorm = norm
        return corr / (norm < 1e-9 ? 1.0 : sqrt(norm))
    }

    /// 二乗和を差分更新しながら正規化相互相関を求める（1 フレームずつ
    /// ずらした窓に対する本家の累積式）。
    private func crossCorrAccumulate(frame: Int, corrLength: Int, anorm: inout Double) -> Double {
        let base = frame * 2
        for channel in 1...2 {
            let value = Double(inputBuffer.sample(atSampleIndex: base - channel))
            anorm -= value * value
        }
        var corr: Double = 0
        for index in 0..<corrLength {
            corr +=
                Double(inputBuffer.sample(atSampleIndex: base + index))
                * Double(midBuffer[index])
        }
        var index = corrLength
        for _ in 0..<2 {
            index -= 1
            let value = Double(inputBuffer.sample(atSampleIndex: base + index))
            anorm += value * value
        }
        return corr / (anorm < 1e-9 ? 1.0 : sqrt(anorm))
    }
}

/// レート変換段（リサンプリングによる音程変換）。本家 SoundTouch.Net の
/// `RateTransposer` に対応する。補間は 3 次（Catmull-Rom 系の係数表）、
/// アンチエイリアス FIR（長さ 64、Hamming 窓 sinc、カットオフは
/// レート > 1 で 0.5 / rate、それ以外で 0.5 × rate）が常時有効。
final class SoundTouchRateTransposer {
    private let inputBuffer = SoundTouchFIFOBuffer()
    private let midBuffer = SoundTouchFIFOBuffer()
    private let outputBuffer = SoundTouchFIFOBuffer()
    /// 補間の小数位置（本家 `InterpolateCubic._fract`）。
    private var fract: Double = 0
    private(set) var rate: Double = 1.0
    /// 2^-14 で割った最終形の FIR 係数。
    private var aaCoefficients: [Float] = []

    /// アンチエイリアス FIR の長さ（本家既定）。
    private static let aaFilterLength = 64

    init() {
        aaCoefficients = Self.calculateCoefficients(cutoff: 0.5)
        clear()
    }

    var availableFrames: Int { outputBuffer.availableFrames }

    func setRate(_ newRate: Double) {
        rate = newRate
        let cutoff = newRate > 1.0 ? 0.5 / newRate : 0.5 * newRate
        aaCoefficients = Self.calculateCoefficients(cutoff: cutoff)
    }

    func clear() {
        outputBuffer.clear()
        midBuffer.clear()
        inputBuffer.clear()
        fract = 0
        // 遅延分（補間の 1 フレーム＋ FIR 長の半分）の無音を入力頭へ。
        inputBuffer.appendSilence(frames: 1 + Self.aaFilterLength / 2)
    }

    func putSamples(_ samples: [Float], frameCount: Int) {
        guard frameCount > 0 else { return }
        inputBuffer.append(samples, frameCount: frameCount)
        if rate < 1.0 {
            transpose(from: inputBuffer, to: midBuffer)
            aaEvaluate(from: midBuffer, to: outputBuffer)
        } else {
            aaEvaluate(from: inputBuffer, to: midBuffer)
            transpose(from: midBuffer, to: outputBuffer)
        }
    }

    @discardableResult
    func receiveSamples(into buffer: inout [Float], offset: Int, maxFrames: Int) -> Int {
        outputBuffer.receive(into: &buffer, offset: offset, maxFrames: maxFrames)
    }

    /// 処理済み出力をすべて取り出す（段の接続替え用）。
    func receiveAllOutput() -> [Float] {
        outputBuffer.receiveAll()
    }

    /// 出力バッファへ直接追加する（段の接続替えで処理済み出力を移す用）。
    func appendToOutput(_ samples: [Float], frameCount: Int) {
        outputBuffer.append(samples, frameCount: frameCount)
    }

    func adjustAmountOfSamples(_ frames: Int) {
        outputBuffer.adjustAmountOfSamples(frames)
    }

    // MARK: - 3 次補間

    private func transpose(from source: SoundTouchFIFOBuffer, to destination: SoundTouchFIFOBuffer) {
        let sourceFrames = source.availableFrames
        let limit = sourceFrames - 4
        guard limit > 0 else { return }
        var produced: [Float] = []
        produced.reserveCapacity((Int(Double(sourceFrames) / rate) + 8) * 2)
        var consumed = 0
        while consumed < limit {
            let f = Float(fract)
            let f2 = f * f
            let f3 = f2 * f
            let c0 = -0.5 * f3 + f2 - 0.5 * f
            let c1 = 1.5 * f3 - 2.5 * f2 + 1.0
            let c2 = -1.5 * f3 + 2.0 * f2 + 0.5 * f
            let c3 = 0.5 * f3 - 0.5 * f2
            produced.append(
                c0 * source.sample(frame: consumed, channel: 0)
                    + c1 * source.sample(frame: consumed + 1, channel: 0)
                    + c2 * source.sample(frame: consumed + 2, channel: 0)
                    + c3 * source.sample(frame: consumed + 3, channel: 0)
            )
            produced.append(
                c0 * source.sample(frame: consumed, channel: 1)
                    + c1 * source.sample(frame: consumed + 1, channel: 1)
                    + c2 * source.sample(frame: consumed + 2, channel: 1)
                    + c3 * source.sample(frame: consumed + 3, channel: 1)
            )
            fract += rate
            let advance = Int(fract)
            fract -= Double(advance)
            consumed += advance
        }
        destination.append(produced, frameCount: produced.count / 2)
        source.discard(frames: consumed)
    }

    // MARK: - アンチエイリアス FIR

    private func aaEvaluate(from source: SoundTouchFIFOBuffer, to destination: SoundTouchFIFOBuffer) {
        let sourceFrames = source.availableFrames
        let length = Self.aaFilterLength
        guard sourceFrames >= length else { return }
        let outputFrames = sourceFrames - length
        var output = [Float](repeating: 0, count: outputFrames * 2)
        for frame in 0..<outputFrames {
            var left: Double = 0
            var right: Double = 0
            for tap in 0..<length {
                let coefficient = Double(aaCoefficients[tap])
                left += Double(source.sample(frame: frame + tap, channel: 0)) * coefficient
                right += Double(source.sample(frame: frame + tap, channel: 1)) * coefficient
            }
            output[frame * 2] = Float(left)
            output[frame * 2 + 1] = Float(right)
        }
        destination.append(output, frameCount: outputFrames)
        source.discard(frames: outputFrames)
    }

    /// FIR 係数の生成。本家 `AntiAliasFilter.CalculateCoefficients` の
    /// 仕様どおり: Hamming 窓 sinc を合計が 16384 になるよう拡縮し、
    /// 符号方向へ 0.5 を加えた float 値を 2^14 で割る（同梱版では
    /// 整数への切り捨ては行われず、この偏りがそのまま残る）。
    private static func calculateCoefficients(cutoff: Double) -> [Float] {
        let length = aaFilterLength
        let omega = 2.0 * Double.pi * cutoff
        let windowStep = 2.0 * Double.pi / Double(length)
        var work = [Double](repeating: 0, count: length)
        var sum: Double = 0
        for index in 0..<length {
            let x = Double(index) - Double(length) / 2.0
            let arg = x * omega
            let sinc = arg == 0 ? 1.0 : sin(arg) / arg
            let value = (0.54 + 0.46 * cos(windowStep * x)) * sinc
            work[index] = value
            sum += value
        }
        let scale = 16384.0 / sum
        return work.map { value in
            var scaled = value * scale
            scaled += scaled >= 0 ? 0.5 : -0.5
            return Float(Double(Float(scaled)) * (1.0 / 16384.0))
        }
    }
}

/// SoundTouch 互換プロセッサ全体。本家 SoundTouch.Net の
/// `SoundTouchProcessor` に対応する。チャンネル数は 2 固定
/// （本家の利用箇所はすべてステレオ）。
public final class SoundTouchProcessor {
    private let stretch = SoundTouchTimeStretch()
    private let transposer = SoundTouchRateTransposer()
    private var effectiveRate: Double = 1.0
    private var effectiveTempo: Double = 1.0
    /// 出力段がレート変換段かどうか（有効レート > 1 のとき）。
    private var outputIsTransposer = false
    /// フラッシュ時の目標出力フレーム数の算出用（本家と同じ累積式）。
    private var samplesExpectedOut: Double = 0
    private var samplesOutput: Int = 0

    public init() {}

    /// テンポ（1.0 = 等速。2.0 で長さが半分になる）。
    public var tempo: Double = 1.0 {
        didSet { updateEffective() }
    }

    /// 音程（1.0 = そのまま。長さは変わらない）。
    public var pitch: Double = 1.0 {
        didSet { updateEffective() }
    }

    /// レート（リサンプリング倍率。本家の利用箇所では常に 1.0）。
    public var rate: Double = 1.0 {
        didSet { updateEffective() }
    }

    /// サンプルレート。時間伸縮段のパラメータ計算に使う。
    public var sampleRate: Int = 44_100 {
        didSet { stretch.setParameters(sampleRate: sampleRate) }
    }

    /// 出力可能なフレーム数。
    public var availableFrames: Int {
        outputIsTransposer ? transposer.availableFrames : stretch.availableFrames
    }

    /// 入力フレーム列を供給する。
    public func putSamples(_ samples: [Float], frameCount: Int) {
        guard frameCount > 0 else { return }
        samplesExpectedOut += Double(frameCount) / (effectiveRate * effectiveTempo)
        if effectiveRate <= 1.0 {
            transposer.putSamples(samples, frameCount: frameCount)
            let moved = transposer.receiveAllOutput()
            stretch.putSamples(moved, frameCount: moved.count / 2)
        } else {
            stretch.putSamples(samples, frameCount: frameCount)
            let moved = stretch.receiveAllOutput()
            transposer.putSamples(moved, frameCount: moved.count / 2)
        }
    }

    /// 出力フレームを取り出す。取り出したフレーム数を返す。
    @discardableResult
    public func receiveSamples(into buffer: inout [Float], offset: Int, maxFrames: Int) -> Int {
        let count =
            outputIsTransposer
            ? transposer.receiveSamples(into: &buffer, offset: offset, maxFrames: maxFrames)
            : stretch.receiveSamples(into: &buffer, offset: offset, maxFrames: maxFrames)
        samplesOutput += count
        return count
    }

    /// 終端処理。期待出力フレーム数に届くまで無音を供給し、出力を
    /// 目標数へ切り詰めたうえで、時間伸縮段の入力を空にする。
    public func flush() {
        var target = Int(samplesExpectedOut + 0.5) - samplesOutput
        if target < 0 { target = 0 }
        let silence = [Float](repeating: 0, count: 128 * 2)
        var iterations = 0
        while target > availableFrames && iterations < 200 {
            putSamples(silence, frameCount: 128)
            iterations += 1
        }
        if outputIsTransposer {
            transposer.adjustAmountOfSamples(target)
        } else {
            stretch.adjustAmountOfSamples(target)
        }
        stretch.clearInput()
    }

    /// 全状態を初期化する（テンポ・音程・レート・サンプルレートは保持）。
    public func clear() {
        samplesExpectedOut = 0
        samplesOutput = 0
        transposer.clear()
        stretch.clear()
    }

    /// 有効テンポ・有効レートの再計算と、段の接続替えに伴う移送。
    private func updateEffective() {
        let newTempo = tempo / pitch
        let newRate = pitch * rate
        if newRate != effectiveRate {
            transposer.setRate(newRate)
        }
        if newTempo != effectiveTempo {
            stretch.setTempo(newTempo)
        }
        effectiveRate = newRate
        effectiveTempo = newTempo
        if newRate <= 1.0 {
            if outputIsTransposer {
                let pending = transposer.receiveAllOutput()
                stretch.appendToOutput(pending, frameCount: pending.count / 2)
                outputIsTransposer = false
            }
        } else if !outputIsTransposer {
            let pending = stretch.receiveAllOutput()
            transposer.appendToOutput(pending, frameCount: pending.count / 2)
            let residue = stretch.receiveAllInput()
            transposer.putSamples(residue, frameCount: residue.count / 2)
            outputIsTransposer = true
        }
    }
}
