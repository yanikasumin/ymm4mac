import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core
import YMM4GPU

// MAC-0034 検証ハーネス: AUD-01（EffectItem 描画 = 本家 EffectSource）と
// AUD-03（クリッピングの実効マスク = AlphaMaskEffectFactory の本番実装）。
// PreviewBox と同じ合成経路（TimelineComposer + MetalSourceProvider +
// MetalEffectPairProvider + MetalAlphaMaskEffectFactory）で人工的な最小
// プロジェクトを合成し、読み戻した画素で数値検証する。
// 画面は 64×64、平面座標は中心原点・y 下向き。フレーム画素 (x, y) の
// 平面点はおよそ (−32 + x + 0.5, −32 + y + 0.5)。

var failures = 0
@MainActor
func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { failures += 1 }
}

@MainActor
func checkPixel(
    _ frame: Frame, _ x: Int, _ y: Int,
    r: Int, g: Int, b: Int, tolerance: Int, _ label: String
) {
    let p = frame.pixel(x, y)
    let ok = abs(p.r - r) <= tolerance && abs(p.g - g) <= tolerance
        && abs(p.b - b) <= tolerance
    print("  \(label): got (R\(p.r),G\(p.g),B\(p.b),A\(p.a)) want (\(r),\(g),\(b)) ±\(tolerance)")
    check(ok, label)
}

@MainActor
func checkAlpha(_ frame: Frame, _ x: Int, _ y: Int, range: ClosedRange<Int>, _ label: String) {
    let p = frame.pixel(x, y)
    print("  \(label): got A\(p.a) want \(range)")
    check(range.contains(p.a), label)
}

// MARK: - 入力画像の生成

let workDir = URL(fileURLWithPath: "/tmp/mac0034")
try! FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

@MainActor
func writePNG(
    name: String, width: Int, height: Int,
    pixels: (Int, Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8)
) {
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
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(
        width: width, height: height,
        bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ),
        provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent
    )!
    let url = workDir.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        check(false, "write PNG \(name)")
    }
}

// 全面の赤 (R255, G0, B0)
writePNG(name: "red.png", width: 64, height: 64) { _, _ in (0, 0, 255, 255) }

// MARK: - 合成と読み戻し

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

    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i + 2]), Int(bytes[i + 1]), Int(bytes[i]), Int(bytes[i + 3]))
    }

    var nonTransparent: Int {
        var count = 0
        for i in 0..<(width * height) where bytes[i * 4 + 3] > 10 {
            count += 1
        }
        return count
    }

    /// 指定色に近い画素数（被覆の数値確認用）。
    func countColor(r: Int, g: Int, b: Int, tolerance: Int) -> Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(x, y)
                if abs(p.r - r) <= tolerance && abs(p.g - g) <= tolerance
                    && abs(p.b - b) <= tolerance && p.a > 250 {
                    count += 1
                }
            }
        }
        return count
    }
}

/// PreviewBox（MAC-0034 配線: factory 注入を含む）と同じ構成の合成器。
final class ComposerBox {
    let devices: MetalGraphicsDevices
    let context: MetalGraphicsContext
    let provider: MetalSourceProvider
    let composer: TimelineComposer

