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

/// シーンアイテムの Source。本家 SceneSource に対応する。
///
/// 本家と同じく、コンストラクタで自前の文脈（CreateContext）を生成して
/// 所有し、参照先シーンの内部 TimelineSource はその文脈を借用する
/// （第2章: 文脈は消費者ごとに新規生成し、TimelineSource は借用）。
/// シーンの解決は、本家では説明（desc.Scenes）に載る ISceneInfo 列から
/// 行うが、こちらでは SceneInfo が識別子のみの契約（MAC-0009）のため、
/// 供給元（MetalSourceProvider）が保持するプロジェクト全体の解決子で
/// 代替する（解決子は説明の列と同じプロジェクトから構築される）。
/// 入れ子上限は本家 Scene.TryCreateVideoSource と同じ: 親シーン列に
/// 参照先 ID が 10 回現れたら生成しない（その場合の出力は空の代替）。
/// SceneId が変わったときだけ内部合成器を作り直す。時刻変換は
/// PlaybackRateMap.GetSourceTime（ContentLength は参照先タイムラインの
/// 長さから求める。本家 SceneItem.ContentLength の定義どおり。エコー
/// 延長分は音声側の量であり、ここでは加算しない）、ループ時は参照先
/// シーンの尺で剰余を取る（VideoSource と同じ式）。
/// 出力は内部合成器の出力が差し替わったときだけ包み直す。
public final class MetalSceneSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: SceneItem
    private let drawingEffect: MetalDrawingEffect
    private let emptyReference = ImageReference(label: "scene-source-empty")
    private let emptyOutput: StandardSourceOutput
    /// シーン ID から内部合成器を生成する境界（供給元が解決と入れ子
    /// 上限を担う）。内部合成器の描画先は、この Source が所有する
    /// 文脈から作る（本家が SceneSource の文脈を内部 TimelineSource
    /// へ貸す構造と同じ）。生成できなければ nil。
    private let composerFactory: (UUID, MetalGraphicsContext) -> TimelineComposer?

    private var resolvedSceneID: UUID?
    private var innerComposer: TimelineComposer?
    private var innerOutput: ImageReference?
    private var output: StandardSourceOutput?

    public init(
        devices: MetalGraphicsDevices,
        item: SceneItem,
        composerFactory: @escaping (UUID, MetalGraphicsContext) -> TimelineComposer?
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.composerFactory = composerFactory
        self.drawingEffect = MetalDrawingEffect(context: context)
        context.devices.register(
            emptyReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
        self.emptyOutput = StandardSourceOutput(
            output: emptyReference, drawingEffect: drawingEffect, dontDispose: true
        )
        self.outputs = [emptyOutput]
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        let sceneID = item.sceneId
        if resolvedSceneID != sceneID {
            resolvedSceneID = sceneID
            innerComposer?.dispose()
            innerComposer = composerFactory(sceneID, context)
            innerOutput = nil
            output = nil
        }

        // 本家 SceneItem.ContentLength = 参照先タイムラインの長さ（時間）。
        let contentLength = innerComposer.map { composer in
            TimeSpanValue(seconds: FrameTime.time(
                fromFrame: composer.timeline.length, fps: composer.timeline.videoInfo.fps
            ))
        } ?? .zero

        let rateMap = PlaybackRateMap(rate: item.playbackRate2)
        var time = rateMap.getSourceTime(
            time: TimeSpanValue(seconds: description.itemPosition.time),
            itemLength: description.itemDuration.frame,
            fps: description.fps,
            contentOffset: item.contentOffset,
            contentLength: contentLength
        )
        if item.isLooped, innerComposer != nil {
            if contentLength == .zero {
                time = .zero
            } else {
                var ticks = time.ticks % contentLength.ticks
                if ticks < 0 && !rateMap.isConstant {
                    ticks += contentLength.ticks
                }
                time = TimeSpanValue(ticks: ticks)
            }
        }

        try innerComposer?.update(time: time, usage: description.usage)

        if innerComposer?.output !== innerOutput {
            innerOutput = innerComposer?.output
            if let innerOutput {
                output = StandardSourceOutput(
                    output: innerOutput, drawingEffect: drawingEffect, dontDispose: true
                )
            } else {
                output = nil
            }
        }
        outputs = [output ?? emptyOutput]
    }

    public func dispose() {
        innerComposer?.dispose()
        innerComposer = nil
        drawingEffect.dispose()
        context.devices.unregister(emptyReference)
        outputs = []
    }
}

