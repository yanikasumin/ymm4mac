#if os(macOS)
import Foundation
import Metal
import YMM4Core

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
/// デコード基盤は `MetalVideoDecoderSupply` 境界の後ろに切り出した
/// （Issue #70 段階2）。既定の供給は AVFoundation
/// （`AVFoundationVideoDecoderSupply`、従来このクラスが直接所有して
/// いた実装の移設で挙動は不変）。AVFoundation が扱えないコンテナ
/// （MKV / WebM / TS 等）向けに FFmpeg 供給
/// （`FFmpegVideoDecoderSupply`）も同じ境界で接続できるが、どちらの
/// 供給を使うかの選択（Factory 層での試行順）は次段階で行うため、
/// 現行の生成経路は従来どおり AVFoundation のみを使う。
/// 提示タイムスタンプ（Issue #55）: 論理時刻 0 は素材の提示開始位置
/// （最初の非空セグメントの提示開始時刻）とし、フレーム取得時に
/// 提示開始位置を加算して資産タイムラインへ読み替える。本家の
/// 映像ファイルソースも `streamStartTime`（最初のサンプルの
/// SampleTime）で同じ補正をし、全長からも差し引く。
/// 配置は画像 Source と同じく中心が原点（端数は 0 方向へ切り捨て）。
public final class MetalVideoSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: VideoItem
    private let baseDirectory: URL?
    private let drawingEffect: MetalDrawingEffect
    private let outputReference = ImageReference(label: "video-source")
    /// デコーダ供給の生成関数。既定は AVFoundation 供給。
    /// テストと次段階の Factory 統合のために差し替え点を持つ。
    private let supplyFactory: () -> any MetalVideoDecoderSupply
    private var loadedPath: String??
    private var isFirstUpdate = true

    /// デコーダ供給（開けなかった場合は nil で、出力は透明に固定される）。
    private var decoder: (any MetalVideoDecoderSupply)?
    /// 素材の提示長（ループの剰余に使う）。供給の値を写したもの。
    /// 提示開始オフセットは含まない論理長（本家の Duration と同じ）。
    private var assetDuration: TimeSpanValue = .zero
    /// 提示開始位置（秒、資産タイムライン上）。論理時刻への加算分。
    private var presentationStartSeconds: Double = 0
    /// 現在保持しているフレームの表示区間 [開始, 終了)（秒）。
    private var currentFrameStart: Double = 0
    private var currentFrameEnd: Double = 0
    private var hasFrame = false
    private var frameTexture: MTLTexture?

    public init(devices: MetalGraphicsDevices, item: VideoItem, baseDirectory: URL? = nil) {
        let context = devices.makeContext()
        self.context = context
        self.item = item
        self.baseDirectory = baseDirectory
        self.drawingEffect = MetalDrawingEffect(context: context)
        self.supplyFactory = { AVFoundationVideoDecoderSupply(devices: context.devices) }
    }

    /// 供給を差し替える生成（テスト・次段階の Factory 統合用）。
    init(
        devices: MetalGraphicsDevices, item: VideoItem, baseDirectory: URL? = nil,
        supplyFactory: @escaping () -> any MetalVideoDecoderSupply
    ) {
        let context = devices.makeContext()
        self.context = context
        self.item = item
        self.baseDirectory = baseDirectory
        self.drawingEffect = MetalDrawingEffect(context: context)
        self.supplyFactory = supplyFactory
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
        if item.isLooped, decoder != nil {
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
        decoder?.close()
        decoder = nil
        frameTexture = nil
        outputs = []
    }

    // MARK: - デコーダ

    private func openDecoder() {
        decoder?.close()
        decoder = nil
        frameTexture = nil
        hasFrame = false
        assetDuration = .zero
        presentationStartSeconds = 0

        if let path = item.filePath,
           let url = resolveMediaURL(path: path, baseDirectory: baseDirectory) {
            let supply = supplyFactory()
            if supply.open(filePath: path, url: url) {
                decoder = supply
                assetDuration = supply.duration
                presentationStartSeconds = supply.presentationStartSeconds
                // 本家 VideoItem.ContentLength はファイルから求めた
                // Duration そのものである。モデル層の保持値へ反映し、
                // GetSourceTime（負レート時の基準）が本家と揃うようにする。
                item.contentLength = assetDuration
            } else {
                supply.close()
            }
        }

        if decoder == nil {
            // 開けない場合の代替: 1×1 完全透明（本家 CreateEmptyBitmap）。
            registerTransparent()
        }
        outputs = [
            StandardSourceOutput(
                output: outputReference, drawingEffect: drawingEffect, dontDispose: true
            ),
        ]
    }

    /// 要求時刻（論理秒）のフレームへ進める。現在フレームの区間内なら
    /// 何もしない。キャッシュ区間は資産タイムラインの絶対秒で保持
    /// するため、論理時刻は提示開始位置を加算して読み替える。
    private func updateFrame(atSeconds requested: Double) {
        guard let decoder else { return }
        let absolute = presentationStartSeconds + requested
        if hasFrame && absolute >= currentFrameStart && absolute < currentFrameEnd {
            return
        }

        guard let frame = decoder.frame(atAbsoluteSeconds: absolute) else {
            // 得られなければ前フレームを維持する。まだ1フレームも
            // 得られていなければ透明を登録しておく（未登録の参照は
            // 合成側で「出力なし」になり、本家の透明代替と食い違う）。
            if !hasFrame {
                registerTransparent()
            }
            return
        }
        frameTexture = frame.texture
        currentFrameStart = frame.startSeconds
        currentFrameEnd = frame.endSeconds
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
