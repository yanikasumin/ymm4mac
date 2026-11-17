import SwiftUI
import YMM4Core

extension TimelineStripView {
    // MARK: - 目盛り計算（本家 TimelineScaleViewModel の規則）

    /// 典型間隔の候補から、目標（約13px分）の0.7倍以上で最も近いものを選ぶ。
    func tickSpan() -> Int {
        let fps = max(timeline.videoInfo.fps, 1)
        let framesPerPixel = 100.0 / zoomPercent
        let target = max(Int(framesPerPixel * 13), 1)
        var candidates = Set<Int>()
        for frame in 1..<120 where fps % (frame * 10) == 0 {
            candidates.insert(frame)
        }
        for step in [1, 2, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1200,
                     1800, 3600, 7200, 14400, 21600, 43200, 86400] {
            let frames = step * fps
            if frames % 10 == 0 {
                candidates.insert(frames / 10)
            }
        }
        let floor = Double(target) * 0.7
        let eligible = candidates.filter { Double($0) >= floor }
        return eligible.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
    }

    /// 縦グリッド線を引くフレーム（大目盛り = 間隔×10 ごと、可視範囲のみ）。
    func verticalGridFrames(viewportWidth: CGFloat) -> [Int] {
        let largeSpan = tickSpan() * 10
        let first = max(0, Int(horizontalOffset / pxPerFrame) - largeSpan)
        let last = min(
            timeline.length,
            Int((horizontalOffset + viewportWidth) / pxPerFrame) + largeSpan
        )
        guard largeSpan > 0, last >= first else { return [] }
        return Array(stride(from: (first / largeSpan) * largeSpan, through: last, by: largeSpan))
    }

    /// `hh:mm:ss.ff` 形式（本家のステータスバー・目盛りラベルと同じ書式）。
    func timeText(frame: Int) -> String {
        let fps = max(timeline.videoInfo.fps, 1)
        let totalSeconds = Double(frame) / Double(fps)
        let whole = Int(totalSeconds)
        let hundredths = Int((totalSeconds - floor(totalSeconds)) * 100)
        return String(
            format: "%02d:%02d:%02d.%02d",
            whole / 3600, (whole % 3600) / 60, whole % 60, hundredths
        )
    }

}
