import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core
import YMM4GPU

// MAC-0023 検証ハーネス: GPU エフェクト Metal 処理器 第1段（10種）。
// PreviewBox と同じ合成経路（TimelineComposer + MetalEffectPairProvider）で
// 既知色の画像へ各エフェクトを適用し、読み戻した画素で期待値を assert する。
// 期待値はシェーダの数式から解析的に導いた値（許容幅つき）。

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

// MARK: - 入力画像の生成（64×64 PNG、BGRA バイト列から直接作る）

let workDir = URL(fileURLWithPath: "/tmp/mac0023")
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

// 単色 (R200, G100, B50)
writePNG(name: "solid.png", width: 64, height: 64) { _, _ in (50, 100, 200, 255) }
// 左半分が黒・右半分が白
writePNG(name: "edge.png", width: 64, height: 64) { x, _ in
    x < 32 ? (0, 0, 0, 255) : (255, 255, 255, 255)
}
// 1px 市松（赤／青）
writePNG(name: "checker.png", width: 64, height: 64) { x, y in
    (x + y) % 2 == 0 ? (0, 0, 255, 255) : (255, 0, 0, 255)
}

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
}

final class ComposerBox {
    let devices: MetalGraphicsDevices
    let context: MetalGraphicsContext
    let composer: TimelineComposer

    init(timeline: Timeline) {
        devices = MetalGraphicsDevices()!
        context = devices.makeContext(
            targetSize: PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
        )
        let provider = MetalSourceProvider(devices: devices, baseDirectory: workDir)
        composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider.source(for:),
            effectProvider: MetalEffectPairProvider(devices: devices)
        )
    }

    func render(frame: Int, fps: Int) -> Frame? {
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

@MainActor
func runCase(
    _ name: String, image: String, effects: [PreservedObject],
    assertions: @MainActor (Frame) -> Void
) {
    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: 30, hz: 44_100, width: 64, height: 64)
    let item = ImageItem()
    item.filePath = image
    item.frame = 0
    item.length = 90
    item.layer = 0
    item.videoEffects = effects
    timeline.items = [item]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0, fps: 30) {
        assertions(frame)
    } else {
        check(false, "\(name): rendered")
    }
    box.composer.dispose()
}

func raw(_ definition: VideoEffectDefinitionBase) -> PreservedObject {
    VideoEffectRegistry.encode(definition)
}

// MARK: - ケース0: 対照（エフェクトなし）

runCase("control", image: "solid.png", effects: []) { frame in
    check(frame.nonTransparent == 4096, "control: full coverage")
    checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "control: center")
}

// MARK: - ケース1: Invert → (55,155,205)

runCase("invert", image: "solid.png", effects: [raw(InvertEffectDefinition())]) { frame in
    check(frame.nonTransparent == 4096, "invert: full coverage")
    checkPixel(frame, 32, 32, r: 55, g: 155, b: 205, tolerance: 3, "invert: center")
}

// MARK: - ケース2: Monocolorization 既定（白・輝度保持）→ グレー 124

runCase("mono-default", image: "solid.png", effects: [raw(MonocolorizationEffectDefinition())]) { frame in
    let p = frame.pixel(32, 32)
    print("  mono-default: got (R\(p.r),G\(p.g),B\(p.b),A\(p.a)) want gray ~124")
    check(
        abs(p.r - 124) <= 4 && abs(p.g - 124) <= 4 && abs(p.b - 124) <= 4,
        "mono-default: value ~124"
    )
    check(
        abs(p.r - p.g) <= 3 && abs(p.g - p.b) <= 3,
        "mono-default: channels equal (grayscale)"
    )
}

// MARK: - ケース3: Monocolorization 赤・輝度保持なし → (124,0,0)

do {
    let definition = MonocolorizationEffectDefinition()
    definition.color = Color(alpha: 255, red: 255, green: 0, blue: 0)
    definition.keepBrightness = false
    runCase("mono-red", image: "solid.png", effects: [raw(definition)]) { frame in
        checkPixel(frame, 32, 32, r: 124, g: 0, b: 0, tolerance: 4, "mono-red: center")
    }
}

// MARK: - ケース4: Sepia（Intensity 100・Strength 100）→ (165,147,114)

do {
    let definition = SepiaEffectDefinition()
    definition.sepiaIntensity.values = [AnimationValue(100)]
    definition.strength.values = [AnimationValue(100)]
    runCase("sepia", image: "solid.png", effects: [raw(definition)]) { frame in
        checkPixel(frame, 32, 32, r: 165, g: 147, b: 114, tolerance: 5, "sepia: center")
    }
}

// MARK: - ケース5: Tint 赤 → (200,0,0)

do {
    let definition = TintEffectDefinition()
    definition.color = Color(alpha: 255, red: 255, green: 0, blue: 0)
    runCase("tint", image: "solid.png", effects: [raw(definition)]) { frame in
        checkPixel(frame, 32, 32, r: 200, g: 0, b: 0, tolerance: 3, "tint: center")
    }
}

// MARK: - ケース6: Exposure +1EV → (255,200,100)

