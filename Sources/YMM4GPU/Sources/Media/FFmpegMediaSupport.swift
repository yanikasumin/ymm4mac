#if os(macOS)
import Foundation
import YMM4Core

/// FFmpeg 供給系の共有基盤（Issue #70 段階3）。
///
/// バイナリ解決・素材状態の台帳（`MediaAvailabilityRegistry`）・映像
/// デコード管理者をひとまとめにし、プレビューと書き出しの両経路が
/// 同じインスタンス（または同じ規則で作ったインスタンス）から
/// Factory と映像供給を取り出すことで、デコーダ選択規則を分けない。
/// 映像の管理者は初回利用時に遅延生成する（タイマーを張るため、
/// 音声だけの利用で作らない）。
///
/// 所有はアプリのセッション単位（Issue #70 段階4）: アプリは
/// ワークスペースが基盤を1つ保持し、プレビュー・再生・書き出し・
/// 長さ取得の全経路へ同じインスタンスを渡す。プロジェクトの
/// 差し替えでは `resetForProjectSwitch()` で状態を持ち越さない。
/// 単独利用（自動テスト等）では生成経路ごとに作ってよい。
public final class FFmpegMediaSupport: @unchecked Sendable {
    public let resolution: FFmpegBinaryResolution
    public let registry: MediaAvailabilityRegistry

    private let lock = NSLock()
    private var videoManagerStorage: FFmpegVideoSessionManager?
    private var videoManagerResolved = false

    public init(
        resolution: FFmpegBinaryResolution = FFmpegBinaryResolver().resolveAll(),
        registry: MediaAvailabilityRegistry = MediaAvailabilityRegistry()
    ) {
        self.resolution = resolution
        self.registry = registry
    }

    /// 映像デコード管理者。ffmpeg / ffprobe が解決できなければ nil
    /// （映像は AVFoundation のみで従来どおり動作する）。
    public var videoManager: FFmpegVideoSessionManager? {
        lock.lock()
        defer { lock.unlock() }
        if !videoManagerResolved {
            videoManagerResolved = true
            if resolution.ffmpeg != nil && resolution.ffprobe != nil {
                videoManagerStorage = FFmpegVideoSessionManager(
                    resolution: resolution, registry: registry
                )
            }
        }
        return videoManagerStorage
    }

    /// プロジェクトの差し替え時のリセット。映像の管理者が生成済み
    /// なら終了させて捨て（次回利用時に新しいプロジェクト用へ
    /// 作り直す）、台帳を空にする。旧プロジェクトのセッションと
    /// 失敗記録を新しいプロジェクトへ持ち越さないための境界。
    /// 終了済みの管理者へ供給を求めた側は superseded で終わる
    /// （枠ゲートの無効化時の契約）ため、表示側の作り直しと競合
    /// しても詰まらない。
    public func resetForProjectSwitch() {
        lock.lock()
        let manager = videoManagerStorage
        videoManagerStorage = nil
        videoManagerResolved = false
        lock.unlock()
        manager?.shutdown()
        registry.removeAll()
    }

    /// 音声の合成 Factory（AVFoundation → FFmpeg）を作る。
    public func makePCMProviderFactory(
        baseDirectory: URL?
    ) -> CompositePCMProviderFactory {
        CompositePCMProviderFactory(
            primary: AVFoundationPCMProviderFactory(baseDirectory: baseDirectory),
            fallback: FFmpegPCMProviderFactory(
                baseDirectory: baseDirectory,
                resolution: resolution,
                registry: registry
            )
        )
    }

    /// 映像の供給を作る。ffmpeg が無ければ AVFoundation 単独
    /// （従来の生成経路と同一）、あれば合成供給になる。
    public func makeVideoSupply(
        devices: MetalGraphicsDevices
    ) -> any MetalVideoDecoderSupply {
        let avSupply = AVFoundationVideoDecoderSupply(devices: devices)
        guard let videoManager else { return avSupply }
        return CompositeVideoDecoderSupply(candidates: [
            avSupply,
            FFmpegVideoDecoderSupply(devices: devices, manager: videoManager),
        ])
    }
}
#endif
