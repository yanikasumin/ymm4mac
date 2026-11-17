#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core

/// 素材パスを解決する。絶対パスと file URL はそのまま使い、相対パスは
/// プロジェクトの基準フォルダから解決する。画像 Source と動画 Source で
/// 共有する。
func resolveMediaURL(path: String, baseDirectory: URL?) -> URL? {
    if let url = URL(string: path), url.isFileURL {
        return url
    }
    // 絶対パスかどうかは生の文字列で判定する。URL(fileURLWithPath:) は
    // 相対パスをカレントディレクトリで絶対化してしまうため、変換後の
    // パスで判定すると相対パスが全て絶対パス扱いになり、基準フォルダ
    // 解決へ到達しない（MAC-0028 検証で発見した MAC-0025 の回帰）。
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
    }
    guard let baseDirectory else { return nil }
    return baseDirectory.appendingPathComponent(path)
}

/// CGImage を BGRA（Premultiplied）のテクスチャへ変換する。
/// 画像 Source（ImageIO のデコード結果）と動画 Source
/// （AVAssetImageGenerator のフレーム）で共有する。
func makePremultipliedTexture(
    device: MTLDevice, cgImage: CGImage
) -> (texture: MTLTexture, width: Int, height: Int)? {
    var width = cgImage.width
    var height = cgImage.height
    guard width > 0, height > 0 else { return nil }
    // テクスチャ上限を超える場合は比例縮小する（画像 Source の従来挙動）。
    let maxDimension = 16384
    if width > maxDimension || height > maxDimension {
        let scale = Double(maxDimension) / Double(max(width, height))
        width = max(1, Int(Double(width) * scale))
        height = max(1, Int(Double(height) * scale))
    }
    let bytesPerRow = width * 4
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
    ), let data = context.data else { return nil }
    // ビットマップ文脈のメモリは先頭行が画像の上端になるため、反転は
    // 不要（反転して描くとテクスチャが上下逆になる。MAC-0028 検証の
    // プローブで実測: 四象限画像の左上が青＝左下の色になった）。
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
        withBytes: data, bytesPerRow: bytesPerRow
    )
    return (texture, width, height)
}

/// 画像アイテムの Source。本家 ImageSource に対応する。
///
/// 本家と同じく、コンストラクタで自前の文脈（CreateContext）を生成して
/// 所有し、ファイルの読み込みは初回 Update と FilePath の変更時にだけ
/// 行う。読み込んだ画像は中心が原点になるよう配置する（本家は
/// (-幅/2, -高さ/2) へ描いて中心化する。端数は本家どおり 0 方向へ
/// 切り捨て）。読み込みに失敗した場合は、本家の ImageFileSourceFactory
/// が null を返したときの代替（CreateEmptyBitmap）と同じく、1×1 完全
/// 透明へ落とす。対応形式は macOS 標準（ImageIO）で読めるものに限る
/// （本家の WIC 等のプラグイン経路は対象外）。
/// 相対パスは baseDirectory（.ymmp のあるフォルダ）基準で解決する。
/// Windows 形式のパスは Mac 上に存在しないため解決できず、透明へ落ちる。
public final class MetalImageSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: ImageItem
    private let baseDirectory: URL?
    private let drawingEffect: MetalDrawingEffect
    private let outputReference = ImageReference(label: "image-source")
    private var loadedPath: String??
    private var isFirstUpdate = true
    /// デコードしたテクスチャ（代替の共有透明テクスチャを使う間は nil）。
    private var decodedTexture: MTLTexture?

    public init(devices: MetalGraphicsDevices, item: ImageItem, baseDirectory: URL? = nil) {
        self.context = devices.makeContext()
        self.item = item
        self.baseDirectory = baseDirectory
        self.drawingEffect = MetalDrawingEffect(context: context)
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        if isFirstUpdate || loadedPath != item.filePath {
            isFirstUpdate = false
            loadedPath = item.filePath
            load()
        }
    }

    public func dispose() {
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        decodedTexture = nil
        outputs = []
    }

    private func load() {
        decodedTexture = nil
        if let path = item.filePath, let url = resolveURL(path),
           let decoded = decodeTexture(url: url) {
            decodedTexture = decoded.texture
            // 本家は (-幅/2, -高さ/2) の描画オフセットで中心化する
            // （C# の float→int 変換＝0 方向への切り捨て）。
            let left = Double(-(decoded.width / 2))
            let top = Double(-(decoded.height / 2))
            context.devices.register(
                outputReference,
                image: MetalImage(
                    texture: decoded.texture,
                    bounds: RectF(
                        left: left, top: top,
                        right: left + Double(decoded.width),
                        bottom: top + Double(decoded.height)
                    )
                )
            )
        } else {
            // 読み込み失敗時の代替: 1×1 完全透明（本家 CreateEmptyBitmap）。
            context.devices.register(
                outputReference,
                image: MetalImage(
                    texture: context.devices.transparentTexture,
                    bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
                )
            )
        }
        outputs = [
            StandardSourceOutput(
                output: outputReference, drawingEffect: drawingEffect, dontDispose: true
            ),
        ]
    }

    private func resolveURL(_ path: String) -> URL? {
        if path.isEmpty { return nil }
        return resolveMediaURL(path: path, baseDirectory: baseDirectory)
    }

    /// ImageIO でデコードし、Premultiplied BGRA のテクスチャへ変換する。
    private func decodeTexture(url: URL) -> (texture: MTLTexture, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return makePremultipliedTexture(device: context.devices.device, cgImage: cgImage)
    }
}

