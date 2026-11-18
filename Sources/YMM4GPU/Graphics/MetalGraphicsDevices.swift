#if os(macOS)
import CoreGraphics
import Foundation
import Metal
import YMM4Core

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
    /// グラデーション生成のパス（Issue #45 第1弾）。
    let gradientPipeline: MTLRenderPipelineState
    /// 輪郭（OutlineLite／FeatherAlpha）のパス（Issue #45 第1弾）。
    let outlinePipeline: MTLRenderPipelineState
    /// ノイズ合成（NoiseBlend）のパス（Issue #45 第1弾）。
    let noiseBlendPipeline: MTLRenderPipelineState
    /// ハーフトーン（HalfTone カスタムシェーダ）のパス（Issue #45 第1弾）。
    let halftonePipeline: MTLRenderPipelineState
    /// ノイズ生成器（値ノイズ／フラクタル／カール）のパス（Issue #45 第1弾）。
    let noisePipeline: MTLRenderPipelineState
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

    /// デバイスと共有資源を生成する。
    public convenience init() throws {
        try self.init(shaderSource: Self.shaderSource)
    }

    /// シェーダソースを指定して生成する。通常は `init()` を使う。
    /// この入口は、初期化失敗の診断（Issue #50）を検証するために
    /// 壊れたシェーダを人為的に渡せるようにするための差し替え点。
    ///
    /// 失敗は握りつぶさず、`MetalInitializationError` として種別と
    /// 下位のエラー内容を保持して投げる（MAC-0021 の通知契約）。
    public init(shaderSource: String) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalInitializationError.deviceUnavailable
        }
        self.device = device

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            throw MetalInitializationError.shaderLibraryFailed(
                underlying: String(describing: error)
            )
        }
        func shaderFunction(_ name: String) throws -> MTLFunction {
            guard let function = library.makeFunction(name: name) else {
                throw MetalInitializationError.shaderFunctionMissing(name: name)
            }
            return function
        }
        let vertexFunction = try shaderFunction("ymm4Vertex")
        let texturedFunction = try shaderFunction("ymm4TexturedFragment")
        let solidFunction = try shaderFunction("ymm4SolidFragment")
        let shapeFunction = try shaderFunction("ymm4ShapeFragment")
        let effectFunction = try shaderFunction("ymm4ColorEffectFragment")
        let blurFunction = try shaderFunction("ymm4BlurFragment")
        let mosaicFunction = try shaderFunction("ymm4MosaicKernel")
        let warpFunction = try shaderFunction("ymm4WarpFragment")
        let compositeFunction = try shaderFunction("ymm4CompositeFragment")
        let morphologyFunction = try shaderFunction("ymm4MorphologyKernel")
        let gradientFunction = try shaderFunction("ymm4GradientFragment")
        let outlineFunction = try shaderFunction("ymm4OutlineFragment")
        let noiseBlendFunction = try shaderFunction("ymm4NoiseBlendFragment")
        let halftoneFunction = try shaderFunction("ymm4HalfToneFragment")
        let noiseFunction = try shaderFunction("ymm4NoiseFragment")

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

        func makePipeline(
            name: String, fragment: MTLFunction
        ) throws -> MTLRenderPipelineState {
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
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                throw MetalInitializationError.pipelineCreationFailed(
                    name: name, underlying: String(describing: error)
                )
            }
        }
        texturedPipeline = try makePipeline(name: "textured", fragment: texturedFunction)
        solidPipeline = try makePipeline(name: "solid", fragment: solidFunction)
        shapePipeline = try makePipeline(name: "shape", fragment: shapeFunction)

        // エフェクト系のパスは中間画像への書き込みであり、合成（ブレンド）
        // は行わない。入力を加工した結果で置き換える。
        func makeEffectPipeline(
            name: String, fragment: MTLFunction
        ) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragment
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                throw MetalInitializationError.pipelineCreationFailed(
                    name: name, underlying: String(describing: error)
                )
            }
        }
        func makeComputePipeline(
            name: String, function: MTLFunction
        ) throws -> MTLComputePipelineState {
            do {
                return try device.makeComputePipelineState(function: function)
            } catch {
                throw MetalInitializationError.pipelineCreationFailed(
                    name: name, underlying: String(describing: error)
                )
            }
        }
        effectPipeline = try makeEffectPipeline(name: "effect", fragment: effectFunction)
        blurPipeline = try makeEffectPipeline(name: "blur", fragment: blurFunction)
        mosaicPipeline = try makeComputePipeline(name: "mosaic", function: mosaicFunction)
        warpPipeline = try makeEffectPipeline(name: "warp", fragment: warpFunction)
        compositePipeline = try makeEffectPipeline(
            name: "composite", fragment: compositeFunction
        )
        morphologyPipeline = try makeComputePipeline(
            name: "morphology", function: morphologyFunction
        )
        gradientPipeline = try makeEffectPipeline(name: "gradient", fragment: gradientFunction)
        outlinePipeline = try makeEffectPipeline(name: "outline", fragment: outlineFunction)
        noiseBlendPipeline = try makeEffectPipeline(name: "noiseBlend", fragment: noiseBlendFunction)
        halftonePipeline = try makeEffectPipeline(name: "halftone", fragment: halftoneFunction)
        noisePipeline = try makeEffectPipeline(name: "noise", fragment: noiseFunction)

        func makeSampler(
            name: String, filter: MTLSamplerMinMagFilter
        ) throws -> MTLSamplerState {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = filter
            descriptor.magFilter = filter
            descriptor.mipFilter = .notMipmapped
            descriptor.sAddressMode = .clampToEdge
            descriptor.tAddressMode = .clampToEdge
            guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
                throw MetalInitializationError.samplerCreationFailed(name: name)
            }
            return sampler
        }
        nearestSampler = try makeSampler(name: "nearest", filter: .nearest)
        linearSampler = try makeSampler(name: "linear", filter: .linear)

        func makeBorderSampler(
            name: String, address: MTLSamplerAddressMode
        ) throws -> MTLSamplerState {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .notMipmapped
            descriptor.sAddressMode = address
            descriptor.tAddressMode = address
            if address == .clampToBorderColor {
                descriptor.borderColor = .transparentBlack
            }
            guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
                throw MetalInitializationError.samplerCreationFailed(name: name)
            }
            return sampler
        }
        borderSampler = try makeBorderSampler(name: "border", address: .clampToBorderColor)
        mirrorSampler = try makeBorderSampler(name: "mirror", address: .mirrorRepeat)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let transparent = device.makeTexture(descriptor: descriptor) else {
            throw MetalInitializationError.textureCreationFailed(width: 1, height: 1)
        }
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

        // グラデーション生成（Issue #45）。本家 Gradient のブラシ幾何:
        // 線形は回転したブラシ空間で t = (−dx・sinθ + dy・cosθ) / (2h) + 0.5
        // （h = max(サイズ/2, 0.01)、中心 = (X, Y)）、円形は
        // t = 中心からの距離 / (サイズ/2)。ストップ間は格納値のまま
        // （sRGB ガンマ空間で）線形補間し、Premultiplied 化してブラシ
        // 不透明度を掛ける。拡張モードは t へ適用する
        // （0=Clamp, 1=Wrap, 2=Mirror）。
        struct GradientUniforms {
            float2 outputOrigin;
            float2 outputSize;
            float2 center;
            float2 sinCos;
            float halfSize;
            float opacity;
            uint type;
            uint extendMode;
            uint stopCount;
            float pad0;
        };

        fragment float4 ymm4GradientFragment(
            VertexOut in [[stage_in]],
            constant GradientUniforms &uniforms [[buffer(0)]],
            constant float4 *stopColors [[buffer(1)]],
            constant float *stopOffsets [[buffer(2)]]
        ) {
            float2 point = uniforms.outputOrigin + in.uv * uniforms.outputSize;
            float2 rel = point - uniforms.center;
            float t;
            if (uniforms.type == 1) {
                t = length(rel) / uniforms.halfSize;
            } else {
                t = (-rel.x * uniforms.sinCos.x + rel.y * uniforms.sinCos.y)
                    / (2.0 * uniforms.halfSize) + 0.5;
            }
            if (uniforms.extendMode == 1) {
                t = fract(t);
            } else if (uniforms.extendMode == 2) {
                float m = fmod(t, 2.0);
                if (m < 0.0) { m += 2.0; }
                t = m <= 1.0 ? m : 2.0 - m;
            } else {
                t = clamp(t, 0.0, 1.0);
            }
            float4 color = stopColors[0];
            if (t >= stopOffsets[uniforms.stopCount - 1]) {
                color = stopColors[uniforms.stopCount - 1];
            } else if (t > stopOffsets[0]) {
                for (uint i = 0; i + 1 < uniforms.stopCount; i++) {
                    if (t <= stopOffsets[i + 1]) {
                        float span = stopOffsets[i + 1] - stopOffsets[i];
                        float f = span > 0.0 ? (t - stopOffsets[i]) / span : 0.0;
                        color = mix(stopColors[i], stopColors[i + 1], f);
                        break;
                    }
                }
            }
            float4 premultiplied = float4(color.rgb * color.a, color.a);
            return premultiplied * uniforms.opacity;
        }

        // 輪郭の2段（Issue #45）。mode 0 = OutlineLite: 中心と Samples 本の
        // 方向サンプルの α 最大値を (m, m, m, m) で出す。サンプル距離は
        // 本家シェーダの実測どおり両軸とも StepPx / 入力テクスチャ高さ
        // （TEXCOORD.w の一律適用）。角形は方向を最大成分で割って
        // 正方形リングにする。mode 1 = FeatherAlpha: s = Smoothness とし
        // lo = (1 − s) / 2、t = clamp((α − lo) / s)、f = t²(3 − 2t) を
        // 非 Premultiplied 化した色へ掛ける（s ≤ 0 では α ≥ 0.5 の段差）。
        struct OutlineUniforms {
            float4 inputPlane;
            float2 inputOffset;
            float2 outputOrigin;
            float2 outputSize;
            float stepUV;
            float smoothness;
            uint samples;
            uint mode;
            uint isAngular;
            float pad0;
        };

        fragment float4 ymm4OutlineFragment(
            VertexOut in [[stage_in]],
            texture2d<float> input [[texture(0)]],
            sampler inputSampler [[sampler(0)]],
            constant OutlineUniforms &uniforms [[buffer(0)]]
        ) {
            float2 point = uniforms.outputOrigin + in.uv * uniforms.outputSize;
            float2 uv = (point + uniforms.inputOffset - uniforms.inputPlane.xy)
                / uniforms.inputPlane.zw;
            if (uniforms.mode == 1) {
                float4 c = input.sample(inputSampler, uv);
                float a = c.a;
                float f;
                if (uniforms.smoothness <= 0.0) {
                    f = a >= 0.5 ? 1.0 : 0.0;
                } else {
                    float lo = (1.0 - uniforms.smoothness) * 0.5;
                    float t = clamp((a - lo) / uniforms.smoothness, 0.0, 1.0);
                    f = t * t * (3.0 - 2.0 * t);
                }
                if (a <= 0.0) {
                    return float4(0.0);
                }
                return float4(c.rgb / a, 1.0) * f;
            }
            float m = input.sample(inputSampler, uv).a;
            uint count = max(uniforms.samples, 1u);
            for (uint i = 0; i < count; i++) {
                float theta = 6.283185307179586 * float(i) / float(count);
                float2 dir = float2(sin(theta), cos(theta));
                if (uniforms.isAngular != 0) {
                    float mc = max(abs(dir.x), abs(dir.y));
                    if (mc > 0.0) { dir /= mc; }
                }
                float sampled = input.sample(
                    inputSampler, uv + dir * uniforms.stepUV).a;
                m = max(m, sampled);
            }
            return float4(m);
        }

        // ノイズ合成（Issue #45）。本家 NoiseBlend の実測式:
        // out = A.r × (入力.r × R.r, 入力.g × G.r, 入力.b × B.r, 入力.α)。
        // 各ノイズテクスチャは赤成分だけを使い、それぞれ自分の平面
        // 写像でサンプルする。
        struct NoiseBlendUniforms {
            float4 planeIn;
            float4 planeA;
            float4 planeR;
            float4 planeG;
            float4 planeB;
            float2 offsetIn;
            float2 offsetA;
            float2 offsetR;
            float2 offsetG;
            float2 offsetB;
            float2 outputOrigin;
            float2 outputSize;
        };

        fragment float4 ymm4NoiseBlendFragment(
            VertexOut in [[stage_in]],
            texture2d<float> texIn [[texture(0)]],
            texture2d<float> texA [[texture(1)]],
            texture2d<float> texR [[texture(2)]],
            texture2d<float> texG [[texture(3)]],
            texture2d<float> texB [[texture(4)]],
            sampler texSampler [[sampler(0)]],
            constant NoiseBlendUniforms &uniforms [[buffer(0)]]
        ) {
            float2 point = uniforms.outputOrigin + in.uv * uniforms.outputSize;
            float4 src = texIn.sample(
                texSampler, (point + uniforms.offsetIn - uniforms.planeIn.xy)
                    / uniforms.planeIn.zw);
            float a = texA.sample(
                texSampler, (point + uniforms.offsetA - uniforms.planeA.xy)
                    / uniforms.planeA.zw).r;
            float r = texR.sample(
                texSampler, (point + uniforms.offsetR - uniforms.planeR.xy)
                    / uniforms.planeR.zw).r;
            float g = texG.sample(
                texSampler, (point + uniforms.offsetG - uniforms.planeG.xy)
                    / uniforms.planeG.zw).r;
            float b = texB.sample(
                texSampler, (point + uniforms.offsetB - uniforms.planeB.xy)
                    / uniforms.planeB.zw).r;
            return a * float4(src.r * r, src.g * g, src.b * b, src.a);
        }

        // ハーフトーン（Issue #45）。本家 HalfTone カスタムシェーダの
        // 数学: 格子候補の中心ごとに、その中心で入力をサンプルした
        // 輝度 lum から cov = clamp(K・lum・Size − 中心までの距離) を
        // 求め、最大の候補が勝つ。出力 = cov × (勝者のサンプル色 ×
        // (1 − Strength) + Color × Strength)。
        // K はモード係数（Triangle: 1 + Distance/√3、Rectangle /
        // Rhombus: 1 + Distance/√2）。候補集合は逆アセンブルから
        // 読み取った格子オフセットそのまま:
        // Rectangle = セル中心の 3×3 近傍、Rhombus = √2・Distance
        // 四方のセル四隅＋中心、Triangle = パリティ調整した基点 B へ
        // {(±0.5, 0.866), (±1, 0), (0.5, 0.433), (0, −0.433),
        // (1, −0.433)}・Distance を加えた7点。
        // モード 1 以外の未知値は本家どおり Rhombus の分岐へ落ちる。
        struct HalfToneUniforms {
            float4 inputPlane;
            float4 color;
            float2 inputOffset;
            float2 outputOrigin;
            float2 outputSize;
            float2 texelSize;
            float distance;
            float size;
            float strength;
            int mode;
        };

        float ymm4HalfToneAdjustedIndex(float f) {
            float f1 = fract(abs(f));
            float f2 = f >= 0.0 ? f1 : (f1 == 0.0 ? 0.0 : 1.0 - f1);
            return floor(f) + (f2 < 0.5 ? -0.5 : 0.5);
        }

        fragment float4 ymm4HalfToneFragment(
            VertexOut in [[stage_in]],
            texture2d<float> input [[texture(0)]],
            sampler inputSampler [[sampler(0)]],
            constant HalfToneUniforms &uniforms [[buffer(0)]]
        ) {
            float2 point = uniforms.outputOrigin + in.uv * uniforms.outputSize;
            float2 uv = (point + uniforms.inputOffset - uniforms.inputPlane.xy)
                / uniforms.inputPlane.zw;
            float d = uniforms.distance;
            float k;
            float2 centers[9];
            int count;
            if (uniforms.mode == 1) {
                k = 1.0 + d * 0.70710678;
                float2 c = (floor(point / d) + 0.5) * d;
                count = 0;
                for (int j = -1; j <= 1; j++) {
                    for (int i = -1; i <= 1; i++) {
                        centers[count++] = c + float2(float(i), float(j)) * d;
                    }
                }
            } else if (uniforms.mode == 0) {
                k = 1.0 + d * 0.57735027;
                float fx = point.x / d;
                float fy = point.y / (d * 0.8660254);
                float iy = floor(fy);
                bool odd = fract(abs(iy) * 0.5) != 0.0;
                float cx = odd ? ymm4HalfToneAdjustedIndex(fx) : floor(fx);
                float2 b = float2(cx * d, iy * d * 0.8660254);
                centers[0] = b + d * float2(0.5, 0.8660254);
                centers[1] = b + d * float2(-0.5, 0.8660254);
                centers[2] = b + d * float2(1.0, 0.0);
                centers[3] = b + d * float2(0.5, 0.4330127);
                centers[4] = b + d * float2(-1.0, 0.0);
                centers[5] = b + d * float2(0.0, -0.4330127);
                centers[6] = b + d * float2(1.0, -0.4330127);
                count = 7;
            } else {
                k = 1.0 + d * 0.70710678;
                float dx = d * 1.4142135;
                float dy = d * 0.70710678;
                float fx = point.x / dx;
                float fy = point.y / dy;
                float iy = floor(fy);
                bool odd = fract(abs(iy) * 0.5) != 0.0;
                float cx = odd ? ymm4HalfToneAdjustedIndex(fx) : floor(fx);
                float2 p = float2(cx * dx, iy * dy);
                centers[0] = p;
                centers[1] = p + float2(dx, 0.0);
                centers[2] = p + float2(0.0, dx);
                centers[3] = p + float2(dx, dx);
                centers[4] = p + float2(dy, dy);
                count = 5;
            }
            float gate = k * uniforms.size;
            float bestCov = 0.0;
            float4 bestColor = float4(0.0);
            for (int i = 0; i < count; i++) {
                float2 delta = centers[i] - point;
                float dist = length(delta);
                float cov = 0.0;
                float4 s = float4(0.0);
                if (gate >= dist) {
                    s = input.sample(inputSampler, uv + delta * uniforms.texelSize);
                    float lum = dot(s.rgb, float3(0.299, 0.587, 0.114))
                        * (s.a != 0.0 ? 1.0 : 0.0);
                    cov = clamp(k * lum * uniforms.size - dist, 0.0, 1.0);
                }
                if (i == 0 || cov > bestCov) {
                    bestCov = cov;
                    bestColor = s;
                }
            }
            return bestCov * (bestColor * (1.0 - uniforms.strength)
                + uniforms.color * uniforms.strength);
        }

        // ノイズ生成器（Issue #45）。本家 NoiseBase の定数ブロック
        // （96 バイト）と生成シェーダの逆アセンブルからの抽出。
        // 値ノイズの格子ハッシュは整数演算そのまま:
        // h = (cell + seed + corner) × C（C は成分ごとの定数）、
        // h ^= h.wxyz ^ (h >> 13)、s = Σ h_i・C_i、s ^= s >> 11、
        // s ^= s・s、値 = s / 2^32。負の格子座標は +999999 で
        // 持ち上げる（本家シェーダの実測）。
        struct NoiseUniforms {
            float x;
            float y;
            float z;
            float threshold;
            float scaleX;
            float scaleY;
            float scaleZ;
            float strength;
            int octaves;
            int seed;
            int levels;
            float angle;
            float warpStrength;
            float warpScale;
            int fractalMode;
            int distanceMode;
            int cellOutput;
            float lacunarity;
            float gain;
            float pad2;
            float stripeInterval;
            float stripeWarpAmount;
            float flowAmount;
            float pad3;
            float2 outputOrigin;
            float2 outputSize;
            int noiseType;
            float padA;
            float padB;
            float padC;
        };

        float ymm4NoiseHash(uint3 cell) {
            uint4 h = uint4(cell, 0u);
            h *= uint4(0xAE3CC725u, 0x9FE72885u, 0xAE36BFB5u, 0x82C1FCADu);
            h ^= h.wxyz ^ (h >> 13u);
            uint s = h.x * 0xAE3CC725u + h.y * 0x9FE72885u
                + h.z * 0xAE36BFB5u + h.w * 0x82C1FCADu;
            s ^= s >> 11u;
            s ^= s * s;
            return float(s) * 2.3283064365386963e-10;
        }

        float ymm4ValueNoise(float3 p, int seed) {
            float3 cell = floor(p);
            float3 f = p - cell;
            float3 w = f * f * (3.0 - 2.0 * f);
            float values[8];
            for (int i = 0; i < 8; i++) {
                float3 corner = float3(
                    float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1));
                float3 h = cell + float(seed) + corner;
                if (h.x < 0.0) { h.x += 999999.0; }
                if (h.y < 0.0) { h.y += 999999.0; }
                if (h.z < 0.0) { h.z += 999999.0; }
                values[i] = ymm4NoiseHash(uint3(h));
            }
            float x00 = mix(values[0], values[1], w.x);
            float x10 = mix(values[2], values[3], w.x);
            float x01 = mix(values[4], values[5], w.x);
            float x11 = mix(values[6], values[7], w.x);
            return mix(mix(x00, x10, w.y), mix(x01, x11, w.y), w.z);
        }

        // シンプレックスノイズ（ワープと Curl 用）。本家変種の定数:
        // permute は ((x・34) + 10)・x mod 289、勾配は
        // (成分 × 2/7 − 13/14)、減衰は (0.5 − |x|²)⁴、
        // 出力は Σ × 52.5 + 0.5 で [0, 1] 帯へ写す。
        float3 ymm4Mod2893(float3 x) {
            return x - floor(x * (1.0 / 289.0)) * 289.0;
        }

        float4 ymm4Mod2894(float4 x) {
            return x - floor(x * (1.0 / 289.0)) * 289.0;
        }

        float4 ymm4NoisePermute(float4 x) {
            return ymm4Mod2894(((x * 34.0) + 10.0) * x);
        }

        float ymm4Snoise01(float3 v) {
            const float2 c = float2(1.0 / 6.0, 1.0 / 3.0);
            float3 i = floor(v + dot(v, c.yyy));
            float3 x0 = v - i + dot(i, c.xxx);
            float3 g = step(x0.yzx, x0.xyz);
            float3 l = 1.0 - g;
            float3 i1 = min(g.xyz, l.zxy);
            float3 i2 = max(g.xyz, l.zxy);
            float3 x1 = x0 - i1 + c.xxx;
            float3 x2 = x0 - i2 + c.yyy;
            float3 x3 = x0 - 0.5;
            i = ymm4Mod2893(i);
            float4 p = ymm4NoisePermute(ymm4NoisePermute(ymm4NoisePermute(
                float4(0.0, i1.z, i2.z, 1.0) + i.z)
                + float4(0.0, i1.y, i2.y, 1.0) + i.y)
                + float4(0.0, i1.x, i2.x, 1.0) + i.x);
            float4 j = p - 49.0 * floor(p * (1.0 / 49.0));
            float4 gx = floor(j * (1.0 / 7.0)) * (2.0 / 7.0) - 13.0 / 14.0;
            float4 gy = floor(j - 7.0 * floor(j * (1.0 / 7.0)))
                * (2.0 / 7.0) - 13.0 / 14.0;
            float4 gz = 1.0 - abs(gx) - abs(gy);
            float4 fold = floor(gx) * 2.0 + 1.0;
            float4 foldY = floor(gy) * 2.0 + 1.0;
            gx = select(gx, gx - fold, gz <= 0.0);
            gy = select(gy, gy - foldY, gz <= 0.0);
            float3 g0 = float3(gx.x, gy.x, gz.x);
            float3 g1 = float3(gx.y, gy.y, gz.y);
            float3 g2 = float3(gx.z, gy.z, gz.z);
            float3 g3 = float3(gx.w, gy.w, gz.w);
            float4 norm = 1.7928428649902344 - 0.8537347316741943 * float4(
                dot(g0, g0), dot(g1, g1), dot(g2, g2), dot(g3, g3));
            g0 *= norm.x;
            g1 *= norm.y;
            g2 *= norm.z;
            g3 *= norm.w;
            float4 m = max(0.5 - float4(
                dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
            m *= m;
            m *= m;
            float4 dots = float4(
                dot(g0, x0), dot(g1, x1), dot(g2, x2), dot(g3, x3));
            return dot(m, dots) * 52.5 + 0.5;
        }

        // 後処理連鎖（全生成器共通、本家シェーダ尾部の実測）:
        // Threshold で引き伸ばし、Strength で白への寄せ／反転側の
        // 伸長、Levels で量子化（255 のときだけ素通し）。
        float ymm4NoisePost(float v, constant NoiseUniforms &uniforms) {
            v = (v - uniforms.threshold) / max(1.0 - uniforms.threshold, 1e-6);
            float s = uniforms.strength;
            v = s < 1.0 ? (1.0 - s) + s * v : (2.0 - s) * v;
            if (uniforms.levels != 255) {
                float lv = float(uniforms.levels - 1);
                v = rint(v * lv) / lv;
            }
            return clamp(v, 0.0, 1.0);
        }

        // FractalMode の整形（0 = そのまま、1 = |2v − 1|、
        // それ以外 = (1 − |2v − 1|)²）。
        float ymm4FractalShape(float v, int mode) {
            if (mode == 0) { return v; }
            float n = abs(clamp(v, 0.0, 1.0) * 2.0 - 1.0);
            if (mode == 1) { return n; }
            float r = 1.0 - n;
            return r * r;
        }

        fragment float4 ymm4NoiseFragment(
            VertexOut in [[stage_in]],
            constant NoiseUniforms &uniforms [[buffer(0)]]
        ) {
            float2 point = uniforms.outputOrigin + in.uv * uniforms.outputSize;
            float3 p = float3(point, 0.0)
                - float3(uniforms.x, uniforms.y, uniforms.z);
            if (uniforms.warpStrength != 0.0) {
                float seedF = float(uniforms.seed);
                float3 seedVec = fract(seedF
                    * float3(0.09730000048875809, 0.10300000011920929,
                             0.1031000018119812));
                seedVec += dot(seedVec.zyx, seedVec.yxz + 33.33);
                float3 pairSums = float3(
                    seedVec.y + seedVec.z, seedVec.x + seedVec.z,
                    seedVec.x + seedVec.y);
                float3 hash3 = fract(seedVec * pairSums);
                float3 q = p * uniforms.warpScale * 0.015625 + hash3 * 289.0;
                float2 w = float2(
                    ymm4Snoise01(q),
                    ymm4Snoise01(q + float3(47.2, 31.6, 11.9)));
                p.xy += uniforms.warpStrength * (w * 2.0 - 1.0);
            }
            p *= float3(uniforms.scaleX, uniforms.scaleY, uniforms.scaleZ);
            float cs = cos(uniforms.angle);
            float sn = sin(uniforms.angle);
            p = float3(
                p.x * cs - p.y * sn, p.x * sn + p.y * cs, p.z);
            float v;
            if (uniforms.noiseType == 1) {
                v = clamp(ymm4ValueNoise(p, uniforms.seed), 0.0, 1.0);
            } else if (uniforms.noiseType == 2) {
                // Curl: オクターブごとに ±0.1 ずらした2点の
                // シンプレックス値の差を 0.78125 倍して中央へ寄せ、
                // Fractal と同じ整形・蓄積を行う（評価点の組は
                // 逆アセンブルからの近似。実装記録に明記）。
                float sum = 0.0;
                float ampSum = 0.0;
                float freq = 1.0;
                float amp = 1.0;
                for (int octave = 0; octave < uniforms.octaves; octave++) {
                    float3 q = p * freq;
                    float diff = ymm4Snoise01(q + float3(0.0, 0.1, 0.0))
                        - ymm4Snoise01(q - float3(0.0, 0.1, 0.0));
                    float shaped = ymm4FractalShape(
                        clamp(diff * 0.78125 + 0.5, 0.0, 1.0),
                        uniforms.fractalMode);
                    sum += shaped * amp;
                    ampSum += amp;
                    freq *= uniforms.lacunarity;
                    amp *= uniforms.gain;
                }
                v = ampSum > 0.0 ? sum / ampSum : 0.0;
            } else {
                float sum = 0.0;
                float ampSum = 0.0;
                float freq = 1.0;
                float amp = 1.0;
                for (int octave = 0; octave < uniforms.octaves; octave++) {
                    float n = ymm4ValueNoise(p * freq, uniforms.seed);
                    sum += ymm4FractalShape(n, uniforms.fractalMode) * amp;
                    ampSum += amp;
                    freq *= uniforms.lacunarity;
                    amp *= uniforms.gain;
                }
                v = ampSum > 0.0 ? clamp(sum / ampSum, 0.0, 1.0) : 0.0;
            }
            float result = ymm4NoisePost(v, uniforms);
            return float4(result, result, result, 1.0);
        }
        """
}

#endif
