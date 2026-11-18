import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core
import YMM4GPU

// MAC-0028 検証ハーネス: GPU エフェクト Metal 処理器 第2段（31種）＋
// 内部合成器への Metal 供給元の伝播。
// PreviewBox と同じ合成経路（TimelineComposer + MetalSourceProvider +
// 共有 MetalEffectPairProvider）で既知パターンの画像へ各エフェクトを
// 適用し、読み戻した画素で解析的な期待値を assert する。
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

let workDir = URL(fileURLWithPath: "/tmp/mac0028")
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

// 単色 (R200, G100, B50) 64×64 / 32×32
writePNG(name: "solid.png", width: 64, height: 64) { _, _ in (50, 100, 200, 255) }
writePNG(name: "solid32.png", width: 32, height: 32) { _, _ in (50, 100, 200, 255) }
// 左半分が黒・右半分が白
writePNG(name: "edge.png", width: 64, height: 64) { x, _ in
    x < 32 ? (0, 0, 0, 255) : (255, 255, 255, 255)
}
// 左半分が赤・右半分が青
writePNG(name: "redblue.png", width: 64, height: 64) { x, _ in
    x < 32 ? (0, 0, 255, 255) : (255, 0, 0, 255)
}
// 四象限: 左上=赤, 右上=緑, 左下=青, 右下=白
writePNG(name: "quad.png", width: 64, height: 64) { x, y in
    switch (x < 32, y < 32) {
    case (true, true): return (0, 0, 255, 255)
    case (false, true): return (0, 255, 0, 255)
    case (true, false): return (255, 0, 0, 255)
    case (false, false): return (255, 255, 255, 255)
    }
}
writePNG(name: "quad32.png", width: 32, height: 32) { x, y in
    switch (x < 16, y < 16) {
    case (true, true): return (0, 0, 255, 255)
    case (false, true): return (0, 255, 0, 255)
    case (true, false): return (255, 0, 0, 255)
    case (false, false): return (255, 255, 255, 255)
    }
}
// 左上の 16×16 だけ赤、残り青
writePNG(name: "corner.png", width: 64, height: 64) { x, y in
    (x < 16 && y < 16) ? (0, 0, 255, 255) : (255, 0, 0, 255)
}
// 白 64×64 / 32×32
writePNG(name: "white.png", width: 64, height: 64) { _, _ in (255, 255, 255, 255) }
writePNG(name: "white32.png", width: 32, height: 32) { _, _ in (255, 255, 255, 255) }
// 32×32、8px セルの赤／青市松
writePNG(name: "checker32.png", width: 32, height: 32) { x, y in
    ((x / 8) + (y / 8)) % 2 == 0 ? (0, 0, 255, 255) : (255, 0, 0, 255)
}
// 中央の 8×8 だけ白い点（残り透明）
writePNG(name: "dot.png", width: 64, height: 64) { x, y in
    (x >= 28 && x < 36 && y >= 28 && y < 36) ? (255, 255, 255, 255) : (0, 0, 0, 0)
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

/// 2フレームの近似一致（面積比で許容する不一致率）。
@MainActor
func checkSimilar(_ a: Frame, _ b: Frame, tolerance: Int, _ label: String) {
    var mismatches = 0
    for i in 0..<(a.width * a.height) {
        let j = i * 4
        if abs(Int(a.bytes[j]) - Int(b.bytes[j])) > tolerance
            || abs(Int(a.bytes[j + 1]) - Int(b.bytes[j + 1])) > tolerance
            || abs(Int(a.bytes[j + 2]) - Int(b.bytes[j + 2])) > tolerance
            || abs(Int(a.bytes[j + 3]) - Int(b.bytes[j + 3])) > tolerance {
            mismatches += 1
        }
    }
    let ratio = Double(mismatches) / Double(a.width * a.height)
    print("  \(label): mismatch \(mismatches) px (\(String(format: "%.2f", ratio * 100))%)")
    check(ratio < 0.02, label)
}

/// PreviewBox（MAC-0028 配線: 供給元共有）と同じ構成の合成器。
final class ComposerBox {
    let devices: MetalGraphicsDevices
    let context: MetalGraphicsContext
    let provider: MetalSourceProvider
    let composer: TimelineComposer

    init(timeline: Timeline, timelines: [Timeline]? = nil) {
        devices = MetalGraphicsDevices()!
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

func solidBrush(_ colorText: String) -> Brush {
    // BRUSH46 で定義側の brush は型付きモデル（Brush）になったため、
    // ハーネスも型付きで組み立てる（往復は VideoEffectRegistry.encode
    // が担う）。
    let brush = Brush()
    let parameter = SolidColorBrushParameter()
    var hex = colorText
    if hex.hasPrefix("#") { hex.removeFirst() }
    let value = UInt32(hex, radix: 16) ?? 0
    parameter.color = Color(
        alpha: UInt8((value >> 24) & 0xFF),
        red: UInt8((value >> 16) & 0xFF),
        green: UInt8((value >> 8) & 0xFF),
        blue: UInt8(value & 0xFF)
    )
    brush.parameter = .solidColor(parameter)
    return brush
}

/// 画像アイテム1つのタイムラインを合成して指定フレームを返す。
@MainActor
func renderImage(
    image: String,
    effects: [PreservedObject] = [],
    frame: Int = 0,
    length: Int = 90,
    configureItem: (ImageItem) -> Void = { _ in }
) -> Frame? {
    let timeline = makeTimeline()
    let item = ImageItem()
    item.filePath = image
    item.frame = 0
    item.length = length
    item.layer = 0
    item.videoEffects = effects
    configureItem(item)
    timeline.items = [item]
    let box = ComposerBox(timeline: timeline)
    let result = box.render(frame: frame)
    box.composer.dispose()
    return result
}

// MARK: - 回帰: 画像の上下方向（デコード反転の再発防止）
// 四象限画像を readBGRA で直接読み、左上=赤・左下=青であることを確認する。
// MAC-0028 検証で、デコード時の反転変換により画像が上下逆になっていた
// 既存欠陥（MAC-0012 以来・従来ハーネスは上下対称パターンで未検出）を
// 修正した。その再発防止として残す。

do {
    let timeline = makeTimeline()
    let item = ImageItem()
    item.filePath = "quad.png"
    item.frame = 0
    item.length = 90
    item.layer = 0
    timeline.items = [item]
    let box = ComposerBox(timeline: timeline)
    try? box.composer.update(time: TimeSpanValue(seconds: 0), usage: .paused)
    if let output = box.composer.output {
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let ok = box.devices.readBGRA(from: output, into: &bytes)
        let i = (8 * 64 + 8) * 4
        let j = (56 * 64 + 8) * 4
        check(ok && bytes[i + 2] == 255 && bytes[i] == 0, "orientation: TL is red (not flipped)")
        check(ok && bytes[j] == 255 && bytes[j + 2] == 0, "orientation: BL is blue (not flipped)")
    } else {
        check(false, "orientation: output exists")
    }
    box.composer.dispose()
}

// MARK: - ケース0: 対照

if let frame = renderImage(image: "solid.png") {
    check(frame.nonTransparent == 4096, "control: full coverage")
    checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "control: center")
} else { check(false, "control: rendered") }

// MARK: - ケース1: Rotate Z=180（四象限が対角へ入れ替わる）

do {
    let definition = RotateEffectDefinition()
    definition.z.values = [AnimationValue(180)]
    if let frame = renderImage(image: "quad.png", effects: [raw(definition)]) {
        checkPixel(frame, 8, 8, r: 255, g: 255, b: 255, tolerance: 4, "rotate180: TL <- BR white")
        checkPixel(frame, 56, 8, r: 0, g: 0, b: 255, tolerance: 4, "rotate180: TR <- BL blue")
        checkPixel(frame, 8, 56, r: 0, g: 255, b: 0, tolerance: 4, "rotate180: BL <- TR green")
        checkPixel(frame, 56, 56, r: 255, g: 0, b: 0, tolerance: 4, "rotate180: BR <- TL red")
    } else { check(false, "rotate180: rendered") }
}

// MARK: - ケース2: Rotate Z=90

do {
    let definition = RotateEffectDefinition()
    definition.z.values = [AnimationValue(90)]
    if let frame = renderImage(image: "quad.png", effects: [raw(definition)]) {
        // Rz(+90°): 出力の右上には入力の左上（赤）が来る。
        checkPixel(frame, 48, 16, r: 255, g: 0, b: 0, tolerance: 4, "rotate90: TR <- TL red")
        checkPixel(frame, 16, 48, r: 255, g: 255, b: 255, tolerance: 4, "rotate90: BL <- BR white")
    } else { check(false, "rotate90: rendered") }
}

// MARK: - ケース3: Skew angleX=45・中心=原点

do {
    let definition = SkewEffectDefinition()
    definition.angleX.values = [AnimationValue(45)]
    if let frame = renderImage(image: "edge.png", effects: [raw(definition)]) {
        // x' = x + y。出力点の源は q.x = p.x − p.y。
        // (40,8) は歪み後の四隅の角ちょうど（q.x = 32 の境界）になるため
        // 内側の (36,8)（q.x = 28）で判定する。
        checkPixel(frame, 36, 8, r: 255, g: 255, b: 255, tolerance: 4, "skew45: upper right white (q.x>0)")
        checkPixel(frame, 4, 8, r: 0, g: 0, b: 0, tolerance: 4, "skew45: upper left black (q.x<0)")
        checkPixel(frame, 40, 56, r: 0, g: 0, b: 0, tolerance: 4, "skew45: lower right black (q.x<0)")
    } else { check(false, "skew45: rendered") }
}

// MARK: - ケース4: CenterPoint（右下・位置保持なし／あり）

do {
    let definition = CenterPointEffectDefinition()
    definition.horizontal = .right
    definition.vertical = .bottom
    if let frame = renderImage(image: "solid.png", effects: [raw(definition)]) {
        print("  centerpoint: coverage=\(frame.nonTransparent) want ~1024")
        check(abs(frame.nonTransparent - 1024) <= 130, "centerpoint: quarter coverage")
        checkPixel(frame, 16, 16, r: 200, g: 100, b: 50, tolerance: 3, "centerpoint: shifted content")
        checkAlpha(frame, 48, 48, range: 0...10, "centerpoint: empty quadrant")
    } else { check(false, "centerpoint: rendered") }
    let keeping = CenterPointEffectDefinition()
    keeping.horizontal = .right
    keeping.vertical = .bottom
    keeping.isKeepPosition = true
    if let frame = renderImage(image: "solid.png", effects: [raw(keeping)]) {
        check(frame.nonTransparent == 4096, "centerpoint-keep: full coverage")
        checkPixel(frame, 48, 48, r: 200, g: 100, b: 50, tolerance: 3, "centerpoint-keep: position kept")
    } else { check(false, "centerpoint-keep: rendered") }
}

// MARK: - ケース5: Crop（上下左右16・中心化なし）

do {
    let definition = CropEffectDefinition()
    definition.left.values = [AnimationValue(16)]
    definition.right.values = [AnimationValue(16)]
    definition.top.values = [AnimationValue(16)]
    definition.bottom.values = [AnimationValue(16)]
    definition.isCentering = false
    if let frame = renderImage(image: "edge.png", effects: [raw(definition)]) {
        print("  crop: coverage=\(frame.nonTransparent) want ~1024")
        check(abs(frame.nonTransparent - 1024) <= 130, "crop: center 32x32 coverage")
        checkPixel(frame, 20, 32, r: 0, g: 0, b: 0, tolerance: 4, "crop: left half black")
        checkPixel(frame, 44, 32, r: 255, g: 255, b: 255, tolerance: 4, "crop: right half white")
        checkAlpha(frame, 4, 4, range: 0...10, "crop: outside transparent")
    } else { check(false, "crop: rendered") }
}

// MARK: - ケース6: Margin → Crop の連鎖（境界拡張が後段へ効く）

do {
    let margin = MarginEffectDefinition()
    margin.left.values = [AnimationValue(32)]
    let crop = CropEffectDefinition()
    crop.left.values = [AnimationValue(48)]
    crop.isCentering = false
    if let frame = renderImage(image: "solid.png", effects: [raw(margin), raw(crop)]) {
        // 余白で境界が (−64,−32,32,32) へ広がった後に左48を切ると
        // 残りは平面 x −16..32 → フレーム x 16..64。
        checkPixel(frame, 20, 32, r: 200, g: 100, b: 50, tolerance: 3, "margin+crop: content from x=16")
        checkAlpha(frame, 8, 32, range: 0...10, "margin+crop: left of crop transparent")
    } else { check(false, "margin+crop: rendered") }
}

// MARK: - ケース7: CopyAndReverse（右・左右反転あり）

do {
    let definition = CopyAndReverseEffectDefinition()
    definition.position = .right
    definition.isLeftRightReversed = true
    definition.isTopBottomReversed = false
    if let frame = renderImage(image: "quad.png", effects: [raw(definition)]) {
        // 複写（反転）が左半分へ来るため、上段は両半分とも緑、下段は白。
        checkPixel(frame, 8, 8, r: 0, g: 255, b: 0, tolerance: 4, "copyreverse: left top green (flipped clone)")
        checkPixel(frame, 8, 56, r: 255, g: 255, b: 255, tolerance: 4, "copyreverse: left bottom white")
        checkPixel(frame, 56, 8, r: 0, g: 255, b: 0, tolerance: 4, "copyreverse: right top green")
    } else { check(false, "copyreverse: rendered") }
}

// MARK: - ケース8: Tiling 2×2（32×32 市松）

do {
    let definition = TilingEffectDefinition()
    definition.x.values = [AnimationValue(2)]
    definition.y.values = [AnimationValue(2)]
    if let frame = renderImage(image: "checker32.png", effects: [raw(definition)]) {
        check(frame.nonTransparent == 4096, "tiling: full coverage")
        checkPixel(frame, 8, 8, r: 255, g: 0, b: 0, tolerance: 4, "tiling: repeated cell red")
        checkPixel(frame, 36, 12, r: 0, g: 0, b: 255, tolerance: 4, "tiling: repeated cell blue")
    } else { check(false, "tiling: rendered") }
}

// MARK: - ケース9: AutomaticZoom UpOnly（32×32 が画面へ拡大される）

do {
    let definition = AutomaticZoomEffectDefinition()
    definition.automaticZoomMode = .upOnly
    definition.automaticZoomTarget = .widthHeight
    if let frame = renderImage(image: "quad32.png", effects: [raw(definition)]) {
        print("  autozoom-up: coverage=\(frame.nonTransparent) want 4096")
        check(frame.nonTransparent == 4096, "autozoom-up: zoomed to full screen")
        checkPixel(frame, 8, 8, r: 255, g: 0, b: 0, tolerance: 4, "autozoom-up: TL red")
    } else { check(false, "autozoom-up: rendered") }
}

// MARK: - ケース10: AutomaticZoom DownOnly（アイテム Zoom 200% が等倍へ収まる）

do {
    let definition = AutomaticZoomEffectDefinition()
    definition.automaticZoomMode = .downOnly
    if let frame = renderImage(
        image: "corner.png", effects: [raw(definition)],
        configureItem: { item in item.zoom.values = [AnimationValue(200)] }
    ) {
        // 倍率 0.5 が掛かり全体が見えるため、左上の赤ブロックが見える。
        checkPixel(frame, 8, 8, r: 255, g: 0, b: 0, tolerance: 4, "autozoom-down: corner block visible")
        checkPixel(frame, 56, 56, r: 0, g: 0, b: 255, tolerance: 4, "autozoom-down: rest blue")
    } else { check(false, "autozoom-down: rendered") }
}

// MARK: - ケース11: RoundCorner（半径32・白）

do {
    let definition = RoundCornerEffectDefinition()
    definition.radius.values = [AnimationValue(32)]
    if let frame = renderImage(image: "white.png", effects: [raw(definition)]) {
        checkAlpha(frame, 0, 0, range: 0...10, "roundcorner: corner transparent")
        checkAlpha(frame, 6, 6, range: 0...60, "roundcorner: near corner mostly transparent")
        checkAlpha(frame, 32, 32, range: 250...255, "roundcorner: center opaque")
        // 辺中央 (32,2): マスクαは2次元減衰込みで Φ 統合 ≈ 0.47 < 0.5
        // のため伝達で 0 になる（本家 D2D でも同じ。旧期待値 250...255 は
        // 水平方向の減衰を見落とした誤り）。(32,6) では α ≈ 0.55 → 不透明。
        checkAlpha(frame, 32, 2, range: 0...10, "roundcorner: edge center eaten by 2D falloff")
        checkAlpha(frame, 32, 6, range: 250...255, "roundcorner: 6px inside opaque")
        checkAlpha(frame, 20, 20, range: 250...255, "roundcorner: inside arc opaque")
    } else { check(false, "roundcorner: rendered") }
}

// MARK: - ケース12: BorderBlur（ぼかし10・白）

do {
    let definition = BorderBlurEffectDefinition()
    definition.blur.values = [AnimationValue(10)]
    if let frame = renderImage(image: "white.png", effects: [raw(definition)]) {
        checkAlpha(frame, 32, 32, range: 250...255, "borderblur: center opaque")
        checkAlpha(frame, 0, 32, range: 0...40, "borderblur: edge faded")
        // 5px 内側: Φ(0.5)≈0.69 → α ≈ (2・0.69−1)・255 ≈ 97。
        checkAlpha(frame, 5, 32, range: 55...145, "borderblur: 5px inside ~97")
    } else { check(false, "borderblur: rendered") }
}

// MARK: - ケース13: DirectionalBlur（σ10）

do {
    let vertical = DirectionalBlurEffectDefinition()
    vertical.standardDeviation.values = [AnimationValue(10)]
    vertical.angle.values = [AnimationValue(0)]
    if let frame = renderImage(image: "edge.png", effects: [raw(vertical)]) {
        // パラメータ 0 → D2D 角度 90° = 縦方向。縦境界は縦ぼかしで不変。
        checkPixel(frame, 31, 32, r: 0, g: 0, b: 0, tolerance: 15, "dirblur-vertical: boundary stays black")
        checkPixel(frame, 32, 32, r: 255, g: 255, b: 255, tolerance: 15, "dirblur-vertical: boundary stays white")
    } else { check(false, "dirblur-vertical: rendered") }
    let horizontal = DirectionalBlurEffectDefinition()
    horizontal.standardDeviation.values = [AnimationValue(10)]
    horizontal.angle.values = [AnimationValue(90)]
    if let frame = renderImage(image: "edge.png", effects: [raw(horizontal)]) {
        let mid = frame.pixel(31, 32)
        print("  dirblur-horizontal: mid=\(mid.r) want 85...175")
        check((85...175).contains(mid.r), "dirblur-horizontal: boundary blurred")
    } else { check(false, "dirblur-horizontal: rendered") }
}

// MARK: - ケース14: ChromaticAberration（強さ50・赤／青）

do {
    let definition = ChromaticAberrationEffectDefinition()
    definition.strength.values = [AnimationValue(50)]
    if let frame = renderImage(image: "redblue.png", effects: [raw(definition)]) {
        checkPixel(frame, 8, 32, r: 255, g: 0, b: 0, tolerance: 4, "chroma: left stays red")
        checkPixel(frame, 40, 32, r: 0, g: 0, b: 255, tolerance: 4, "chroma: inner right blue")
        // 右端は B の縮小サンプルが入力外へ出るため黒になる（本家も同挙動）。
        checkPixel(frame, 56, 32, r: 0, g: 0, b: 0, tolerance: 4, "chroma: far right black (B sampled outside)")
    } else { check(false, "chroma: rendered") }
}

// MARK: - ケース15: Shadow（黒ブラシ・X+16・ぼかし0・不透明度100）

do {
    let definition = ShadowEffectDefinition()
    definition.brush = solidBrush("#FF000000")
    definition.x.values = [AnimationValue(16)]
    definition.y.values = [AnimationValue(0)]
    definition.blur.values = [AnimationValue(0)]
    definition.opacity.values = [AnimationValue(100)]
    if let frame = renderImage(image: "white32.png", effects: [raw(definition)]) {
        checkPixel(frame, 24, 32, r: 255, g: 255, b: 255, tolerance: 4, "shadow: original white")
        checkPixel(frame, 56, 32, r: 0, g: 0, b: 0, tolerance: 4, "shadow: shifted silhouette black")
        checkAlpha(frame, 56, 32, range: 250...255, "shadow: silhouette opaque")
    } else { check(false, "shadow: rendered") }
}

// MARK: - ケース16: FillBackground（赤・余白16）

do {
    let definition = FillBackgroundEffectDefinition()
    definition.brush = solidBrush("#FFFF0000")
    definition.top.values = [AnimationValue(16)]
    definition.bottom.values = [AnimationValue(16)]
    definition.left.values = [AnimationValue(16)]
    definition.right.values = [AnimationValue(16)]
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        checkPixel(frame, 4, 4, r: 255, g: 0, b: 0, tolerance: 4, "fillbg: expanded area red")
        checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "fillbg: center is image")
    } else { check(false, "fillbg: rendered") }
    let only = FillBackgroundEffectDefinition()
    only.brush = solidBrush("#FFFF0000")
    only.top.values = [AnimationValue(16)]
    only.bottom.values = [AnimationValue(16)]
    only.left.values = [AnimationValue(16)]
    only.right.values = [AnimationValue(16)]
    only.isBackgroundOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(only)]) {
        checkPixel(frame, 4, 4, r: 255, g: 0, b: 0, tolerance: 4, "fillbg-only: outside red")
        checkAlpha(frame, 32, 32, range: 0...10, "fillbg-only: image area cut out")
    } else { check(false, "fillbg-only: rendered") }
}

