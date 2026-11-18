import Foundation
import Metal
import YMM4Core
import YMM4GPU

// NOISE7 検証ハーネス: Noise 生成器（全10種のうち新規7種 +
// Fractal 照合）を MetalNoiseProcessor 経由で描画し、画素の
// バイト列を標準出力へ出す。期待値は本家シェーダの DXBC を
// 実行するインタプリタの出力（refs/ に凍結済み）で、
// 比較は compare.py が行う。実測結果は
// docs/IMPLEMENTATION_LOG.md の NOISE7 節に記録。

let devices: MetalGraphicsDevices
do {
    devices = try MetalGraphicsDevices()
} catch {
    print("FAIL: MetalGraphicsDevices init: \(error)")
    exit(1)
}
let context = devices.makeContext()

func makeDescription() -> EffectDescription {
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 32, height: 32),
        timelinePosition: FramePosition(frame: 0, fps: 30),
        timelineDuration: FramePosition(frame: 300, fps: 30),
        fps: 30, usage: .paused, sceneId: UUID(), scenes: []
    )
    let item = TimelineItemSourceDescription(base, itemFrame: 0, itemLength: 100, layer: 0)
    return EffectDescription(itemDescription: item, drawDescription: DrawDescription())
}

@MainActor
func makeInput(width: Int, height: Int) -> MetalImage {
    let bytes = [UInt8](repeating: 255, count: width * height * 4)
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

func readPixels(_ image: MetalImage) -> (width: Int, height: Int, bytes: [UInt8]) {
    let w = image.texture.width
    let h = image.texture.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { raw in
        image.texture.getBytes(
            raw.baseAddress!, bytesPerRow: w * 4,
            from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0
        )
    }
    return (w, h, bytes)
}

func animationJSON(_ value: Double) -> JSONValue {
    .object([
        (key: "Values", value: .array([.object([(key: "Value", value: .number(value))])])),
        (key: "Span", value: .number(0)),
        (key: "AnimationType", value: .string("なし")),
    ])
}

func buildDefinition(_ c: NoiseCase) -> NoiseEffectDefinition {
    let definition = NoiseEffectDefinition()
    definition.noiseType = c.type
    definition.isColor = c.isColor
    definition.isAlpha = !c.isColor
    var fields: [(key: String, value: JSONValue)] = [
        (key: "$type", value: .string(
            "YukkuriMovieMaker.Project.Effects.NoiseParameters.\(c.typeName)NoiseParameter, YukkuriMovieMaker"))
    ]
    for (key, value) in c.fields {
        fields.append((key: key, value: animationJSON(value)))
    }
    fields.append((key: "FractalMode", value: .string(c.fractalMode)))
    fields.append((key: "DistanceMode", value: .string(c.distanceMode)))
    fields.append((key: "OutputMode", value: .string(c.outputMode)))
    definition.noiseParameter = PreservedObject(.object(fields))
    return definition
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

for c in noiseCases {
    let input = makeInput(width: 32, height: 32)
    let processor = MetalNoiseProcessor(
        context: context, definition: buildDefinition(c))
    guard let output = run(processor, input: input) else {
        print("CASE \(c.name) RENDER-FAILED")
        processor.dispose()
        continue
    }
    let img = readPixels(output)
    func channel(_ offset: Int) -> String {
        var vals: [String] = []
        for y in 0..<32 {
            for x in 0..<32 {
                vals.append(String(img.bytes[(y * 32 + x) * 4 + offset]))
            }
        }
        return vals.joined(separator: ",")
    }
    // BGRA バイト順: B = +0, G = +1, R = +2。
    print("CASE \(c.name)")
    print("R \(channel(2))")
    if c.isColor {
        print("G \(channel(1))")
        print("B \(channel(0))")
    }
    processor.dispose()
}
