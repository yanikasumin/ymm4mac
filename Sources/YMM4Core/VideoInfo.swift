import Foundation

/// 動画の基本情報（解像度・フレームレート・サンプリングレート）。
///
/// 本家 `VideoInfo` の仕様を再現する。値域は本家の Range 属性に基づくが、
/// 本家の setter は範囲によるクランプや例外を行わない（素通しの代入）ため、
/// ここでも代入はそのまま保持し、範囲は検証用のメタデータとして提供する。
/// 範囲の強制が検証・UI 層のどこで行われるかはモデル層からは未確認。
public struct VideoInfo: Equatable, Sendable {
    /// フレームレート（fps）。既定 30、有効範囲 1...240。
    public var fps: Int
    /// サンプリングレート（Hz）。既定 48000、有効範囲 8000...192000。
    public var hz: Int
    /// 幅（px）。既定 1920、有効範囲 1...16384。
    public var width: Int
    /// 高さ（px）。既定 1080、有効範囲 1...16384。
    public var height: Int
    /// 背景色。既定は透明。
    public var backgroundColor: Color

    public init(
        fps: Int = 30,
        hz: Int = 48_000,
        width: Int = 1920,
        height: Int = 1080,
        backgroundColor: Color = .transparent
    ) {
        self.fps = fps
        self.hz = hz
        self.width = width
        self.height = height
        self.backgroundColor = backgroundColor
    }

    // MARK: - 有効範囲（本家の Range 属性）

    public static let fpsRange = 1...240
    public static let hzRange = 8_000...192_000
    public static let widthRange = 1...16_384
    public static let heightRange = 1...16_384

    /// 全プロパティが有効範囲内に収まっているか。
    public var isWithinValidRanges: Bool {
        Self.fpsRange.contains(fps)
            && Self.hzRange.contains(hz)
            && Self.widthRange.contains(width)
            && Self.heightRange.contains(height)
    }

    // MARK: - フレーム⇔時間換算（FrameTime へ FPS を渡す本家の換算メソッド）

    /// 時間（秒）に対応するフレーム番号。
    public func frame(from time: TimeInterval) -> Int {
        FrameTime.frame(from: time, fps: fps)
    }

    /// フレーム番号に対応する時間（秒）。
    public func time(fromFrame frame: Int) -> TimeInterval {
        FrameTime.time(fromFrame: frame, fps: fps)
    }
}