// MARK: - ケース17: FillForeground（青・不透明度50）

do {
    let definition = FillForegroundEffectDefinition()
    definition.brush = solidBrush("#FF0000FF")
    definition.opacity.values = [AnimationValue(50)]
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 青×0.5 + 原画×0.5 = (100, 50, 152) 付近。
        checkPixel(frame, 32, 32, r: 100, g: 50, b: 152, tolerance: 8, "fillfg: half blue over image")
    } else { check(false, "fillfg: rendered") }
    let only = FillForegroundEffectDefinition()
    only.brush = solidBrush("#FF0000FF")
    only.opacity.values = [AnimationValue(50)]
    only.isBrushOnly = true
    if let frame = renderImage(image: "solid32.png", effects: [raw(only)]) {
        let p = frame.pixel(32, 32)
        print("  fillfg-only: got (R\(p.r),G\(p.g),B\(p.b),A\(p.a)) want B~127 A~128")
        check(abs(p.a - 128) <= 10 && abs(p.b - 127) <= 12, "fillfg-only: masked brush at half opacity")
    } else { check(false, "fillfg-only: rendered") }
}

// MARK: - ケース18: FrameLine（緑・太さ4・前面）

do {
    let definition = FrameLineEffectDefinition()
    definition.brush = solidBrush("#FF00FF00")
    definition.thickness.values = [AnimationValue(4)]
    definition.renderPlacement = .front
    if let frame = renderImage(image: "solid32.png", effects: [raw(definition)]) {
        // 画像境界 (−16..16) の外側4pxに帯。上の帯は平面 y −20..−16。
        checkPixel(frame, 32, 14, r: 0, g: 255, b: 0, tolerance: 4, "frameline: top strip green")
        checkPixel(frame, 14, 14, r: 0, g: 255, b: 0, tolerance: 4, "frameline: corner square green")
        checkPixel(frame, 32, 32, r: 200, g: 100, b: 50, tolerance: 3, "frameline: center is image")
    } else { check(false, "frameline: rendered") }
}

