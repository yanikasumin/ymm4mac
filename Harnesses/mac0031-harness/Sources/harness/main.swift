import CoreGraphics
import CoreText
import Foundation
import ImageIO
import YMM4Core
import YMM4GPU

// MAC-0031: 実ファイルのテキスト描画（文字分割）の帯状化を切り分ける。
// 段階: (a) Source 単体 → (b) EffectedItemSource → (c) フル合成。
// あわせて分割 OFF の同条件コピーと、CoreText 直接描画の参照を出す。
// 出力 PNG は全て outDir へ。数値プロファイル（行ごとの不透明量）を
// 標準出力へ出し、形状を目視だけでなく数値でも追えるようにする。

let args = CommandLine.arguments
if args.count >= 2, args[1] == "imgprobe" {
    try! FileManager.default.createDirectory(
        atPath: "/tmp/mac0031-out", withIntermediateDirectories: true
    )
    runImageProbe()
    exit(0)
}
if args.count >= 2, args[1] == "divprobe" {
    try! FileManager.default.createDirectory(
        atPath: "/tmp/mac0031-out", withIntermediateDirectories: true
    )
    runDividedProbe()
    exit(0)
}
guard args.count >= 3 else {
    print("usage: harness <ymmp> <frame> [outDir] | harness imgprobe")
    exit(2)
}
let ymmpPath = args[1]
let targetFrame = Int(args[2]) ?? 2810
let outDir = args.count >= 4 ? args[3] : "/tmp/mac0031-out"
try! FileManager.default.createDirectory(
    atPath: outDir, withIntermediateDirectories: true
)

func writePNG(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    ) else { print("PNG dest failed: \(name)"); return }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { print("PNG write failed: \(name)") }
}

/// CGImage を BGRA バイト列へ（行0 = 画像の上端）。
func readPixels(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = bytes.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (bytes, width, height)
}

/// 不透明ピクセルの外接矩形と、行プロファイルの要約を出す。
func profile(_ image: CGImage, label: String) {
    let (bytes, width, height) = readPixels(of: image)
    var minX = width, minY = height, maxX = -1, maxY = -1
    var rowCounts = [Int](repeating: 0, count: height)
    var total = 0
    for y in 0..<height {
        var row = 0
        for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 10 {
            row += 1
            if x < minX { minX = x }
            if x > maxX { maxX = x }
        }
        rowCounts[y] = row
        if row > 0 {
            if y < minY { minY = y }
            if y > maxY { maxY = y }
            total += row
        }
    }
    if maxX < 0 {
        print("  [\(label)] size=\(width)x\(height) EMPTY")
        return
    }
    print("  [\(label)] size=\(width)x\(height) ink=\(total) bbox=x:\(minX)...\(maxX) y:\(minY)...\(maxY) (w=\(maxX - minX + 1) h=\(maxY - minY + 1))")
    // 行プロファイル（10行ごとの最大値）で帯の位置と厚さを見る。
    var summary: [String] = []
    var y = 0
    while y < height {
        let end = min(y + 10, height)
        let peak = rowCounts[y..<end].max() ?? 0
        summary.append("\(y):\(peak)")
        y = end
    }
    print("    rows(10行ごとの最大): \(summary.joined(separator: " "))")
}

func crop(_ image: CGImage, x: Int, y: Int, w: Int, h: Int) -> CGImage? {
    let rect = CGRect(x: x, y: y, width: w, height: h)
        .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
    return image.cropping(to: rect)
}

// MARK: - 読み込みと対象アイテムの特定

let (project, diagnostics) = try YmmpCodec.load(fromFile: ymmpPath)
print("skipped=\(diagnostics.skippedItems.count) migrated=\(diagnostics.migratedTypeNames.count)")
let timeline = project.timelines[0]
let vi = timeline.videoInfo
print("timeline: \(vi.width)x\(vi.height) \(vi.fps)fps length=\(timeline.length) items=\(timeline.items.count)")

var target: TextItem?
for item in timeline.items {
    guard item.frame <= targetFrame, targetFrame < item.frame + item.length else { continue }
    if let text = item as? TextItem {
        let a = text.appearance
        print("TextItem @frame \(targetFrame): text=\(text.text) frame=\(text.frame) len=\(text.length) layer=\(text.layer) font=\(a.font) size=\(a.fontSize.value(atFrame: targetFrame - text.frame, length: text.length, fps: vi.fps)) divided=\(a.isDevidedPerCharacter) basePoint=\(a.basePoint.honkeName) style=\(a.style.honkeName) effects=\(text.videoEffects.count)")
        if text.text.contains("同志") { target = text }
    }
}
guard let item = target else {
    print("対象の TextItem が見つからない")
    exit(1)
}
print("effects(raw): \(item.videoEffects.map { $0.typeName ?? "?" })")
let decodedEffects = item.videoEffects.compactMap { VideoEffectRegistry.decode($0) }
print("effects(decoded): \(decodedEffects.map { String(describing: type(of: $0)) })")

