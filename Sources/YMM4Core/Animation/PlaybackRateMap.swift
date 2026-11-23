import Foundation

/// 再生速度カーブの積分テーブル。本家 `PlaybackRateMap` に対応する。
///
/// 再生速度（%）をフレームごとに評価し、台形積分で累積消費 tick を持つ。
/// アイテム分割時の右側 `ContentOffset` 計算（非定数レート経路）に使う。
/// 本家は内部クラスだが、分割の意味論の一部であるため公開する。
public struct PlaybackRateMap: Sendable {
    /// 元の再生速度アニメーション（アイテムの `PlaybackRate2`）。
    public var rate: Animation

    public init(rate: Animation) {
        self.rate = rate
    }

    /// レートが定数かどうか。本家 `IsConstant`（型が「なし」のとき定数）。
    public var isConstant: Bool {
        rate.animationType == .none
    }

    /// 先頭のレート値（%）。
    public var firstRate: Double {
        rate.firstValue
    }

    /// フレームごとのレートと累積消費 tick のテーブル。
    public struct Table: Sendable {
        public var length: Int
        public var fps: Int
        /// フレーム 0...length のレート値。
        public var rates: [Double]
        /// フレーム 0...length の累積消費 tick。
        public var cumulativeTicks: [Double]

        public var frameDurationTicks: Double {
            10_000_000.0 / Double(fps)
        }

        /// 時刻 tick におけるレート（%）。本家 `Table.GetRate`。
        ///
        /// フレーム内はレートが線形に変化するものとして補間する。
        /// 可変速度の SOLA ピッチ補正（ブロック中央時刻の速度参照）で使う。
        public func getRate(timeTicks: Int64) -> Double {
            let frameDuration = frameDurationTicks
            let frame = min(max(Int((Double(timeTicks) / frameDuration).rounded(.down)), 0), length)
            let inFrame = Double(timeTicks) - Double(frame) * frameDuration
            let rateHere = rates[frame]
            let rateNext = rates[min(frame + 1, length)]
            return rateHere + (rateNext - rateHere) * inFrame / frameDuration
        }

        /// 時刻 tick における消費 tick。本家 `Table.GetConsumedTicks`。
        ///
        /// フレーム内はレートが線形に変化するものとして台形で積分する。
        public func getConsumedTicks(timeTicks: Int64) -> Double {
            let frameDuration = frameDurationTicks
            let frame = min(max(Int((Double(timeTicks) / frameDuration).rounded(.down)), 0), length)
            let inFrame = Double(timeTicks) - Double(frame) * frameDuration
            let rateHere = rates[frame]
            let rateSlope = (rates[min(frame + 1, length)] - rateHere) / frameDuration
            return cumulativeTicks[frame] + (rateHere + rateSlope * inFrame / 2.0) / 100.0 * inFrame
        }
    }

    /// テーブルを構築する。本家 `GetTable(itemLength, fps)`。
    public func table(itemLength: Int, fps: Int) -> Table {
        let length = max(1, itemLength)
        let fps = max(1, fps)
        var rates = [Double](repeating: 0, count: length + 1)
        for frame in 0...length {
            rates[frame] = rate.value(atFrame: frame, length: length, fps: fps)
        }
        let frameDuration = 10_000_000.0 / Double(fps)
        var cumulative = [Double](repeating: 0, count: length + 1)
        for frame in 0..<length {
            cumulative[frame + 1] = cumulative[frame]
                + (rates[frame] + rates[frame + 1]) / 2.0 / 100.0 * frameDuration
        }
        return Table(length: length, fps: fps, rates: rates, cumulativeTicks: cumulative)
    }

    /// 時刻までに消費する素材側の長さ。本家 `GetConsumedContent`。
    public func getConsumedContent(time: TimeSpanValue, itemLength: Int, fps: Int) -> TimeSpanValue {
        if isConstant || fps <= 0 {
            return TimeSpanValue(ticks: Int64(Double(time.ticks) * firstRate / 100.0))
        }
        let consumed = table(itemLength: itemLength, fps: fps).getConsumedTicks(timeTicks: time.ticks)
        return TimeSpanValue(ticks: Int64(consumed.rounded(.awayFromZero)))
    }

