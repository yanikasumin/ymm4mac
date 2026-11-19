#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// FFmpeg デコードセッションによるデコーダ供給（Issue #70 段階2）。
///
/// Core の `FFmpegVideoSessionManager` からセッションを引き、
/// 得た 8bit BGRA フレームを共有メモリテクスチャへ転写して返す。
/// 時刻はセッションと同じく資産タイムラインの絶対時刻で扱い、
/// フレームの表示区間はセッションが PTS 基準で確定したものを
/// そのまま伝える。
///
/// どの供給を使うかの選択（Factory 層）は次段階。本クラスは
/// 接続点の実装であり、既存の生成経路からはまだ使われない。
public final class FFmpegVideoDecoderSupply: MetalVideoDecoderSupply {
    private let devices: MetalGraphicsDevices
    private let manager: FFmpegVideoSessionManager
    private var handle: FFmpegVideoSessionHandle?
    public private(set) var duration: TimeSpanValue = .zero
    public private(set) var presentationStartSeconds: Double = 0
    public private(set) var frameDurationSeconds: Double = 1.0 / 30.0

    public init(devices: MetalGraphicsDevices, manager: FFmpegVideoSessionManager) {
        self.devices = devices
        self.manager = manager
    }

    public func open(filePath: String?, url: URL?) -> Bool {
        close()
        guard let url else { return false }
        let key = MediaMaterialKey(filePath: url.path)
        do {
            let probe = try manager.probeInfo(for: key)
            guard let video = probe.primaryVideoStream,
                  let probedDuration = probe.duration else {
                return false
            }
            duration = probedDuration
            presentationStartSeconds =
                video.startTimeSeconds ?? probe.startTimeSeconds ?? 0
            if let rate = video.averageFrameRate, rate > 0 {
                frameDurationSeconds = 1.0 / rate
            }
            handle = manager.acquireSession(for: key)
            return true
        } catch {
            return false
        }
    }

    public func frame(atAbsoluteSeconds seconds: Double) -> MetalVideoDecodedFrame? {
        guard let handle else { return nil }
        do {
            let frame = try handle.frame(at: TimeSpanValue(seconds: seconds))
            guard let texture = makeTexture(from: frame) else { return nil }
            return MetalVideoDecodedFrame(
                texture: texture,
                width: frame.width,
                height: frame.height,
                startSeconds: frame.presentationStart.seconds,
                endSeconds: frame.presentationEnd.seconds
            )
        } catch {
            // 失敗の記録は管理者が台帳へ行う。供給側は「フレームが
            // 得られなかった」だけを返し、呼び出し側の従来の
            // フォールバック（前フレーム維持／透明）に委ねる。
            return nil
        }
    }

    public func close() {
        handle?.release()
        handle = nil
        duration = .zero
        presentationStartSeconds = 0
        frameDurationSeconds = 1.0 / 30.0
    }

    /// BGRA 生フレームをテクスチャへ転写する。セッションの出力は
    /// 素材の格納形式どおり非プリマルチプライの BGRA で、行は
    /// 幅×4 バイト詰め（セッションの契約）。
    private func makeTexture(from frame: FFmpegVideoFrame) -> MTLTexture? {
        guard frame.width > 0, frame.height > 0,
              frame.pixelData.count == frame.byteCount else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: frame.width, height: frame.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = devices.device.makeTexture(descriptor: descriptor)
        else { return nil }
        frame.pixelData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                mipmapLevel: 0, withBytes: base, bytesPerRow: frame.width * 4
            )
        }
        return texture
    }
}
#endif
