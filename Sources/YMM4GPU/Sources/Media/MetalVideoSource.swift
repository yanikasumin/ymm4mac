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

/// 動画アイテムの Source。本家 VideoSource に対応する。
///
/// 本家と同じく、コンストラクタで自前の文脈（CreateContext）を生成して
/// 所有し、デコーダの生成は初回 Update と FilePath の変更時にだけ行う
/// （本家は MF モード設定の変更でも作り直すが、設定層が未実装のため
/// その条件は持たない）。デコーダが開けなければ、本家の
/// VideoFileSourceFactory が null を返したときの代替（CreateEmptyBitmap）
/// と同じく 1×1 完全透明へ落とす。
/// 時刻変換は本家どおり: PlaybackRateMap.GetSourceTime で素材時刻へ
/// 変換し、ループ時はデコーダの Duration で剰余を取る（負値の調整は
/// 非定数レートのときだけ、本家の式どおり）。デコーダは常に現在表示中の
/// 1フレームだけを保持し、要求時刻がその区間内なら再デコードしない
/// （本家の各デコーダに共通する方式。MEDIA-IO-FACTS §6）。
/// デコード基盤は AVFoundation（AVAssetImageGenerator）。本家は
/// FFmpeg → MediaFoundation → DirectShow のプラグイン試行であり、
/// AVFoundation が扱えないコンテナ（MKV / WebM / TS 等）はこちらでも
/// 開けず透明へ落ちる。FFmpeg 併用の要否は設計の土台事項のため、
/// 本件では判断せず差し替え点（このクラスのデコーダ生成部）に留める。
/// 回転は AVAssetImageGenerator の preferredTransform 適用で焼き込む
/// （本家のデコーダ出力の中心化・回転補正に相当）。SAR（表示幅補正）は
/// 未対応。配置は画像 Source と同じく中心が原点（端数は 0 方向へ切り捨て）。
public final class MetalVideoSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: VideoItem
    private let baseDirectory: URL?
    private let drawingEffect: MetalDrawingEffect
    private let outputReference = ImageReference(label: "video-source")
    private var loadedPath: String??
    private var isFirstUpdate = true

    /// デコーダ（開けなかった場合は nil で、出力は透明に固定される）。
    private var generator: AVAssetImageGenerator?
    /// デコーダの総尺（ループの剰余と終端フォールバックに使う）。
    private var assetDuration: TimeSpanValue = .zero
    /// 1フレームの表示区間の長さ（秒）。キャッシュ判定に使う。
    private var frameDuration: Double = 1.0 / 30.0
    /// 現在保持しているフレームの表示区間 [開始, 終了)（秒）。
    private var currentFrameStart: Double = 0
    private var currentFrameEnd: Double = 0
    private var hasFrame = false
    private var frameTexture: MTLTexture?

    public init(devices: MetalGraphicsDevices, item: VideoItem, baseDirectory: URL? = nil) {
        self.context = devices.makeContext()
        self.item = item
        self.baseDirectory = baseDirectory
        self.drawingEffect = MetalDrawingEffect(context: context)
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        if isFirstUpdate || loadedPath != item.filePath {
            isFirstUpdate = false
            loadedPath = item.filePath
            openDecoder()
        }

        let rateMap = PlaybackRateMap(rate: item.playbackRate2)
        var time = rateMap.getSourceTime(
            time: TimeSpanValue(seconds: description.itemPosition.time),
            itemLength: description.itemDuration.frame,
            fps: description.fps,
            contentOffset: item.contentOffset,
            contentLength: item.contentLength
        )
        if item.isLooped, generator != nil {
            if assetDuration == .zero {
                time = .zero
            } else {
                var ticks = time.ticks % assetDuration.ticks
                if ticks < 0 && !rateMap.isConstant {
                    ticks += assetDuration.ticks
                }
                time = TimeSpanValue(ticks: ticks)
            }
        }
        updateFrame(atSeconds: time.seconds)
    }

    public func dispose() {
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        generator = nil
        frameTexture = nil
        outputs = []
    }

    // MARK: - デコーダ

    private func openDecoder() {
        generator = nil
        frameTexture = nil
        hasFrame = false
        assetDuration = .zero

        if let path = item.filePath,
           let url = resolveMediaURL(path: path, baseDirectory: baseDirectory) {
            let assetBox = AVSendableBox(AVURLAsset(url: url))
            // メタデータは async の load API で読む（同期プロパティは
            // macOS 13 以降非推奨）。
            let metadata = try? runAVBlocking { () async throws -> (duration: Double, frameDuration: Double)? in
                let asset = assetBox.value
                let duration = try await asset.load(.duration)
                guard duration.isValid, !duration.isIndefinite,
                      let track = try await asset.loadTracks(withMediaType: .video).first
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
                return (CMTimeGetSeconds(duration), frameDuration)
            }
            if let metadata {
                let imageGenerator = AVAssetImageGenerator(asset: assetBox.value)
                imageGenerator.appliesPreferredTrackTransform = true
                generator = imageGenerator
                assetDuration = TimeSpanValue(seconds: metadata.duration)
                // 本家 VideoItem.ContentLength はファイルから求めた
                // Duration そのものである。モデル層の保持値へ反映し、
                // GetSourceTime（負レート時の基準）が本家と揃うようにする。
                item.contentLength = assetDuration
                frameDuration = metadata.frameDuration
            }
        }

        if generator == nil {
            // 開けない場合の代替: 1×1 完全透明（本家 CreateEmptyBitmap）。
            registerTransparent()
        }
        outputs = [
            StandardSourceOutput(
                output: outputReference, drawingEffect: drawingEffect, dontDispose: true
            ),
        ]
    }

    /// 要求時刻のフレームへ進める。現在フレームの区間内なら何もしない。
    private func updateFrame(atSeconds requested: Double) {
        guard let generator else { return }
        if hasFrame && requested >= currentFrameStart && requested < currentFrameEnd {
            return
        }

        // 終端を超えた要求には最終フレームを出す（本家の各デコーダ共通）。
        // 負の時刻は 0 へ寄せる（本家のシークも負方向は素材先頭で止まる）。
        let duration = assetDuration.seconds
        var target = max(0, requested)
        var toleranceBefore = CMTime.zero
        if target >= duration {
            target = duration
            toleranceBefore = .positiveInfinity
        }

        let frame = fetchFrame(generator: generator, at: target, toleranceBefore: toleranceBefore)
            ?? (toleranceBefore == .zero
                ? fetchFrame(generator: generator, at: target, toleranceBefore: .positiveInfinity)
                : nil)
        guard let frame else {
            // 得られなければ前フレームを維持する。まだ1フレームも
            // 得られていなければ透明を登録しておく（未登録の参照は
            // 合成側で「出力なし」になり、本家の透明代替と食い違う）。
            if !hasFrame {
                registerTransparent()
            }
            return
        }
        frameTexture = frame.texture
        currentFrameStart = frame.actualSeconds
        currentFrameEnd = frame.actualSeconds + frameDuration
        hasFrame = true
        // 本家は (-幅/2, -高さ/2) の描画で中心化する（画像 Source と同じ。
        // 端数は 0 方向への切り捨て）。
        let left = Double(-(frame.width / 2))
        let top = Double(-(frame.height / 2))
        context.devices.register(
            outputReference,
            image: MetalImage(
                texture: frame.texture,
                bounds: RectF(
                    left: left, top: top,
                    right: left + Double(frame.width),
                    bottom: top + Double(frame.height)
                )
            )
        )
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
                device: context.devices.device, cgImage: result.image
              )
        else { return nil }
        return (
            texture: converted.texture, width: converted.width, height: converted.height,
            actualSeconds: CMTimeGetSeconds(result.actualTime)
        )
    }

    private func registerTransparent() {
        context.devices.register(
            outputReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
    }
}

#endif