let devices = MetalGraphicsDevices()!
let baseDirectory = URL(fileURLWithPath: ymmpPath).deletingLastPathComponent()
let scene = TimelineScene(timeline: timeline)
let base = TimelineSourceDescription(
    screenSize: PixelSize(width: vi.width, height: vi.height),
    timelinePosition: FramePosition(frame: targetFrame, fps: vi.fps),
    timelineDuration: FramePosition(frame: timeline.length, fps: vi.fps),
    fps: vi.fps, usage: .paused, sceneId: scene.sceneID, scenes: [scene]
)
let itemFrame = targetFrame - item.frame
let description = TimelineItemSourceDescription(
    base, itemFrame: itemFrame, itemLength: item.length, layer: item.layer
)

// MARK: - (a) Source 単体

var pieceImages: [CGImage] = []
var nodivImage: CGImage?
print("== (a) MetalTextSource 単体 ==")
do {
    let provider = MetalSourceProvider(devices: devices, baseDirectory: baseDirectory)
    let source = provider.source(for: item)
    try source.update(description)
    print("outputs: \(source.outputs.count)")
    for (index, output) in source.outputs.enumerated() {
        guard let metal = devices.image(for: output.output) else {
            print("  output \(index): no metal image")
            continue
        }
        print("  output \(index): texture=\(metal.texture.width)x\(metal.texture.height) bounds=(\(metal.bounds.left),\(metal.bounds.top))-(\(metal.bounds.right),\(metal.bounds.bottom)) drawingOffset=(\(output.drawingOffset.x),\(output.drawingOffset.y)) center=(\(output.center.x),\(output.center.y))")
        if let cg = MetalGraphicsDevices.makeCGImage(from: metal.texture) {
            writePNG(cg, "a-piece-\(index).png")
            profile(cg, label: "a-piece-\(index)")
            pieceImages.append(cg)
        }
    }
    source.dispose()
} catch {
    print("  (a) error: \(error)")
}

// MARK: - (a2) 分割 OFF の同条件コピー

print("== (a2) 分割 OFF コピー ==")
do {
    let off = TextItem()
    off.text = item.text
    off.decorations = item.decorations
    off.appearance = item.appearance
    off.appearance.isDevidedPerCharacter = false
    off.frame = item.frame
    off.length = item.length
    off.layer = item.layer
    off.x = item.x
    off.y = item.y
    off.z = item.z
    off.opacity = item.opacity
    off.zoom = item.zoom
    off.rotation = item.rotation
    let source = MetalTextSource(devices: devices, item: off)
    try source.update(description)
    print("outputs: \(source.outputs.count)")
    for (index, output) in source.outputs.enumerated() {
        guard let metal = devices.image(for: output.output) else { continue }
        print("  output \(index): texture=\(metal.texture.width)x\(metal.texture.height) bounds=(\(metal.bounds.left),\(metal.bounds.top))-(\(metal.bounds.right),\(metal.bounds.bottom))")
        if let cg = MetalGraphicsDevices.makeCGImage(from: metal.texture) {
            writePNG(cg, "a2-nodiv-\(index).png")
            profile(cg, label: "a2-nodiv-\(index)")
            if index == 0 { nodivImage = cg }
        }
    }
    source.dispose()
} catch {
    print("  (a2) error: \(error)")
}

// MARK: - (a3) 分割ピース vs 分割 OFF 全体像の形状重なり
//
// 分割 OFF のテクスチャではグリフ i のペンは x = pad + advance*i にある。
// 分割ピースではペンは x = pad。したがってピースの中央 advance 幅と、
// 分割 OFF 側の (pad + advance*i) を中心とする advance 幅は、同じグリフの
// 同じ描画になるはずで、alpha マスクの IoU が高いことを確認する。

print("== (a3) ピース形状の重なり検証 ==")
if let nodiv = nodivImage, !pieceImages.isEmpty {
    let (nodivBytes, nodivW, nodivH) = readPixels(of: nodiv)
    let advance = 100.0
    let pad = 17.0
    for (index, piece) in pieceImages.enumerated() {
        let (pieceBytes, pieceW, pieceH) = readPixels(of: piece)
        // 比較窓: どちらのテクスチャでもグリフはペン位置から advance
        // 幅に描かれる。ピースのペンは x = (W - advance)/2 + ... ではなく
        // boundsLeft の反転で pad 相当 (17)、分割 OFF では pad + advance*i。
        let pieceX0 = Int(pad)
        let nodivX0 = Int(pad + advance * Double(index))
        var intersection = 0
        var union = 0
        let h = min(pieceH, nodivH)
        for y in 0..<h {
            for dx in 0..<Int(advance) {
                let pa = pieceBytes[(y * pieceW + pieceX0 + dx) * 4 + 3] > 10
                let nx = nodivX0 + dx
                let na = nx >= 0 && nx < nodivW
                    && nodivBytes[(y * nodivW + nx) * 4 + 3] > 10
                if pa && na { intersection += 1 }
                if pa || na { union += 1 }
            }
        }
        let iou = union > 0 ? Double(intersection) / Double(union) : 0
        print("  piece \(index): IoU=\(String(format: "%.3f", iou)) (intersection=\(intersection) union=\(union))")
    }
} else {
    print("  比較材料が揃わない")
}