/// 合成グループ（GroupItem.IsComposite）の Source。本家 CompositeSource
/// に対応する（MAC-0027）。
///
/// 本家の意味論（実コードで確認）:
/// - 生成時に自前の文脈（CreateContext）を所有し、内部 TimelineSource は
///   同じシーン・同じタイムラインを、対象グループに束縛した
///   CompositeItemPicker で合成する。子の選定はグループのレイヤー範囲
///   （Layer < 子 <= Layer + GroupRange、IsGroupOnly 時はグループ番号の
///   一致も要求）で行われ、入れ子の合成グループの子はそのグループが
///   代表する（内部合成器の選定が再帰的に担う）。
/// - Update は内部合成をタイムライン絶対時刻で回す（ピッカー側で
///   グループ末尾フレームへクランプされる）。
/// - 出力は内部合成の画像を AffineTransform2D で −center だけ平行移動
///   したもの。center は CompositeCenter が ImageCenter のとき内部画像の
///   局所境界（内容境界）の中心、ScreenCenter のとき (0, 0)。
///   SourceOutput の DrawingOffset は +center、Center は (0, 0)。
///   これによりグループ自身の変形（回転・ズーム）は内容中心を軸に効き、
///   変形が既定値のとき合成は恒等になる。
/// - グループ自身の VideoEffects は外側の EffectedItemSource が自前
///   エフェクトとして合成結果全体へ一度だけ適用する（子へは流れない。
///   親グループ解決は合成グループで打ち切られる）。
///
/// こちらでは MetalSceneSource と同じ型で実装する: 文脈を所有し、内部
/// TimelineComposer はその文脈を借用する。平行移動は実体の境界を
/// −center ずらすことで表す（テクスチャとその平面範囲は不変であり、
/// 描画時の UV 写像で画素対応が保たれる）。
public final class MetalCompositeSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: GroupItem
    private let drawingEffect: MetalDrawingEffect
    private let innerComposer: TimelineComposer
    private let outputReference = ImageReference(label: "composite-source")
    private let emptyReference = ImageReference(label: "composite-source-empty")
    private let emptyOutput: StandardSourceOutput
    private var output: StandardSourceOutput?

    /// - Parameters:
    ///   - composerFactory: 内部合成器の生成境界（供給元が、対象グループに
    ///     束縛した選定と子の供給元を持つ合成器を、この Source が所有する
    ///     文脈で構築する）。
    public init(
        devices: MetalGraphicsDevices,
        item: GroupItem,
        composerFactory: (MetalGraphicsContext) -> TimelineComposer
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.drawingEffect = MetalDrawingEffect(context: context)
        self.innerComposer = composerFactory(context)
        context.devices.register(
            emptyReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
        self.emptyOutput = StandardSourceOutput(
            output: emptyReference, drawingEffect: drawingEffect, dontDispose: true
        )
        self.outputs = [emptyOutput]
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        // 本家は TimelinePosition の絶対時刻で内部合成を回す。
        try innerComposer.update(
            time: TimeSpanValue(seconds: description.timelinePosition.time),
            usage: description.usage
        )

        guard let innerOutput = innerComposer.output,
              let innerImage = context.devices.image(for: innerOutput)
        else {
            output = nil
            outputs = [emptyOutput]
            return
        }

        // 中心: ImageCenter のとき内部画像の局所境界（内容境界）の中心、
        // ScreenCenter のとき原点（本家 CompositeSource.Update）。
        // 本家は CompositeCenter == ImageCenter のときだけ画像中心を使い、
        // それ以外（ScreenCenter・未知値）は (0, 0)。
        let center: Vector2
        if item.compositeCenter == .imageCenter {
            center = Vector2(
                x: (innerImage.bounds.left + innerImage.bounds.right) / 2,
                y: (innerImage.bounds.top + innerImage.bounds.bottom) / 2
            )
        } else {
            center = .zero
        }

        // 平行移動（−center）は境界のずらしと planeOffset で表す。
        // テクスチャ・平面範囲・変換は内部画像のままで、ローカル座標の
        // 点は planeOffset（= center）を加えた平面位置の画素に対応する。
        context.devices.register(
            outputReference,
            image: MetalImage(
                texture: innerImage.texture,
                bounds: RectF(
                    left: innerImage.bounds.left - center.x,
                    top: innerImage.bounds.top - center.y,
                    right: innerImage.bounds.right - center.x,
                    bottom: innerImage.bounds.bottom - center.y
                ),
                texturePlaneRect: innerImage.texturePlaneRect,
                planeOffset: Vector2(
                    x: innerImage.planeOffset.x + center.x,
                    y: innerImage.planeOffset.y + center.y
                ),
                transform: innerImage.transform,
                opacity: innerImage.opacity,
                interpolation: innerImage.interpolation
            )
        )
        // DrawingOffset（= center）は出力の固定値であり、中心はフレーム
        // ごとに変わりうるため、出力は更新のたびに作り直す（本家も
        // Update のたびに旧出力を破棄して新しく作る）。
        output = StandardSourceOutput(
            output: outputReference,
            drawingEffect: drawingEffect,
            drawingOffset: center,
            center: .zero,
            dontDispose: true
        )
        outputs = [output ?? emptyOutput]
    }

    public func dispose() {
        innerComposer.dispose()
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        context.devices.unregister(emptyReference)
        outputs = []
    }
}