/// 図形アイテムの Source。本家 ShapeSource（＋ GeometryShapeParameterSource）
/// に対応する。
///
/// MAC-0008 で型付け済みの RectangleShapeParameter と単色ブラシだけを
/// 対象とし、それ以外のパラメータ（生保持）は透明を返す（未対応として
/// 台帳に記録）。評価は本家 GetSize の式どおり:
/// - WidthHeight: 幅 = Width、高さ = Height
/// - SizeAspect: 幅 = Size × (1 − max(0, AspectRate/100))、
///   高さ = Size × (1 + min(0, AspectRate/100))
/// 描画は本家の実現化規則の可視結果を再現する: 枠線の太さが
/// min(幅, 高さ)/2 + 0.25 を超えれば全面塗り、そうでなければ内側へ
/// 太さ分の帯だけを塗る。角の丸み（Round）は角丸半径として適用する。
/// 図形は中心が原点のテクスチャへ SDF で描き込む（テクスチャ寸法は
/// 4096 へ丸める。巨大な図形では境界が粗くなる。台帳に記録）。
public final class MetalShapeSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: ShapeItem
    private let drawingEffect: MetalDrawingEffect
    private let outputReference = ImageReference(label: "shape-source")
    private var renderedTexture: MTLTexture?
    private var renderedKey: RenderKey?

    private struct RenderKey: Equatable {
        var width: Double
        var height: Double
        var round: Double
        var strokeThickness: Double
        var color: Color
    }

    /// 図形テクスチャの寸法上限。
    private static let maxTextureDimension = 4096

    public init(devices: MetalGraphicsDevices, item: ShapeItem) {
        self.context = devices.makeContext()
        self.item = item
        self.drawingEffect = MetalDrawingEffect(context: context)
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        guard case .rectangle(let parameter) = item.shapeParameter else {
            // 型付けされていない図形パラメータは未対応（透明）。
            registerTransparent()
            return
        }
        let frame = description.itemPosition.frame
        let length = description.itemDuration.frame
        let fps = description.fps
        let size = Self.evaluateSize(parameter: parameter, frame: frame, length: length, fps: fps)
        let round = parameter.round.value(atFrame: frame, length: length, fps: fps)
        let stroke = parameter.strokeThickness.value(atFrame: frame, length: length, fps: fps)
        // 単色ブラシ以外のブラシは未対応のため白で代用する（本家の
        // 既定ブラシも単色・白）。
        let color: Color
        if case .solidColor(let solid) = parameter.brush.parameter {
            color = solid.color
        } else {
            color = .white
        }
        let key = RenderKey(
            width: size.width, height: size.height,
            round: round, strokeThickness: stroke, color: color
        )
        if renderedKey != key {
            renderedKey = key
            renderedTexture = rasterize(key: key)
        }
        if let renderedTexture {
            context.devices.register(
                outputReference,
                image: MetalImage(
                    texture: renderedTexture,
                    bounds: RectF(
                        left: -size.width / 2, top: -size.height / 2,
                        right: size.width / 2, bottom: size.height / 2
                    )
                )
            )
        } else {
            registerTransparent()
            return
        }
        ensureOutputs()
    }

    public func dispose() {
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        renderedTexture = nil
        outputs = []
    }

    /// 本家 SizeAndAspectShapeParameterBase.GetSize の式。
    static func evaluateSize(
        parameter: RectangleShapeParameter, frame: Int, length: Int, fps: Int
    ) -> (size: Double, width: Double, height: Double) {
        if parameter.sizeMode == .widthHeight {
            let width = parameter.width.value(atFrame: frame, length: length, fps: fps)
            let height = parameter.height.value(atFrame: frame, length: length, fps: fps)
            return (size: max(width, height), width: width, height: height)
        }
        let size = parameter.size.value(atFrame: frame, length: length, fps: fps)
        let aspect = parameter.aspectRate.value(atFrame: frame, length: length, fps: fps)
        let width = size * (1 - max(0, aspect / 100))
        let height = size * (1 + min(0, aspect / 100))
        return (size: size, width: width, height: height)
    }

    private func ensureOutputs() {
        if outputs.isEmpty {
            outputs = [
                StandardSourceOutput(
                    output: outputReference, drawingEffect: drawingEffect, dontDispose: true
                ),
            ]
        }
    }

    private func registerTransparent() {
        context.devices.register(
            outputReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
        ensureOutputs()
    }

    /// 図形をテクスチャへ描き込む。完了まで待つ（合成全体が同期実行の
    /// ため、この段も同期で確定させる）。
    private func rasterize(key: RenderKey) -> MTLTexture? {
        guard key.width > 0, key.height > 0 else { return nil }
        let width = max(1, min(Self.maxTextureDimension, Int(ceil(key.width))))
        let height = max(1, min(Self.maxTextureDimension, Int(ceil(key.height))))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = context.devices.device.makeTexture(descriptor: descriptor),
              let commandBuffer = context.commandQueue.makeCommandBuffer()
        else { return nil }
        let passDescriptor = MTLRenderPassDescriptor()
        let attachment = passDescriptor.colorAttachments[0]
        attachment?.texture = texture
        attachment?.loadAction = .clear
        attachment?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        attachment?.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return nil }

        // 全面の四角形。uv 属性の場所へ平面座標（図形中心が原点）を渡す。
        let halfPlaneWidth = key.width / 2
        let halfPlaneHeight = key.height / 2
        let corners: [(Double, Double)] = [
            (-halfPlaneWidth, -halfPlaneHeight), (halfPlaneWidth, -halfPlaneHeight),
            (-halfPlaneWidth, halfPlaneHeight), (halfPlaneWidth, halfPlaneHeight),
        ]
        let vertices: [QuadVertex] = corners.map { corner in
            QuadVertex(
                position: SIMD4<Float>(
                    Float(corner.0 / halfPlaneWidth), Float(-corner.1 / halfPlaneHeight), 0, 1
                ),
                uv: SIMD2<Float>(Float(corner.0), Float(corner.1))
            )
        }
        struct ShapeUniforms {
            var halfSize: SIMD2<Float>
            var radius: Float
            var bandWidth: Float
            var aaScale: Float
            var color: SIMD4<Float>
        }
        let alpha = Double(key.color.alpha) / 255
        let isFilled = key.strokeThickness
            > min(key.width, key.height) / 2 + 0.25
        var uniforms = ShapeUniforms(
            halfSize: SIMD2<Float>(Float(halfPlaneWidth), Float(halfPlaneHeight)),
            radius: Float(min(key.round, min(key.width, key.height) / 2)),
            bandWidth: isFilled ? -1 : Float(key.strokeThickness),
            aaScale: Float(max(key.width / Double(width), key.height / Double(height))),
            color: SIMD4<Float>(
                Float(Double(key.color.red) / 255 * alpha),
                Float(Double(key.color.green) / 255 * alpha),
                Float(Double(key.color.blue) / 255 * alpha),
                Float(alpha)
            )
        )
        encoder.setRenderPipelineState(context.devices.shapePipeline)
        encoder.setVertexBytes(
            vertices, length: MemoryLayout<QuadVertex>.stride * vertices.count, index: 0
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return texture
    }
}

