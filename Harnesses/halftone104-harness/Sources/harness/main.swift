import Foundation
import Metal
import YMM4Core
import YMM4GPU

// Issue #104: HalfTone の期待値を修正済み DXBC インタプリタで
// 再生成し、実描画と比較する。ケースは gpu45-harness の K/L/M と
// 同一条件（K=菱形、L=矩形、M=三角）。出力テクスチャ全画素を
// 乗算済みバイトの CSV で /tmp/ht104/ へ書き出す。

let devices = try! MetalGraphicsDevices()
let context = devices.makeContext()

func makeDescription() -> EffectDescription {
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 64, height: 64),
        timelinePosition: FramePosition(frame: 0, fps: 30),
        timelineDuration: FramePosition(frame: 300, fps: 30),
        fps: 30, usage: .paused, sceneId: UUID(), scenes: []
    )
    let item = TimelineItemSourceDescription(base, itemFrame: 0, itemLength: 100, layer: 0)
    return EffectDescription(itemDescription: item, drawDescription: DrawDescription())
}

@MainActor
func makeInput(width: Int, height: Int, fill: (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> MetalImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let p = fill(x, y)
            let i = (y * width + x) * 4
            bytes[i] = p.b; bytes[i + 1] = p.g; bytes[i + 2] = p.r; bytes[i + 3] = p.a
        }
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    descriptor.usage = [.shaderRead, .renderTarget]
    descriptor.storageMode = .shared
    let texture = devices.device.makeTexture(descriptor: descriptor)!
    bytes.withUnsafeBytes { raw in
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: raw.baseAddress!, bytesPerRow: width * 4
        )
    }
    return MetalImage(
        texture: texture,
        bounds: RectF(left: 0, top: 0, right: Double(width), bottom: Double(height))
    )
}

@MainActor
func run(_ processor: MetalEffectProcessor, input: MetalImage) -> MetalImage? {
    let reference = ImageReference(label: "harness-input")
    devices.register(reference, image: input)
    processor.setInput(reference)
    do {
        _ = try processor.update(makeDescription())
    } catch {
        print("processor error: \(error)")
        return nil
    }
    guard let output = processor.output else { return nil }
    return devices.image(for: output)
}

func const(_ value: Double, _ minV: Double, _ maxV: Double) -> Animation {
    Animation(defaultValue: value, minValue: minV, maxValue: maxV)
}

func dumpCSV(_ name: String, _ image: MetalImage) {
    let w = image.texture.width
    let h = image.texture.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { raw in
        image.texture.getBytes(
            raw.baseAddress!, bytesPerRow: w * 4,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0
        )
    }
    var lines: [String] = []
    for y in 0..<h {
        var cells: [String] = []
        for x in 0..<w {
            let i = (y * w + x) * 4
            // BGRA 乗算済みバイトを r:g:b:a 順で出す。
            cells.append("\(bytes[i + 2]):\(bytes[i + 1]):\(bytes[i]):\(bytes[i + 3])")
        }
        lines.append(cells.joined(separator: ","))
    }
    let dir = "/tmp/ht104"
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try! lines.joined(separator: "\n").write(
        toFile: "\(dir)/\(name).csv", atomically: true, encoding: .utf8
    )
    print("dumped \(name): \(w)x\(h) bounds=\(image.bounds)")
}

@MainActor
func runCase(
    name: String, layout: HalfToneLayout, size: Int, square: (Int, Int, Int, Int),
    distance: Double, color: Color
) {
    let input = makeInput(width: size, height: size) { x, y in
        (x >= square.0 && x < square.2 && y >= square.1 && y < square.3)
            ? (255, 255, 255, 255) : (0, 0, 0, 0)
    }
    let definition = HalfToneShadowEffectDefinition()
    definition.layout = layout
    definition.distance = const(distance, 0.1, 500)
    definition.size = const(100, 0, 100)
    definition.strength = const(100, 0, 100)
    definition.color = color
    definition.blur = const(0, 0, 250)
    let processor = MetalHalfToneShadowProcessor(context: context, definition: definition)
    if let output = run(processor, input: input) {
        dumpCSV(name, output)
    } else {
        print("FAIL: \(name) rendered")
        exit(1)
    }
    processor.dispose()
}

runCase(
    name: "halftone-rhombus", layout: .rhombus, size: 32,
    square: (8, 8, 24, 24), distance: 6.1,
    color: Color(alpha: 255, red: 255, green: 0, blue: 0)
)
runCase(
    name: "halftone-rectangle", layout: .rectangle, size: 24,
    square: (4, 4, 20, 20), distance: 4,
    color: Color(alpha: 255, red: 0, green: 0, blue: 0)
)
runCase(
    name: "halftone-triangle", layout: .triangle, size: 32,
    square: (8, 8, 24, 24), distance: 6.1,
    color: Color(alpha: 255, red: 255, green: 0, blue: 0)
)
runCase(
    name: "halftone-triangle-d43", layout: .triangle, size: 32,
    square: (6, 6, 26, 26), distance: 4.3,
    color: Color(alpha: 255, red: 255, green: 0, blue: 0)
)
print("HT104-DONE")
