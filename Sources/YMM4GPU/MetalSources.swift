#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core

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
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if let baseDirectory {
            return baseDirectory.appendingPathComponent(path)
        }
        return nil
    }

    /// ImageIO でデコードし、Premultiplied BGRA のテクスチャへ変換する。
    /// 寸法がデバイス上限（16384）を超える場合は比例縮小する。
    private func decodeTexture(url: URL) -> (texture: MTLTexture, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let maxDimension = 16384
        var width = cgImage.width
        var height = cgImage.height
        if width > maxDimension || height > maxDimension {
            let scale = Double(maxDimension) / Double(max(width, height))
            width = max(1, Int(Double(width) * scale))
            height = max(1, Int(Double(height) * scale))
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let bitmap = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else { return false }
            // ビットマップの行順を画像の上端からにする（上下反転の打ち消し）。
            bitmap.translateBy(x: 0, y: CGFloat(height))
            bitmap.scaleBy(x: 1, y: -1)
            bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = context.devices.device.makeTexture(descriptor: descriptor)
        else { return nil }
        bytes.withUnsafeBytes { buffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: buffer.baseAddress!, bytesPerRow: width * 4
            )
        }
        return (texture, width, height)
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
/// Text（次ブロック）・Video・Scene・Tachie・Effect・合成グループ等が
/// 対象であり、未対応であることは台帳に明記する。DrawingEffect は実物を
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
/// sourceProvider に渡す）。対応は ImageItem / ShapeItem のみで、
/// それ以外は MetalEmptySource（透明）を返す。
public struct MetalSourceProvider {
    public let devices: MetalGraphicsDevices
    /// 相対パスの解決基準（.ymmp のあるフォルダ）。
    public let baseDirectory: URL?

    public init(devices: MetalGraphicsDevices, baseDirectory: URL? = nil) {
        self.devices = devices
        self.baseDirectory = baseDirectory
    }

    public func source(for item: BaseItem & VideoItemProperties) -> any Source {
        switch item {
        case let imageItem as ImageItem:
            return MetalImageSource(
                devices: devices, item: imageItem, baseDirectory: baseDirectory
            )
        case let shapeItem as ShapeItem:
            return MetalShapeSource(devices: devices, item: shapeItem)
        default:
            return MetalEmptySource(devices: devices)
        }
    }
}
#endif