// MARK: - (b) EffectedItemSource 経由

print("== (b) EffectedItemSource（OutlineEffect 含む） ==")
do {
    let context = devices.makeContext(
        targetSize: PixelSize(width: vi.width, height: vi.height)
    )
    let provider = MetalSourceProvider(devices: devices, baseDirectory: baseDirectory)
    let source = provider.source(for: item)
    let effected = EffectedItemSource(
        item: item, source: source, targetFactory: context,
        effectProvider: MetalEffectPairProvider(devices: devices)
    )
    try effected.update(description)
    if let outRef = effected.output, let metal = devices.image(for: outRef) {
        print("  effected output: texture=\(metal.texture.width)x\(metal.texture.height) bounds=(\(metal.bounds.left),\(metal.bounds.top))-(\(metal.bounds.right),\(metal.bounds.bottom)) planeRect=(\(metal.texturePlaneRect.left),\(metal.texturePlaneRect.top))-(\(metal.texturePlaneRect.right),\(metal.texturePlaneRect.bottom))")
        if let cg = MetalGraphicsDevices.makeCGImage(from: metal.texture) {
            writePNG(cg, "b-effected.png")
            profile(cg, label: "b-effected")
            // 中央帯の切り出し（テキストがあるはずの領域）。
            if let c = crop(cg, x: 300, y: 300, w: 1300, h: 500) {
                writePNG(c, "b-effected-crop.png")
            }
        }
    } else {
        print("  effected output: none")
    }
    effected.dispose()
} catch {
    print("  (b) error: \(error)")
}

// MARK: - (c) フル合成

print("== (c) TimelineComposer フル合成 ==")
do {
    let context = devices.makeContext(
        targetSize: PixelSize(width: vi.width, height: vi.height)
    )
    let provider = MetalSourceProvider(
        devices: devices, baseDirectory: baseDirectory,
        sceneResolver: { id in project.timelines.first { $0.id == id } },
        timeline: timeline
    )
    let composer = TimelineComposer(
        scene: TimelineScene(timeline: timeline),
        targetFactory: context,
        sourceProvider: provider.source(for:),
        effectProvider: MetalEffectPairProvider(devices: devices)
    )
    try composer.update(
        time: TimeSpanValue(seconds: FrameTime.time(fromFrame: targetFrame, fps: vi.fps)),
        usage: .paused
    )
    if let outRef = composer.output, let cg = devices.makeCGImage(from: outRef) {
        writePNG(cg, "c-full.png")
        profile(cg, label: "c-full")
        if let c = crop(cg, x: 300, y: 300, w: 1300, h: 500) {
            writePNG(c, "c-full-crop.png")
            profile(c, label: "c-full-crop")
        }
    } else {
        print("  composer output: none")
    }
    composer.dispose()
} catch {
    print("  (c) error: \(error)")
}

// MARK: - 参照: CoreText 直接描画

print("== 参照: CoreText 直接描画 ==")
do {
    let fontName = item.appearance.font
    let font = CTFontCreateWithName(fontName as CFString, 100, nil)
    let resolvedName = CTFontCopyPostScriptName(font) as String
    print("  CTFontCreateWithName(\(fontName)) -> \(resolvedName) ascent=\(CTFontGetAscent(font)) descent=\(CTFontGetDescent(font))")
    let text = item.text as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
    ]
    let attributed = NSAttributedString(string: text as String, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    print("  line width=\(lineWidth) ascent=\(ascent) descent=\(descent)")
    let w = Int(ceil(lineWidth)) + 40
    let h = Int(ceil(ascent + descent)) + 40
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let bitmap = CGContext(
            data: buffer.baseAddress, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return false }
        // 左下原点・y-up の素直な描画（ベースラインは下から descent+20）。
        bitmap.textPosition = CGPoint(x: 20, y: 20 + descent)
        CTLineDraw(line, bitmap)
        return true
    }
    if drawn {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            ),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
        writePNG(cg, "ref-coretext.png")
        profile(cg, label: "ref-coretext")
    }
}

print("done -> \(outDir)")
