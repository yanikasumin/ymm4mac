import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core
import YMM4GPU

// BRUSH46 検証ハーネス: ブラシ基盤（型付きブラシモデル＋ GPU 塗り）。
// PreviewBox と同じ合成経路（TimelineComposer + MetalSourceProvider +
// 共有 MetalEffectPairProvider）で、ブラシを使う4エフェクト
// （Shadow / FillBackground / FillForeground / FrameLine）と図形
// アイテムへ型付きブラシを適用し、読み戻した画素で解析的な期待値を
// assert する。期待値は本家のブラシ幾何（MetalBrushFill.swift の
// 根拠コメント）から手計算したもの。
// 画面は 64×64、平面座標は中心原点・y 下向き。フレーム画素 (x, y) の
// 平面点はおよそ (−32 + x + 0.5, −32 + y + 0.5)。
// 入力の solid32 / white32 は平面 −16..16（フレーム画素 16..47）。

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

let workDir = URL(fileURLWithPath: "/tmp/brush46")
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

// 単色 (R200, G100, B50) 32×32 / 白 32×32
writePNG(name: "solid32.png", width: 32, height: 32) { _, _ in (50, 100, 200, 255) }
writePNG(name: "white32.png", width: 32, height: 32) { _, _ in (255, 255, 255, 255) }
// ビットマップブラシ用タイル 16×16: 左半分 = 赤、右半分 = 青
writePNG(name: "tile16.png", width: 16, height: 16) { x, _ in
    x < 8 ? (0, 0, 255, 255) : (255, 0, 0, 255)
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
}

/// PreviewBox（MAC-0028 配線: 供給元共有）と同じ構成の合成器。
final class ComposerBox {
    let devices: MetalGraphicsDevices
    let context: MetalGraphicsContext
    let provider: MetalSourceProvider
    let composer: TimelineComposer

    init(timeline: Timeline, timelines: [Timeline]? = nil) {
        do {
            devices = try MetalGraphicsDevices()
        } catch {
            fatalError("MetalGraphicsDevices の初期化に失敗: \(error)")
        }
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
            effectProvider: effectProvider
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

func makeTimeline() -> Timeline {
    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: 30, hz: 44_100, width: 64, height: 64)
    return timeline
}

func raw(_ definition: VideoEffectDefinitionBase) -> PreservedObject {
    VideoEffectRegistry.encode(definition)
}

/// 画像アイテム1つのタイムラインを合成して指定フレームを返す。
@MainActor
func renderImage(
    image: String,
    effects: [PreservedObject] = [],
    frame: Int = 0,
    length: Int = 90
) -> Frame? {
    let timeline = makeTimeline()
    let item = ImageItem()
    item.filePath = image
    item.frame = 0
    item.length = length
    item.layer = 0
    item.videoEffects = effects
    timeline.items = [item]
    let box = ComposerBox(timeline: timeline)
    let result = box.render(frame: frame)
    box.composer.dispose()
    return result
}

// MARK: - ブラシの組み立て

func argb(_ a: UInt8, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color {
    Color(alpha: a, red: r, green: g, blue: b)
}

func makeBrush(_ parameter: BrushParameter) -> Brush {
    let brush = Brush()
    brush.parameter = parameter
    return brush
}

/// 赤 (Offset 0) → 青 (Offset 1) の線形グラデーション。
func redBlueLinear(
    mode: BrushCoordinateMode, size: Double = 100, offset: Double = 0, angle: Double = 0
) -> Brush {
    let parameter = LinearGradientBrushParameter()
    parameter.stops = [
        GradientStopValue(offset: 0, color: argb(255, 255, 0, 0)),
        GradientStopValue(offset: 1, color: argb(255, 0, 0, 255)),
    ]
    parameter.coordinateMode = mode
    parameter.size.values = [AnimationValue(size)]
    parameter.offset.values = [AnimationValue(offset)]
    parameter.angle.values = [AnimationValue(angle)]
    return makeBrush(.linearGradient(parameter))
}

// MARK: - ケース1: FillForeground + 線形グラデーション (Relative)

// 境界 (−16..16) に対し L = 32、始点 (−16, 0)・終点 (16, 0)。
// t = (x + 16) / 32 で赤→青。IsBrushOnly で原画は混ざらない。
do {
    let definition = FillForegroundEffectDefinition()
    definition.brush = redBlueLinear(mode: .relative)
    definition.isBrushOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 x = −11.5 → t = 0.1406 → (219, 0, 36)
        checkPixel(frame, 20, 32, r: 219, g: 0, b: 36, tolerance: 6, "lin-rel: left")
        // 平面 x = 0.5 → t = 0.5156 → (124, 0, 131)
        checkPixel(frame, 32, 32, r: 124, g: 0, b: 131, tolerance: 6, "lin-rel: center")
        // 平面 x = 12.5 → t = 0.8906 → (28, 0, 227)
        checkPixel(frame, 44, 32, r: 28, g: 0, b: 227, tolerance: 6, "lin-rel: right")
    } else { check(false, "lin-rel: rendered") }
}

// MARK: - ケース2: FillForeground + 線形グラデーション (Pixel)

// Size = 32, Offset = 8 → 始点 (−8, 0)・終点 (24, 0)（原点基準）。
do {
    let definition = FillForegroundEffectDefinition()
    definition.brush = redBlueLinear(mode: .pixel, size: 32, offset: 8)
    definition.isBrushOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 x = −11.5 → t < 0 → Clamp で赤
        checkPixel(frame, 20, 32, r: 255, g: 0, b: 0, tolerance: 4, "lin-px: clamped start")
        // 平面 x = 12.5 → t = 0.6406 → (92, 0, 163)
        checkPixel(frame, 44, 32, r: 92, g: 0, b: 163, tolerance: 6, "lin-px: right")
    } else { check(false, "lin-px: rendered") }
}

