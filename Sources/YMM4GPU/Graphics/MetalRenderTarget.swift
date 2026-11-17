#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// GPU 実行層が検出した描画の失敗（MAC-0021）。RenderTarget.close() が
/// このエラーを投げることで、不完全な画像が正常な出力として公開される
/// ことを防ぐ。本家には対応する通知経路が無いため、これは Swift 側の
/// 契約追加であり、本家の失敗挙動の再現ではない。
public enum MetalRenderError: Error {
    /// 描画先テクスチャの生成に失敗した。
    case textureCreationFailed(width: Int, height: Int)
    /// コマンドバッファの実行がエラーで完了した。
    case commandBufferFailed(underlying: (any Error)?)
}

/// 描画先の Metal 実装。本家 ID2D1DeviceContext + ID2D1CommandList の組に
/// 対応する（MAC-0010 の抽象 RenderTarget の実物）。
///
/// 本家のコマンドリストは無限平面だが、こちらは文脈の targetSize
/// （画面サイズ）のテクスチャを実体とし、平面座標（原点 = 中心）を
/// そのままテクスチャへ写す。したがって画面外へはみ出す内容は、本家では
/// 最終合成まで残るのに対し、こちらでは各描画先の段階で切り取られる
/// （内部差分として台帳に記録）。
/// 記録したコマンドは close() で一括実行し、完了まで待つ（本家は遅延
/// 評価だが、この段階では同期完了として観測を単純にする。内部差分）。
/// 実行の失敗は close() が MetalRenderError を投げて通知する（MAC-0021）。
public final class MetalRenderTarget: RenderTarget {
    /// この描画先を表す画像参照（登録表へ実体を結び付け済み）。
    public let image: ImageReference

    private let context: MetalGraphicsContext
    private var texture: MTLTexture?
    /// テクスチャ生成に失敗した場合に保持する失敗。描画操作は全て無言で
    /// 落ちるため、失敗の通知は close() まで遅らせる（MAC-0021）。
    private let textureFailure: MetalRenderError?
    private var commandBuffer: MTLCommandBuffer?
    private var encoder: MTLRenderCommandEncoder?
    /// 次にエンコーダを作るとき透明でクリアするか（本家 Clear の畳み込み。
    /// 記録途中の Clear は、それまでの内容を破棄する点まで再現する）。
    private var needsClear = true
    /// 記録した内容の境界（描画した画像・矩形の外接矩形の和集合）。
    /// 本家のコマンドリストは内容の局所境界を持ち、GetImageLocalBounds が
    /// それを返す。こちらも同じ量を記録し、close() の完了時に登録済みの
    /// 実体の境界を内容境界へ差し替える（テクスチャが張る平面範囲は
    /// 画面矩形のまま。MAC-0027）。
    private var contentBounds: RectF?
    private var isClosed = false
    private var isDisposed = false

