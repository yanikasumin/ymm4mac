#if os(macOS)
import Foundation
import Metal
import YMM4Core

// MARK: - 影・塗り・枠線系（ブラシ全般。BRUSH46）

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
/// 連鎖: シルエット（ブラシ塗り × 入力α。本家は入力境界でブラシを
/// 塗って AlphaMask する。単色ブラシではブラシ色 × 入力α と等しい）
/// → ガウスぼかし σ = Blur（BorderMode は未設定のため Soft と
/// する。記録）→ 回転（中心は IsRotateAtCenter で境界中心、
/// それ以外は原点）・拡縮 Zoom/100 ・平行移動 (X, Y) →
/// 不透明度 Opacity/100 → 原画の下へ SourceOver。
/// GPU で描けないブラシ（グラデーションメッシュ・ノイズ等）は素通し。
public final class MetalShadowProcessor: MetalEffectProcessor {
    private let definition: ShadowEffectDefinition

    public init(context: MetalGraphicsContext, definition: ShadowEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        // シルエット（ブラシ塗り × 入力α）。本家がブラシの Update へ
        // 渡す境界は影の出力境界 = 入力境界。
        let silhouette: MetalImage
        if let brushColor = solidBrushColor(definition.brush) {
            silhouette = try renderWarp(
                input: input, mask: nil, outputBounds: input.bounds, mode: 5,
                param0: premultipliedVector(brushColor)
            )
        } else if let fill = try brushFillImage(
            brush: definition.brush, patternBounds: input.bounds,
            outputBounds: input.bounds, description: description
        ) {
            silhouette = try renderWarp(
                input: fill, mask: input, outputBounds: input.bounds, mode: 3
            )
        } else {
            return input
        }
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
        let round = evaluate(definition.round, description)
        // 塗り。本家がブラシの Update へ渡す境界は塗り矩形（正規化済み）。
        // 単色以外はブラシ塗りを角丸の被覆率で切り取る。
        let fill: MetalImage
        if let brushColor = solidBrushColor(definition.brush) {
            guard let solid = try renderRoundedRectFill(
                context: context, rect: fillRect, radius: round,
                color: brushColor, outputBounds: outputBounds
            ) else { return nil }
            fill = solid
        } else if let pattern = try brushFillImage(
            brush: definition.brush, patternBounds: fillRect,
            outputBounds: outputBounds, description: description
        ) {
            guard let coverage = try renderRoundedRectFill(
                context: context, rect: fillRect, radius: round,
                color: .white, outputBounds: outputBounds
            ) else { return nil }
            fill = try renderWarp(
                input: pattern, mask: coverage, outputBounds: outputBounds, mode: 3
            )
        } else {
            return input
        }
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
/// ブラシを入力境界で塗り、入力αでマスク（AlphaMask）し、
/// 不透明度 Opacity/100 を掛ける。IsBrushOnly でなければ入力の上へ
/// 通常合成する（混合モード通常以外は通常合成へ落とす。既存方針）。
/// 本家がブラシの Update へ渡す境界は入力境界。
public final class MetalFillForegroundProcessor: MetalEffectProcessor {
    private let definition: FillForegroundEffectDefinition

    public init(context: MetalGraphicsContext, definition: FillForegroundEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let fill: MetalImage
        if let brushColor = solidBrushColor(definition.brush) {
            guard let solid = try renderRoundedRectFill(
                context: context, rect: input.bounds, radius: 0,
                color: brushColor, outputBounds: input.bounds
            ) else { return nil }
            fill = solid
        } else if let pattern = try brushFillImage(
            brush: definition.brush, patternBounds: input.bounds,
            outputBounds: input.bounds, description: description
        ) {
            fill = pattern
        } else {
            return input
        }
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
        // 本家がブラシの Update へ渡す境界は種別ごとの帯の外接矩形
        // （全方向のときは余白＋太さで広げた矩形 = 出力境界と一致）。
        let patternBounds: RectF
        switch type {
        case .top:
            patternBounds = RectF(
                left: bounds.left - left, top: bounds.top - top - thickness,
                right: bounds.right + right, bottom: bounds.top - top
            )
        case .bottom:
            patternBounds = RectF(
                left: bounds.left - left, top: bounds.bottom + bottom,
                right: bounds.right + right, bottom: bounds.bottom + bottom + thickness
            )
        case .left:
            patternBounds = RectF(
                left: bounds.left - left - thickness, top: bounds.top - top,
                right: bounds.left - left, bottom: bounds.bottom + bottom
            )
        case .right:
            patternBounds = RectF(
                left: bounds.right + right, top: bounds.top - top,
                right: bounds.right + right + thickness, bottom: bounds.bottom + bottom
            )
        case .all, .unknown:
            patternBounds = RectF(
                left: bounds.left - left - thickness, top: bounds.top - top - thickness,
                right: bounds.right + right + thickness,
                bottom: bounds.bottom + bottom + thickness
            )
        }
        // 帯の塗り。単色以外はブラシ塗りを帯の被覆率で切り取る。
        let lineImage: MetalImage
        if let brushColor = solidBrushColor(definition.brush) {
            guard let solid = try renderSolidRects(
                rects: rects, color: brushColor, outputBounds: outputBounds
            ) else { return nil }
            lineImage = solid
        } else if let pattern = try brushFillImage(
            brush: definition.brush, patternBounds: patternBounds,
            outputBounds: outputBounds, description: description
        ) {
            guard let coverage = try renderSolidRects(
                rects: rects, color: .white, outputBounds: outputBounds
            ) else { return nil }
            lineImage = try renderWarp(
                input: pattern, mask: coverage, outputBounds: outputBounds, mode: 3
            )
        } else {
            return input
        }
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

/// グラデーションのユニフォーム（MetalGraphics の GradientUniforms と一致）。
struct GradientPassUniforms {
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var center: SIMD2<Float>
    var sinCos: SIMD2<Float>
    var halfSize: Float
    var opacity: Float
    var type: UInt32
    var extendMode: UInt32
    var stopCount: UInt32
    var pad0: Float
}

/// グラデーション。本家 `GradientEffect`（Issue #45）。
/// 入力境界と同じ寸法の画像へブラシを描く: 線形は中心 (X, Y)・回転 θ の
/// ブラシ空間で t = (−dx・sinθ + dy・cosθ) / (2h) + 0.5
/// （h = max(Size/2, 0.01)）、円形は t = 中心からの距離 / (Size/2)。
/// 凸形はストップを CPU 側で鏡像化して線形として扱う（本家どおり）。
/// ストップ間の補間は格納値のまま（D2D の GAMMA_2_2 = sRGB 空間の
/// 線形補間。本家が使う Vortice の CreateGradientStopCollection の
/// 既定で確認）。ブラシ不透明度 Opacity/100 を掛け、入力の上へ
/// SourceOver し、最後に入力 α でマスクする（本家の連鎖）。
/// 混合モードが通常以外の場合は通常合成へ落とす（MAC-0012 台帳の
/// 既存方針）。形状が unknown の場合は素通し。
public final class MetalGradientProcessor: MetalEffectProcessor {
    private let definition: GradientEffectDefinition

    public init(context: MetalGraphicsContext, definition: GradientEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let type: UInt32
        var stops = definition.stops
        switch definition.gradientType {
        case .linear:
            type = 0
        case .round:
            type = 1
        case .convex:
            // 凸形: ストップを半分へ圧縮したものと、その鏡像を連結する。
            let forward = stops.map {
                GradientStopValue(offset: $0.offset / 2, color: $0.color)
            }
            let mirrored = stops.reversed().map {
                GradientStopValue(offset: 1 - $0.offset / 2, color: $0.color)
            }
            stops = forward + mirrored
            type = 0
        case .unknown:
            return input
        }
        guard !stops.isEmpty else { return input }
        let size = evaluate(definition.size, description)
        // 円形で Size = 0 のとき本家は半径 0 のブラシになる（未計測）。
        // ゼロ除算だけを避け、見た目は最終ストップ色一色に倒す。
        let halfSize = max(size / 2, 0.01)
        let angle = evaluate(definition.rotation, description) * Double.pi / 180
        let extend: UInt32 = switch definition.extendMode {
        case .wrap: 1
        case .mirror: 2
        default: 0
        }
        var uniforms = GradientPassUniforms(
            outputOrigin: SIMD2<Float>(
                Float(input.bounds.left), Float(input.bounds.top)),
            outputSize: SIMD2<Float>(
                Float(input.bounds.right - input.bounds.left),
                Float(input.bounds.bottom - input.bounds.top)),
            center: SIMD2<Float>(
                Float(evaluate(definition.x, description)),
                Float(evaluate(definition.y, description))),
            sinCos: SIMD2<Float>(Float(sin(angle)), Float(cos(angle))),
            halfSize: Float(halfSize),
            opacity: Float(evaluate(definition.opacity, description) / 100),
            type: type,
            extendMode: extend,
            stopCount: UInt32(stops.count),
            pad0: 0
        )
        var colors: [SIMD4<Float>] = stops.map { stop in
            SIMD4<Float>(
                Float(stop.color.red) / 255, Float(stop.color.green) / 255,
                Float(stop.color.blue) / 255, Float(stop.color.alpha) / 255
            )
        }
        var offsets: [Float] = stops.map { Float($0.offset) }
        let outWidth = input.bounds.right - input.bounds.left
        let outHeight = input.bounds.bottom - input.bounds.top
        guard outWidth > 0, outHeight > 0 else { return input }
        let gradientTexture = try makeTexture(
            width: Int(ceil(outWidth)), height: Int(ceil(outHeight)),
            usage: [.renderTarget, .shaderRead]
        )
        try executeRenderPass(
            output: gradientTexture, pipeline: context.devices.gradientPipeline
        ) { encoder in
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<GradientPassUniforms>.size, index: 0
            )
            encoder.setFragmentBytes(
                &colors, length: MemoryLayout<SIMD4<Float>>.stride * colors.count, index: 1
            )
            encoder.setFragmentBytes(
                &offsets, length: MemoryLayout<Float>.stride * offsets.count, index: 2
            )
        }
        let gradient = MetalImage(texture: gradientTexture, bounds: input.bounds)
        let blended = try renderComposite(
            top: gradient, bottom: input, outputBounds: input.bounds, mode: 0
        )
        return try renderWarp(
            input: blended, mask: input, outputBounds: input.bounds, mode: 3
        )
    }
}

/// 輪郭のユニフォーム（MetalGraphics の OutlineUniforms と一致）。
struct OutlinePassUniforms {
    var inputPlane: SIMD4<Float>
    var inputOffset: SIMD2<Float>
    var outputOrigin: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var stepUV: Float
    var smoothness: Float
    var samples: UInt32
    var mode: UInt32
    var isAngular: UInt32
    var pad0: Float
}

/// 輪郭。本家 `OutlineEffect`（Issue #45）。
/// 連鎖（OutlineEffect.cs の実測）: 太さを Math.Round(x, 1)
/// （.NET 既定 = 偶数丸め）→ DecomposeThicknessToSteps（2^k ずつ
/// 切り出し降順）で OutlineLite を多段に掛け（Samples =
/// min(Quality, (int)(step×2)² + 1)、出力境界は各段 ceil(step)
/// ずつ拡大）→ FeatherAlpha（Smoothness/100）→ ブラシ単色塗りを
/// AlphaMask → ガウスぼかし σ = Blur → 不透明度 Opacity/100 →
/// 原画との合成（IsOutlineOnly または移動ありは DestinationOut の
/// リング、それ以外は原画を上へ SourceOver）→ 回転・拡縮・平行移動
/// （行ベクトル順: 回転→拡縮→移動、原点中心）→ 移動ありかつ
/// 輪郭のみでない場合は膨張境界で切り取った原画の上へ最終合成。
/// OutlineLite のサンプル距離は本家シェーダの実測どおり両軸とも
/// StepPx / 入力テクスチャ高さ。単色ブラシ以外は素通し（ブラシ
/// サブシステムが差し替え点）。移動なしの場合の恒等変換パスは
/// 省略する（等値サンプリングのため結果は同一）。
public final class MetalOutlineProcessor: MetalEffectProcessor {
    private let definition: OutlineEffectDefinition

    public init(context: MetalGraphicsContext, definition: OutlineEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    /// 本家 DecomposeThicknessToSteps の写し（float 演算の切り出し）。
    public static func decomposeThickness(_ thickness: Double) -> [Double] {
        var steps: [Double] = []
        var remaining = thickness
        var k = 0
        while true {
            let step = min(remaining, pow(2.0, Double(k)))
            if step <= 0 { break }
            steps.append(step)
            remaining -= step
            k += 1
        }
        if steps.isEmpty { steps = [0] }
        return steps.sorted(by: >)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let brushColor = solidBrushColor(definition.strokeBrush) else {
            return input
        }
        let quality = Int(evaluate(definition.quality, description))
        let thickness = (evaluate(definition.strokeThickness, description) * 10)
            .rounded(.toNearestOrEven) / 10
        var current = input
        for step in Self.decomposeThickness(thickness) {
            let samples = min(quality, Int(pow(step * 2, 2)) + 1)
            let expand = ceil(step)
            let bounds = RectF(
                left: current.bounds.left - expand, top: current.bounds.top - expand,
                right: current.bounds.right + expand, bottom: current.bounds.bottom + expand
            )
            current = try renderOutlinePass(
                input: current, outputBounds: bounds, mode: 0,
                stepUV: Float(step / Double(current.texture.height)),
                smoothness: 0, samples: max(1, samples),
                isAngular: definition.isAngular
            )
        }
        let dilatedBounds = current.bounds
        // FeatherAlpha（Smoothness は % → 0〜1）。
        let feathered = try renderOutlinePass(
            input: current, outputBounds: dilatedBounds, mode: 1,
            stepUV: 0,
            smoothness: Float(evaluate(definition.smoothness, description) / 100),
            samples: 1, isAngular: false
        )
        guard let fill = try renderRoundedRectFill(
            context: context, rect: dilatedBounds, radius: 0,
            color: brushColor, outputBounds: dilatedBounds
        ) else { return nil }
        var chain = try renderWarp(
            input: fill, mask: feathered, outputBounds: dilatedBounds, mode: 3
        )
        let blur = evaluate(definition.blur, description)
        if blur > 0 {
            chain = try renderGaussianBlurred(input: chain, sigma: blur, hardBorder: false)
        }
        let opacity = evaluate(definition.opacity, description) / 100
        if opacity != 1 {
            chain = try renderColorEffect(
                input: chain,
                uniforms: ColorEffectUniforms(
                    mode: 7,
                    param0: SIMD4<Float>(
                        Float(opacity), Float(opacity), Float(opacity), Float(opacity)),
                    param1: .zero
                )
            )
        }
        let x = evaluate(definition.x, description)
        let y = evaluate(definition.y, description)
        let zoom = evaluate(definition.zoom, description)
        let rotation = evaluate(definition.rotation, description)
        let isMoved = x != 0 || y != 0 || zoom != 100 || rotation != 0
        let unionBounds = input.bounds.union(chain.bounds)
        var combined: MetalImage
        if definition.isOutlineOnly || isMoved {
            combined = try renderComposite(
                top: input, bottom: chain, outputBounds: unionBounds, mode: 1
            )
        } else {
            combined = try renderComposite(
                top: input, bottom: chain, outputBounds: unionBounds, mode: 0
            )
        }
        if isMoved {
            let matrix = Matrix4x4.createRotationZ(rotation * Double.pi / 180)
                * Matrix4x4.createScale(x: zoom / 100, y: zoom / 100, z: 1, center: .zero)
                * Matrix4x4.createTranslation(x: x, y: y, z: 0)
            let transformedBounds = MetalDrawingEffect.boundingRect(
                of: combined.bounds, transformedBy: matrix
            )
            combined = try renderTransformed(
                input: combined, matrix: matrix, outputBounds: transformedBounds,
                interpolation: .linear
            )
        }
        if isMoved && !definition.isOutlineOnly {
            // 膨張境界で切り取った原画を下地にする（本家 Crop 相当:
            // 平面写像は原画のまま、境界だけ膨張側へ付け替えることで
            // 範囲外は borderSampler が透明として読む）。
            let cropped = MetalImage(
                texture: input.texture, bounds: dilatedBounds,
                texturePlaneRect: input.texturePlaneRect,
                planeOffset: input.planeOffset,
                interpolation: input.interpolation
            )
            return try renderComposite(
                top: combined, bottom: cropped,
                outputBounds: dilatedBounds.union(combined.bounds), mode: 0
            )
        }
        return combined
    }

    /// OutlineLite（mode 0）/ FeatherAlpha（mode 1）の1パス。
    private func renderOutlinePass(
        input: MetalImage,
        outputBounds: RectF,
        mode: UInt32,
        stepUV: Float,
        smoothness: Float,
        samples: Int,
        isAngular: Bool
    ) throws -> MetalImage {
        let outWidth = outputBounds.right - outputBounds.left
        let outHeight = outputBounds.bottom - outputBounds.top
        let outputTexture = try makeTexture(
            width: Int(ceil(outWidth)), height: Int(ceil(outHeight)),
            usage: [.renderTarget, .shaderRead]
        )
        var uniforms = OutlinePassUniforms(
            inputPlane: planeVector(input),
            inputOffset: SIMD2<Float>(
                Float(input.planeOffset.x), Float(input.planeOffset.y)),
            outputOrigin: SIMD2<Float>(
                Float(outputBounds.left), Float(outputBounds.top)),
            outputSize: SIMD2<Float>(Float(outWidth), Float(outHeight)),
            stepUV: stepUV,
            smoothness: smoothness,
            samples: UInt32(max(1, samples)),
            mode: mode,
            isAngular: isAngular ? 1 : 0,
            pad0: 0
        )
        try executeRenderPass(
            output: outputTexture, pipeline: context.devices.outlinePipeline
        ) { encoder in
            encoder.setFragmentTexture(input.texture, index: 0)
            encoder.setFragmentSamplerState(context.devices.borderSampler, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<OutlinePassUniforms>.size, index: 0
            )
        }
        return MetalImage(texture: outputTexture, bounds: outputBounds)
    }
}

#endif
