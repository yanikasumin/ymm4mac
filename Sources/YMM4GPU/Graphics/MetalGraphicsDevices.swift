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
    /// ブラシ塗りのパス（BRUSH46: グラデーション・パターン・ビットマップ）。
    let brushPipeline: MTLRenderPipelineState
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
    /// 範囲外を繰り返しとして読むサンプラ（ビットマップブラシの Wrap 用）。
    let repeatSampler: MTLSamplerState

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
              let brushFunction = library.makeFunction(name: "ymm4BrushFragment"),
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
              let brush = makeEffectPipeline(fragment: brushFunction),
              let composite = makeEffectPipeline(fragment: compositeFunction),
              let morphology = try? device.makeComputePipelineState(function: morphologyFunction)
        else { return nil }
        effectPipeline = effect
        blurPipeline = blur
        mosaicPipeline = mosaic
        warpPipeline = warp
        brushPipeline = brush
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
              let mirror = makeBorderSampler(address: .mirrorRepeat),
              let repeatWrap = makeBorderSampler(address: .repeat)
        else { return nil }
        borderSampler = border
        mirrorSampler = mirror
        repeatSampler = repeatWrap

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

        // ブラシ塗り（BRUSH46）。本家の D2D ブラシ（グラデーション・
        // パターン・ビットマップ）を平面座標で解析的に評価する。
        // 幾何の根拠は MetalBrushFill.swift のコメントに記す。
        // mode: 0=線形グラデーション, 1=放射グラデーション,
        //       2=市松, 3=ドット, 4=格子線, 5=ビットマップ
        // グラデーションの分岐点は直色（非 Premultiplied）で渡し、
        // 成分線形補間（本家の Gamma.StandardRgb = 成分線形空間での
        // 補間）の後に Premultiplied 化する。パターン色は Premultiplied
        // で渡す。
        // pointA/pointB: 線形 = 始点/終点、放射 = 中心/焦点。
        // invA/invC/invT: パターン座標への逆変換
        //   q = (invA.x・px + invC.x・py + invT.x,
        //        invA.y・px + invC.y・py + invT.y)。
        // pattern: 市松 = (セル寸法, 0, 0, 0)、ドット = (間隔, 半径, 0, 0)、
        //   格子線 = (タイル幅, タイル高さ, 線の太さ, 0)。
        struct BrushUniforms {
            float2 outputOrigin;
            float2 outputSize;
            float2 pointA;
            float2 pointB;
            float2 radii;
            float2 invA;
            float2 invC;
            float2 invT;
            float4 color1;
            float4 color2;
            float4 pattern;
            uint mode;
            uint extendMode;
            uint stopCount;
            float pad0;
        };

        float ymm4BrushExtend(float t, uint extendMode) {
            if (extendMode == 1) {
                // Wrap
                return t - floor(t);
            }
            if (extendMode == 2) {
                // Mirror（三角波）
                float m = fmod(fabs(t), 2.0);
                return m <= 1.0 ? m : 2.0 - m;
            }
            return clamp(t, 0.0, 1.0);
        }

        float4 ymm4BrushGradient(
            float t,
            constant BrushUniforms &uniforms,
            constant float4 *stopColors,
            constant float *stopOffsets
        ) {
            uint count = uniforms.stopCount;
            if (count == 0) {
                return float4(0.0);
            }
            float4 straight = stopColors[count - 1];
            if (count > 1) {
                float et = ymm4BrushExtend(t, uniforms.extendMode);
                if (et <= stopOffsets[0]) {
                    straight = stopColors[0];
                } else if (et < stopOffsets[count - 1]) {
                    for (uint i = 0; i + 1 < count; i++) {
                        if (et >= stopOffsets[i] && et <= stopOffsets[i + 1]) {
                            float span = stopOffsets[i + 1] - stopOffsets[i];
                            float f = span > 0.0 ? (et - stopOffsets[i]) / span : 0.0;
                            straight = mix(stopColors[i], stopColors[i + 1], f);
                            break;
                        }
                    }
                }
            }
            return float4(straight.rgb * straight.a, straight.a);
        }

        fragment float4 ymm4BrushFragment(
            VertexOut in [[stage_in]],
            texture2d<float> tile [[texture(0)]],
            sampler tileSampler [[sampler(0)]],
            constant BrushUniforms &uniforms [[buffer(0)]],
            constant float4 *stopColors [[buffer(1)]],
            constant float *stopOffsets [[buffer(2)]]
        ) {
            float2 point = uniforms.outputOrigin + in.uv * uniforms.outputSize;
            float2 q = float2(
                uniforms.invA.x * point.x + uniforms.invC.x * point.y + uniforms.invT.x,
                uniforms.invA.y * point.x + uniforms.invC.y * point.y + uniforms.invT.y);
            switch (uniforms.mode) {
                case 0: {
                    // 線形: t = (p − A)・(B − A) / |B − A|^2。
                    float2 axis = uniforms.pointB - uniforms.pointA;
                    float denom = dot(axis, axis);
                    if (denom <= 0.0) {
                        // 始点=終点（縮退）。本家の D2D はグラデーション
                        // 軸が潰れた場合に終端色で塗る。
                        if (uniforms.stopCount == 0) {
                            return float4(0.0);
                        }
                        float4 last = stopColors[uniforms.stopCount - 1];
                        return float4(last.rgb * last.a, last.a);
                    }
                    float t = dot(point - uniforms.pointA, axis) / denom;
                    return ymm4BrushGradient(t, uniforms, stopColors, stopOffsets);
                }
                case 1: {
                    // 放射: 楕円族 center(t) = F + t・(C − F)、
                    // radii(t) = t・(rx, ry) が q を通る t を二次方程式で解く。
                    float2 radii = uniforms.radii;
                    if (radii.x <= 0.0 || radii.y <= 0.0 || uniforms.stopCount == 0) {
                        if (uniforms.stopCount == 0) {
                            return float4(0.0);
                        }
                        float4 last = stopColors[uniforms.stopCount - 1];
                        return float4(last.rgb * last.a, last.a);
                    }
                    float2 du = q - uniforms.pointB;
                    float2 dc = uniforms.pointA - uniforms.pointB;
                    float2 r2 = radii * radii;
                    float a = (dc.x * dc.x) / r2.x + (dc.y * dc.y) / r2.y - 1.0;
                    float b = -2.0 * ((du.x * dc.x) / r2.x + (du.y * dc.y) / r2.y);
                    float c = (du.x * du.x) / r2.x + (du.y * du.y) / r2.y;
                    float t;
                    if (fabs(a) < 1e-6) {
                        t = fabs(b) > 1e-6 ? -c / b : 0.0;
                    } else {
                        float disc = max(b * b - 4.0 * a * c, 0.0);
                        float sq = sqrt(disc);
                        float t1 = (-b + sq) / (2.0 * a);
                        float t2 = (-b - sq) / (2.0 * a);
                        t = max(t1, t2);
                    }
                    return ymm4BrushGradient(t, uniforms, stopColors, stopOffsets);
                }
                case 2: {
                    // 市松: セル寸法で割った床の和のパリティ。
                    float size = max(uniforms.pattern.x, 1.0);
                    float cell = floor(q.x / size) + floor(q.y / size);
                    return (int(cell) & 1) != 0 ? uniforms.color2 : uniforms.color1;
                }
                case 3: {
                    // ドット: タイル中心からの距離で円の内外。
                    float span = max(uniforms.pattern.x, 1.0);
                    float2 local = q - span * floor(q / span);
                    float d = length(local - span * 0.5);
                    return d <= uniforms.pattern.y ? uniforms.color1 : uniforms.color2;
                }
                case 4: {
                    // 格子線: タイル境界からの最短距離が太さの半分未満。
                    float w = max(uniforms.pattern.x, 1.0);
                    float h = max(uniforms.pattern.y, 1.0);
                    float fx = q.x - w * floor(q.x / w);
                    float fy = q.y - h * floor(q.y / h);
                    float edge = min(min(fx, w - fx), min(fy, h - fy));
                    return edge < uniforms.pattern.z * 0.5
                        ? uniforms.color1 : uniforms.color2;
                }
                case 5: {
                    // ビットマップ: q はビットマップの画素座標。
                    float2 size = float2(tile.get_width(), tile.get_height());
                    if (size.x <= 0.0 || size.y <= 0.0) {
                        return float4(0.0);
                    }
                    return tile.sample(tileSampler, q / size);
                }
                default:
                    return float4(0.0);
            }
        }
        """
}

#endif
