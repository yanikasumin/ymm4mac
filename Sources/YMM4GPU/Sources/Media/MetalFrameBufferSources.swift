#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import Metal
import YMM4Core

/// フレームバッファ系 Source の共通基底。本家 FrameBufferSource の
/// Metal 実体であり、派生が FrameBufferItem 用（MetalFrameBufferSource）
/// と EffectItem 用（MetalEffectSource、MAC-0035）の2つある。
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
///
/// 派生ごとの差は3つのフック（背景クリア／Flood の透明化／境界拡張）と
/// DrawingEffect の種類だけで、蓄積画像の実体化はこの基底が担う。
/// フックの既定値は本家で FrameBufferItem として null を渡した場合の
/// 帰結（B-1: ClearBackground = false、Flood は不透明な黒、境界は
/// 画面サイズ）であり、EffectItem 用の派生は既定値のまま使う。
public class MetalFrameBufferSourceBase: FrameBufferSource {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    /// 合成済みの蓄積画像（借用。所有権は移らない）。合成側が設定する。
    public var input: ImageReference?
    /// フレームのサイズ。合成側が設定する。
    public var frameSize: PixelSize = PixelSize(width: 0, height: 0)
    /// 背景をクリアするか（合成側が引き継ぎ描画の判断に使う）。
    public var clearBackground: Bool { behaviorClearBackground }

    /// 背景クリアの実値（派生が差し替える）。
    var behaviorClearBackground: Bool { false }
    /// Flood を透明にするか（本家 IsAlphaEnabled に対応）。
    var floodIsTransparent: Bool { false }
    /// 切り抜き境界を入力画像の局所境界まで広げるか（本家
    /// IsFrameOutImageRenderingEnabled に対応）。
    var expandsBoundsToInput: Bool { false }

    let context: MetalGraphicsContext
    private let drawingEffect: any DrawingEffectProcessor
    private let outputReference = ImageReference(label: "framebuffer-source")
    private var outputTexture: MTLTexture?
    private var outputPixelWidth: Int = 0
    private var outputPixelHeight: Int = 0

    init(context: MetalGraphicsContext, drawingEffect: any DrawingEffectProcessor) {
        self.context = context
        self.drawingEffect = drawingEffect
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
        if expandsBoundsToInput, let inputImage {
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
        attachment?.clearColor = floodIsTransparent
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

/// フレームバッファアイテムの Source。本家 FrameBufferSource に対応する。
/// アイテムの保持値（ClearBackground / IsAlphaEnabled /
/// IsFrameOutImageRenderingEnabled）を基底のフックへそのまま渡し、
/// DrawingEffect は通常のアイテム変形（MetalDrawingEffect）を使う。
public final class MetalFrameBufferSource: MetalFrameBufferSourceBase {
    private let item: FrameBufferItem

    public init(devices: MetalGraphicsDevices, item: FrameBufferItem) {
        self.item = item
        let context = devices.makeContext()
        super.init(
            context: context,
            drawingEffect: MetalDrawingEffect(context: context)
        )
    }

    override var behaviorClearBackground: Bool { item.clearBackground }
    override var floodIsTransparent: Bool { item.isAlphaEnabled }
    override var expandsBoundsToInput: Bool { item.isFrameOutImageRenderingEnabled }
}

#endif
