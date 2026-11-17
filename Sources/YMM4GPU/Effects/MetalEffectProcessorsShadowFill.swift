#if os(macOS)
import Foundation
import Metal
import YMM4Core

// MARK: - 影・塗り・枠線系（単色ブラシのみ）

/// 角丸矩形の塗りをテクスチャへ描く（FillBackground の下地用）。
/// 図形シェーダ（SDF）の全面塗りを使い、`outputBounds` を張る
/// テクスチャのうち `rect` の範囲だけを単色で塗る。
/// nil を返すのは出力境界が空（描くものが無い正当な無処理）の場合
/// だけで、テクスチャ確保・コマンドバッファの失敗は
/// `MetalRenderError` を投げる（GPU28-03 / MAC-0033）。
func renderRoundedRectFill(
    context: MetalGraphicsContext,
    rect: RectF,
    radius: Double,
    color: Color,
    outputBounds: RectF
) throws -> MetalImage? {
    let outWidth = outputBounds.right - outputBounds.left
    let outHeight = outputBounds.bottom - outputBounds.top
    guard outWidth > 0, outHeight > 0 else { return nil }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: max(1, Int(ceil(outWidth))), height: max(1, Int(ceil(outHeight))),
        mipmapped: false
    )
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .shared
    guard let texture = context.devices.device.makeTexture(descriptor: descriptor) else {
        throw MetalRenderError.textureCreationFailed(
            width: max(1, Int(ceil(outWidth))), height: max(1, Int(ceil(outHeight)))
        )
    }
    guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
        throw MetalRenderError.commandBufferFailed(underlying: nil)
    }
    let passDescriptor = MTLRenderPassDescriptor()
    let attachment = passDescriptor.colorAttachments[0]
    attachment?.texture = texture
    attachment?.loadAction = .clear
    attachment?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    attachment?.storeAction = .store
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
    else {
        throw MetalRenderError.commandBufferFailed(underlying: nil)
    }
    let centerX = (rect.left + rect.right) / 2
    let centerY = (rect.top + rect.bottom) / 2
    let corners: [(Double, Double)] = [
        (rect.left, rect.top), (rect.right, rect.top),
        (rect.left, rect.bottom), (rect.right, rect.bottom),
    ]
    let vertices: [QuadVertex] = corners.map { corner in
        QuadVertex(
            position: SIMD4<Float>(
                Float(2 * (corner.0 - outputBounds.left) / outWidth - 1),
                Float(-(2 * (corner.1 - outputBounds.top) / outHeight - 1)),
                0, 1
            ),
            uv: SIMD2<Float>(Float(corner.0 - centerX), Float(corner.1 - centerY))
        )
    }
    struct ShapeUniforms {
        var halfSize: SIMD2<Float>
        var radius: Float
        var bandWidth: Float
        var aaScale: Float
        var color: SIMD4<Float>
    }
    let rectWidth = rect.right - rect.left
    let rectHeight = rect.bottom - rect.top
    var uniforms = ShapeUniforms(
        halfSize: SIMD2<Float>(Float(rectWidth / 2), Float(rectHeight / 2)),
        radius: Float(min(radius, min(rectWidth, rectHeight) / 2)),
        bandWidth: -1,
        aaScale: 1,
        color: premultipliedVector(color)
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
    if commandBuffer.status == .error {
        throw MetalRenderError.commandBufferFailed(underlying: commandBuffer.error)
    }
    return MetalImage(texture: texture, bounds: outputBounds)
}

/// 影。本家 `ShadowEffect`。
/// 連鎖: シルエット（白 × 入力α）をブラシでマスク（単色ブラシでは
/// ブラシ色 × 入力α と等しい）→ ガウスぼかし σ = Blur（BorderMode は
/// 未設定のため Soft とする。記録）→ 回転（中心は IsRotateAtCenter で
/// 境界中心、それ以外は原点）・拡縮 Zoom/100 ・平行移動 (X, Y) →
/// 不透明度 Opacity/100 → 原画の下へ SourceOver。
/// 単色ブラシ以外（グラデーション等）は素通し（ブラシサブシステムが
/// 差し替え点）。
public final class MetalShadowProcessor: MetalEffectProcessor {
    private let definition: ShadowEffectDefinition