    /// 素材が尽きる時刻（アイテム内時刻）。本家 `FindContentExhaustedTime`。
    ///
    /// テーブル範囲内では、累積消費が素材範囲 [0, contentLength] の
    /// 境界へ達するフレーム内位置を、レートの線形変化に対する二次式で
    /// 解く（本家の SolveCrossingTau）。範囲内で尽きない場合は末尾の
    /// レートで外挿し、末尾レートが 0 のときだけ nil を返す。
    /// `contentStart` は消費の起点（通常は開始レートの符号で
    /// `contentOffset` か `contentLength - contentOffset`）。
    public func findContentExhaustedTime(
        itemLength: Int, fps: Int,
        contentOffset: TimeSpanValue, contentLength: TimeSpanValue,
        contentStart: TimeSpanValue? = nil
    ) -> TimeSpanValue? {
        let contentTicks = contentLength.ticks
        let table = table(itemLength: itemLength, fps: fps)
        let frameDuration = table.frameDurationTicks
        let start = contentStart.map { Double($0.ticks) }
            ?? (table.rates[0] >= 0
                ? Double(contentOffset.ticks)
                : Double(contentTicks - contentOffset.ticks))
        if start < 0 || Double(contentTicks) < start {
            return .zero
        }
        var previous = start
        for i in 1...table.length {
            let current = start + table.cumulativeTicks[i]
            let rate0 = table.rates[i - 1]
            let rate1 = table.rates[i]
            let slope = (rate1 - rate0) / frameDuration
            if rate0 * rate1 < 0 {
                // フレーム内でレートの符号が変わる場合はゼロ交点を先に見る。
                let tauZero = (0 - rate0) / slope
                let atZero = previous + (rate0 + slope * tauZero / 2) / 100 * tauZero
                if atZero < 0 || Double(contentTicks) < atZero {
                    let boundary = atZero < 0 ? 0.0 : Double(contentTicks)
                    let tau = Self.solveCrossingTau(
                        previous: previous, rate0: rate0, slopePerTick: slope,
                        boundary: boundary, tauLimit: tauZero
                    ) ?? tauZero
                    return TimeSpanValue(
                        ticks: Int64(Double(i - 1) * frameDuration + tau)
                    )
                }
            }
            if current < 0 || Double(contentTicks) < current {
                let boundary = current < 0 ? 0.0 : Double(contentTicks)
                let fallback = min(max((boundary - previous) / (current - previous), 0), 1)
                    * frameDuration
                let tau = Self.solveCrossingTau(
                    previous: previous, rate0: rate0, slopePerTick: slope,
                    boundary: boundary, tauLimit: frameDuration
                ) ?? fallback
                return TimeSpanValue(
                    ticks: Int64(Double(i - 1) * frameDuration + tau)
                )
            }
            previous = current
        }
        // テーブルの末尾までに尽きなければ、末尾レートで外挿する。
        let endRate = table.rates[table.length] / 100
        let consumedAtEnd = start + table.cumulativeTicks[table.length]
        let itemEndTicks = Double(table.length) * frameDuration
        if endRate > 0 {
            return TimeSpanValue(
                ticks: Int64(itemEndTicks + (Double(contentTicks) - consumedAtEnd) / endRate)
            )
        }
        if endRate < 0 {
            return TimeSpanValue(
                ticks: Int64(itemEndTicks + consumedAtEnd / (0 - endRate))
            )
        }
        return nil
    }

    /// 境界へ達するフレーム内位置（tick）を二次式で解く。
    /// 本家 `SolveCrossingTau`。(0, tauLimit] に入る小さい方の解を返す。
    private static func solveCrossingTau(
        previous: Double, rate0: Double, slopePerTick: Double,
        boundary: Double, tauLimit: Double
    ) -> Double? {
        let a = slopePerTick / 200
        let b = rate0 / 100
        let c = previous - boundary
        var root1: Double
        var root2: Double
        if abs(a) < 1e-18 {
            if b == 0 { return nil }
            root1 = -c / b
            root2 = root1
        } else {
            let discriminant = b * b - 4 * a * c
            if discriminant < 0 { return nil }
            let sqrtD = discriminant.squareRoot()
            root1 = (-b - sqrtD) / (2 * a)
            root2 = (-b + sqrtD) / (2 * a)
            if root2 < root1 { swap(&root1, &root2) }
        }
        if 0 < root1 && root1 <= tauLimit { return root1 }
        if 0 < root2 && root2 <= tauLimit { return root2 }
        return nil
    }