do {
    let definition = ExposureEffectDefinition()
    definition.value.values = [AnimationValue(100)]
    runCase("exposure", image: "solid.png", effects: [raw(definition)]) { frame in
        let p = frame.pixel(32, 32)
        print("  exposure: got (R\(p.r),G\(p.g),B\(p.b),A\(p.a)) want (255,200,100)")
        check(p.r >= 252, "exposure: R clamps to 255")
        check(
            abs(p.g - 200) <= 4 && abs(p.b - 100) <= 4,
            "exposure: G,B doubled"
        )
    }
}

// MARK: - ケース7: GammaCorrection Gamma=2 → (226,160,113)

do {
    let definition = GammaCorrectionEffectDefinition()
    definition.gamma.values = [AnimationValue(2)]
    runCase("gamma", image: "solid.png", effects: [raw(definition)]) { frame in
        checkPixel(frame, 32, 32, r: 226, g: 160, b: 113, tolerance: 5, "gamma: center")
    }
}

// MARK: - ケース8: Posterize 2階調 → (255,0,0)

do {
    let definition = PosterizeEffectDefinition()
    definition.r.values = [AnimationValue(2)]
    definition.g.values = [AnimationValue(2)]
    definition.b.values = [AnimationValue(2)]
    runCase("posterize", image: "solid.png", effects: [raw(definition)]) { frame in
        let p = frame.pixel(32, 32)
        print("  posterize: got (R\(p.r),G\(p.g),B\(p.b),A\(p.a)) want (255,0,0)")
        check(p.r >= 252 && p.g <= 3 && p.b <= 3, "posterize: quantized to (255,0,0)")
    }
}

// MARK: - ケース9: LinearTransfer（R傾き50・B切片50）→ (100,100,178)

do {
    let definition = LinearTransferEffectDefinition()
    definition.redSlope.values = [AnimationValue(50)]
    definition.blueYIntercept.values = [AnimationValue(50)]
    runCase("linear", image: "solid.png", effects: [raw(definition)]) { frame in
        checkPixel(frame, 32, 32, r: 100, g: 100, b: 178, tolerance: 5, "linear: center")
    }
}

// MARK: - ケース10: GaussianBlur Hard・単色 → 不変

do {
    let definition = GaussianBlurEffectDefinition()
    definition.blur.values = [AnimationValue(10)]
    definition.isHardBorderMode = true
    runCase("blur-uniform", image: "solid.png", effects: [raw(definition)]) { frame in
        checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "blur-uniform: center")
        checkPixel(frame, 0, 0, r: 200, g: 100, b: 50, tolerance: 3, "blur-uniform: corner")
    }
}

// MARK: - ケース11: GaussianBlur Hard・境界 → 中央が鈍る

do {
    let definition = GaussianBlurEffectDefinition()
    definition.blur.values = [AnimationValue(10)]
    definition.isHardBorderMode = true
    runCase("blur-edge", image: "edge.png", effects: [raw(definition)]) { frame in
        let left = frame.pixel(2, 32)
        let right = frame.pixel(61, 32)
        let midLeft = frame.pixel(31, 32)
        let midRight = frame.pixel(32, 32)
        let quarter = frame.pixel(16, 32)
        let threeQuarter = frame.pixel(47, 32)
        print("  blur-edge: left=\(left.r) quarter=\(quarter.r) midL=\(midLeft.r) midR=\(midRight.r) 3/4=\(threeQuarter.r) right=\(right.r)")
        check(left.r <= 15 && left.g <= 15 && left.b <= 15, "blur-edge: far left stays black")
        check(right.r >= 240 && right.g >= 240 && right.b >= 240, "blur-edge: far right stays white")
        check(
            (85...175).contains(midLeft.r) && (85...175).contains(midRight.r),
            "blur-edge: boundary pixels are mid gray"
        )
        check(
            quarter.r < midLeft.r && midRight.r < threeQuarter.r,
            "blur-edge: monotonic transition"
        )
    }
}

// MARK: - ケース12: GaussianBlur Soft・単色 → 中心はほぼ不変

do {
    let definition = GaussianBlurEffectDefinition()
    definition.blur.values = [AnimationValue(10)]
    definition.isHardBorderMode = false
    runCase("blur-soft", image: "solid.png", effects: [raw(definition)]) { frame in
        checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 5, "blur-soft: center")
    }
}

// MARK: - ケース13: Mosaic（既定セル10）・市松 → セル平均の紫

runCase("mosaic", image: "checker.png", effects: [raw(MosaicEffectDefinition())]) { frame in
    check(frame.nonTransparent == 4096, "mosaic: full coverage")
    for (x, y) in [(32, 32), (5, 5), (60, 60)] {
        let p = frame.pixel(x, y)
        print("  mosaic (\(x),\(y)): got (R\(p.r),G\(p.g),B\(p.b),A\(p.a)) want (~128,0,~128)")
        check(
            (118...138).contains(p.r) && p.g <= 3 && (118...138).contains(p.b),
            "mosaic: cell average at (\(x),\(y))"
        )
    }
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
