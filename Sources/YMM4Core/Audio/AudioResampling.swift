import Foundation

/// 補間カーネル。本家 `IInterpolationAlgorithm`（Commons）に対応する。
/// `taps` は中心から片側に参照するフレーム数、`weight` は距離への重み。
public protocol InterpolationKernel {
    var taps: Int { get }
    func weight(distance: Double) -> Double
}

/// 線形補間カーネル。本家 Commons `Linear` に対応する。
public struct LinearInterpolationKernel: InterpolationKernel {
    public init() {}
    public var taps: Int { 1 }
    public func weight(distance: Double) -> Double {
        distance <= 1 ? 1 - distance : 0
    }
}

/// Cubic 補間カーネル。本家 Commons `Cubic` に対応する。
/// 重み関数はモデル層の `Cubic`（A = -0.5）をそのまま使う。
public struct CubicInterpolationKernel: InterpolationKernel {
    private let cubic = Cubic()
    public init() {}
    public var taps: Int { 2 }
    public func weight(distance: Double) -> Double {
        cubic.weight(distance: distance)
    }
}

/// 帯域制限補間（窓関数 sinc）によるサンプル生成コア。
///
/// リサンプラの「契約」（長さ・シーク・位置の変換式と素通し規則）は
/// 本家 MFT ラッパーの実測式で固定し、差し替えるのはこの生成コアだけ
/// とする設計（AUDIO-FIDELITY-PLAN §1.1 の候補 (a)）。位置写像は
/// 出力フレーム j → 素材位置 j × (Input.Hz / Hz) のままで、カーネルは
/// 中心遅延 0 の対称 FIR として構成するため、遅延は生じない。
///
/// カーネルの形（正式仕様、2026-11-17 決定。AUDIO-FIDELITY-PLAN
/// §3.1.3）:
/// - 倍率 scale = max(1, Input.Hz / Hz)。ダウンスンプル時は出力
///   ナイキストに合わせてカーネルを scale 倍に広げ、折り返しを防ぐ
///   （アップサンプル時は scale = 1 で入力ナイキストが帯域制限）。
/// - 重み h(t) = sinc(t / scale) × Kaiser 窓(t / 支持幅) / scale。
///   支持幅は片側 `halfWidthCycles` = 96 零点（scale = 1 のとき
///   片側 96 フレーム、計 193 タップ）、Kaiser 窓の β は
///   `kaiserBeta` = 8.96（設計減衰 A ≈ 90 dB に対応）。
/// - 選定経緯: 当初は Blackman 窓・片側 48 零点で「帯域端でも
///   -80dB 級」と見ていたが、QA24-01 の周波数掃引（25Hz 格子）で
///   阻止帯域 [23.2k–24kHz] の最悪値は -60.27 dB（帯域端）と判明
///   し、その記述は撤回した。同じ測定系での候補比較（§3.1.2）の
///   結果、正式合格値（阻止帯域の最悪値 -80 dB 以下、通過帯域
///   20kHz まで ±0.1 dB 以内）を余裕を持って満たしたのは
///   Kaiser 96 のみ（実測: 最悪値 -94.54 dB、平坦さ 0.0001 dB
///   未満）。制限要因は窓長ではなく窓関数のサイドローブ構造
///   だった。
/// - コストは素朴な実装のままで Blackman 48 の約 3.1 倍
///   （Release、§3.1.2）。係数テーブル化／ポリフェーズ化は
///   将来作業として計画書に残す。
/// - 出力は重みの総和で割って正規化する。定数信号が厳密に保存され、
///   DC ゲインが 1 になることを保証するため（窓掛けで落ちる
///   ゲインを補う）。本家の MFT と波形が等しいことは引き続き
///   **未検証**で、品質は自前の周波数応答実測で担保する。
struct BandLimitedResamplingCore {
    /// カーネル片側の零点数（scale = 1 のときのタップ半幅）。
    /// 正式仕様として固定（2026-11-17、§3.1.3）。
    static let halfWidthCycles = 96.0

    /// Kaiser 窓の β。設計減衰 A ≈ 90 dB（β = 0.1102 × (A − 8.7)
    /// ≈ 8.96）に対応する。正式仕様として固定（§3.1.3）。
    static let kaiserBeta = 8.96

    /// 窓の正規化分母 I0(β)。β が固定のため事前に1回だけ評価する。
    static let kaiserDenominator = besselI0(kaiserBeta)

