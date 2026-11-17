import Foundation

/// フレームと時間の換算。
///
/// 本家 `FrameTime` の換算規則を再現する。丸めはいずれも
/// `MidpointRounding.AwayFromZero`（0.5 を 0 から遠い側へ丸める）。
public enum FrameTime {
    /// 時間からフレームを求める。`Round(秒 × fps, AwayFromZero)`。
    public static func frame(from time: TimeInterval, fps: Int) -> Int {
        Int((time * Double(fps)).rounded(.toNearestOrAwayFromZero))
    }

    /// フレームから時間（秒）を求める。
    ///
    /// 本家は `TimeSpan.FromTicks(Round(frame × 10^7 / fps, AwayFromZero))` で
    /// 100ns 単位（tick）に丸めてから時間化する。その粒度まで含めて再現する。
    public static func time(fromFrame frame: Int, fps: Int) -> TimeInterval {
        let ticks = (Double(frame) * 10_000_000 / Double(fps)).rounded(.toNearestOrAwayFromZero)
        return ticks / 10_000_000
    }
}