// Angle = 90（v = (0, 1)、y 下向き）: 上が始点色・下が終点色。
do {
    let definition = FillForegroundEffectDefinition()
    definition.brush = redBlueLinear(mode: .pixel, size: 32, angle: 90)
    definition.isBrushOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 y = −11.5 → t = 0.1406 → (219, 0, 36)
        checkPixel(frame, 32, 20, r: 219, g: 0, b: 36, tolerance: 6, "lin-90: top")
        // 平面 y = 12.5 → t = 0.8906 → (28, 0, 227)
        checkPixel(frame, 32, 44, r: 28, g: 0, b: 227, tolerance: 6, "lin-90: bottom")
    } else { check(false, "lin-90: rendered") }
}

// MARK: - ケース3: Shadow + 線形グラデーション (Relative)

// 白 32×32 へ X = +16 の影。シルエットは入力境界で塗った
// グラデーション × 入力α を平行移動したもの。
do {
    let definition = ShadowEffectDefinition()
    definition.brush = redBlueLinear(mode: .relative)
    definition.x.values = [AnimationValue(16)]
    definition.y.values = [AnimationValue(0)]
    definition.blur.values = [AnimationValue(0)]
    definition.opacity.values = [AnimationValue(100)]
    if let frame = renderImage(image: "white32.png", effects: [raw(definition)]) {
        // 平面 (24.5, 0.5): シルエット局所点 (8.5, 0.5) → t = 0.7656
        // → (60, 0, 195)。原画の外なので影だけが見える。
        checkPixel(frame, 56, 32, r: 60, g: 0, b: 195, tolerance: 6, "shadow-grad: shifted")
        checkAlpha(frame, 56, 32, range: 250...255, "shadow-grad: opaque")
        // 平面 (8.5, 0.5) は原画（白）の下。
        checkPixel(frame, 40, 32, r: 255, g: 255, b: 255, tolerance: 4, "shadow-grad: original on top")
    } else { check(false, "shadow-grad: rendered") }
}

// MARK: - ケース4: FillBackground + 放射グラデーション