    /// 素材位置 `sourcePosition`（入力フレーム単位）における補間値。
    /// `ratio` は Input.Hz / Hz（入力フレーム / 出力フレーム）。
    static func sample(
        window: InputFrameWindow, at sourcePosition: Double, ratio: Double
    ) -> (left: Float, right: Float) {
        let scale = max(1.0, ratio)
        let support = halfWidthCycles * scale
        let firstIndex = Int((sourcePosition - support).rounded(.up))
        let lastIndex = Int((sourcePosition + support).rounded(.down))
        var numeratorLeft = 0.0
        var numeratorRight = 0.0
        var denominator = 0.0
        for index in firstIndex...lastIndex {
            let distance = sourcePosition - Double(index)
            let weight = kernelWeight(distance: distance, scale: scale, support: support)
            if weight == 0 { continue }
            let frame = window.frame(at: index)
            numeratorLeft += Double(frame.left) * weight
            numeratorRight += Double(frame.right) * weight
            denominator += weight
        }
        guard denominator != 0 else { return (0, 0) }
        return (
            Float(numeratorLeft / denominator),
            Float(numeratorRight / denominator)
        )
    }

    /// 窓関数 sinc の重み。|distance| >= support では 0。
    static func kernelWeight(distance: Double, scale: Double, support: Double) -> Double {
        let magnitude = abs(distance)
        if magnitude >= support { return 0 }
        let scaled = distance / scale
        let sincValue = scaled == 0 ? 1.0 : sin(.pi * scaled) / (.pi * scaled)
        // Kaiser 窓。phase は -1..<1 で、支持端では I0(0)/I0(β)
        // （小さいが 0 ではない。|distance| >= support の扱いは
        // 冒頭の早期 return が担う）、中心で 1。
        let phase = distance / support
        let windowValue =
            besselI0(kaiserBeta * (1 - phase * phase).squareRoot()) / kaiserDenominator
        return sincValue * windowValue / scale
    }

    /// 第1種変形ベッセル関数 I0 の級数展開。項が和に対して
    /// 1e-15 を下回った時点で打ち切る（|x| <= 8.96 の範囲では
    /// 数十項で収束する）。
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let y = x * x / 4
        var k = 1.0
        while k < 200 {
            term *= y / (k * k)
            sum += term
            if term < sum * 1e-15 { break }
            k += 1
        }
        return sum
    }
}

/// サンプリングレート変換。本家 `Resampler`（MediaFoundation の
/// リサンプラー MFT）に対応する位置づけの処理器。
///
/// 本家との関係: 本家は Windows の Resampler MFT（COM）に変換を委ね、
/// `Input.Hz == Hz` のときだけ素通しする。ここでは変換を
/// `BandLimitedResamplingCore`（窓関数 sinc の帯域制限補間）で
/// 自前実装する。**変換の品質・位相特性が本家の MFT と等しいことは
/// 未検証**であり、台帳に記録する前提の置換である。
///
/// 意味論（本家どおり）:
/// - 目標 Hz 指定と倍率指定の2形式。倍率形式の出力 Hz は
///   `Int(Input.Hz × 倍率)`。
/// - 長さは `Input.Duration × (Hz / Input.Hz)` を偶数へ切り捨て。
///   入力が無制限・0 の場合はそのまま。
/// - シークは位置を `Input.Hz / Hz` 倍して偶数へ切り捨て、入力へ転送。
/// - 素通し時は読み取り・シークとも入力へそのまま転送する。
public final class ResamplerStream: AudioEffectProcessorBase {
    private enum Mode {
        case toHz(Int)
        case byRate(Double)
    }

    private let mode: Mode
    private var window: InputFrameWindow?

    /// 目標 Hz への変換。
    public init(toHz targetHz: Int) {
        mode = .toHz(targetHz)
        super.init()
    }

    /// 倍率による変換（出力 Hz が入力の `rate` 倍になる）。
    public init(byRate rate: Double) {
        mode = .byRate(rate)
        super.init()
    }

    public override var hz: Int {
        guard let input else { return 0 }
        switch mode {
        case .toHz(let target): return target
        case .byRate(let rate): return Int(Double(input.hz) * rate)
        }
    }

    public override var duration: Int {
        guard let input else { return 0 }
        let inputDuration = input.duration
        if inputDuration == Int.max || inputDuration == 0 { return inputDuration }
        guard input.hz > 0, hz > 0 else { return 0 }
        let scaled = Int(Double(inputDuration) * (Double(hz) / Double(input.hz)))
        return scaled - scaled % 2
    }

