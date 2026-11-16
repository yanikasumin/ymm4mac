#if os(macOS)
import CoreGraphics
import Foundation
import Metal
import YMM4Core

/// Metal 側の画像実体。MAC-0009 の `ImageReference`（不透明なトークン）に
/// 対する実体の組であり、デバイス単位の登録表でトークンと結び付ける。
///
/// 本家 ID2D1Image は「無限平面上の画像」であり、内容は平面座標の境界
/// （bounds）を持ち、描画時に変換（transform）が適用される。こちらも
/// 同じ3点（テクスチャ・境界・変換）を保持し、DrawingEffect 相当の変換は
/// 中間テクスチャを作らず変換の記録として合成する（遅延評価）。
/// 座標系は本家どおり、原点 = 画面中心・x 右・y 下・単位ピクセル。
public struct MetalImage {
    /// ピクセルの実体。属性は本家どおり BGRA 8bit / Premultiplied を基本とする
    /// （IMG-06: 合成コアに色管理は無い）。
    public var texture: MTLTexture
    /// transform 適用前の、平面座標における内容の境界。
    public var bounds: RectF
    /// 描画時に境界へ適用する変換（透視の M34 = -0.001 を含む 4×4）。
    public var transform: Matrix4x4
    /// 不透明度（0.0〜1.0）。Premultiplied の全成分へ乗算する（本家の
    /// ColorMatrix によるアルファ拡縮と等価）。
    public var opacity: Double
    /// 拡大縮小の補間方式。
    public var interpolation: InterpolationMode

    public init(
        texture: MTLTexture,
        bounds: RectF,
        transform: Matrix4x4 = .identity,
        opacity: Double = 1,
        interpolation: InterpolationMode = .linear
    ) {
        self.texture = texture
        self.bounds = bounds
        self.transform = transform
        self.opacity = opacity
        self.interpolation = interpolation
    }
}

/// GPU 資源の土台。本家 GraphicsDevices に対応する。
///
/// 第2章の契約どおり、デバイス（MTLDevice）はこの1インスタンス内で共有し、
/// 描画の実行文脈（MTLCommandQueue）は `makeContext()` で消費者ごとに
/// 新規生成する。所有者ごとに独立したデバイス一式が作られる点も本家と
/// 同じ（アプリ全体のシングルトンは存在しない）。
/// パイプライン・サンプラ・1×1 透明テクスチャはデバイス生成時に即時生成
/// する（本家のコンストラクタ即時生成と同じ）。
public final class MetalGraphicsDevices {
    /// 共有デバイス。
    public let device: MTLDevice

    let texturedPipeline: MTLRenderPipelineState
    let solidPipeline: MTLRenderPipelineState
    let shapePipeline: MTLRenderPipelineState
    let nearestSampler: MTLSamplerState
    let linearSampler: MTLSamplerState

    /// 1×1 完全透明のテクスチャ（読み込み失敗時の代替・空出力の実体）。
    public let transparentTexture: MTLTexture

    private var registry: [ObjectIdentifier: MetalImage] = [:]
    private let registryLock = NSLock()

