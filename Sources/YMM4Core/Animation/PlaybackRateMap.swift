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