    private var isPassthrough: Bool {
        guard let input else { return false }
        return input.hz == hz
    }

    override func seekImpl(_ position: Int) {
        guard let input else { return }
        if isPassthrough {
            input.seek(to: position)
            return
        }
        guard input.hz > 0, hz > 0 else { return }
        var target = Int(Double(position) * (Double(input.hz) / Double(hz)))
        target -= target % 2
        input.seek(to: target)
        window?.invalidate()
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input else { return 0 }
        if isPassthrough {
            return input.read(into: &buffer, offset: offset, count: count)
        }
        guard input.hz > 0, hz > 0 else { return 0 }
        let window = self.window ?? InputFrameWindow(input: input)
        self.window = window
        let ratio = Double(input.hz) / Double(hz)
        let startFrame = position / 2
        let frameCount = count / 2
        for frameIndex in 0..<frameCount {
            let sourcePosition = Double(startFrame + frameIndex) * ratio
            let value = BandLimitedResamplingCore.sample(
                window: window, at: sourcePosition, ratio: ratio
            )
            buffer[offset + frameIndex * 2] = value.left
            buffer[offset + frameIndex * 2 + 1] = value.right
        }
        return frameCount * 2
    }
}

/// 定数再生速度（リサンプリング方式）。本家 `PlaybackRateEffect`
/// （再生速度を入力 Hz の申告変更として MFT リサンプラへ渡す）に対応する。
///
/// 意味論（本家どおり）:
/// - 長さは `Input.Duration / |rate|` を偶数へ切り捨て（rate = 0 なら 0、
///   入力が無制限・0 ならそのまま）。
/// - シークは位置 × rate を偶数へ切り捨てて入力へ転送。rate = 1 のときは
///   そのまま転送し、読み取りも素通し。rate ≦ 0 ではシークも読み取りも
///   何もしない（読み取りは 0 を返す）。
/// - SOLA 方式（本家 `PlaybackRateSolaTimeStretchEffect`）は差し替え点
///   とし、ここではリサンプリング方式（ピッチも変わる）で代替する。
public final class PlaybackRateStream: AudioEffectProcessorBase {
    /// 速度倍率（1.0 = 等速）。符号なし（負の速度は Reverse が担う）。
    public let rate: Double
    private var window: InputFrameWindow?

    public init(rate: Double) {
        self.rate = rate
        super.init()
    }

    public override var duration: Int {
        guard let input else { return 0 }
        let inputDuration = input.duration
        if inputDuration == Int.max || inputDuration == 0 { return inputDuration }
        if rate == 0 { return 0 }
        let scaled = Int(Double(inputDuration) / abs(rate))
        return scaled - scaled % 2
    }

    override func seekImpl(_ position: Int) {
        guard let input, rate > 0 else { return }
        if rate == 1 {
            input.seek(to: position)
            return
        }
        var target = Int(Double(position) * rate)
        target -= target % 2
        input.seek(to: target)
        window?.invalidate()
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input, rate > 0 else { return 0 }
        if rate == 1 {
            return input.read(into: &buffer, offset: offset, count: count)
        }
        let window = self.window ?? InputFrameWindow(input: input)
        self.window = window
        let startFrame = position / 2
        let frameCount = count / 2
        for frameIndex in 0..<frameCount {
            let sourcePosition = Double(startFrame + frameIndex) * rate
            let lower = Int(sourcePosition.rounded(.down))
            let fraction = Float(sourcePosition - Double(lower))
            let first = window.frame(at: lower)
            let second = window.frame(at: lower + 1)
            buffer[offset + frameIndex * 2] = first.left + (second.left - first.left) * fraction
            buffer[offset + frameIndex * 2 + 1] =
                first.right + (second.right - first.right) * fraction
        }
        return frameCount * 2
    }
}

