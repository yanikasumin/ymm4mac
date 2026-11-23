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