// MARK: - ケース19: Morphology（膨張／縮小）

do {
    let dilate = MorphologyEffectDefinition()
    dilate.mode = .dilate
    dilate.width.values = [AnimationValue(5)]
    dilate.height.values = [AnimationValue(5)]
    if let frame = renderImage(image: "dot.png", effects: [raw(dilate)]) {
        // 8×8 の点が各方向へ2px広がる: 平面 (5.5, 0) は白、(7.5, 0) は透明。
        checkAlpha(frame, 37, 32, range: 250...255, "morph-dilate: grown area white")
        checkAlpha(frame, 39, 32, range: 0...10, "morph-dilate: beyond growth transparent")
    } else { check(false, "morph-dilate: rendered") }
    let erode = MorphologyEffectDefinition()
    erode.mode = .erode
    erode.width.values = [AnimationValue(5)]
    erode.height.values = [AnimationValue(5)]
    if let frame = renderImage(image: "white.png", effects: [raw(erode)]) {
        checkAlpha(frame, 0, 32, range: 0...10, "morph-erode: edge eroded by outside transparency")
        checkAlpha(frame, 32, 32, range: 250...255, "morph-erode: center stays white")
    } else { check(false, "morph-erode: rendered") }
}

// MARK: - ケース20: Jump（フレーム0は静止、フレーム7は跳躍で画面外）