// 余白 16 で塗り矩形は画面全体 (−32..32)。中心 (0, 0)・半径 32 の
// 白→黒。余白部だけがグラデーションになる（中心は原画）。
do {
    let parameter = RadialGradientBrushParameter()
    parameter.stops = [
        GradientStopValue(offset: 0, color: argb(255, 255, 255, 255)),
        GradientStopValue(offset: 1, color: argb(255, 0, 0, 0)),
    ]
    parameter.radiusX.values = [AnimationValue(32)]
    parameter.radiusY.values = [AnimationValue(32)]
    let definition = FillBackgroundEffectDefinition()
    definition.brush = makeBrush(.radialGradient(parameter))
    definition.top.values = [AnimationValue(16)]
    definition.bottom.values = [AnimationValue(16)]
    definition.left.values = [AnimationValue(16)]
    definition.right.values = [AnimationValue(16)]
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 (−29.5, −29.5): r = 41.7 → t > 1 → 黒
        checkPixel(frame, 2, 2, r: 0, g: 0, b: 0, tolerance: 4, "radial: corner black")
        // 平面 (0.5, −29.5): r = 29.5 → t = 0.922 → 20
        checkPixel(frame, 32, 2, r: 20, g: 20, b: 20, tolerance: 6, "radial: top mid")
        // 平面 (−7.5, −23.5): r = 24.7 → t = 0.771 → 58
        checkPixel(frame, 24, 8, r: 58, g: 58, b: 58, tolerance: 8, "radial: inner")
        // 中心は原画。
        checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "radial: center is image")
    } else { check(false, "radial: rendered") }
}

// 焦点を (16, 0) へずらした放射。楕円族の解（大きい方の根）を
// 前向き計算で検証した期待値。
do {
    let parameter = RadialGradientBrushParameter()
    parameter.stops = [
        GradientStopValue(offset: 0, color: argb(255, 255, 255, 255)),
        GradientStopValue(offset: 1, color: argb(255, 0, 0, 0)),
    ]
    parameter.radiusX.values = [AnimationValue(32)]
    parameter.radiusY.values = [AnimationValue(32)]
    parameter.originX.values = [AnimationValue(16)]
    let definition = FillBackgroundEffectDefinition()
    definition.brush = makeBrush(.radialGradient(parameter))
    definition.top.values = [AnimationValue(16)]
    definition.bottom.values = [AnimationValue(16)]
    definition.left.values = [AnimationValue(16)]
    definition.right.values = [AnimationValue(16)]
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 (17.5, 0.5): 焦点 (16, 0) のすぐ外側 → t = 0.096 → 230
        checkPixel(frame, 49, 32, r: 230, g: 230, b: 230, tolerance: 8, "radial-focal: near focal")
        // 平面 (−17.5, 0.5): 焦点から遠い側 → t = 0.698 → 77
        checkPixel(frame, 14, 32, r: 77, g: 77, b: 77, tolerance: 8, "radial-focal: far side")
        // 平面 (−16.5, −16.5) → t = 0.802 → 50、
        // 平面 (16.5, −16.5) → t = 0.606 → 100（非対称の実値確認）
        checkPixel(frame, 15, 15, r: 50, g: 50, b: 50, tolerance: 10, "radial-focal: corner far")
        checkPixel(frame, 48, 15, r: 100, g: 100, b: 100, tolerance: 10, "radial-focal: corner near")
        // 中心は原画。
        checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "radial-focal: center is image")
    } else { check(false, "radial-focal: rendered") }
}

// MARK: - ケース5: FrameLine + 市松

// 太さ 4・余白 0・全方向・前面。市松 Size = 8、色1 = 赤・色2 = 青。
// パリティは floor(x/8) + floor(y/8) の偶奇（偶 = 色1）。
do {
    let parameter = CheckeredBrushParameter()
    parameter.color1 = argb(255, 255, 0, 0)
    parameter.color2 = argb(255, 0, 0, 255)
    parameter.size.values = [AnimationValue(8)]
    let definition = FrameLineEffectDefinition()
    definition.brush = makeBrush(.checkered(parameter))
    definition.thickness.values = [AnimationValue(4)]
    definition.renderPlacement = .front
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 (0.5, −17.5): 0 + (−3) = −3 奇数 → 青
        checkPixel(frame, 32, 14, r: 0, g: 0, b: 255, tolerance: 4, "checkered: top odd")
        // 平面 (8.5, −17.5): 1 + (−3) = −2 偶数 → 赤
        checkPixel(frame, 40, 14, r: 255, g: 0, b: 0, tolerance: 4, "checkered: top even")
        // 平面 (−17.5, −17.5): (−3) + (−3) = −6 偶数 → 赤（四隅）
        checkPixel(frame, 14, 14, r: 255, g: 0, b: 0, tolerance: 4, "checkered: corner")
        // 帯の内側は原画。
        checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "checkered: center is image")
    } else { check(false, "checkered: rendered") }
}

