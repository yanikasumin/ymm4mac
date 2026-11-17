#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core

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

    struct RenderKey: Equatable {
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
        let color = Self.fillColor(for: parameter)
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

    /// 塗りの色。単色ブラシ以外のブラシは未対応のため白で代用する
    /// （本家の既定ブラシも単色・白）。
    static func fillColor(for parameter: RectangleShapeParameter) -> Color {
        if case .solidColor(let solid) = parameter.brush.parameter {
            return solid.color
        }
        return .white
    }

    /// パラメータを評価して図形テクスチャを描く（EffectItem のマスク
    /// 形状と共有する入口）。寸法が正でない場合と生成失敗時は nil。
    static func rasterizeShape(
        context: MetalGraphicsContext,
        parameter: RectangleShapeParameter,
        frame: Int, length: Int, fps: Int
    ) -> (texture: MTLTexture, width: Double, height: Double)? {
        let size = evaluateSize(parameter: parameter, frame: frame, length: length, fps: fps)
        let key = RenderKey(
            width: size.width, height: size.height,
            round: parameter.round.value(atFrame: frame, length: length, fps: fps),
            strokeThickness: parameter.strokeThickness.value(
                atFrame: frame, length: length, fps: fps
            ),
            color: fillColor(for: parameter)
        )
        guard let texture = rasterize(context: context, key: key) else { return nil }
        return (texture, size.width, size.height)
    }

    /// 図形をテクスチャへ描き込む。完了まで待つ（合成全体が同期実行の
    /// ため、この段も同期で確定させる）。
    private func rasterize(key: RenderKey) -> MTLTexture? {
        Self.rasterize(context: context, key: key)
    }

    static func rasterize(context: MetalGraphicsContext, key: RenderKey) -> MTLTexture? {
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

#endif