do {
    let definition = JumpEffectDefinition()
    if let frame0 = renderImage(image: "solid32.png", effects: [raw(definition)], frame: 0) {
        print("  jump f0: coverage=\(frame0.nonTransparent) want ~1024")
        check(abs(frame0.nonTransparent - 1024) <= 130, "jump: frame 0 at rest")
    } else { check(false, "jump f0: rendered") }
    if let frame7 = renderImage(image: "solid32.png", effects: [raw(definition)], frame: 7) {
        // t=7/30: 位相 0.467、跳躍量 = 100・sin(84°) ≈ 99.5 → 画面外。
        print("  jump f7: coverage=\(frame7.nonTransparent) want ~0")
        check(frame7.nonTransparent <= 10, "jump: frame 7 airborne off-screen")
    } else { check(false, "jump f7: rendered") }
}

// MARK: - ケース21: InOutMosaic（入り際はモザイク、抜け後は素）

do {
    let definition = InOutMosaicEffectDefinition()
    definition.isOutEffect = false
    let mosaic = MosaicEffectDefinition()
    if let frame0 = renderImage(image: "checker32.png", effects: [raw(definition)], frame: 0) {
        // セル10の平均（赤／青市松 → 紫）。比較用に通常モザイクも併記。
        let p = frame0.pixel(32, 32)
        print("  inoutmosaic f0: got (R\(p.r),G\(p.g),B\(p.b)) want ~(128,0,128)")
        check((110...146).contains(p.r) && p.g <= 5 && (110...146).contains(p.b), "inoutmosaic: frame 0 mosaic average")
    } else { check(false, "inoutmosaic f0: rendered") }
    _ = mosaic
    if let frame45 = renderImage(image: "checker32.png", effects: [raw(definition)], frame: 45) {
        let p = frame45.pixel(32, 32)
        print("  inoutmosaic f45: got (R\(p.r),G\(p.g),B\(p.b)) want pure red or blue")
        check(p.g <= 5 && ((p.r >= 250 && p.b <= 5) || (p.b >= 250 && p.r <= 5)), "inoutmosaic: frame 45 clean checker")
    } else { check(false, "inoutmosaic f45: rendered") }
}

