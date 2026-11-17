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
///
/// 境界とテクスチャの平面範囲は分けて持つ。本家の画像は無限平面上の
/// 存在であり、局所境界（GetImageLocalBounds）は内容のある範囲を指し、
/// テクスチャの広がりとは一致しない（コマンドリストの内容境界など）。
/// こちらでも、描画先（コマンドリスト相当）の内容境界はテクスチャが
/// 張る平面範囲（texturePlaneRect）より小さくなりうる。描画時の UV は
/// texturePlaneRect から求める。通常の画像（素材・生成テクスチャ）では
/// 両者は一致する。
public struct MetalImage {
    /// ピクセルの実体。属性は本家どおり BGRA 8bit / Premultiplied を基本とする
    /// （IMG-06: 合成コアに色管理は無い）。
    public var texture: MTLTexture
    /// transform 適用前の、平面座標における内容の境界。
    public var bounds: RectF
    /// テクスチャが張る平面範囲（UV (0,0) が左上、(1,1) が右下に対応）。
    /// 既定は bounds と同じ。
    public var texturePlaneRect: RectF
    /// ローカル座標（bounds の座標系）からテクスチャ平面座標へのずれ。
    /// 通常は (0, 0) で両者は一致する。合成グループの出力のように、
    /// 内容を平行移動してから1つの画像として扱う場合にだけ非ゼロになる
    /// （ローカル点 + planeOffset が、その画素がテクスチャ平面上で
    /// 置かれている位置）。
    public var planeOffset: Vector2
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
        texturePlaneRect: RectF? = nil,
        planeOffset: Vector2 = .zero,
        transform: Matrix4x4 = .identity,
        opacity: Double = 1,
        interpolation: InterpolationMode = .linear
    ) {
        self.texture = texture
        self.bounds = bounds
        self.texturePlaneRect = texturePlaneRect ?? bounds
        self.planeOffset = planeOffset
        self.transform = transform
        self.opacity = opacity
        self.interpolation = interpolation
    }

    /// ローカル座標の点をテクスチャ UV へ写す（planeOffset を加えてから
    /// texturePlaneRect 基準で写す）。
    public func uv(forLocalX x: Double, y: Double) -> SIMD2<Float> {
        uv(forPlaneX: x + planeOffset.x, y: y + planeOffset.y)
    }

    /// 平面座標の点をテクスチャ UV へ写す（texturePlaneRect 基準）。
    public func uv(forPlaneX x: Double, y: Double) -> SIMD2<Float> {
        let width = texturePlaneRect.right - texturePlaneRect.left
        let height = texturePlaneRect.bottom - texturePlaneRect.top
        guard width != 0, height != 0 else { return SIMD2(0, 0) }
        return SIMD2(
            Float((x - texturePlaneRect.left) / width),
            Float((y - texturePlaneRect.top) / height)
        )
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
    /// 色変換系エフェクトのパス（ブレンドなし。入力テクセルをそのまま読む）。
    let effectPipeline: MTLRenderPipelineState
    /// ガウスぼかしのパス（ブレンドなし。サンプラ経由で読む）。
    let blurPipeline: MTLRenderPipelineState
    /// モザイク（矩形）のコンピュートカーネル。
    let mosaicPipeline: MTLComputePipelineState
    /// ワープ系エフェクトのパス（MAC-0028: アルファマスク・色収差・タイリング）。
    let warpPipeline: MTLRenderPipelineState
    /// 合成系エフェクトのパス（MAC-0028: 影・塗り・枠線・複写反転）。
    let compositePipeline: MTLRenderPipelineState
    /// モルフォロジーのコンピュートカーネル（MAC-0028）。
    let morphologyPipeline: MTLComputePipelineState
    let nearestSampler: MTLSamplerState
    let linearSampler: MTLSamplerState
    /// 範囲外を透明黒として読むサンプラ（ぼかしの Soft 境界用）。
    let borderSampler: MTLSamplerState
    /// 範囲外を鏡像として読むサンプラ（ぼかしの Hard 境界用）。
    let mirrorSampler: MTLSamplerState

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
              let shapeFunction = library.makeFunction(name: "ymm4ShapeFragment"),
              let effectFunction = library.makeFunction(name: "ymm4ColorEffectFragment"),
              let blurFunction = library.makeFunction(name: "ymm4BlurFragment"),
              let mosaicFunction = library.makeFunction(name: "ymm4MosaicKernel"),
              let warpFunction = library.makeFunction(name: "ymm4WarpFragment"),
              let compositeFunction = library.makeFunction(name: "ymm4CompositeFragment"),
              let morphologyFunction = library.makeFunction(name: "ymm4MorphologyKernel")
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

        // エフェクト系のパスは中間画像への書き込みであり、合成（ブレンド）
        // は行わない。入力を加工した結果で置き換える。
        func makeEffectPipeline(fragment: MTLFunction) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragment
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let effect = makeEffectPipeline(fragment: effectFunction),
              let blur = makeEffectPipeline(fragment: blurFunction),
              let mosaic = try? device.makeComputePipelineState(function: mosaicFunction),
              let warp = makeEffectPipeline(fragment: warpFunction),
              let composite = makeEffectPipeline(fragment: compositeFunction),
              let morphology = try? device.makeComputePipelineState(function: morphologyFunction)
        else { return nil }
        effectPipeline = effect
        blurPipeline = blur
        mosaicPipeline = mosaic
        warpPipeline = warp
        compositePipeline = composite
        morphologyPipeline = morphology

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

        func makeBorderSampler(address: MTLSamplerAddressMode) -> MTLSamplerState? {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .notMipmapped
            descriptor.sAddressMode = address
            descriptor.tAddressMode = address
            if address == .clampToBorderColor {
                descriptor.borderColor = .transparentBlack
            }
            return device.makeSamplerState(descriptor: descriptor)
        }
        guard let border = makeBorderSampler(address: .clampToBorderColor),
              let mirror = makeBorderSampler(address: .mirrorRepeat)
        else { return nil }
        borderSampler = border
        mirrorSampler = mirror

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

    /// 参照のテクスチャを BGRA バイト列として読み戻す（書き出し用）。
    ///
    /// `bytes` はテクスチャ寸法 × 4 バイトちょうどでなければならず、
    /// サイズが合わない場合は何も書かずに false を返す。読み戻される
    /// 並びはテクスチャの素の画素（BGRA / Premultiplied）で、本家の
    /// 書き出しがレンダラから受け取る `byte[Width * Height * 4]` と
    /// 同じ前提に立つ。
    public func readBGRA(from reference: ImageReference, into bytes: inout [UInt8]) -> Bool {
        guard let metal = image(for: reference) else { return false }
        let texture = metal.texture
        guard texture.width > 0, texture.height > 0,
              texture.width * texture.height * 4 == bytes.count
        else { return false }
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(
                base, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return true
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

        // 色変換系エフェクトの共通フラグメント。入力テクセルを座標そのまま
        // 読み、mode ごとの数式で書き換える。いずれも本家が使う D2D 組み込み
        // エフェクト（Invert / Sepia / Tint / Exposure / GammaTransfer /
        // Posterize / LinearTransfer）と、本家カスタムシェーダの単色化に
        // 対応する。入力は Premultiplied 前提。
        // mode: 0=Invert, 1=Monocolorization, 2=Sepia, 3=Tint, 4=Exposure,
        //       5=Gamma, 6=Posterize, 7=LinearTransfer
        struct ColorEffectUniforms {
            uint mode;
            float4 param0;
            float4 param1;
        };

        fragment float4 ymm4ColorEffectFragment(
            VertexOut in [[stage_in]],
            texture2d<float> input [[texture(0)]],
            constant ColorEffectUniforms &uniforms [[buffer(0)]]
        ) {
            float4 color = input.read(uint2(in.position.xy));
            float alpha = color.a;
            switch (uniforms.mode) {
                case 0: {
                    // Invert: 直色の反転を Premultiplied で表すと a - rgb。
                    color = float4(alpha - color.rgb, alpha);
                    break;
                }
                case 1: {
                    // 単色化: 輝度で基準色を調変し、Strength で原画と混合する。
                    // param0 = 基準色 (Premultiplied), param1 = (Strength,
                    // KeepBrightness ? 1 : 0, 基準色の輝度, 0)。
                    float3 straight = alpha > 0.0 ? color.rgb / alpha : float3(0.0);
                    float gray = dot(straight, float3(0.299, 0.587, 0.114));
                    float tintAlpha = uniforms.param0.a;
                    float3 tint = tintAlpha > 0.0
                        ? uniforms.param0.rgb / tintAlpha : float3(0.0);
                    float3 tinted;
                    if (uniforms.param1.y > 0.5) {
                        float tintLuma = uniforms.param1.z;
                        tinted = tintLuma > 0.0
                            ? tint * (gray / tintLuma) : float3(0.0);
                    } else {
                        tinted = tint * gray;
                    }
                    float3 mixed = mix(straight, tinted, uniforms.param1.x);
                    color = float4(mixed * alpha, alpha);
                    break;
                }
                case 2: {
                    // Sepia: param0 = (Intensity, CrossFade の Weight, 0, 0)。
                    // D2D Sepia（セピア行列と輝度グレーの混合）の出力を
                    // Weight で原画と CrossFade する本家の構成を1パスに畳む。
                    float3 straight = alpha > 0.0 ? color.rgb / alpha : float3(0.0);
                    float gray = dot(straight, float3(0.2126, 0.7152, 0.0722));
                    float3 sepia = float3(
                        dot(straight, float3(0.393, 0.769, 0.189)),
                        dot(straight, float3(0.349, 0.686, 0.168)),
                        dot(straight, float3(0.272, 0.534, 0.131)));
                    float3 tone = mix(float3(gray), sepia, uniforms.param0.x);
                    float3 mixed = mix(straight, tone, uniforms.param0.y);
                    color = float4(mixed * alpha, alpha);
                    break;
                }
                case 3: {
                    // Tint: param0 = 色 (Premultiplied の Vector4)。成分ごとの
                    // 乗算（D2D Tint の定義どおり）。
                    color = color * uniforms.param0;
                    break;
                }
                case 4: {
                    // Exposure: param0.x = 2^EV。色成分だけを拡縮する。
                    color = float4(color.rgb * uniforms.param0.x, alpha);
                    break;
                }
                case 5: {
                    // GammaTransfer: param0 = (R, G, B, A) の指数。
                    // Premultiplied の各成分へ独立に pow を適用する。
                    color = float4(
                        pow(color.r, uniforms.param0.x),
                        pow(color.g, uniforms.param0.y),
                        pow(color.b, uniforms.param0.z),
                        pow(alpha, uniforms.param0.w));
                    break;
                }
                case 6: {
                    // Posterize: param0.xyz = (R, G, B) の階調数。
                    // 離散転送（テーブル値 i/(n-1), 添字 floor(v*n) を n-1 で
                    // クランプ）と等価な量子化。
                    float3 counts = uniforms.param0.xyz;
                    color = float4(
                        min(floor(color.r * counts.x), counts.x - 1.0) / (counts.x - 1.0),
                        min(floor(color.g * counts.y), counts.y - 1.0) / (counts.y - 1.0),
                        min(floor(color.b * counts.z), counts.z - 1.0) / (counts.z - 1.0),
                        alpha);
                    break;
                }
                case 7: {
                    // LinearTransfer: param0 = 傾き (RGBA), param1 = 切片 (RGBA)。
                    color = color * uniforms.param0 + uniforms.param1;
                    break;
                }
                default:
                    break;
            }
            return color;
        }

        // ガウスぼかしの1パス。重みは対称であるため中心と片側だけを持つ。
        // mapScale / mapOffset は入力 uv への写像（縮小・境界拡張を伴う
        // 準備パス用。通常パスでは恒等写像）。
        struct BlurUniforms {
            float2 step;
            float2 mapScale;
            float2 mapOffset;
            int radius;
        };

        fragment float4 ymm4BlurFragment(
            VertexOut in [[stage_in]],
            texture2d<float> input [[texture(0)]],
            sampler inputSampler [[sampler(0)]],
            constant BlurUniforms &uniforms [[buffer(0)]],
            constant float *weights [[buffer(1)]]
        ) {
            float2 uv = in.uv * uniforms.mapScale + uniforms.mapOffset;
            float4 acc = input.sample(inputSampler, uv) * weights[0];
            for (int i = 1; i <= uniforms.radius; i++) {
                float2 offset = uniforms.step * float(i);
                acc += (input.sample(inputSampler, uv + offset)
                      + input.sample(inputSampler, uv - offset)) * weights[i];
            }
            return acc;
        }

        // 矩形モザイク。スレッドがセル1つを担当し、セル内のテクセル平均を
        // セル全体へ書き戻す。セルの格子は入力の左上（テクセル原点）に
        // 固定する（本家カスタムシェーダの InputRect 基準に相当）。
        struct MosaicUniforms {
            float size;
            uint width;
            uint height;
        };

        // ワープ系エフェクトの共通フラグメント（MAC-0028）。出力テクスチャの
        // 平面座標から入力をサンプルし直す系を mode で切り替える。いずれも
        // 本家の D2D 効果チェーンの構成を1パスへ畳んだもので、数式の根拠は
        // 各処理器のコメントに記す。
        // mode: 0=ぼかしアルファによるマスク（縁ぼかし・角丸）, 1=色収差,
        //       2=タイリング, 3=素のアルファマスク, 4=複写反転, 5=シルエット,
        //       6=調整つきアルファマスク（EffectItem 用: マスクαの反転と
        //       不透明度係数をマスク側へ先に適用してから入力へ乗算する。
        //       本家 Primitive.Mask の ColorMatrix（反転）→ ColorMatrix
        //       （不透明度）→ AlphaMask の畳み込み）
        struct WarpUniforms {
            float4 inputPlane;
            float4 maskPlane;
            float4 param0;
            float4 param1;
            float2 inputOffset;
            float2 maskOffset;
            float2 outputOrigin;
            float2 outputSize;
            uint mode;
            float pad0;
            float pad1;
            float pad2;
        };

        float2 ymm4WarpUV(float2 plane, float4 rect, float2 offset) {
            return (plane + offset - rect.xy) / rect.zw;
        }

        fragment float4 ymm4WarpFragment(
            VertexOut in [[stage_in]],
            texture2d<float> input [[texture(0)]],
            texture2d<float> mask [[texture(1)]],
            sampler inputSampler [[sampler(0)]],
            constant WarpUniforms &uniforms [[buffer(0)]]
        ) {
            float2 point = uniforms.outputOrigin + in.uv * uniforms.outputSize;
            switch (uniforms.mode) {
                case 0: {
                    // out = 入力 × clamp(clamp(2・ぼかしα − 1) × param0.x)。
                    // 本家 Primitive.BorderBlur / RoundCorner の
                    // GaussianBlur → LinearTransfer(AlphaSlope 2, 切片 −1,
                    // Clamp) → （角丸のみ第2の LinearTransfer）→ AlphaMask。
                    float4 color = input.sample(
                        inputSampler, ymm4WarpUV(point, uniforms.inputPlane, uniforms.inputOffset));
                    float blurredAlpha = mask.sample(
                        inputSampler, ymm4WarpUV(point, uniforms.maskPlane, uniforms.maskOffset)).a;
                    float a1 = clamp(2.0 * blurredAlpha - 1.0, 0.0, 1.0);
                    float a2 = clamp(a1 * uniforms.param0.x, 0.0, 1.0);
                    return color * a2;
                }
                case 1: {
                    // 色収差: R は 1/(1+s) 拡縮点、G は同点、B は 1/(1−s)
                    // 拡縮点から取り、Composite(Plus) して [0,1] へクランプ
                    // する（本家 ChromaticAberration の ColorMatrix 分離 →
                    // AffineTransform2D → Composite Plus → Clamp の構成）。
                    float4 cr = input.sample(
                        inputSampler, ymm4WarpUV(
                            point / uniforms.param0.x, uniforms.inputPlane, uniforms.inputOffset));
                    float4 cg = input.sample(
                        inputSampler, ymm4WarpUV(point, uniforms.inputPlane, uniforms.inputOffset));
                    float4 cb = input.sample(
                        inputSampler, ymm4WarpUV(
                            point / uniforms.param0.y, uniforms.inputPlane, uniforms.inputOffset));
                    float4 sum = float4(cr.r, cg.g, cb.b, cr.a + cg.a + cb.a);
                    return clamp(sum, 0.0, 1.0);
                }
                case 2: {
                    // タイリング: param0 = 入力境界 (L, T, W, H)、
                    // param1.xy = 平行移動量。移動前の座標を入力境界で剰余し
                    // てサンプルする（本家 Tile + Crop + 平行移動の構成）。
                    float2 pre = point - uniforms.param1.xy;
                    float w = uniforms.param0.z;
                    float h = uniforms.param0.w;
                    float qx = w > 0.0
                        ? uniforms.param0.x + (fmod(fmod(pre.x - uniforms.param0.x, w) + w, w))
                        : pre.x;
                    float qy = h > 0.0
                        ? uniforms.param0.y + (fmod(fmod(pre.y - uniforms.param0.y, h) + h, h))
                        : pre.y;
                    return input.sample(
                        inputSampler, ymm4WarpUV(float2(qx, qy), uniforms.inputPlane, uniforms.inputOffset));
                }
                case 3: {
                    // 素のアルファマスク: tex0 × tex1.α（本家 AlphaMask）。
                    float4 color = input.sample(
                        inputSampler, ymm4WarpUV(point, uniforms.inputPlane, uniforms.inputOffset));
                    float maskAlpha = mask.sample(
                        inputSampler, ymm4WarpUV(point, uniforms.maskPlane, uniforms.maskOffset)).a;
                    return color * maskAlpha;
                }
                case 4: {
                    // 複写反転: param0 = (分割座標, 中心X, 中心Y, 軸 0=X/1=Y)、
                    // param1 = (複写の平行移動 dx, dy, 反転符号 sx, sy)、
                    // maskPlane.xy = (平行移動の半分 dx/2, dy/2)、
                    // maskPlane.z = 原本側 (0=以上側, 1=以下側)。
                    float2 pre = point + uniforms.maskPlane.xy;
                    float coord = uniforms.param0.w < 0.5 ? pre.x : pre.y;
                    bool isOriginal = uniforms.maskPlane.z < 0.5
                        ? coord >= uniforms.param0.x
                        : coord <= uniforms.param0.x;
                    float2 q = pre;
                    if (!isOriginal) {
                        q = float2(
                            uniforms.param0.y + (pre.x - uniforms.param1.x - uniforms.param0.y) * uniforms.param1.z,
                            uniforms.param0.z + (pre.y - uniforms.param1.y - uniforms.param0.z) * uniforms.param1.w);
                    }
                    return input.sample(
                        inputSampler, ymm4WarpUV(q, uniforms.inputPlane, uniforms.inputOffset));
                }
                case 5: {
                    // シルエット: param0 = 単色 (Premultiplied) × 入力α。
                    float4 color = input.sample(
                        inputSampler, ymm4WarpUV(point, uniforms.inputPlane, uniforms.inputOffset));
                    return uniforms.param0 * color.a;
                }
                case 6: {
                    // 調整つきアルファマスク: param0.x = 反転フラグ
                    // (0.5 超で反転), param0.y = マスク不透明度係数。
                    float4 color = input.sample(
                        inputSampler, ymm4WarpUV(point, uniforms.inputPlane, uniforms.inputOffset));
                    float maskAlpha = mask.sample(
                        inputSampler, ymm4WarpUV(point, uniforms.maskPlane, uniforms.maskOffset)).a;
                    float adjusted = (uniforms.param0.x > 0.5
                        ? 1.0 - maskAlpha : maskAlpha) * uniforms.param0.y;
                    return color * adjusted;
                }
                default:
                    return float4(0.0);
            }
        }

        // 合成系エフェクトの共通フラグメント（MAC-0028）。平面座標で2つの
        // 画像をサンプルして合成する。
        // mode: 0=SourceOver (A over B), 1=DestinationOut の結果 (B × (1 − A.α))
        struct CompositeUniforms {
            float4 planeA;
            float4 planeB;
            float2 offsetA;
            float2 offsetB;
            float2 outputOrigin;
            float2 outputSize;
            float opacityA;
            float opacityB;
            uint mode;
            float pad0;
        };

        fragment float4 ymm4CompositeFragment(
            VertexOut in [[stage_in]],
            texture2d<float> texA [[texture(0)]],
            texture2d<float> texB [[texture(1)]],
            sampler texSampler [[sampler(0)]],
            constant CompositeUniforms &uniforms [[buffer(0)]]
        ) {
            float2 point = uniforms.outputOrigin + in.uv * uniforms.outputSize;
            float4 aRaw = texA.sample(
                texSampler, (point + uniforms.offsetA - uniforms.planeA.xy) / uniforms.planeA.zw);
            float4 bRaw = texB.sample(
                texSampler, (point + uniforms.offsetB - uniforms.planeB.xy) / uniforms.planeB.zw);
            switch (uniforms.mode) {
                case 0: {
                    float4 a = aRaw * uniforms.opacityA;
                    float4 b = bRaw * uniforms.opacityB;
                    return a + b * (1.0 - a.a);
                }
                case 1: {
                    float4 b = bRaw * uniforms.opacityB;
                    return b * (1.0 - aRaw.a);
                }
                case 2: {
                    // 加重和（MAC-0036）。本家 D2D CrossFade と同じく
                    // Premultiplied 同士の重み付き加算であり、SourceOver
                    // の2回描画では半透明部が一致しないため専用モードを持つ。
                    return aRaw * uniforms.opacityA + bRaw * uniforms.opacityB;
                }
                case 3: {
                    // マスク乗算（MAC-0036）。b を a のアルファで切り取る
                    // （本家 AlphaMask の可視結果に相当）。
                    return bRaw * uniforms.opacityB * aRaw.a;
                }
                default:
                    return float4(0.0);
            }
        }

        // モルフォロジー（MAC-0028）。1軸ぶんの最大／最小フィルタ。
        // テクスチャ外のサンプルは透明として扱う（本家の無限平面モデルで
        // 入力境界の外が透明であることに対応）。mode: 0=縮小 (min),
        // 1=膨張 (max)。axis: 0=横パス, 1=縦パス。
        struct MorphologyUniforms {
            int start;
            uint count;
            uint mode;
            uint axis;
        };

        kernel void ymm4MorphologyKernel(
            texture2d<float, access::read> input [[texture(0)]],
            texture2d<float, access::write> output [[texture(1)]],
            constant MorphologyUniforms &uniforms [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
                return;
            }
            float4 acc = uniforms.mode == 1 ? float4(0.0) : float4(1.0);
            for (uint i = 0; i < uniforms.count; i++) {
                int2 coord = int2(gid) + (uniforms.axis == 0
                    ? int2(uniforms.start + int(i), 0)
                    : int2(0, uniforms.start + int(i)));
                float4 value = float4(0.0);
                if (coord.x >= 0 && coord.y >= 0
                    && coord.x < int(input.get_width())
                    && coord.y < int(input.get_height())) {
                    value = input.read(uint2(coord));
                }
                acc = uniforms.mode == 1 ? max(acc, value) : min(acc, value);
            }
            output.write(acc, gid);
        }

        kernel void ymm4MosaicKernel(
            texture2d<float, access::read> input [[texture(0)]],
            texture2d<float, access::write> output [[texture(1)]],
            constant MosaicUniforms &uniforms [[buffer(0)]],
            uint2 cell [[thread_position_in_grid]]
        ) {
            float size = max(uniforms.size, 1.0);
            int x0 = max(int(ceil(float(cell.x) * size - 0.5)), 0);
            int y0 = max(int(ceil(float(cell.y) * size - 0.5)), 0);
            int x1 = min(int(ceil(float(cell.x + 1) * size - 0.5)), int(uniforms.width));
            int y1 = min(int(ceil(float(cell.y + 1) * size - 0.5)), int(uniforms.height));
            if (x0 >= x1 || y0 >= y1) {
                return;
            }
            float4 sum = float4(0.0);
            for (int y = y0; y < y1; y++) {
                for (int x = x0; x < x1; x++) {
                    sum += input.read(uint2(uint(x), uint(y)));
                }
            }
            float4 average = sum / float((x1 - x0) * (y1 - y0));
            for (int y = y0; y < y1; y++) {
                for (int x = x0; x < x1; x++) {
                    output.write(average, uint2(uint(x), uint(y)));
                }
            }
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