    public init(context: MetalGraphicsContext, definition: ShadowEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.brush) else {
            return input
        }
        // シルエット（ブラシ色 × 入力α）。
        let silhouette = try renderWarp(
            input: input, mask: nil, outputBounds: input.bounds, mode: 5,
            param0: premultipliedVector(brushColor)
        )
        let blur = evaluate(definition.blur, description)
        let blurred = try renderGaussianBlurred(
            input: silhouette, sigma: blur, hardBorder: false
        )
        // 変形: 回転・拡縮（中心は境界中心か原点）→ 平行移動。
        let center = definition.isRotateAtCenter
            ? Vector3(
                x: (input.bounds.left + input.bounds.right) / 2,
                y: (input.bounds.top + input.bounds.bottom) / 2, z: 0)
            : Vector3.zero
        let zoom = evaluate(definition.zoom, description) / 100
        let angle = evaluate(definition.angle, description)
        // 中心 c まわりの回転 = T(−c) · Rz · T(c)（左端から適用される）。
        let rotation = Matrix4x4.createTranslation(Vector3(x: -center.x, y: -center.y, z: 0))
            * Matrix4x4.createRotationZ(angle * Double.pi / 180)
            * Matrix4x4.createTranslation(center)
        let scale = Matrix4x4.createScale(x: zoom, y: zoom, z: 1, center: center)
        let translation = Matrix4x4.createTranslation(
            x: evaluate(definition.x, description),
            y: evaluate(definition.y, description), z: 0
        )
        let matrix = rotation * scale * translation
        let shadowBounds = MetalDrawingEffect.boundingRect(of: blurred.bounds, transformedBy: matrix)
        let shadow = try renderTransformed(
            input: blurred, matrix: matrix, outputBounds: shadowBounds,
            interpolation: .linear
        )
        let outputBounds = input.bounds.union(shadow.bounds)
        let opacity = evaluate(definition.opacity, description) / 100
        return try renderComposite(
            top: input, bottom: shadow, outputBounds: outputBounds, mode: 0,
            opacityBottom: opacity
        )
    }
}

/// 背景塗りつぶし。本家 `FillBackgroundEffect`。
/// 入力境界を上下左右へ広げた矩形 E を角丸（Round）付きでブラシ色に
/// 塗り（不透明度 = Opacity/100)、その上へ入力を描く。
/// IsBackgroundOnly の場合は DestinationOut（塗り × (1 − 入力α)）。
/// 混合モードが通常以外の場合は通常合成へ落とす（MAC-0012 台帳の
/// 既存方針）。入力境界の幅・高さが 1 以下のときは本家どおり無効。
/// 塗り矩形の寸法は本家が (int) 化してジオメトリを作るため、画素
/// 単位では最大1pxのずれがありうる（差分として記録）。
public final class MetalFillBackgroundProcessor: MetalEffectProcessor {
    private let definition: FillBackgroundEffectDefinition

    public init(context: MetalGraphicsContext, definition: FillBackgroundEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.brush) else {
            return input
        }
        let width = input.bounds.right - input.bounds.left
        let height = input.bounds.bottom - input.bounds.top
        guard width > 1, height > 1 else { return input }
        let expanded = RectF(
            left: input.bounds.left - evaluate(definition.left, description),
            top: input.bounds.top - evaluate(definition.top, description),
            right: input.bounds.right + evaluate(definition.right, description),
            bottom: input.bounds.bottom + evaluate(definition.bottom, description)
        )
        let fillRect = RectF(
            left: min(expanded.left, expanded.right), top: min(expanded.top, expanded.bottom),
            right: max(expanded.left, expanded.right), bottom: max(expanded.top, expanded.bottom)
        )
        let outputBounds = input.bounds.union(fillRect)
        guard let fill = try renderRoundedRectFill(
            context: context, rect: fillRect,
            radius: evaluate(definition.round, description),
            color: brushColor, outputBounds: outputBounds
        ) else { return nil }
        let opacity = evaluate(definition.opacity, description) / 100
        if definition.isBackgroundOnly {
            return try renderComposite(
                top: input, bottom: fill, outputBounds: outputBounds, mode: 1,
                opacityBottom: opacity
            )
        }
        return try renderComposite(
            top: input, bottom: fill, outputBounds: outputBounds, mode: 0,
            opacityBottom: opacity
        )
    }
}

/// 前景塗りつぶし。本家 `FillForegroundEffect`。
/// ブラシ色を入力境界で塗り、入力αでマスク（AlphaMask）し、
/// 不透明度 Opacity/100 を掛ける。IsBrushOnly でなければ入力の上へ
/// 通常合成する（混合モード通常以外は通常合成へ落とす。既存方針）。
public final class MetalFillForegroundProcessor: MetalEffectProcessor {
    private let definition: FillForegroundEffectDefinition

    public init(context: MetalGraphicsContext, definition: FillForegroundEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.brush) else {
            return input
        }
        guard let fill = try renderRoundedRectFill(
            context: context, rect: input.bounds, radius: 0,
            color: brushColor, outputBounds: input.bounds
        ) else { return nil }
        let masked = try renderWarp(
            input: fill, mask: input, outputBounds: input.bounds, mode: 3
        )
        let opacity = evaluate(definition.opacity, description) / 100
        if definition.isBrushOnly {
            return try renderColorEffect(
                input: masked,
                uniforms: ColorEffectUniforms(
                    mode: 7,
                    param0: SIMD4<Float>(Float(opacity), Float(opacity), Float(opacity), Float(opacity)),
                    param1: .zero
                )
            )
        }
        return try renderComposite(
            top: masked, bottom: input, outputBounds: input.bounds, mode: 0,
            opacityTop: opacity
        )
    }
}

