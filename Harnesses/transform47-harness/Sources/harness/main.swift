import CoreGraphics
import Foundation
import Metal
import YMM4Core
import YMM4GPU

// TRANSFORM47 検証ハーネス: 変形・不透明度つき入力に対する共通規則
// （Issue #47）。
//
// 検証内容:
// 1. Source の出力が変換・不透明度を持つ（プレーンでない）場合でも、
//    後段の Metal エフェクト処理器の効果が効くこと。入力は自作 Source
//    で直接与える（現行の組み込み Source はすべてプレーンな出力しか
//    出さないため、通常のタイムライン経由ではこの入力形は作れない）。
//    旧来の基底ガードでは効果が適用されず素通しになっていたケースを、
//    期待画素で判別する。
// 2. 実体化の発動がデバイスの診断カウンタで数えられること。プレーンな
//    入力では発動しないこと。
// 3. 測定モード（--measure <ymmp パス>）: 実プロジェクトを読み込み、
//    エフェクト持ちアイテムがアクティブなフレームをサンプリングして
//    合成し、実体化の発動回数を報告する（Issue の「まず発火頻度を
//    実プロジェクトで測る」への対応）。
//
// 画面は 64×64、平面座標は中心原点・y 下向き。フレーム画素 (x, y) の
// 平面点はおよそ (−32 + x + 0.5, −32 + y + 0.5)。

var failures = 0
@MainActor
func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { failures += 1 }
}

struct Frame {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        let w = image.width
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let context = buffer.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        }!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        width = w
        height = h
        bytes = buffer
    }

    /// Premultiplied の格納値（B, G, R, A の順のバイト列から読む）。
    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i + 2]), Int(bytes[i + 1]), Int(bytes[i]), Int(bytes[i + 3]))
    }
}

@MainActor
func checkPixel(
    _ frame: Frame, _ x: Int, _ y: Int,
    r: Int, g: Int, b: Int, a: Int, tolerance: Int, _ label: String
) {
    let p = frame.pixel(x, y)
    let ok = abs(p.r - r) <= tolerance && abs(p.g - g) <= tolerance
        && abs(p.b - b) <= tolerance && abs(p.a - a) <= tolerance
    print("  \(label): got (R\(p.r),G\(p.g),B\(p.b),A\(p.a)) want (R\(r),G\(g),B\(b),A\(a)) ±\(tolerance)")
    check(ok, label)
}

// MARK: - 測定モード

/// 実プロジェクトでの実体化の発動頻度を測る。素材ファイルが手元に
/// 無い環境では Source は透明を返すが、エフェクト連鎖の構造（どの
/// 処理器へどんな形の入力が届くか）は素材の有無に依存しないため、
/// 発動回数の測定としては有効。
func measure(projectPath: String) {
    let project: Project
    do {
        let (loaded, _) = try YmmpCodec.load(fromFile: projectPath)
        project = loaded
    } catch {
        print("MEASURE: load failed: \(error)")
        exit(2)
    }
    let timeline = project.timelines[0]
    let devices = try! MetalGraphicsDevices()
    let context = devices.makeContext(
        targetSize: PixelSize(
            width: timeline.videoInfo.width, height: timeline.videoInfo.height
        )
    )
    let effectProvider = MetalEffectPairProvider(devices: devices)
    let provider = MetalSourceProvider(
        devices: devices,
        baseDirectory: URL(fileURLWithPath: projectPath).deletingLastPathComponent(),
        sceneResolver: { id in project.timelines.first { $0.id == id } },
        timeline: timeline,
        effectProvider: effectProvider
    )
    let composer = TimelineComposer(
        scene: TimelineScene(timeline: timeline),
        targetFactory: context,
        sourceProvider: provider.source(for:),
        effectProvider: effectProvider
    )
    // エフェクト持ちアイテムがアクティブなフレームを候補にし、
    // 等間隔に最大40フレームまでサンプリングする。
    var candidates = Set<Int>()
    for item in timeline.items {
        guard let videoItem = item as? any VideoItemProperties else { continue }
        let hasEffects = videoItem.videoEffects.contains { raw in
            (VideoEffectRegistry.decode(raw)?.isEnabled) ?? false
        }
        guard hasEffects, item.length > 0 else { continue }
        candidates.insert(item.frame)
        candidates.insert(item.frame + item.length / 2)
        candidates.insert(item.frame + item.length - 1)
    }
    var frames = Array(candidates.sorted())
    if frames.count > 40 {
        let step = Double(frames.count) / 40.0
        frames = (0..<40).map { frames[Int(Double($0) * step)] }
    }
    let fps = timeline.videoInfo.fps
    let before = devices.materializedInputCount
    var composed = 0
    for frame in frames {
        do {
            try composer.update(
                time: TimeSpanValue(seconds: FrameTime.time(fromFrame: frame, fps: fps)),
                usage: .paused
            )
            composed += 1
        } catch {
            print("MEASURE: composer update failed at frame \(frame): \(error)")
        }
    }
    let fired = devices.materializedInputCount - before
    print("MEASURE: project=\(projectPath)")
    print("MEASURE: items=\(timeline.items.count), sampled frames=\(composed), materialized inputs=\(fired)")
    composer.dispose()
}