    /// 素材境界（ループの繰り返し境界）を横切る時刻を、アイテム
    /// 時間軸の順に遅延列挙する（本家 `EnumerateContentBoundaryCrossings`）。
    ///
    /// 各フレーム区間について、その区間の両端での累積消費位置
    /// （素材時刻）の間に素材長の整数倍があれば、その境界を横切る
    /// 時刻を区間内の線形補間で求める。逆行（消費位置が減少する
    /// 区間）でも境界を列挙する。横切時刻は本家どおりフレーム内
    /// 位置を線形補間してティックへ切り捨てる
    /// （`findContentExhaustedTime` の二次求解とは別方式で、本家も
    /// この列挙では線形補間を使う）。
    ///
    /// 開始位置は、先頭レートが非負なら素材オフセット位置、負なら
    /// 素材末尾からオフセットを引いた位置（逆再生では素材末尾側
    /// から消費が始まる）。列挙は遅延であり、消費側が打ち切れば
    /// 残りは計算されない（ループ素材では横切回数がアイテム長と
    /// 素材長の比まで増えるため）。
    ///
    /// 素材長がゼロ以下なら空。
    public func enumerateContentBoundaryCrossings(
        itemLength: Int,
        fps: Int,
        contentOffset: TimeSpanValue,
        contentLength: TimeSpanValue
    ) -> AnySequence<TimeSpanValue> {
        let contentTicks = contentLength.ticks
        guard contentTicks > 0 else { return AnySequence([]) }
        let table = table(itemLength: itemLength, fps: fps)
        let start = table.rates[0] >= 0
            ? Double(contentOffset.ticks)
            : Double(contentTicks - contentOffset.ticks)
        return AnySequence {
            BoundaryCrossingIterator(
                start: start,
                contentSpan: Double(contentTicks),
                frameDurationTicks: table.frameDurationTicks,
                cumulativeTicks: table.cumulativeTicks,
                frameCount: table.length
            )
        }
    }

    /// 素材側の時刻。本家 `GetSourceTime`。
    ///
    /// 定数レートでは符号で向きを切り替える。非定数ではテーブルの積分を
    /// 使い、開始レートの符号で起点（`contentOffset` か
    /// `contentLength - contentOffset`）を選ぶ。
    public func getSourceTime(
        time: TimeSpanValue, itemLength: Int, fps: Int,
        contentOffset: TimeSpanValue, contentLength: TimeSpanValue
    ) -> TimeSpanValue {
        if isConstant || fps <= 0 {
            let rate = firstRate
            if rate != 100.0 {
                if rate != 0.0 {
                    let scaled = TimeSpanValue(ticks: Int64(Double(time.ticks) * rate / 100.0))
                    if rate > 0 {
                        return scaled + contentOffset
                    }
                    return contentLength + scaled - contentOffset
                }
                return contentOffset
            }
            return time + contentOffset
        }
        let table = table(itemLength: itemLength, fps: fps)
        let base = table.rates[0] >= 0 ? contentOffset : contentLength - contentOffset
        let consumed = table.getConsumedTicks(timeTicks: time.ticks)
        return base + TimeSpanValue(ticks: Int64(consumed.rounded(.awayFromZero)))
    }
}

/// `PlaybackRateMap.enumerateContentBoundaryCrossings` の遅延列挙。
/// 本家が境界を発見するたびに yield return するのと同じく、現在の
/// フレーム・横断方向・次の境界番号を状態として保持し、`next()`
/// ごとに1件ずつ返す（FE-R43-136-01）。フレーム内に多数の境界が
/// あっても、先頭だけを取り出す消費では残りの境界を計算しない。
private struct BoundaryCrossingIterator: IteratorProtocol {
    let start: Double
    let contentSpan: Double
    let frameDurationTicks: Double
    let cumulativeTicks: [Double]
    let frameCount: Int