// MARK: - ケース22: InOutMoveFromOutsideImage（左・入り際は画面外）

do {
    let definition = InOutMoveFromOutsideImageEffectDefinition()
    definition.isOutEffect = false
    if let frame0 = renderImage(image: "solid.png", effects: [raw(definition)], frame: 0) {
        print("  inoutmove f0: coverage=\(frame0.nonTransparent) want ~0")
        check(frame0.nonTransparent <= 10, "inoutmove: frame 0 off-screen")
    } else { check(false, "inoutmove f0: rendered") }
    if let frame45 = renderImage(image: "solid.png", effects: [raw(definition)], frame: 45) {
        check(frame45.nonTransparent == 4096, "inoutmove: frame 45 settled")
    } else { check(false, "inoutmove f45: rendered") }
}

// MARK: - ケース23: InOutRotate（入り際は90°、抜け後は0°）

do {
    let definition = InOutRotateEffectDefinition()
    definition.isOutEffect = false
    if let frame0 = renderImage(image: "quad.png", effects: [raw(definition)], frame: 0) {
        checkPixel(frame0, 48, 16, r: 255, g: 0, b: 0, tolerance: 4, "inoutrotate f0: TR red (90 deg)")
    } else { check(false, "inoutrotate f0: rendered") }
    if let frame45 = renderImage(image: "quad.png", effects: [raw(definition)], frame: 45) {
        checkPixel(frame45, 48, 16, r: 0, g: 255, b: 0, tolerance: 4, "inoutrotate f45: TR green (0 deg)")
    } else { check(false, "inoutrotate f45: rendered") }
}