// MARK: - 自作 Source（非プレーンな出力を与える）

/// 固定の MetalImage をそのまま出す Source。変換・不透明度つきの
/// 出力をエフェクト連鎖へ流すために使う。
final class FixedImageSource: Source {
    let controllers: [VideoController] = []
    private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let drawingEffect: MetalDrawingEffect
    private let reference = ImageReference(label: "transform47-fixed")

    init(devices: MetalGraphicsDevices, image: MetalImage) {
        context = devices.makeContext(targetSize: PixelSize(width: 64, height: 64))
        drawingEffect = MetalDrawingEffect(context: context)
        context.devices.register(reference, image: image)
        outputs = [
            StandardSourceOutput(
                output: reference, drawingEffect: drawingEffect, dontDispose: true
            ),
        ]
    }

    func update(_ description: TimelineItemSourceDescription) throws {
        // 固定画像のため更新内容は無い。
    }

    func dispose() {
        drawingEffect.dispose()
        context.devices.unregister(reference)
    }
}

/// BGRA テクスチャを画素関数から生成する。
func makeTexture(
    devices: MetalGraphicsDevices, width: Int, height: Int,
    pixels: (Int, Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8)
) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    descriptor.usage = [.shaderRead, .renderTarget]
    descriptor.storageMode = .shared
    let texture = devices.device.makeTexture(descriptor: descriptor)!
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let p = pixels(x, y)
            let i = (y * width + x) * 4
            bytes[i] = p.b
            bytes[i + 1] = p.g
            bytes[i + 2] = p.r
            bytes[i + 3] = p.a
        }
    }
    bytes.withUnsafeBytes { raw in
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: raw.baseAddress!, bytesPerRow: width * 4
        )
    }
    return texture
}

// MARK: - 合成ボックス

final class ChainBox {
    let devices: MetalGraphicsDevices
    let context: MetalGraphicsContext
    let composer: TimelineComposer

    init(image: MetalImage, effects: [PreservedObject]) {
        devices = try! MetalGraphicsDevices()
        context = devices.makeContext(targetSize: PixelSize(width: 64, height: 64))
        let timeline = Timeline()
        timeline.videoInfo = VideoInfo(fps: 30, hz: 44_100, width: 64, height: 64)
        let item = ImageItem()
        item.frame = 0
        item.length = 90
        item.layer = 0
        item.videoEffects = effects
        timeline.items = [item]
        let source = FixedImageSource(devices: devices, image: image)
        let effectProvider = MetalEffectPairProvider(devices: devices)
        composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: { _ in source },
            effectProvider: effectProvider
        )
    }

    func render(frame: Int = 0) -> Frame? {
        do {
            try composer.update(
                time: TimeSpanValue(seconds: FrameTime.time(fromFrame: frame, fps: 30)),
                usage: .paused
            )
        } catch {
            print("composer update error: \(error)")
            return nil
        }
        guard let output = composer.output,
              let image = devices.makeCGImage(from: output)
        else { return nil }
        return Frame(image)
    }
}

func raw(_ definition: VideoEffectDefinitionBase) -> PreservedObject {
    VideoEffectRegistry.encode(definition)
}