/// 可変再生速度。本家 `VariablePlaybackRateEffect` に対応する。
///
/// 出力フレームごとに、既存実装 `PlaybackRateMap` の積分テーブルで
/// 「アイテム時刻までに消費する素材 tick」を求め、開始オフセット
/// （開始レートが負なら素材末尾から測る）を加えて素材フレーム位置を
/// 得る。素材位置は線形補間で読む。ループ時は素材フレーム数で剰余を
/// 取り、範囲外は無音を書いて読み進める。素材が尽きるアイテム時刻
/// （本家 `FindContentExhaustedTime`）以降は読み取りが短くなる。
///
/// 本家との差: 尽きる時刻の算出は本家では `PlaybackRateMap` 内の
/// 専用探索だが、既存の Swift 実装には無いため、ここでは累積 tick の
/// 走査＋二分探索で近似する（台帳に記録）。SOLA のピッチ補正
/// （本家 `VariableSolaPitchCorrectionEffect`）は差し替え点とし、
/// 適用しない。
public final class VariablePlaybackRateStream: AudioEffectProcessorBase {
    /// 速度カーブの積分マップ（既存実装を利用）。
    public let rateMap: PlaybackRateMap
    /// アイテムの長さ（フレーム）。
    public let itemLength: Int
    /// プロジェクトの FPS。
    public let fps: Int
    /// 素材の開始位置オフセット。
    public let contentOffset: TimeSpanValue
    /// ループするか。
    public let isLooped: Bool

    private var cachedTable: PlaybackRateMap.Table?
    private var cachedExhaustedPosition: Int?
    private var window: InputFrameWindow?

    public init(
        rateMap: PlaybackRateMap, itemLength: Int, fps: Int,
        contentOffset: TimeSpanValue, isLooped: Bool
    ) {
        self.rateMap = rateMap
        self.itemLength = itemLength
        self.fps = fps
        self.contentOffset = contentOffset
        self.isLooped = isLooped
        super.init()
    }

    private var table: PlaybackRateMap.Table {
        if let cachedTable { return cachedTable }
        let built = rateMap.table(itemLength: itemLength, fps: fps)
        cachedTable = built
        return built
    }

    /// 素材のフレーム数（偶数調整済み長さの半分）。
    private var contentFrameCount: Int {
        guard let input else { return 0 }
        let evenDuration = input.duration - input.duration % 2
        return evenDuration / 2
    }

    /// 素材の長さ（tick、偶数調整済み長さから換算）。
    private var contentDurationTicks: Int64 {
        guard let input else { return 0 }
        let evenDuration = input.duration - input.duration % 2
        return positionToTimeTicks(evenDuration)
    }

    /// 消費 tick の起点。本家 `GetStartTicks`（contentStartProvider は
    /// 使わない経路）: 開始レートが負なら素材末尾からオフセットを引く。
    private var startTicks: Int64 {
        if table.rates.first ?? 0 >= 0 {
            return contentOffset.ticks
        }
        return contentDurationTicks - contentOffset.ticks
    }

    /// 素材が尽きる出力位置（サンプル）。尽きなければ `Int.max`。
    private var exhaustedPosition: Int {
        if let cachedExhaustedPosition { return cachedExhaustedPosition }
        let result = computeExhaustedPosition()
        cachedExhaustedPosition = result
        return result
    }

    private func computeExhaustedPosition() -> Int {
        let contentTicks = contentDurationTicks
        let start = startTicks
        let table = self.table
        // 開始時点で既に範囲外なら 0。
        if start < 0 || start > contentTicks { return 0 }
        var previousTicks: Int64 = 0
        var previousSource = start
        for frame in 0...table.length {
            let frameTicks = Int64(
                (Double(frame) * 10_000_000 / Double(max(fps, 1)))
                    .rounded(.toNearestOrAwayFromZero)
            )
            let source = start + Int64(table.cumulativeTicks[frame])
            let crossed = (previousSource < contentTicks && source >= contentTicks)
                || (previousSource > 0 && source <= 0)
            if crossed && frame > 0 {
                // このフレーム区間内で境界と交わるアイテム tick を二分探索。
                let boundary: Int64 = source >= contentTicks ? contentTicks : 0
                var low = previousTicks
                var high = frameTicks
                for _ in 0..<48 {
                    let mid = (low + high) / 2
                    let midSource = start + Int64(table.getConsumedTicks(timeTicks: mid))
                    if (boundary == contentTicks && midSource < boundary)
                        || (boundary == 0 && midSource > boundary)
                    {
                        low = mid
                    } else {
                        high = mid
                    }
                }
                return timeToPosition(high)
            }
            previousTicks = frameTicks
            previousSource = source
        }
        return Int.max
    }

    public override var duration: Int {
        if isLooped { return Int.max }
        return exhaustedPosition
    }