/// 未対応アイテム種別の Source。透明な出力を返す。
///
/// Video・Scene・Tachie・Effect・合成グループ等が対象であり、
/// 未対応であることは台帳に明記する。DrawingEffect は実物を
/// 持つため、変形・不透明度を適用しても結果は透明のままになる。
public final class MetalEmptySource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let drawingEffect: MetalDrawingEffect
    private let outputReference = ImageReference(label: "empty-source")

    public init(devices: MetalGraphicsDevices) {
        self.context = devices.makeContext()
        self.drawingEffect = MetalDrawingEffect(context: context)
        context.devices.register(
            outputReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
        outputs = [
            StandardSourceOutput(
                output: outputReference, drawingEffect: drawingEffect, dontDispose: true
            ),
        ]
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        // 未対応の種別は常に透明。評価する内容は無い。
    }

    public func dispose() {
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        outputs = []
    }
}

/// アイテム種別から Source を供給する境界（TimelineComposer の
/// sourceProvider に渡す）。対応は ImageItem / ShapeItem / TextItem /
/// VoiceItem（字幕）/ VideoItem / SceneItem / FrameBufferItem /
/// TachieItem / 合成グループ（GroupItem.IsComposite）で、それ以外は
/// MetalEmptySource（透明）を返す。
public struct MetalSourceProvider {
    public let devices: MetalGraphicsDevices
    /// 相対パスの解決基準（.ymmp のあるフォルダ）。
    public let baseDirectory: URL?
    /// シーン参照の解決子（プロジェクト全体のタイムライン列から引く）。
    /// 本家では説明の Scenes 列が担う役割。未設定ならシーンは空になる。
    public let sceneResolver: ((UUID) -> Timeline?)?
    /// 親シーンの連鎖（入れ子上限の判定用。通常は呼び出し側で設定しない）。
    public let parentSceneChain: [UUID]
    /// 立ち絵描画器の生成境界。未設定なら立ち絵は出力を持たない
    /// （本家で対応プラグインが無い場合と同じ）。
    public let tachieRendererFactory: (any MetalTachieRendererFactory)?
    /// この供給元のアイテムが属するタイムライン。合成グループの内部
    /// 合成（同じタイムラインの再合成）に使う。本家では CreateVideoSource
    /// へシーンが渡ることが担う役割。未設定なら合成グループは空になる。
    public let timeline: Timeline?
    /// 内部合成器（シーン・合成グループ）へ伝播させるエフェクト供給元。
    /// 外側の合成器と同じインスタンスを渡すことで、内部の子にも GPU
    /// エフェクト（Metal 処理器）が外側と同じく効く（MAC-0028）。
    /// 未設定なら内部合成器は Core の型付き供給元を使う。
    public let effectProvider: (any EffectPairProvider)?