/// 64×64 の一様色テクスチャ（Premultiplied の格納値で指定）。
func solidImage(
    devices: MetalGraphicsDevices,
    r: UInt8, g: UInt8, b: UInt8, a: UInt8,
    transform: Matrix4x4 = .identity, opacity: Double = 1
) -> MetalImage {
    let texture = makeTexture(devices: devices, width: 64, height: 64) { _, _ in
        (b: b, g: g, r: r, a: a)
    }
    return MetalImage(
        texture: texture,
        bounds: RectF(left: -32, top: -32, right: 32, bottom: 32),
        transform: transform, opacity: opacity
    )
}

// MARK: - 実行

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--measure"), index + 1 < arguments.count {
    measure(projectPath: arguments[index + 1])
    exit(0)
}

// ケース A: 不透明度 0.5 の入力 + Invert。
// 入力の格納値は (R200, G100, B50) を不透明で持ち、不透明度 0.5 は
// 実体の opacity として付く。実体化で全成分が 0.5 倍され
// (R100, G50, B25, A128)、Invert は (A−R, A−G, A−B, A) を返すため
// 期待値は (28, 78, 103, 128)。旧ガードの素通しでは反転されず
// (100, 50, 25, 128) 相当（最終描画で不透明度が適用される）になる。
do {
    let probe = try! MetalGraphicsDevices()
    let image = solidImage(
        devices: probe, r: 200, g: 100, b: 50, a: 255, opacity: 0.5
    )
    let box = ChainBox(image: image, effects: [raw(InvertEffectDefinition())])
    let before = box.devices.materializedInputCount
    if let frame = box.render() {
        checkPixel(
            frame, 32, 32, r: 28, g: 78, b: 103, a: 128, tolerance: 4,
            "A: opacity input is materialized and inverted"
        )
    } else { check(false, "A: rendered") }
    check(
        box.devices.materializedInputCount - before == 1,
        "A: materialization counted once"
    )
    box.composer.dispose()
}

// ケース B: 回転 Z +90° の入力 + Invert。
// 左半分が赤・右半分が青。+90° 回転（y 下向きの画面では時計回り）で
// 左半分は上半分へ移る。Invert 後は上半分がシアン (0,255,255)、
// 下半分が黄 (255,255,0)。旧ガードの素通しでは配置が左右のままで
// 反転もされない。
do {
    let probe = try! MetalGraphicsDevices()
    let texture = makeTexture(devices: probe, width: 64, height: 64) { x, _ in
        x < 32 ? (b: 0, g: 0, r: 255, a: 255) : (b: 255, g: 0, r: 0, a: 255)
    }
    let image = MetalImage(
        texture: texture,
        bounds: RectF(left: -32, top: -32, right: 32, bottom: 32),
        transform: Matrix4x4.createRotationZ(.pi / 2)
    )
    let box = ChainBox(image: image, effects: [raw(InvertEffectDefinition())])
    let before = box.devices.materializedInputCount
    if let frame = box.render() {
        checkPixel(
            frame, 32, 8, r: 0, g: 255, b: 255, a: 255, tolerance: 4,
            "B: rotated input, top is inverted red (cyan)"
        )
        checkPixel(
            frame, 32, 56, r: 255, g: 255, b: 0, a: 255, tolerance: 4,
            "B: rotated input, bottom is inverted blue (yellow)"
        )
    } else { check(false, "B: rendered") }
    check(
        box.devices.materializedInputCount - before == 1,
        "B: materialization counted once"
    )
    box.composer.dispose()
}