// MARK: - ケース24: InOutGetUp（下基線・入り際は倒れて潰れる）

do {
    let definition = InOutGetUpEffectDefinition()
    definition.isOutEffect = false
    if let frame0 = renderImage(image: "solid.png", effects: [raw(definition)], frame: 0) {
        print("  getup f0: coverage=\(frame0.nonTransparent) want << 4096")
        check(frame0.nonTransparent < 600, "getup: frame 0 collapsed to baseline")
    } else { check(false, "getup f0: rendered") }
    if let frame45 = renderImage(image: "solid.png", effects: [raw(definition)], frame: 45) {
        check(frame45.nonTransparent == 4096, "getup: frame 45 upright")
    } else { check(false, "getup f45: rendered") }
}

// MARK: - ケース25: InOutGaussianBlur / InOutBorderBlur

do {
    let blur = InOutGaussianBlurEffectDefinition()
    blur.isOutEffect = false
    if let frame0 = renderImage(image: "edge.png", effects: [raw(blur)], frame: 0) {
        let mid = frame0.pixel(31, 32)
        print("  inoutblur f0: mid=\(mid.r) want 85...175")
        check((85...175).contains(mid.r), "inoutblur: frame 0 blurred boundary")
    } else { check(false, "inoutblur f0: rendered") }
    if let frame45 = renderImage(image: "edge.png", effects: [raw(blur)], frame: 45) {
        checkPixel(frame45, 31, 32, r: 0, g: 0, b: 0, tolerance: 15, "inoutblur: frame 45 sharp")
    } else { check(false, "inoutblur f45: rendered") }
    let border = InOutBorderBlurEffectDefinition()
    border.isOutEffect = false
    if let frame0 = renderImage(image: "white.png", effects: [raw(border)], frame: 0) {
        checkAlpha(frame0, 0, 32, range: 0...40, "inoutborderblur: edge faded")
        checkAlpha(frame0, 32, 32, range: 250...255, "inoutborderblur: center opaque")
    } else { check(false, "inoutborderblur f0: rendered") }
}