/// フレームバッファアイテムの Source。本家 FrameBufferSource に対応する。
///
/// 契約（第1章 IMG-04）は MAC-0009/0010 で用意済みであり、こちらは
/// その Metal 実体である。合成側（TimelineComposer）が合成途中で
/// Input（閉じた描画先の画像）と FrameSize を外部から設定し、その後に
/// Update が呼ばれる。本家の内部構造は Flood → Composite(SourceOver)
/// → Crop の連鎖であり、可視結果は次のとおり:
/// - 下地は Flood の色: アルファ有効時は透明 (0,0,0,0)、無効時は
///   不透明な黒 (0,0,0,1)。入力画像をその上に通常合成する。
/// - 出力の境界は Crop 矩形: 通常はフレーム矩形（中心原点の
///   -W/2..W/2, -H/2..H/2）。フレーム外描画が有効な場合は、入力画像の
///   局所境界とフレーム矩形の和集合まで広げる。
/// こちらでは専用の描画パスで同じ結果をテクスチャ化する（下地色で
/// クリアした描画先へ入力画像を描く）。出力テクスチャの画素 (0,0) は
/// Crop 矩形の左上に対応し、登録する境界は Crop 矩形そのものとする。
/// 入力の局所境界は、本家の GetImageLocalBounds に相当する量として、
/// 登録済み実体の境界へ実体自身の変換を適用した外接矩形で近似する。
public final class MetalFrameBufferSource: FrameBufferSource {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    /// 合成済みの蓄積画像（借用。所有権は移らない）。合成側が設定する。
    public var input: ImageReference?
    /// フレームのサイズ。合成側が設定する。
    public var frameSize: PixelSize = PixelSize(width: 0, height: 0)
    /// 背景をクリアするか（アイテムの保持値。合成側が引き継ぎ描画の
    /// 判断に使う）。
    public var clearBackground: Bool { item.clearBackground }

    private let context: MetalGraphicsContext
    private let item: FrameBufferItem
    private let drawingEffect: MetalDrawingEffect
    private let outputReference = ImageReference(label: "framebuffer-source")
    private var outputTexture: MTLTexture?
    private var outputPixelWidth: Int = 0
    private var outputPixelHeight: Int = 0

