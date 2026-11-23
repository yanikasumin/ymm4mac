import SwiftUI
import YMM4Core

/// 目盛り計算（本家 TimelineScaleViewModel の規則）の純粋関数置き場。
/// SwiftUI 側（縦グリッド線）と AppKit 側（目盛りビュー）の双方が
/// 同じ規則を使うため、状態を持たない関数として切り出す。
enum TimelineScale {

    /// 典型間隔の候補から、目標（約13px分）の0.7倍以上で最も近いものを選ぶ。
    static func tickSpan(fps: Int, zoomPercent: Double) -> Int {
        let fps = max(fps, 1)
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

    /// `hh:mm:ss.ff` 形式（本家のステータスバー・目盛りラベルと同じ書式）。
    static func timeText(frame: Int, fps: Int) -> String {
        let fps = max(fps, 1)
        let totalSeconds = Double(frame) / Double(fps)
        let whole = Int(totalSeconds)
        let hundredths = Int((totalSeconds - floor(totalSeconds)) * 100)
        return String(
            format: "%02d:%02d:%02d.%02d",
            whole / 3600, (whole % 3600) / 60, whole % 60, hundredths
        )
    }
}

extension TimelineStripView {
    // MARK: - 目盛り計算（TimelineScale への委譲）

    func tickSpan() -> Int {
        TimelineScale.tickSpan(
            fps: timeline.videoInfo.fps, zoomPercent: zoomPercent)
    }

    /// 縦グリッド線を引くフレームと主線／サブ線の別（可視範囲のみ）。
    /// 位置はモデルの TimelineVerticalLine（種別・間隔・開始フレーム・
    /// グループ）の規則で Core が計算する（本家 GetLineFrames /
    /// UpdateLines。FE-UNIT5 で接続）。無効な間は空を返す。
    func verticalGridLines(
        viewportWidth: CGFloat
    ) -> [(frame: Int, isSubLine: Bool)] {
        guard pxPerFrame > 0 else { return [] }
        let first = max(0, Int(horizontalOffset / pxPerFrame))
        let last = Int((horizontalOffset + viewportWidth) / pxPerFrame)
        guard last >= first else { return [] }
        return timeline.verticalLine.displayLines(
            videoInfo: timeline.videoInfo,
            enumerateFrom: first, throughFrame: last,
            pxPerFrame: Double(pxPerFrame)
        )
    }

    /// `hh:mm:ss.ff` 形式（本家のステータスバー・目盛りラベルと同じ書式）。
    func timeText(frame: Int) -> String {
        TimelineScale.timeText(frame: frame, fps: timeline.videoInfo.fps)
    }

}