// MARK: - ケース6: FillForeground + ストライプ

// 幅 8 + 8・Angle 0・Offset 0: 始点 (−4, 0)・終点 (12, 0)、
// 周期 16、境界位置 0.5、Wrap。白/黒。
do {
    let parameter = StripeBrushParameter()
    parameter.color1 = argb(255, 255, 255, 255)
    parameter.width1.values = [AnimationValue(8)]
    parameter.color2 = argb(255, 0, 0, 0)
    parameter.width2.values = [AnimationValue(8)]
    let definition = FillForegroundEffectDefinition()
    definition.brush = makeBrush(.stripe(parameter))
    definition.isBrushOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 x = −3.5 → t = 0.03125 → 白
        checkPixel(frame, 28, 32, r: 255, g: 255, b: 255, tolerance: 4, "stripe: white band")
        // 平面 x = 4.5 → t = 0.53125 → 黒
        checkPixel(frame, 36, 32, r: 0, g: 0, b: 0, tolerance: 4, "stripe: black band")
        // 平面 x = −11.5 → t = −0.46875 → Wrap 0.53125 → 黒
        checkPixel(frame, 20, 32, r: 0, g: 0, b: 0, tolerance: 4, "stripe: wrapped black")
        // 平面 x = 12.5 → t = 1.03125 → Wrap 0.03125 → 白
        checkPixel(frame, 44, 32, r: 255, g: 255, b: 255, tolerance: 4, "stripe: wrapped white")
    } else { check(false, "stripe: rendered") }
}

// MARK: - ケース7: FillForeground + ドット

// 間隔 16・半径 5、前景 = 赤・背景 = 青。タイル中心 (8, 8) 周期。
do {
    let parameter = DotBrushParameter()
    parameter.foreground = argb(255, 255, 0, 0)
    parameter.background = argb(255, 0, 0, 255)
    parameter.radius.values = [AnimationValue(5)]
    parameter.span.values = [AnimationValue(16)]
    let definition = FillForegroundEffectDefinition()
    definition.brush = makeBrush(.dot(parameter))
    definition.isBrushOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 (−7.5, −7.5) → タイル内 (8.5, 8.5)、中心距離 0.71 → 赤
        checkPixel(frame, 24, 24, r: 255, g: 0, b: 0, tolerance: 4, "dot: center red")
        // 平面 (−14.5, −14.5) → タイル内 (1.5, 1.5)、距離 9.19 → 青
        checkPixel(frame, 17, 17, r: 0, g: 0, b: 255, tolerance: 4, "dot: corner blue")
        // 平面 (0.5, −7.5) → タイル内 (0.5, 8.5)、距離 7.52 → 青
        checkPixel(frame, 32, 24, r: 0, g: 0, b: 255, tolerance: 4, "dot: edge blue")
    } else { check(false, "dot: rendered") }
}

// MARK: - ケース8: FillForeground + 格子線

// タイル 16×16・太さ 2、線 = 白・背景 = 青。境界から 1 未満が線。
do {
    let parameter = GridLineBrushParameter()
    parameter.strokeColor = argb(255, 255, 255, 255)
    parameter.backgroundColor = argb(255, 0, 0, 255)
    parameter.thickness.values = [AnimationValue(2)]
    parameter.width.values = [AnimationValue(16)]
    parameter.height.values = [AnimationValue(16)]
    let definition = FillForegroundEffectDefinition()
    definition.brush = makeBrush(.gridLine(parameter))
    definition.isBrushOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 (−15.5, −7.5): 左端から 0.5 → 白（縦線）
        checkPixel(frame, 16, 24, r: 255, g: 255, b: 255, tolerance: 4, "grid: vertical line")
        // 平面 (−7.5, 0.5): 下端から 0.5 → 白（横線）
        checkPixel(frame, 24, 32, r: 255, g: 255, b: 255, tolerance: 4, "grid: horizontal line")
        // 平面 (−7.5, −7.5): どちらの境界からも 7.5 → 青
        checkPixel(frame, 24, 24, r: 0, g: 0, b: 255, tolerance: 4, "grid: cell interior")
    } else { check(false, "grid: rendered") }
}