    public init(devices: MetalGraphicsDevices, item: FrameBufferItem) {
        self.context = devices.makeContext()
        self.item = item
        self.drawingEffect = MetalDrawingEffect(context: context)
        outputs = [
            StandardSourceOutput(
                output: outputReference, drawingEffect: drawingEffect, dontDispose: true
            ),
        ]
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        let frameRect = RectF(
            left: -Double(frameSize.width) / 2, top: -Double(frameSize.height) / 2,
            right: Double(frameSize.width) / 2, bottom: Double(frameSize.height) / 2
        )
        var cropRect = frameRect
        let inputImage = input.flatMap { context.devices.image(for: $0) }
        if item.isFrameOutImageRenderingEnabled, let inputImage {
            let inputBounds = MetalDrawingEffect.boundingRect(
                of: inputImage.bounds, transformedBy: inputImage.transform
            )
            cropRect = frameRect.union(inputBounds)
        }

        let pixelWidth = max(1, Int(ceil(cropRect.right - cropRect.left)))
        let pixelHeight = max(1, Int(ceil(cropRect.bottom - cropRect.top)))
        if outputTexture == nil || outputPixelWidth != pixelWidth || outputPixelHeight != pixelHeight {
            outputPixelWidth = pixelWidth
            outputPixelHeight = pixelHeight
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: pixelWidth, height: pixelHeight, mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            outputTexture = context.devices.device.makeTexture(descriptor: descriptor)
        }
        guard let outputTexture else {
            registerTransparent()
            return
        }

        render(inputImage: inputImage, into: outputTexture, cropRect: cropRect)
        context.devices.register(
            outputReference,
            image: MetalImage(texture: outputTexture, bounds: cropRect)
        )
    }

    public func dispose() {
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        outputTexture = nil
        outputs = []
    }