// ケース C: 拡大 2 倍の入力 + GaussianBlur(10)。
// 左半分が黒・右半分が白。実体化で境界は (−64..64) へ広がり、
// エッジは画面中心に残る。ぼかしで中心付近が中間値になり、
// 画面端は黒・白のまま。旧ガードではぼかしが効かず中心の両側は
// 0 / 255 のままになる。
do {
    let probe = try! MetalGraphicsDevices()
    let texture = makeTexture(devices: probe, width: 64, height: 64) { x, _ in
        x < 32 ? (b: 0, g: 0, r: 0, a: 255) : (b: 255, g: 255, r: 255, a: 255)
    }
    let image = MetalImage(
        texture: texture,
        bounds: RectF(left: -32, top: -32, right: 32, bottom: 32),
        transform: Matrix4x4.createScale(x: 2, y: 2, z: 1, center: .zero)
    )
    let definition = GaussianBlurEffectDefinition()
    definition.blur.values = [AnimationValue(10)]
    let box = ChainBox(image: image, effects: [raw(definition)])
    let before = box.devices.materializedInputCount
    if let frame = box.render() {
        let nearLeft = frame.pixel(29, 32)
        let nearRight = frame.pixel(34, 32)
        print("  C: near-edge values L=\(nearLeft.r) R=\(nearRight.r)")
        check(
            nearLeft.r > 10 && nearLeft.r < 245 && nearRight.r > 10 && nearRight.r < 245,
            "C: scaled input is blurred at the edge"
        )
        checkPixel(
            frame, 2, 32, r: 0, g: 0, b: 0, a: 255, tolerance: 4,
            "C: far left stays black"
        )
        checkPixel(
            frame, 62, 32, r: 255, g: 255, b: 255, a: 255, tolerance: 4,
            "C: far right stays white"
        )
    } else { check(false, "C: rendered") }
    check(
        box.devices.materializedInputCount - before == 1,
        "C: materialization counted once"
    )
    box.composer.dispose()
}

// ケース D: 複合（回転 45° + 不透明度 0.5）+ Invert。
// 一様色のため中心の期待値はケース A と同じ (28, 78, 103, 128)。
// 変換と不透明度が両方あっても実体化は1件として数えられる。
do {
    let probe = try! MetalGraphicsDevices()
    let image = solidImage(
        devices: probe, r: 200, g: 100, b: 50, a: 255,
        transform: Matrix4x4.createRotationZ(.pi / 4), opacity: 0.5
    )
    let box = ChainBox(image: image, effects: [raw(InvertEffectDefinition())])
    let before = box.devices.materializedInputCount
    if let frame = box.render() {
        checkPixel(
            frame, 32, 32, r: 28, g: 78, b: 103, a: 128, tolerance: 4,
            "D: combined transform+opacity input is inverted"
        )
    } else { check(false, "D: rendered") }
    check(
        box.devices.materializedInputCount - before == 1,
        "D: combined input counts as one materialization"
    )
    box.composer.dispose()
}

// ケース E: プレーンな入力 + Invert（回帰）。
// 従来どおり反転が効き、実体化は発動しない。
do {
    let probe = try! MetalGraphicsDevices()
    let image = solidImage(devices: probe, r: 200, g: 100, b: 50, a: 255)
    let box = ChainBox(image: image, effects: [raw(InvertEffectDefinition())])
    let before = box.devices.materializedInputCount
    if let frame = box.render() {
        checkPixel(
            frame, 32, 32, r: 55, g: 155, b: 205, a: 255, tolerance: 4,
            "E: plain input is inverted as before"
        )
    } else { check(false, "E: rendered") }
    check(
        box.devices.materializedInputCount - before == 0,
        "E: no materialization for plain input"
    )
    box.composer.dispose()
}

// ケース F: 不透明度 0.5 の入力 + GaussianBlur(0)。
// ぼかし 0 では処理器は入力をそのまま返す。この経路でも実体化が
// 保持され、最終画素は不透明度を適用した値 (100, 50, 25, 128) に
// なる（旧ガードの素通しと同じ見た目だが、実体化済みであることが
// カウンタで区別できる）。
do {
    let probe = try! MetalGraphicsDevices()
    let image = solidImage(
        devices: probe, r: 200, g: 100, b: 50, a: 255, opacity: 0.5
    )
    let definition = GaussianBlurEffectDefinition()
    definition.blur.values = [AnimationValue(0)]
    let box = ChainBox(image: image, effects: [raw(definition)])
    let before = box.devices.materializedInputCount
    if let frame = box.render() {
        checkPixel(
            frame, 32, 32, r: 100, g: 50, b: 25, a: 128, tolerance: 4,
            "F: pass-through processor keeps materialized opacity"
        )
    } else { check(false, "F: rendered") }
    check(
        box.devices.materializedInputCount - before == 1,
        "F: materialization counted once"
    )
    box.composer.dispose()
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