    init(context: MetalGraphicsContext) {
        self.context = context
        let width = max(1, context.targetSize.width)
        let height = max(1, context.targetSize.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        texture = context.devices.device.makeTexture(descriptor: descriptor)
        textureFailure = texture == nil
            ? .textureCreationFailed(width: width, height: height)
            : nil
        image = ImageReference(label: "render-target")
        if let texture {
            context.devices.register(
                image,
                image: MetalImage(
                    texture: texture,
                    bounds: RectF(
                        left: -Double(width) / 2, top: -Double(height) / 2,
                        right: Double(width) / 2, bottom: Double(height) / 2
                    )
                )
            )
        }
    }

    // MARK: - RenderTarget

    public func beginDraw() {
        guard !isClosed, !isDisposed, texture != nil else { return }
        if commandBuffer == nil {
            commandBuffer = context.commandQueue.makeCommandBuffer()
        }
    }

    public func clear() {
        endEncoder()
        needsClear = true
        // Clear はそれまでの内容を破棄するため、内容境界も空に戻す。
        contentBounds = nil
    }

    public func fillRect(_ rect: RectF, color: Color) {
        contentBounds = contentBounds?.union(rect) ?? rect
        guard let encoder = ensureEncoder() else { return }
        let alpha = Double(color.alpha) / 255
        var premultiplied = SIMD4<Float>(
            Float(Double(color.red) / 255 * alpha),
            Float(Double(color.green) / 255 * alpha),
            Float(Double(color.blue) / 255 * alpha),
            Float(alpha)
        )
        let vertices = quadVertices(
            corners: [
                (rect.left, rect.top), (rect.right, rect.top),
                (rect.left, rect.bottom), (rect.right, rect.bottom),
            ],
            convert: { x, y in (x: x, y: y, w: 1) }
        )
        encoder.setRenderPipelineState(context.devices.solidPipeline)
        encoder.setVertexBytes(
            vertices, length: MemoryLayout<QuadVertex>.stride * vertices.count, index: 0
        )
        encoder.setFragmentBytes(&premultiplied, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    public func drawImage(_ image: ImageReference) {
        draw(image, interpolationOverride: nil)
    }

    public func drawImage(_ image: ImageReference, blend: Blend, interpolation: InterpolationMode) {
        // Blend の特殊合成（本家の BlendImage 相当）は差し替え点とし、
        // ここでは全て通常合成（DrawImage 相当）で描く（台帳に記録）。
        draw(image, interpolationOverride: interpolation)
    }

    public func endDraw() {
        endEncoder()
    }

    public func close() throws {
        guard !isClosed else { return }
        isClosed = true
        endEncoder()
        if let textureFailure {
            commandBuffer = nil
            throw textureFailure
        }
        guard let buffer = commandBuffer else { return }
        buffer.commit()
        buffer.waitUntilCompleted()
        commandBuffer = nil
        // 完了を待っただけでは失敗は見えない。エラーで完了したコマンド
        // バッファの内容は不完全なため、正常な出力として公開しない。
        if buffer.status == .error {
            throw MetalRenderError.commandBufferFailed(underlying: buffer.error)
        }
        // 内容が記録されていたら、登録済み実体の境界を内容境界へ差し替える
        // （本家 GetImageLocalBounds の内容境界に相当。テクスチャが張る
        // 平面範囲は画面矩形のままなので、描画時の画素対応は変わらない）。
        if let contentBounds, let texture, !isDisposed {
            context.devices.register(
                image,
                image: MetalImage(
                    texture: texture,
                    bounds: contentBounds,
                    texturePlaneRect: RectF(
                        left: -Double(texture.width) / 2, top: -Double(texture.height) / 2,
                        right: Double(texture.width) / 2, bottom: Double(texture.height) / 2
                    )
                )
            )
        }
    }

    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        endEncoder()
        commandBuffer = nil
        context.devices.unregister(image)
        texture = nil
    }

    // MARK: - 内部

    private func draw(_ image: ImageReference, interpolationOverride: InterpolationMode?) {
        guard let metal = context.devices.image(for: image),
              let encoder = ensureEncoder(),
              let targetTexture = texture
        else { return }
        let bounds = metal.bounds
        let transform = metal.transform
        // 内容境界は、描画される画像の変換後の外接矩形で積み上げる
        // （本家のコマンドリストが保持する内容境界と同じ量）。
        let drawnRect = MetalDrawingEffect.boundingRect(of: bounds, transformedBy: transform)
        contentBounds = contentBounds?.union(drawnRect) ?? drawnRect
        // 頂点: 位置は境界の四隅を変換したもの、UV は変換前の平面座標を
        // テクスチャの平面範囲で写したもの（内容境界とテクスチャの範囲が
        // ずれる画像でも画素対応が保たれる）。
        let halfWidth = Double(targetTexture.width) / 2
        let halfHeight = Double(targetTexture.height) / 2
        let corners: [(Double, Double)] = [
            (bounds.left, bounds.top), (bounds.right, bounds.top),
            (bounds.left, bounds.bottom), (bounds.right, bounds.bottom),
        ]
        let vertices: [QuadVertex] = corners.map { corner in
            let v = transform.transform(x: corner.0, y: corner.1, z: 0, w: 1)
            let w = v.w == 0 ? 1 : v.w
            return QuadVertex(
                position: SIMD4<Float>(
                    Float(v.x / w / halfWidth) * Float(w),
                    Float(-(v.y / w) / halfHeight) * Float(w),
                    0, Float(w)
                ),
                uv: metal.uv(forLocalX: corner.0, y: corner.1)
            )
        }
        var opacity = Float(metal.opacity)
        encoder.setRenderPipelineState(context.devices.texturedPipeline)
        encoder.setVertexBytes(
            vertices, length: MemoryLayout<QuadVertex>.stride * vertices.count, index: 0
        )
        encoder.setFragmentTexture(metal.texture, index: 0)
        let interpolation = interpolationOverride ?? metal.interpolation
        encoder.setFragmentSamplerState(
            interpolation == .nearestNeighbor
                ? context.devices.nearestSampler : context.devices.linearSampler,
            index: 0
        )
        encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// 平面座標の四隅をクリップ空間頂点へ変換する。変換後の同次座標 w を
    /// 位置の w へ残すことで、uv の補間が透視補正される。
    private func quadVertices(
        corners: [(Double, Double)],
        convert: (Double, Double) -> (x: Double, y: Double, w: Double)
    ) -> [QuadVertex] {
        guard let texture else { return [] }
        let halfWidth = Double(texture.width) / 2
        let halfHeight = Double(texture.height) / 2
        let uvs: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1),
        ]
        return corners.enumerated().map { index, corner in
            let converted = convert(corner.0, corner.1)
            let w = Float(converted.w)
            return QuadVertex(
                position: SIMD4<Float>(
                    Float(converted.x / halfWidth) * w,
                    Float(-converted.y / halfHeight) * w,
                    0, w
                ),
                uv: uvs[index]
            )
        }
    }

    private func ensureEncoder() -> MTLRenderCommandEncoder? {
        if let encoder { return encoder }
        guard !isClosed, !isDisposed, let texture else { return nil }
        beginDraw()
        guard let commandBuffer else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        let attachment = descriptor.colorAttachments[0]
        attachment?.texture = texture
        attachment?.loadAction = needsClear ? .clear : .load
        attachment?.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        attachment?.storeAction = .store
        needsClear = false
        encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        return encoder
    }

    private func endEncoder() {
        encoder?.endEncoding()
        encoder = nil
    }
}
#endif