    /// Flood の下地＋入力の通常合成を出力テクスチャへ描く。
    private func render(inputImage: MetalImage?, into texture: MTLTexture, cropRect: RectF) {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else { return }
        let passDescriptor = MTLRenderPassDescriptor()
        let attachment = passDescriptor.colorAttachments[0]
        attachment?.texture = texture
        attachment?.loadAction = .clear
        // Flood の色（本家 FrameBufferSource.Update）: アルファ有効時は
        // 透明、無効時は不透明な黒。どちらも Premultiplied では同値。
        attachment?.clearColor = item.isAlphaEnabled
            ? MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            : MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        attachment?.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        if let inputImage {
            let bounds = inputImage.bounds
            let transform = inputImage.transform
            let corners: [(Double, Double)] = [
                (bounds.left, bounds.top), (bounds.right, bounds.top),
                (bounds.left, bounds.bottom), (bounds.right, bounds.bottom),
            ]
            let centerX = (cropRect.left + cropRect.right) / 2
            let centerY = (cropRect.top + cropRect.bottom) / 2
            let halfWidth = max(1, (cropRect.right - cropRect.left) / 2)
            let halfHeight = max(1, (cropRect.bottom - cropRect.top) / 2)
            let vertices: [QuadVertex] = corners.map { corner in
                let v = transform.transform(x: corner.0, y: corner.1, z: 0, w: 1)
                let w = v.w == 0 ? 1 : v.w
                let planeX = v.x / w
                let planeY = v.y / w
                return QuadVertex(
                    position: SIMD4<Float>(
                        Float((planeX - centerX) / halfWidth) * Float(w),
                        Float(-(planeY - centerY) / halfHeight) * Float(w),
                        0, Float(w)
                    ),
                    // UV は変換前の平面座標をテクスチャの平面範囲で写す
                    // （入力の内容境界がテクスチャ範囲より小さい場合の
                    // 画素対応を保つ。MAC-0027）。
                    uv: inputImage.uv(forLocalX: corner.0, y: corner.1)
                )
            }
            var opacity = Float(inputImage.opacity)
            encoder.setRenderPipelineState(context.devices.texturedPipeline)
            encoder.setVertexBytes(
                vertices, length: MemoryLayout<QuadVertex>.stride * vertices.count, index: 0
            )
            encoder.setFragmentTexture(inputImage.texture, index: 0)
            encoder.setFragmentSamplerState(
                inputImage.interpolation == .nearestNeighbor
                    ? context.devices.nearestSampler : context.devices.linearSampler,
                index: 0
            )
            encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
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

/// 口の形。本家 MouthShape に対応する。
public enum MetalTachieMouthShape: Sendable {
    case silent
    case a
    case i
    case u
    case e
    case o
}

/// 顔アイテム1件の説明。本家 TachieFaceDescription に対応する。
public struct MetalTachieFaceDescription {
    /// 顔アイテム内位置（タイムライン位置 − アイテム開始）。
    public var itemPosition: FramePosition
    /// 顔アイテムの長さ。
    public var itemDuration: FramePosition
    /// レイヤー。
    public var layer: Int
    /// 顔パラメータ（プラグイン型のため生保持のまま渡す）。
    public var faceParameter: PreservedObject?

    public init(
        itemPosition: FramePosition, itemDuration: FramePosition,
        layer: Int, faceParameter: PreservedObject?
    ) {
        self.itemPosition = itemPosition
        self.itemDuration = itemDuration
        self.layer = layer
        self.faceParameter = faceParameter
    }
}

/// 立ち絵の更新説明。本家 TachieSourceDescription（アイテム説明＋
/// TachieDescription＋音量＋口形）に対応する。
public struct MetalTachieUpdateDescription {
    /// 元のアイテム説明。
    public var itemDescription: TimelineItemSourceDescription
    /// キャラクターの立ち絵パラメータ（プラグイン型のため生保持）。
    public var characterParameter: PreservedObject?
    /// 立ち絵アイテムのパラメータ（プラグイン型のため生保持）。
    public var itemParameter: PreservedObject?
    /// 顔アイテム列の説明（ActiveFaces の順）。
    public var faces: [MetalTachieFaceDescription]
    /// 口パク音量。本家は LipSyncEnvelope の非同期計算結果であり、
    /// 計算が無い場合のフォールバックは「声の範囲内なら 0、範囲外・
    /// 声なしなら -1」（本家 ReadVolumeAfterRequiredWait の経路）。
    /// 包絡計算そのものは差し替え点の先（音声側の基盤）にある。
    public var volume: Double
    /// 口形。LipSyncFrames はモデル層で生保持のため評価は未実装で、
    /// 常に .silent（本家の「リップシンク情報なし」の既定と同じ）。
    public var mouthShape: MetalTachieMouthShape

    public init(
        itemDescription: TimelineItemSourceDescription,
        characterParameter: PreservedObject?,
        itemParameter: PreservedObject?,
        faces: [MetalTachieFaceDescription],
        volume: Double,
        mouthShape: MetalTachieMouthShape
    ) {
        self.itemDescription = itemDescription
        self.characterParameter = characterParameter
        self.itemParameter = itemParameter
        self.faces = faces
        self.volume = volume
        self.mouthShape = mouthShape
    }
}

/// 立ち絵プラグインの描画境界。本家 ITachieSource2 に対応する
/// 差し替え点。立ち絵の描画は本家でも全面的にプラグインの責務であり、
/// プラグイン DLL はバイナリ互換が無いため、こちらでは境界だけを用意
/// する（パラメータはプラグイン型のため生保持のまま渡る）。
public protocol MetalTachieRenderer: AnyObject {
    /// 現在の出力（未生成なら nil）。
    var output: ImageReference? { get }
    /// 説明に基づいて出力を更新する。
    func update(_ description: MetalTachieUpdateDescription)
    /// 自身が所有する資源を解放する。
    func dispose()
}

/// 立ち絵描画器の生成境界。本家 TachieSourceFactory.CreateSource に
/// 対応する。プラグインが見つからなければ nil を返す。
public protocol MetalTachieRendererFactory {
    func makeRenderer(
        devices: MetalGraphicsDevices, tachieType: String?
    ) -> (any MetalTachieRenderer)?
}

/// 描画器を何も登録しない生成境界（既定）。本家で対応プラグインが
/// 無い場合と同じく、立ち絵は出力を持たない。
public struct EmptyTachieRendererFactory: MetalTachieRendererFactory {
    public init() {}

    public func makeRenderer(
        devices: MetalGraphicsDevices, tachieType: String?
    ) -> (any MetalTachieRenderer)? {
        nil
    }
}

/// 立ち絵アイテムの Source。本家 TachieSource に対応する。
///
/// 本家と同じく、コンストラクタで自前の文脈（CreateContext）を生成
/// して所有する。描画器は Character の TachieType が変わったときだけ
/// 生成し直す（本家の再生成条件）。ActiveVoice / ActiveFaces は
/// TimelineSource 相当（TimelineComposer）が顔解決の結果として
/// 書き込む受け口であり、Update はその内容から顔説明列を組み立てて
/// 描画器へ渡す（本家 TachieSource.Update の ITachieSource2 経路）。
/// 出力の公開条件も本家どおり: 描画器の出力の境界の最大辺が 2 未満
/// なら出力なし（isEmptyOutput）とする。
/// 口パクの包絡計算（本家 LipSyncEnvelope の非同期基盤）と口形の評価
/// は未実装であり、音量は本家のフォールバック値、口形は .silent を
/// 渡す（MetalTachieUpdateDescription の説明を参照）。
public final class MetalTachieSource: TachieSource {
    /// 現在の声（TimelineComposer が書き込む）。
    public var activeVoice: VoiceItem?
    /// 現在の顔アイテム列（TimelineComposer が書き込む。レイヤー降順）。
    public var activeFaces: [any FaceItem] = []

    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: TachieItem
    private let drawingEffect: MetalDrawingEffect
    private let rendererFactory: any MetalTachieRendererFactory

    private var renderer: (any MetalTachieRenderer)?
    private var currentTachieType: String?
    private var hasResolvedType = false
    private var currentRendererOutput: ImageReference?
    private var output: StandardSourceOutput?

    public init(
        devices: MetalGraphicsDevices,
        item: TachieItem,
        rendererFactory: (any MetalTachieRendererFactory)? = nil
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.rendererFactory = rendererFactory ?? EmptyTachieRendererFactory()
        self.drawingEffect = MetalDrawingEffect(context: context)
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        let tachieType = item.character?.tachieType
        if !hasResolvedType || currentTachieType != tachieType {
            hasResolvedType = true
            currentTachieType = tachieType
            renderer?.dispose()
            renderer = rendererFactory.makeRenderer(
                devices: context.devices, tachieType: tachieType
            )
            currentRendererOutput = nil
            output = nil
        }

        // 顔説明列（本家 TachieSource.Update の faces 構築どおり:
        // 位置 = タイムライン位置 − アイテム開始、長さ、レイヤー、
        // 顔パラメータ）。
        let faces: [MetalTachieFaceDescription] = activeFaces.compactMap { face in
            guard let base = face as? BaseItem else { return nil }
            let parameter: PreservedObject?
            if let faceItem = face as? TachieFaceItem {
                parameter = faceItem.tachieFaceParameter
            } else if let voiceItem = face as? VoiceItem {
                parameter = voiceItem.tachieFaceParameter
            } else {
                parameter = nil
            }
            return MetalTachieFaceDescription(
                itemPosition: FramePosition(
                    frame: description.timelinePosition.frame - base.frame, fps: description.fps
                ),
                itemDuration: FramePosition(frame: base.length, fps: description.fps),
                layer: base.layer,
                faceParameter: parameter
            )
        }

        // 音量は本家のフォールバック値（包絡未計算時）: 声の範囲内なら
        // 0、範囲外・声なしなら -1。
        let volume: Double
        if let voice = activeVoice {
            let voiceFrame = description.timelinePosition.frame - voice.frame
            volume = (voiceFrame >= 0 && voiceFrame < voice.length) ? 0 : -1
        } else {
            volume = -1
        }

        renderer?.update(MetalTachieUpdateDescription(
            itemDescription: description,
            characterParameter: item.character?.tachieCharacterParameter,
            itemParameter: item.tachieItemParameter,
            faces: faces,
            volume: volume,
            mouthShape: .silent
        ))

        // 出力の公開（本家: 出力境界の最大辺が 2 未満なら出力なし）。
        let rendererOutput = renderer?.output
        if rendererOutput !== currentRendererOutput {
            currentRendererOutput = rendererOutput
            if let rendererOutput,
               let image = context.devices.image(for: rendererOutput),
               max(image.bounds.right - image.bounds.left,
                   image.bounds.bottom - image.bounds.top) >= 2 {
                output = StandardSourceOutput(
                    output: rendererOutput, drawingEffect: drawingEffect, dontDispose: true
                )
            } else {
                output = nil
            }
        }
        outputs = output.map { [$0] } ?? []
    }

    public func dispose() {
        renderer?.dispose()
        renderer = nil
        drawingEffect.dispose()
        outputs = []
    }
}
#endif