    public init(
        devices: MetalGraphicsDevices,
        baseDirectory: URL? = nil,
        sceneResolver: ((UUID) -> Timeline?)? = nil,
        parentSceneChain: [UUID] = [],
        tachieRendererFactory: (any MetalTachieRendererFactory)? = nil,
        timeline: Timeline? = nil,
        effectProvider: (any EffectPairProvider)? = nil
    ) {
        self.devices = devices
        self.baseDirectory = baseDirectory
        self.sceneResolver = sceneResolver
        self.parentSceneChain = parentSceneChain
        self.tachieRendererFactory = tachieRendererFactory
        self.timeline = timeline
        self.effectProvider = effectProvider
    }

    public func source(for item: BaseItem & VideoItemProperties) -> any Source {
        switch item {
        case let imageItem as ImageItem:
            return MetalImageSource(
                devices: devices, item: imageItem, baseDirectory: baseDirectory
            )
        case let shapeItem as ShapeItem:
            return MetalShapeSource(devices: devices, item: shapeItem)
        case let textItem as TextItem:
            return MetalTextSource(devices: devices, item: textItem)
        case let voiceItem as VoiceItem:
            return MetalJimakuSource(devices: devices, item: voiceItem)
        case let videoItem as VideoItem:
            return MetalVideoSource(
                devices: devices, item: videoItem, baseDirectory: baseDirectory
            )
        case let sceneItem as SceneItem:
            return MetalSceneSource(
                devices: devices, item: sceneItem, composerFactory: sceneComposerFactory()
            )
        case let frameBufferItem as FrameBufferItem:
            return MetalFrameBufferSource(devices: devices, item: frameBufferItem)
        case let tachieItem as TachieItem:
            return MetalTachieSource(
                devices: devices, item: tachieItem, rendererFactory: tachieRendererFactory
            )
        case let groupItem as GroupItem where groupItem.isComposite:
            // 合成グループは内部合成を持つ Source を返す。属するタイム
            // ラインが分からない供給元では内部合成を作れないため空に倒す
            // （通常の配線では常に設定される）。
            guard let timeline else { return MetalEmptySource(devices: devices) }
            return MetalCompositeSource(
                devices: devices, item: groupItem,
                composerFactory: compositeComposerFactory(group: groupItem, timeline: timeline)
            )
        default:
            return MetalEmptySource(devices: devices)
        }
    }