    /// デバイスと共有資源を生成する。Metal が使えない環境では nil。
    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            return nil
        }
        guard let vertexFunction = library.makeFunction(name: "ymm4Vertex"),
              let texturedFunction = library.makeFunction(name: "ymm4TexturedFragment"),
              let solidFunction = library.makeFunction(name: "ymm4SolidFragment"),
              let shapeFunction = library.makeFunction(name: "ymm4ShapeFragment")
        else { return nil }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 16
        vertexDescriptor.attributes[1].bufferIndex = 0
        // QuadVertex の実ストライド（SIMD4 のアライメントで末尾に
        // パディングが入るため 24 ではなく 32）。ずらすと頂点が壊れる。
        vertexDescriptor.layouts[0].stride = MemoryLayout<QuadVertex>.stride

        func makePipeline(fragment: MTLFunction) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragment
            descriptor.vertexDescriptor = vertexDescriptor
            let attachment = descriptor.colorAttachments[0]
            attachment?.pixelFormat = .bgra8Unorm
            // Premultiplied 前提の通常合成（SourceOver）。本家 DrawImage の
            // 既定合成と同じ。
            attachment?.isBlendingEnabled = true
            attachment?.rgbBlendOperation = .add
            attachment?.alphaBlendOperation = .add
            attachment?.sourceRGBBlendFactor = .one
            attachment?.sourceAlphaBlendFactor = .one
            attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let textured = makePipeline(fragment: texturedFunction),
              let solid = makePipeline(fragment: solidFunction),
              let shape = makePipeline(fragment: shapeFunction)
        else { return nil }
        texturedPipeline = textured
        solidPipeline = solid
        shapePipeline = shape

        func makeSampler(filter: MTLSamplerMinMagFilter) -> MTLSamplerState? {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = filter
            descriptor.magFilter = filter
            descriptor.mipFilter = .notMipmapped
            descriptor.sAddressMode = .clampToEdge
            descriptor.tAddressMode = .clampToEdge
            return device.makeSamplerState(descriptor: descriptor)
        }
        guard let nearest = makeSampler(filter: .nearest),
              let linear = makeSampler(filter: .linear)
        else { return nil }
        nearestSampler = nearest
        linearSampler = linear

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let transparent = device.makeTexture(descriptor: descriptor) else { return nil }
        var zero: UInt32 = 0
        transparent.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &zero, bytesPerRow: 4
        )
        transparentTexture = transparent
    }

    /// 消費者ごとの実行文脈を新規生成する（本家 CreateContext に対応）。
    /// 文脈は自分のコマンドキューを持ち、デバイスと登録表は共有する。
    public func makeContext(
        targetSize: PixelSize = PixelSize(width: 1920, height: 1080)
    ) -> MetalGraphicsContext {
        MetalGraphicsContext(devices: self, targetSize: targetSize)
    }

    // MARK: - 画像の登録表（デバイス共有）

    /// トークンへ実体を結び付ける。既存の結び付けは差し替える。
    public func register(_ reference: ImageReference, image: MetalImage) {
        registryLock.lock()
        registry[ObjectIdentifier(reference)] = image
        registryLock.unlock()
    }

    /// トークンの実体を引く。
    public func image(for reference: ImageReference) -> MetalImage? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return registry[ObjectIdentifier(reference)]
    }

    /// トークンの結び付けを外す（実体の解放は保持者の責務）。
    public func unregister(_ reference: ImageReference) {
        registryLock.lock()
        registry.removeValue(forKey: ObjectIdentifier(reference))
        registryLock.unlock()
    }

    // MARK: - 読み戻し

    /// 参照のテクスチャを CGImage として読み戻す。変換・不透明度は適用
    /// しない（最終合成結果のように、テクスチャ自体が完成画像である参照に
    /// 対して使う。プレビュー表示用）。
    public func makeCGImage(from reference: ImageReference) -> CGImage? {
        guard let metal = image(for: reference) else { return nil }
        return Self.makeCGImage(from: metal.texture)
    }

    /// テクスチャのピクセルを読み戻す（BGRA Premultiplied のまま）。
    public static func makeCGImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            texture.getBytes(
                buffer.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0
            )
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            ),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - シェーダ

    /// 描画パイプラインのシェーダ一式。ビルド時の .metal 配置を避け、
    /// 起動時に文字列からコンパイルする。
    /// - ymm4TexturedFragment: テクスチャ付き四角形。不透明度は
    ///   Premultiplied の全成分へ乗算する。
    /// - ymm4SolidFragment: 単色の四角形（塗り）。
    /// - ymm4ShapeFragment: 角丸矩形の SDF で被覆率を出す。uv 属性の場所に
    ///   平面座標（図形中心が原点）が入る。bandWidth < 0 で全面塗り、
    ///   そうでなければ内側へ bandWidth の幅の帯だけを塗る（本家の
    ///   WidenedIntersection の可視結果に相当）。
    static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float4 position [[attribute(0)]];
            float2 uv [[attribute(1)]];
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut ymm4Vertex(VertexIn in [[stage_in]]) {
            VertexOut out;
            out.position = in.position;
            out.uv = in.uv;
            return out;
        }

        fragment float4 ymm4TexturedFragment(
            VertexOut in [[stage_in]],
            texture2d<float> texture [[texture(0)]],
            sampler textureSampler [[sampler(0)]],
            constant float &opacity [[buffer(0)]]
        ) {
            float4 color = texture.sample(textureSampler, in.uv);
            return color * opacity;
        }

        fragment float4 ymm4SolidFragment(
            VertexOut in [[stage_in]],
            constant float4 &color [[buffer(0)]]
        ) {
            return color;
        }

        struct ShapeUniforms {
            float2 halfSize;
            float radius;
            float bandWidth;
            float aaScale;
            float4 color;
        };

        fragment float4 ymm4ShapeFragment(
            VertexOut in [[stage_in]],
            constant ShapeUniforms &uniforms [[buffer(0)]]
        ) {
            float2 q = abs(in.uv) - uniforms.halfSize + uniforms.radius;
            float d = length(max(q, float2(0.0)))
                + min(max(q.x, q.y), 0.0) - uniforms.radius;
            float inner = clamp(0.5 - d / uniforms.aaScale, 0.0, 1.0);
            float alpha = inner;
            if (uniforms.bandWidth >= 0.0) {
                float outer = clamp(0.5 - (d + uniforms.bandWidth) / uniforms.aaScale, 0.0, 1.0);
                alpha = clamp(inner - outer, 0.0, 1.0);
            }
            return uniforms.color * alpha;
        }
        """
}

/// 描画頂点（クリップ空間位置＋uv）。パイプラインの頂点記述と一致させる。
struct QuadVertex {
    var position: SIMD4<Float>
    var uv: SIMD2<Float>
}

/// 消費者ごとの実行文脈。本家 GraphicsDevicesAndContext に対応する。
///
/// 自分の MTLCommandQueue を所有し、RenderTargetFactory として描画先を
/// 生成する。描画先の大きさは targetSize（画面サイズ）で固定する
/// （本家のコマンドリストは無限平面だが、ここでは画面サイズのテクスチャ
/// へ畳み込む。内部差分として台帳に記録）。
public final class MetalGraphicsContext: RenderTargetFactory {
    /// 共有デバイス側。
    public let devices: MetalGraphicsDevices
    /// この文脈専用のコマンドキュー。
    public let commandQueue: MTLCommandQueue
    /// 生成する描画先の大きさ（ピクセル）。
    public var targetSize: PixelSize

    init(devices: MetalGraphicsDevices, targetSize: PixelSize) {
        self.devices = devices
        self.targetSize = targetSize
        // デバイスが存在する以上キューの生成失敗は想定しない（本家も
        // CreateContext の失敗を契約に含めない）。
        self.commandQueue = devices.device.makeCommandQueue()!
    }

    /// 描画先を新規生成する。所有権は呼び出し側へ移る。
    public func makeTarget() -> any RenderTarget {
        MetalRenderTarget(context: self)
    }
}
#endif