// MARK: - ケース9: FillForeground + ビットマップ

// タイル 16×16（左 = 赤・右 = 青）を Wrap で敷く。変換は
// 中心化 (−8, −8) のみのため q = 平面点 + (8, 8)。
do {
    let parameter = BitmapBrushParameter()
    parameter.filePath = workDir.appendingPathComponent("tile16.png").path
    let definition = FillForegroundEffectDefinition()
    definition.brush = makeBrush(.bitmap(parameter))
    definition.isBrushOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 平面 (−3.5, 0.5) → q = (4.5, 8.5) → 左半分 = 赤
        checkPixel(frame, 28, 32, r: 255, g: 0, b: 0, tolerance: 4, "bitmap: left red")
        // 平面 (−11.5, 0.5) → q = (−3.5, 8.5) → Wrap で 12.5 → 右半分 = 青
        checkPixel(frame, 20, 32, r: 0, g: 0, b: 255, tolerance: 4, "bitmap: wrapped blue")
        // 平面 (12.5, 0.5) → q = (20.5, 8.5) → Wrap で 4.5 → 赤
        checkPixel(frame, 44, 32, r: 255, g: 0, b: 0, tolerance: 4, "bitmap: wrapped red")
    } else { check(false, "bitmap: rendered") }
}

// MARK: - ケース10: 図形アイテム + 線形グラデーション (Relative)

// 32×32 の矩形（全面塗り）。境界は図形の (−16..16) で、
// 期待値はケース1と同じ。
do {
    let timeline = makeTimeline()
    let item = ShapeItem()
    item.frame = 0
    item.length = 90
    item.layer = 0
    let parameter = RectangleShapeParameter()
    parameter.sizeMode = .widthHeight
    parameter.width.values = [AnimationValue(32)]
    parameter.height.values = [AnimationValue(32)]
    parameter.brush = redBlueLinear(mode: .relative)
    item.shapeParameter = .rectangle(parameter)
    timeline.items = [item]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        checkPixel(frame, 20, 32, r: 219, g: 0, b: 36, tolerance: 6, "shape-grad: left")
        checkPixel(frame, 44, 32, r: 28, g: 0, b: 227, tolerance: 6, "shape-grad: right")
        checkAlpha(frame, 4, 4, range: 0...10, "shape-grad: outside transparent")
    } else { check(false, "shape-grad: rendered") }
    box.composer.dispose()
}

// MARK: - ケース11: 未対応ブラシの素通し（回帰）

// ノイズブラシ（GPU 未対応）とグラデーションメッシュ（生保持）は
// 従来どおり素通し = 原画がそのまま出る。
do {
    let definition = FillForegroundEffectDefinition()
    definition.brush = makeBrush(.noise(NoiseBrushParameter()))
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "passthrough: noise brush")
    } else { check(false, "passthrough: noise rendered") }

    let meshBrush = Brush()
    meshBrush.parameter = .preserved(PreservedObject(.object([
        (key: "$type", value: .string("YukkuriMovieMaker.Brush.GradientMeshBrushParameter, YukkuriMovieMaker")),
        (key: "HorizontalCount", value: .number(2)),
    ])))
    let shadow = ShadowEffectDefinition()
    shadow.brush = meshBrush
    shadow.x.values = [AnimationValue(16)]
    shadow.blur.values = [AnimationValue(0)]
    if let frame = renderImage(image: "white32.png", effects: [raw(shadow)]) {
        checkPixel(frame, 32, 32, r: 255, g: 255, b: 255, tolerance: 4, "passthrough: mesh brush keeps image")
        checkAlpha(frame, 56, 32, range: 0...10, "passthrough: mesh brush no shadow")
    } else { check(false, "passthrough: mesh rendered") }
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
if failures > 0 {
    exit(1)
}