// MARK: - ケース26: RandomRotate（Span=0、参照 = 同角度の Rotate）

do {
    let definition = RandomRotateEffectDefinition()
    definition.z.values = [AnimationValue(180)]
    definition.span.values = [AnimationValue(0)]
    // 期待角度は Core の乱数式で組み立てる（種は randomSeed = 0、ID は Z = 2）。
    let rate = StatelessRandom.getDouble(keys: [0, 2, 3, 0])
    let expectedAngle = 180 * rate - 90
    print("  randomrotate: rate=\(rate) expected angle=\(expectedAngle)")
    let reference = RotateEffectDefinition()
    reference.z.values = [AnimationValue(expectedAngle)]
    if let actual = renderImage(image: "quad.png", effects: [raw(definition)], frame: 3),
       let expected = renderImage(image: "quad.png", effects: [raw(reference)], frame: 3) {
        checkSimilar(actual, expected, tolerance: 4, "randomrotate: matches Rotate at computed angle")
    } else { check(false, "randomrotate: rendered") }
}

// MARK: - ケース27: RepeatRotate（Span=0、奇数フレーム = to、偶数 = from）

do {
    let definition = RepeatRotateEffectDefinition()
    definition.z.values = [AnimationValue(90)]
    definition.span.values = [AnimationValue(0)]
    // IsCentering（既定 true）の中心化 −(to−from)/2 を切って単純な
    // 偶奇規則だけを照合する（中心化込みの挙動は本家式どおり別途計算済み）。
    definition.isCentering = false
    let reference = RotateEffectDefinition()
    reference.z.values = [AnimationValue(90)]
    if let actual = renderImage(image: "quad.png", effects: [raw(definition)], frame: 1),
       let expected = renderImage(image: "quad.png", effects: [raw(reference)], frame: 1) {
        checkSimilar(actual, expected, tolerance: 4, "repeatrotate: odd frame = Rotate 90")
    } else { check(false, "repeatrotate odd: rendered") }
    if let actual = renderImage(image: "quad.png", effects: [raw(definition)], frame: 2),
       let expected = renderImage(image: "quad.png", effects: [], frame: 2) {
        checkSimilar(actual, expected, tolerance: 4, "repeatrotate: even frame = unrotated")
    } else { check(false, "repeatrotate even: rendered") }
}

// MARK: - ケース28: RandomSkew / RepeatSkew（参照 = Skew）

do {
    let definition = RandomSkewEffectDefinition()
    definition.angleX.values = [AnimationValue(90)]
    definition.angleY.values = [AnimationValue(0)]
    definition.span.values = [AnimationValue(0)]
    let rate = StatelessRandom.getDouble(keys: [0, 0, 5, 0])
    let expectedAngle = 90 * rate - 45
    print("  randomskew: rate=\(rate) expected angleX=\(expectedAngle)")
    let reference = SkewEffectDefinition()
    reference.angleX.values = [AnimationValue(expectedAngle)]
    if let actual = renderImage(image: "edge.png", effects: [raw(definition)], frame: 5),
       let expected = renderImage(image: "edge.png", effects: [raw(reference)], frame: 5) {
        checkSimilar(actual, expected, tolerance: 4, "randomskew: matches Skew at computed angle")
    } else { check(false, "randomskew: rendered") }

    let repeating = RepeatSkewEffectDefinition()
    repeating.angleX.values = [AnimationValue(45)]
    repeating.span.values = [AnimationValue(0)]
    repeating.isCentering = false
    let skewReference = SkewEffectDefinition()
    skewReference.angleX.values = [AnimationValue(45)]
    if let actual = renderImage(image: "edge.png", effects: [raw(repeating)], frame: 1),
       let expected = renderImage(image: "edge.png", effects: [raw(skewReference)], frame: 1) {
        checkSimilar(actual, expected, tolerance: 4, "repeatskew: odd frame = Skew 45")
    } else { check(false, "repeatskew: rendered") }
}