/// 枠線。本家 `FrameLineEffect`。
/// 上下左右の余白（(int) 化）の外側へ太さ Thickness の帯（＋全方向の
/// ときは四隅の正方形）をブラシ色で描き、不透明度 Opacity/100 を
/// 掛けて、RenderPlacement に従い入力の前／後へ SourceOver する。
/// 本家どおり、帯が出るのは入力境界の幅が 1 より大きいときだけ。
/// 帯の描画は単色四角形の複数回描画で1テクスチャへ集める。
public final class MetalFrameLineProcessor: MetalEffectProcessor {
    private let definition: FrameLineEffectDefinition

    public init(context: MetalGraphicsContext, definition: FrameLineEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.brush) else {
            return input
        }
        let bounds = input.bounds
        guard bounds.right - bounds.left > 1 else { return input }
        let left = Double(Int(evaluate(definition.left, description)))
        let top = Double(Int(evaluate(definition.top, description)))
        let right = Double(Int(evaluate(definition.right, description)))
        let bottom = Double(Int(evaluate(definition.bottom, description)))
        let thickness = evaluate(definition.thickness, description)
        // unknown は定義の既定 (.all) として評価する（MAC-0018 の方針）。
        let type: FrameLineType = if case .unknown = definition.type {
            .all
        } else {
            definition.type
        }
        var rects: [RectF] = []
        if type == .all || type == .top {
            rects.append(RectF(
                left: bounds.left - left, top: bounds.top - top - thickness,
                right: bounds.right + right, bottom: bounds.top - top
            ))
        }
        if type == .all || type == .bottom {
            rects.append(RectF(
                left: bounds.left - left, top: bounds.bottom + bottom,
                right: bounds.right + right, bottom: bounds.bottom + bottom + thickness
            ))
        }
        if type == .all || type == .left {
            rects.append(RectF(
                left: bounds.left - left - thickness, top: bounds.top - top,
                right: bounds.left - left, bottom: bounds.bottom + bottom
            ))
        }
        if type == .all || type == .right {
            rects.append(RectF(
                left: bounds.right + right, top: bounds.top - top,
                right: bounds.right + right + thickness, bottom: bounds.bottom + bottom
            ))
        }
        if type == .all {
            let corners: [(Double, Double)] = [
                (bounds.left - left - thickness, bounds.top - top - thickness),
                (bounds.right + right, bounds.top - top - thickness),
                (bounds.left - left - thickness, bounds.bottom + bottom),
                (bounds.right + right, bounds.bottom + bottom),
            ]
            for corner in corners {
                rects.append(RectF(
                    left: corner.0, top: corner.1,
                    right: corner.0 + thickness, bottom: corner.1 + thickness
                ))
            }
        }
        guard !rects.isEmpty, thickness > 0 else { return input }
        var outputBounds = bounds
        for rect in rects { outputBounds = outputBounds.union(rect) }
        guard let lineImage = try renderSolidRects(
            rects: rects, color: brushColor, outputBounds: outputBounds
        ) else { return nil }
        let opacity = evaluate(definition.opacity, description) / 100
        if definition.renderPlacement == .front {
            return try renderComposite(
                top: lineImage, bottom: input, outputBounds: outputBounds, mode: 0,
                opacityTop: opacity
            )
        }
        // .back（定義の既定）および unknown は後ろとして扱う。
        return try renderComposite(
            top: input, bottom: lineImage, outputBounds: outputBounds, mode: 0,
            opacityBottom: opacity
        )
    }

    /// 単色四角形の列を1つのテクスチャへ描く（全面四角形×単色シェーダ）。
    private func renderSolidRects(
        rects: [RectF], color: Color, outputBounds: RectF
    ) throws -> MetalImage? {
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        guard outWidth > 0, outHeight > 0 else { return nil }
        let texture = try makeTexture(
            width: Int(ceil(outWidth)), height: Int(ceil(outHeight)),
            usage: [.renderTarget, .shaderRead]
        )
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        let passDescriptor = MTLRenderPassDescriptor()
        let attachment = passDescriptor.colorAttachments[0]
        attachment?.texture = texture
        attachment?.loadAction = .clear
        attachment?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        attachment?.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            throw MetalRenderError.commandBufferFailed(underlying: nil)
        }
        encoder.setRenderPipelineState(context.devices.solidPipeline)
        var fillColor = premultipliedVector(color)
        encoder.setFragmentBytes(
            &fillColor, length: MemoryLayout<SIMD4<Float>>.size, index: 0
        )
        for rect in rects {
            let corners: [(Double, Double)] = [
                (rect.left, rect.top), (rect.right, rect.top),
                (rect.left, rect.bottom), (rect.right, rect.bottom),
            ]
            let vertices: [QuadVertex] = corners.map { corner in
                QuadVertex(
                    position: SIMD4<Float>(
                        Float(2 * (corner.0 - outputBounds.left) / outWidth - 1),
                        Float(-(2 * (corner.1 - outputBounds.top) / outHeight - 1)),
                        0, 1
                    ),
                    uv: SIMD2<Float>(0, 0)
                )
            }
            encoder.setVertexBytes(
                vertices, length: MemoryLayout<QuadVertex>.stride * vertices.count, index: 0
            )
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw MetalRenderError.commandBufferFailed(underlying: commandBuffer.error)
        }
        return MetalImage(texture: texture, bounds: outputBounds)
    }
}

#endif
