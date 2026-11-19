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
