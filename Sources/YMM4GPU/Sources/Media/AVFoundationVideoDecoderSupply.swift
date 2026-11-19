#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import Metal
import YMM4Core

/// 同期文脈から AVFoundation の async API を呼ぶための橋渡し。
///
/// 合成全体が同期実行（描画先の close() で完了まで待つ）ため、ここで
/// 完了を待っても観測可能な順序は変わらない。結果の受け渡しは
/// セマフォの前後関係で同期される。
/// （Issue #70 段階2で `MetalVideoSource` から移設。実装は不変。）
private final class AVBridgeResult<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}

/// 非 Sendable な AVFoundation オブジェクトを橋渡しへ渡すための箱。
/// 橋渡しはセマフォで直列化され、同時に走る要求は常に1つだけなので、
/// 並行アクセスは起きない。
private final class AVSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private func runAVBlocking<T>(
    _ operation: @Sendable @escaping () async throws -> T
) throws -> T {
    let box = AVBridgeResult<T>()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            box.value = .success(try await operation())
        } catch {
            box.value = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.value!.get()
}

/// AVFoundation によるデコーダ供給。
///
/// Issue #70 段階2で `MetalVideoSource` が直接所有していた
/// AVAssetImageGenerator 周りの実装を、`MetalVideoDecoderSupply`
/// 境界の後ろへそのまま移設したもの。挙動は移設前と同一:
/// - 提示区間はセグメントの提示配置から決める（音声側の工場と
///   同じ規則）。全長は提示長であり、資産全体の長さではない。
/// - フレーム取得は要求時刻を含むフレームを取る（前方許容誤差 0）。
///   終端を超えた要求には最終フレームを出す。
/// - 回転は AVAssetImageGenerator の preferredTransform 適用で
///   焼き込む。SAR（表示幅補正）は未対応（移設前と同じ）。
public final class AVFoundationVideoDecoderSupply: MetalVideoDecoderSupply {
    private let devices: MetalGraphicsDevices
    private var generator: AVAssetImageGenerator?
    public private(set) var duration: TimeSpanValue = .zero
    public private(set) var presentationStartSeconds: Double = 0
    public private(set) var frameDurationSeconds: Double = 1.0 / 30.0

    public init(devices: MetalGraphicsDevices) {
        self.devices = devices
    }

    public func open(filePath: String?, url: URL?) -> Bool {
        close()
        guard let url else { return false }
        let assetBox = AVSendableBox(AVURLAsset(url: url))
        // メタデータは async の load API で読む（同期プロパティは
        // macOS 13 以降非推奨）。
        let metadata = try? runAVBlocking { () async throws -> (duration: Double, frameDuration: Double, start: Double)? in
            let asset = assetBox.value
            guard let track = try await asset.loadTracks(withMediaType: .video).first
            else { return nil }
            // 提示区間はセグメントの提示配置から決める（音声側の
            // 工場と同じ規則）。全長は提示長であり、資産全体の
            // 長さではない（提示開始オフセットを含むため）。
            let trackRange = try await track.load(.timeRange)
            let segments = (try? await track.load(.segments)) ?? []
            let presentation = AVFoundationPCMProviderFactory.presentationRange(
                segments: segments, fallback: trackRange
            )
            guard presentation.duration.isValid, !presentation.duration.isIndefinite
            else { return nil }
            let minDuration = CMTimeGetSeconds(try await track.load(.minFrameDuration))
            var frameDuration = 1.0 / 30.0
            if minDuration.isFinite && minDuration > 0 {
                frameDuration = minDuration
            } else {
                let rate = try await track.load(.nominalFrameRate)
                if rate > 0 {
                    frameDuration = 1.0 / Double(rate)
                }
            }
            return (
                CMTimeGetSeconds(presentation.duration), frameDuration,
                CMTimeGetSeconds(presentation.start)
            )
        }
        guard let metadata else { return false }
        let imageGenerator = AVAssetImageGenerator(asset: assetBox.value)
        imageGenerator.appliesPreferredTrackTransform = true
        generator = imageGenerator
        duration = TimeSpanValue(seconds: metadata.duration)
        presentationStartSeconds = metadata.start.isFinite ? metadata.start : 0
        frameDurationSeconds = metadata.frameDuration
        return true
    }

    public func frame(atAbsoluteSeconds seconds: Double) -> MetalVideoDecodedFrame? {
        guard let generator else { return nil }
        // 終端（提示終端）を超えた要求には最終フレームを出す（本家の
        // 各デコーダ共通）。負の論理時刻は論理 0（提示開始位置）へ
        // 寄せる（本家のシークも負方向は素材先頭で止まる）。
        // 呼び出し側は論理時刻へ提示開始位置を加算して渡すため、
        // ここでの下限寄せは提示開始位置がそのまま下限になる。
        let end = presentationStartSeconds + duration.seconds
        var target = max(presentationStartSeconds, seconds)
        var toleranceBefore = CMTime.zero
        if target >= end {
            target = end
            toleranceBefore = .positiveInfinity
        }

        let fetched = fetchFrame(generator: generator, at: target, toleranceBefore: toleranceBefore)
            ?? (toleranceBefore == .zero
                ? fetchFrame(generator: generator, at: target, toleranceBefore: .positiveInfinity)
                : nil)
        guard let fetched else { return nil }
        return MetalVideoDecodedFrame(
            texture: fetched.texture,
            width: fetched.width,
            height: fetched.height,
            startSeconds: fetched.actualSeconds,
            endSeconds: fetched.actualSeconds + frameDurationSeconds
        )
    }

    public func close() {
        generator = nil
        duration = .zero
        presentationStartSeconds = 0
        frameDurationSeconds = 1.0 / 30.0
    }

    /// 指定時刻のフレームを1枚取得する。前方許容誤差は常に 0（要求時刻を
    /// 含むフレームを取る。本家の「要求時刻を含むサンプルで止める」方式）。
    private func fetchFrame(
        generator: AVAssetImageGenerator, at seconds: Double, toleranceBefore: CMTime
    ) -> (texture: MTLTexture, width: Int, height: Int, actualSeconds: Double)? {
        generator.requestedTimeToleranceBefore = toleranceBefore
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let generatorBox = AVSendableBox(generator)
        guard let result = try? runAVBlocking({ try await generatorBox.value.image(at: time) }),
              let converted = makePremultipliedTexture(
                device: devices.device, cgImage: result.image
              )
        else { return nil }
        return (
            texture: converted.texture, width: converted.width, height: converted.height,
            actualSeconds: CMTimeGetSeconds(result.actualTime)
        )
    }
}
#endif