    init(timeline: Timeline, timelines: [Timeline]? = nil) {
        devices = try! MetalGraphicsDevices()
        context = devices.makeContext(
            targetSize: PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
        )
        let allTimelines = timelines ?? [timeline]
        let effectProvider = MetalEffectPairProvider(devices: devices)
        provider = MetalSourceProvider(
            devices: devices, baseDirectory: workDir,
            sceneResolver: { id in allTimelines.first { $0.id == id } },
            timeline: timeline,
            effectProvider: effectProvider
        )
        composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider.source(for:),
            effectProvider: effectProvider,
            alphaMaskFactory: MetalAlphaMaskEffectFactory(context: context)
        )
    }

    func render(frame: Int, fps: Int = 30) -> Frame? {
        do {
            try composer.update(
                time: TimeSpanValue(seconds: FrameTime.time(fromFrame: frame, fps: fps)),
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

// MARK: - プロジェクト部品

func makeTimeline() -> Timeline {
    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: 30, hz: 44_100, width: 64, height: 64)
    return timeline
}

func raw(_ definition: VideoEffectDefinitionBase) -> PreservedObject {
    VideoEffectRegistry.encode(definition)
}

/// 幅×高さの矩形パラメータ（枠線 4000 = 全面塗り、単色ブラシ白が既定）。
func rectParameter(width: Double, height: Double) -> ShapeParameter {
    let parameter = RectangleShapeParameter()
    parameter.sizeMode = .widthHeight
    parameter.width = Animation(defaultValue: width, minValue: 0, maxValue: 100_000)
    parameter.height = Animation(defaultValue: height, minValue: 0, maxValue: 100_000)
    return .rectangle(parameter)
}

func makeImage(layer: Int, clipping: Bool = false) -> ImageItem {
    let item = ImageItem()
    item.filePath = "red.png"
    item.frame = 0
    item.length = 90
    item.layer = layer
    item.isClippingWithObjectAbove = clipping
    return item
}

func makeShape(layer: Int, width: Double, height: Double) -> ShapeItem {
    let item = ShapeItem()
    item.frame = 0
    item.length = 90
    item.layer = layer
    item.shapeParameter = rectParameter(width: width, height: height)
    return item
}

/// 右半分（平面 x ∈ [0, 32]）を覆うマスクを持つ EffectItem。
func makeEffect(layer: Int, invertMask: Bool = false) -> EffectItem {
    let item = EffectItem()
    item.frame = 0
    item.length = 90
    item.layer = layer
    item.x = Animation(defaultValue: 16, minValue: -100_000, maxValue: 100_000)
    item.shapeParameter = rectParameter(width: 32, height: 64)
    item.invertMask = invertMask
    item.videoEffects = [raw(InvertEffectDefinition())]
    return item
}

// MARK: - A0: EffectItem 単体（B-1: Flood は不透明な黒・境界は画面サイズ）

do {
    let timeline = makeTimeline()
    timeline.items = [makeEffect(layer: 0)]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        // 蓄積は透明だが、EffectSource の中では不透明な黒 Flood の上に
        // 合成されるため、Invert を通すと全面が白になる。マスク内
        // （右半分）だけがその白で上書きされ、マスク外は引き継ぎの
        // 透明のまま。右半分が白く不透明であることが、Flood が透明で
        // なく不透明な黒であることの検証になる（透明なら Invert 後も
        // 透明になる）。
        checkPixel(frame, 56, 32, r: 255, g: 255, b: 255, tolerance: 4, "A0 right inverted to white")
        checkAlpha(frame, 56, 32, range: 250...255, "A0 right opaque (flood is opaque black)")
        checkAlpha(frame, 8, 32, range: 0...10, "A0 left masked out to transparent")
        check(abs(frame.nonTransparent - 2048) <= 40, "A0 coverage ~2048 (right half), got \(frame.nonTransparent)")
    } else {
        check(false, "A0 rendered")
    }
    box.composer.dispose()
}

// MARK: - A1: EffectItem のマスク（右半分だけ Invert が効く）

do {
    let timeline = makeTimeline()
    timeline.items = [makeImage(layer: 0), makeEffect(layer: 1)]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        checkPixel(frame, 8, 32, r: 255, g: 0, b: 0, tolerance: 4, "A1 left red unchanged")
        checkPixel(frame, 56, 32, r: 0, g: 255, b: 255, tolerance: 4, "A1 right inverted cyan")
        check(frame.nonTransparent == 4096, "A1 full coverage, got \(frame.nonTransparent)")
    } else {
        check(false, "A1 rendered")
    }
    box.composer.dispose()
}

// MARK: - A2: InvertMask（マスク反転で左半分だけ Invert が効く）

do {
    let timeline = makeTimeline()
    timeline.items = [makeImage(layer: 0), makeEffect(layer: 1, invertMask: true)]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        checkPixel(frame, 8, 32, r: 0, g: 255, b: 255, tolerance: 4, "A2 left inverted cyan")
        checkPixel(frame, 56, 32, r: 255, g: 0, b: 0, tolerance: 4, "A2 right red unchanged")
    } else {
        check(false, "A2 rendered")
    }
    box.composer.dispose()
}

// MARK: - A3: マスク不透明度（Opacity 50% が1回だけ効く）

do {
    let timeline = makeTimeline()
    let effect = makeEffect(layer: 1)
    effect.opacity = Animation(defaultValue: 50, minValue: 0, maxValue: 100)
    timeline.items = [makeImage(layer: 0), effect]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        // シアン (α0.5) over 赤 = (128,128,128)。二重適用なら G≈64。
        checkPixel(frame, 56, 32, r: 128, g: 128, b: 128, tolerance: 8, "A3 right half-blended gray")
        checkPixel(frame, 8, 32, r: 255, g: 0, b: 0, tolerance: 4, "A3 left red unchanged")
    } else {
        check(false, "A3 rendered")
    }
    box.composer.dispose()
}

// MARK: - B1: クリッピング（直下の図形の形状で切り抜かれる）