    /// 合成グループの内部合成器を生成する境界。内部合成器は対象グループに
    /// 束縛した CompositeItemPicker で、同じタイムラインを再合成する。
    /// 描画先の文脈は呼び出し側（MetalCompositeSource が所有する文脈）を
    /// 借り、その寸法をタイムラインの VideoInfo へ合わせる。子の供給元は
    /// 同じタイムラインを引き継ぐため、入れ子の合成グループも再帰的に
    /// 内部合成を持つ（階層はレイヤー範囲で有限に閉じる）。
    private func compositeComposerFactory(
        group: GroupItem, timeline: Timeline
    ) -> (MetalGraphicsContext) -> TimelineComposer {
        let devices = self.devices
        let baseDirectory = self.baseDirectory
        let sceneResolver = self.sceneResolver
        let parentSceneChain = self.parentSceneChain
        let tachieRendererFactory = self.tachieRendererFactory
        let effectProvider = self.effectProvider
        return { context in
            context.targetSize = PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
            let childProvider = MetalSourceProvider(
                devices: devices,
                baseDirectory: baseDirectory,
                sceneResolver: sceneResolver,
                parentSceneChain: parentSceneChain,
                tachieRendererFactory: tachieRendererFactory,
                timeline: timeline,
                effectProvider: effectProvider
            )
            let scene = TimelineScene(sceneID: timeline.id, timeline: timeline)
            return TimelineComposer(
                scene: scene,
                picker: CompositeItemPicker(groupItem: group),
                targetFactory: context,
                sourceProvider: { item in childProvider.source(for: item) },
                effectProvider: effectProvider ?? TypedEffectPairProvider()
            )
        }
    }

    /// シーンの内部合成器を生成する境界。解決・入れ子上限（本家
    /// Scene.TryCreateVideoSource: 親シーン列に参照先 ID が 10 回
    /// 現れたら生成しない）を担う。描画先の文脈は呼び出し側
    /// （MetalSceneSource が所有する文脈）を借り、その寸法を参照先
    /// タイムラインの VideoInfo へ合わせる。内部合成器は子の供給元を
    /// 持ち、その供給元がさらに内側のシーンを解決する。
    private func sceneComposerFactory() -> (UUID, MetalGraphicsContext) -> TimelineComposer? {
        let devices = self.devices
        let baseDirectory = self.baseDirectory
        let sceneResolver = self.sceneResolver
        let parentSceneChain = self.parentSceneChain
        let tachieRendererFactory = self.tachieRendererFactory
        let effectProvider = self.effectProvider
        return { sceneID, context in
            guard let timeline = sceneResolver?(sceneID) else { return nil }
            if parentSceneChain.filter({ $0 == sceneID }).count >= 10 { return nil }
            context.targetSize = PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
            let childProvider = MetalSourceProvider(
                devices: devices,
                baseDirectory: baseDirectory,
                sceneResolver: sceneResolver,
                parentSceneChain: parentSceneChain + [sceneID],
                tachieRendererFactory: tachieRendererFactory,
                timeline: timeline,
                effectProvider: effectProvider
            )
            let scene = TimelineScene(sceneID: timeline.id, timeline: timeline)
            return TimelineComposer(
                scene: scene,
                targetFactory: context,
                sourceProvider: { item in childProvider.source(for: item) },
                effectProvider: effectProvider ?? TypedEffectPairProvider()
            )
        }
    }
}
#endif