    override func seekImpl(_ position: Int) {
        // 本家はウィンドウを捨てるだけで、入力へのシークは読み取り時に
        // 位置計算から行う。
        window?.invalidate()
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input else { return 0 }
        let frameCount = contentFrameCount
        if frameCount <= 0 { return 0 }
        let window = self.window ?? InputFrameWindow(input: input)
        self.window = window
        let table = self.table
        let start = startTicks
        let exhausted = isLooped ? Int.max : exhaustedPosition
        var written = 0
        while written < count - 1 {
            let outputPosition = position + written
            if outputPosition >= exhausted { break }
            let itemTicks = positionToTimeTicks(outputPosition)
            let consumed = table.getConsumedTicks(timeTicks: itemTicks)
            var sourceFrame = (Double(start) + consumed) * (Double(hz) / 10_000_000.0)
            if isLooped {
                sourceFrame = sourceFrame.truncatingRemainder(dividingBy: Double(frameCount))
                if sourceFrame < 0 { sourceFrame += Double(frameCount) }
            } else if sourceFrame < 0 || sourceFrame >= Double(frameCount) {
                buffer[offset + written] = 0
                buffer[offset + written + 1] = 0
                written += 2
                continue
            }
            var lower = Int(sourceFrame.rounded(.down))
            if lower >= frameCount { lower = frameCount - 1 }
            var fraction = Float(sourceFrame - Double(lower))
            var upper = lower + 1
            if upper >= frameCount {
                upper = lower
                fraction = 0
            }
            let first = window.frame(at: lower)
            let second = window.frame(at: upper)
            buffer[offset + written] = first.left + (second.left - first.left) * fraction
            buffer[offset + written + 1] = first.right + (second.right - first.right) * fraction
            written += 2
        }
        return written
    }
}

/// 整数倍アップサンプリング（VoiceItem 専用）。本家 `Upsampler` に対応する。
///
/// 倍率は `targetHz / Input.Hz` の整数商（最低 1）。出力フレーム位置から
/// 入力位置への写像は本家どおり
/// `in = out / rate + 1 / (2 × rate) - 0.5` で、写像先を中心に
/// カーネルの重み付き和を取る。本家は 8000 サンプル × 3 枚のバッファで
/// 前後を引くが、ここでは入力窓（InputFrameWindow）で代替する
/// （観測できる出力は同じになるよう写像と重みを一致させる）。
/// カーネルは Linear / Cubic を実装し、その他（Lanczos 等）は
/// 差し替え点として台帳に残す。
public final class UpsamplerStream: AudioEffectProcessorBase {
    /// 目標 Hz（タイムラインの Hz）。
    public let targetHz: Int
    /// 補間カーネル。
    public let kernel: any InterpolationKernel
    private var resolvedRate: Int = 0
    private var window: InputFrameWindow?

    public init(targetHz: Int, kernel: any InterpolationKernel) {
        self.targetHz = targetHz
        self.kernel = kernel
        super.init()
    }

    /// 整数倍率。本家 `Rate`（遅延評価）。
    public var rate: Int {
        if resolvedRate == 0 {
            let inputHz = max(input?.hz ?? 0, 1)
            resolvedRate = max(targetHz / inputHz, 1)
        }
        return resolvedRate
    }

    public override var hz: Int { (input?.hz ?? 0) * rate }

    public override var duration: Int {
        guard let input else { return 0 }
        if input.duration == Int.max { return Int.max }
        let scaled = input.duration * rate
        return scaled - scaled % 2
    }

    override func seekImpl(_ position: Int) {
        window?.invalidate()
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input else { return 0 }
        let window = self.window ?? InputFrameWindow(input: input)
        self.window = window
        let rate = self.rate
        let startFrame = position / 2
        let frameCount = count / 2
        for frameIndex in 0..<frameCount {
            let outputFrame = startFrame + frameIndex
            let inputPosition = Double(outputFrame) / Double(rate)
                + 1.0 / (2.0 * Double(rate)) - 0.5
            let center = Int(inputPosition.rounded(.toNearestOrAwayFromZero))
            var left: Float = 0
            var right: Float = 0
            for tap in -kernel.taps...kernel.taps {
                let index = center + tap
                let weight = kernel.weight(distance: abs(inputPosition - Double(index)))
                if weight == 0 { continue }
                let frame = window.frame(at: index)
                left += frame.left * Float(weight)
                right += frame.right * Float(weight)
            }
            buffer[offset + frameIndex * 2] = left
            buffer[offset + frameIndex * 2 + 1] = right
        }
        return frameCount * 2
    }
}