    /// 処理中のフレーム番号（1始まり。0 は未進入）。
    private var frame = 0
    /// 処理中の区間の開始側の消費位置。
    private var previous: Double
    /// 処理中の区間の終了側の消費位置。
    private var current: Double = 0
    /// 処理中の区間内で次に返す境界の倍数。本家が境界番号 k を
    /// long で保持するのと同じく Int64 で保持する（FE-R44-136-01）。
    /// Double で保持すると、絶対値が 2^53 以上で ±1 の加減が
    /// 失われ、同じ境界を無期限に返して列挙が終了しなくなる。
    /// 区間へ入るたびに横断方向に応じて初期化し、境界を1件
    /// 返すたびに進める。区間内に残りの境界が無ければ nil。
    private var nextMultiple: Int64?
    private var isInFrame = false
    /// 境界番号の初期値を Int64 へ変換できなかった（範囲外・
    /// 非有限）ため、列挙を打ち切る状態。変換でトラップはしない。
    private var isExhausted = false

    init(
        start: Double,
        contentSpan: Double,
        frameDurationTicks: Double,
        cumulativeTicks: [Double],
        frameCount: Int
    ) {
        self.start = start
        self.contentSpan = contentSpan
        self.frameDurationTicks = frameDurationTicks
        self.cumulativeTicks = cumulativeTicks
        self.frameCount = frameCount
        self.previous = start
    }

    mutating func next() -> TimeSpanValue? {
        while true {
            if isExhausted { return nil }
            if !isInFrame {
                guard frame < frameCount else { return nil }
                frame += 1
                current = start + cumulativeTicks[frame]
                if current > previous {
                    nextMultiple = initialMultiple(after: previous, step: 1)
                } else if current < previous {
                    nextMultiple = initialMultiple(after: previous, step: -1)
                } else {
                    nextMultiple = nil
                }
                isInFrame = true
            }
            if let multiple = nextMultiple {
                // 境界位置は Double へ変換してから素材長を掛ける。
                // 本家は k * contentTicks を long 演算するが、Mac 側は
                // 消費位置そのものを Double で保持しており、整数乗算を
                // 導入すると k と素材ティックの双方が大きい場合に
                // Int64 へ収まらない。変換後の乗算なら桁あふれは
                // 生じず、境界番号自体の前進は Int64 で保証される。
                let boundary = Double(multiple) * contentSpan
                let isForward = current > previous
                if isForward ? boundary <= current : boundary >= current {
                    let advanced = multiple.addingReportingOverflow(isForward ? 1 : -1)
                    nextMultiple = advanced.overflow ? nil : advanced.partialValue
                    return crossingTime(
                        frame: frame, previous: previous, current: current,
                        boundary: boundary
                    )
                }
                nextMultiple = nil
            }
            previous = current
            isInFrame = false
        }
    }

    /// 区間へ入る際の最初の境界番号。本家どおり商を切り捨て／
    /// 切り上げしてから進行方向へ1つ進める。商の導出は Double
    /// 演算のままだが、Int64 への変換が範囲外・非有限で失敗した
    /// 場合は、境界番号を表現できないためトラップせず列挙を
    /// 終える（Mac 側の安全措置。本家は変換の飽和・未定義動作に
    /// 依存する範囲であり、実用上の入力では到達しない）。
    private mutating func initialMultiple(after position: Double, step: Int64) -> Int64? {
        let quotient = step > 0
            ? (position / contentSpan).rounded(.down)
            : (position / contentSpan).rounded(.up)
        guard let base = Int64(exactly: quotient) else {
            isExhausted = true
            return nil
        }
        let advanced = base.addingReportingOverflow(step)
        if advanced.overflow {
            isExhausted = true
            return nil
        }
        return advanced.partialValue
    }

    /// 境界を横切る時刻。フレーム内位置は線形補間で、本家の
    /// `CrossingTime` どおりティックへ切り捨てる。
    private func crossingTime(
        frame: Int, previous: Double, current: Double, boundary: Double
    ) -> TimeSpanValue {
        let fraction = min(1, max(0, (boundary - previous) / (current - previous)))
        let ticks = (Double(frame - 1) + fraction) * frameDurationTicks
        return TimeSpanValue(ticks: Int64(ticks))
    }
}