// MARK: - ケース29: InOutSkew（入り際フレーム0 = Skew 45 と一致）

do {
    let definition = InOutSkewEffectDefinition()
    definition.angleX = 45
    definition.isOutEffect = false
    let reference = SkewEffectDefinition()
    reference.angleX.values = [AnimationValue(45)]
    if let actual = renderImage(image: "edge.png", effects: [raw(definition)], frame: 0),
       let expected = renderImage(image: "edge.png", effects: [raw(reference)], frame: 0) {
        checkSimilar(actual, expected, tolerance: 4, "inoutskew: frame 0 = Skew 45")
    } else { check(false, "inoutskew: rendered") }
}

// MARK: - ケース30: DrawLazy（回転の焼き込みは通常描画と等価）

do {
    let lazy = DrawLazyEffectEffectDefinition()
    lazy.isRotation = true
    if let actual = renderImage(
        image: "quad.png", effects: [raw(lazy), raw(InvertEffectDefinition())],
        configureItem: { item in item.rotation.values = [AnimationValue(90)] }
    ),
    let expected = renderImage(
        image: "quad.png", effects: [raw(InvertEffectDefinition())],
        configureItem: { item in item.rotation.values = [AnimationValue(90)] }
    ) {
        checkSimilar(actual, expected, tolerance: 4, "drawlazy: baked rotation equals plain rotation")
    } else { check(false, "drawlazy: rendered") }
}

// MARK: - ケース31: InOutJump（長尺アイテム、中盤は静止）

do {
    let definition = InOutJumpEffectDefinition()
    definition.effectTimeSeconds = 1
    definition.x = 0
    if let frame0 = renderImage(image: "solid32.png", effects: [raw(definition)], frame: 0, length: 300) {
        // 本家式の手計算（EffectTime=1, frame 0）: time=1, 位相 0.2 は
        // インターバル内 → num8 = −4·sin(2π/3) ≈ −3.46, Zoom.Y ≈ 0.783,
        // Zoom.X = 1/0.783 ≈ 1.276（面積保存）。被覆 ≈ 32×40.8 の交差
        // ≈ 1023。本家の X 補正を見落とした旧期待値（785）は誤り。
        print("  inoutjump f0: coverage=\(frame0.nonTransparent) want ~1023 (squash + X compensation)")
        check((960...1070).contains(frame0.nonTransparent), "inoutjump: frame 0 in distortion phase")
    } else { check(false, "inoutjump f0: rendered") }
    if let frame150 = renderImage(image: "solid32.png", effects: [raw(definition)], frame: 150, length: 300) {
        print("  inoutjump f150: coverage=\(frame150.nonTransparent) want ~1024")
        check(abs(frame150.nonTransparent - 1024) <= 130, "inoutjump: mid at rest")
    } else { check(false, "inoutjump f150: rendered") }
}

// MARK: - ケース32: 伝播（シーン内部の子へ GPU エフェクトが効く）

do {
    let sub = makeTimeline()
    let child = ShapeItem()
    child.frame = 0
    child.length = 90
    child.layer = 0
    child.videoEffects = [raw(InvertEffectDefinition())]
    sub.items = [child]
    let main = makeTimeline()
    let sceneItem = SceneItem()
    sceneItem.sceneId = sub.id
    sceneItem.frame = 0
    sceneItem.length = 90
    sceneItem.layer = 0
    main.items = [sceneItem]
    let box = ComposerBox(timeline: main, timelines: [main, sub])
    if let frame = box.render(frame: 0) {
        // 子の白図形が内部合成で反転されていれば中心は黒。
        checkPixel(frame, 32, 32, r: 0, g: 0, b: 0, tolerance: 4, "propagation-scene: inner invert applied")
    } else { check(false, "propagation-scene: rendered") }
    box.composer.dispose()
}

// MARK: - ケース33: 伝播（合成グループ内部の子へ GPU エフェクトが効く）

do {
    let timeline = makeTimeline()
    let group = GroupItem()
    group.frame = 0
    group.length = 90
    group.layer = 0
    group.groupRange = 10
    group.isComposite = true
    let child = ShapeItem()
    child.frame = 0
    child.length = 90
    child.layer = 1
    child.videoEffects = [raw(InvertEffectDefinition())]
    timeline.items = [group, child]
    let box = ComposerBox(timeline: timeline)
    if let frame = box.render(frame: 0) {
        checkPixel(frame, 32, 32, r: 0, g: 0, b: 0, tolerance: 4, "propagation-group: inner invert applied")
    } else { check(false, "propagation-group: rendered") }
    box.composer.dispose()
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