do {
    let timeline = makeTimeline()
    timeline.items = [
        makeShape(layer: 0, width: 32, height: 32),
        makeImage(layer: 1, clipping: true),
    ]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        checkPixel(frame, 32, 32, r: 255, g: 0, b: 0, tolerance: 4, "B1 center red inside mask")
        checkAlpha(frame, 2, 2, range: 0...10, "B1 corner clipped away")
        checkAlpha(frame, 8, 32, range: 0...10, "B1 left outside mask clipped")
        checkAlpha(frame, 32, 8, range: 0...10, "B1 top outside mask clipped")
        let red = frame.countColor(r: 255, g: 0, b: 0, tolerance: 10)
        check(abs(red - 1024) <= 80, "B1 red coverage ~1024 (32x32), got \(red)")
    } else {
        check(false, "B1 rendered")
    }
    box.composer.dispose()
}

// MARK: - B2: クリッピング・先行画像なし（白 Flood で全面表示、B-2(i)）

do {
    let timeline = makeTimeline()
    timeline.items = [makeImage(layer: 0, clipping: true)]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        checkPixel(frame, 2, 2, r: 255, g: 0, b: 0, tolerance: 4, "B2 corner red via flood mask")
        checkPixel(frame, 60, 60, r: 255, g: 0, b: 0, tolerance: 4, "B2 far corner red via flood mask")
        check(frame.nonTransparent == 4096, "B2 full coverage, got \(frame.nonTransparent)")
    } else {
        check(false, "B2 rendered")
    }
    box.composer.dispose()
}

// MARK: - B3: 合成グループ内部のクリッピング（内部合成器への factory 注入）

do {
    let timeline = makeTimeline()
    let group = GroupItem()
    group.frame = 0
    group.length = 90
    group.layer = 0
    group.groupRange = 10
    group.isComposite = true
    timeline.items = [
        group,
        makeShape(layer: 1, width: 32, height: 32),
        makeImage(layer: 2, clipping: true),
    ]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        checkPixel(frame, 32, 32, r: 255, g: 0, b: 0, tolerance: 4, "B3 center red inside mask")
        checkAlpha(frame, 2, 2, range: 0...10, "B3 corner clipped away")
    } else {
        check(false, "B3 rendered")
    }
    box.composer.dispose()
}

// MARK: - B4: シーン内部のクリッピング（シーン合成器への factory 注入）

do {
    let sceneTimeline = makeTimeline()
    sceneTimeline.items = [
        makeShape(layer: 0, width: 32, height: 32),
        makeImage(layer: 1, clipping: true),
    ]
    let timeline = makeTimeline()
    let sceneItem = SceneItem()
    sceneItem.frame = 0
    sceneItem.length = 90
    sceneItem.layer = 0
    sceneItem.sceneId = sceneTimeline.id
    timeline.items = [sceneItem]
    let box = ComposerBox(timeline: timeline, timelines: [timeline, sceneTimeline])
    if let frame = box.render(frame: 0) {
        checkPixel(frame, 32, 32, r: 255, g: 0, b: 0, tolerance: 4, "B4 center red inside mask")
        checkAlpha(frame, 2, 2, range: 0...10, "B4 corner clipped away")
    } else {
        check(false, "B4 rendered")
    }
    box.composer.dispose()
}

// MARK: - B5: 書き出し経路のクリッピング（MetalExportVideoProvider）

do {
    let timeline = makeTimeline()
    timeline.items = [
        makeShape(layer: 0, width: 32, height: 32),
        makeImage(layer: 1, clipping: true),
    ]
    if let provider = MetalExportVideoProvider(
        timeline: timeline, timelines: [timeline], baseDirectory: workDir
    ) {
        let buffer = ExportVideoFrameBuffer(byteCount: 64 * 64 * 4)
        do {
            try provider.fillFrame(0, into: buffer)
            let center = (32 * 64 + 32) * 4
            let corner = (2 * 64 + 2) * 4
            let centerOK = buffer.bytes[center + 2] == 255
                && buffer.bytes[center + 1] == 0 && buffer.bytes[center] == 0
                && buffer.bytes[center + 3] == 255
            print("  B5 center BGRA: \(buffer.bytes[center]),\(buffer.bytes[center + 1]),\(buffer.bytes[center + 2]),\(buffer.bytes[center + 3])")
            check(centerOK, "B5 export center red")
            print("  B5 corner alpha: \(buffer.bytes[corner + 3])")
            check(buffer.bytes[corner + 3] <= 10, "B5 export corner clipped away")
        } catch {
            check(false, "B5 fillFrame error: \(error)")
        }
        provider.dispose()
    } else {
        check(false, "B5 provider created")
    }
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
