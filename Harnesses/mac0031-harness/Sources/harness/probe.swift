import CoreGraphics
import Foundation
import ImageIO
import YMM4Core
import YMM4GPU

// 分割テキストの合成チェック: 縁取りスタイル付き・複数行でも、ピースが
// 完全なグリフ（＋縁取り）を含むことを確認する。
func runDividedProbe() {
    let devices = try! MetalGraphicsDevices()
    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: 60, hz: 48_000, width: 1920, height: 1080)
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 1920, height: 1080),
        timelinePosition: FramePosition(frame: 0, fps: 60),
        timelineDuration: FramePosition(frame: 90, fps: 60),
        fps: 60, usage: .paused, sceneId: UUID(), scenes: []
    )
    func checkCase(_ label: String, text: String, style: TextStyle) {
        let item = TextItem()
        item.text = text
        item.frame = 0
        item.length = 90
        item.layer = 0
        item.appearance.fontSize = YMM4Core.Animation(
            defaultValue: 100, minValue: 1, maxValue: 1000
        )
        item.appearance.isDevidedPerCharacter = true
        item.appearance.style = style
        item.appearance.basePoint = .centerCenter
        let description = TimelineItemSourceDescription(
            base, itemFrame: 0, itemLength: 90, layer: 0
        )
        let source = MetalTextSource(devices: devices, item: item)
        do {
            try source.update(description)
            print("divprobe[\(label)]: outputs=\(source.outputs.count)")
            for (index, output) in source.outputs.enumerated() {
                if let metal = devices.image(for: output.output),
                   let cg = MetalGraphicsDevices.makeCGImage(from: metal.texture) {
                    profile(cg, label: "divprobe[\(label)]-\(index)")
                    if index == 0 {
                        probeWritePNG(cg, "divprobe-\(label)-0.png")
                    }
                }
            }
        } catch {
            print("divprobe[\(label)]: error \(error)")
        }
        source.dispose()
    }
    checkCase("border", text: "同志", style: .border)
    checkCase("shadow", text: "同志", style: .shadow)
    checkCase("multiline", text: "同志が\n描いた", style: .normal)
}

// 画像アイテム単体の切り分け（mac0023 ハーネスの control ケース相当）。
// 64x64 の単色 PNG を作り、(1) MetalImageSource 単体の出力テクスチャ、
// (2) TimelineComposer のフル合成、の両方をダンプする。
func probeWritePNG(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: "/tmp/mac0031-out").appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    ) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    _ = CGImageDestinationFinalize(dest)
}

func runImageProbe() {
    let workDir = URL(fileURLWithPath: "/tmp/mac0031-imgprobe")
    try! FileManager.default.createDirectory(
        at: workDir, withIntermediateDirectories: true
    )
    // 単色 PNG (R200 G100 B50) を生成する。
    let w = 64, h = 64
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for i in 0..<(w * h) {
        bytes[i * 4 + 0] = 50   // B
        bytes[i * 4 + 1] = 100  // G
        bytes[i * 4 + 2] = 200  // R
        bytes[i * 4 + 3] = 255  // A
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cgImage = CGImage(
        width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ),
        provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent
    )!
    let pngURL = workDir.appendingPathComponent("solid.png")
    let dest = CGImageDestinationCreateWithURL(
        pngURL as CFURL, "public.png" as CFString, 1, nil
    )!
    CGImageDestinationAddImage(dest, cgImage, nil)
    print("probe: png written = \(CGImageDestinationFinalize(dest))")

    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: 30, hz: 44_100, width: 64, height: 64)
    let item = ImageItem()
    item.filePath = "solid.png"
    item.frame = 0
    item.length = 90
    item.layer = 0
    timeline.items = [item]

    let devices = try! MetalGraphicsDevices()
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 64, height: 64),
        timelinePosition: FramePosition(frame: 0, fps: 30),
        timelineDuration: FramePosition(frame: 90, fps: 30),
        fps: 30, usage: .paused, sceneId: UUID(), scenes: []
    )
    let description = TimelineItemSourceDescription(
        base, itemFrame: 0, itemLength: 90, layer: 0
    )

    // (1) Source 単体
    do {
        let source = MetalImageSource(
            devices: devices, item: item, baseDirectory: workDir
        )
        try source.update(description)
        print("probe: source outputs = \(source.outputs.count)")
        for output in source.outputs {
            if let metal = devices.image(for: output.output) {
                print("probe: source texture = \(metal.texture.width)x\(metal.texture.height) bounds=(\(metal.bounds.left),\(metal.bounds.top))-(\(metal.bounds.right),\(metal.bounds.bottom))")
                if let cg = MetalGraphicsDevices.makeCGImage(from: metal.texture) {
                    probeWritePNG(cg, "probe-source.png")
                    profile(cg, label: "probe-source")
                }
            } else {
                print("probe: source output has no metal image")
            }
        }
        source.dispose()
    } catch {
        print("probe: source error: \(error)")
    }

    // (2) フル合成
    do {
        let context = devices.makeContext(
            targetSize: PixelSize(width: 64, height: 64)
        )
        let provider2 = MetalSourceProvider(devices: devices, baseDirectory: workDir)
        let composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider2.source(for:),
            effectProvider: MetalEffectPairProvider(devices: devices)
        )
        try composer.update(
            time: TimeSpanValue(seconds: 0), usage: .paused
        )
        if let outRef = composer.output, let cg = devices.makeCGImage(from: outRef) {
            probeWritePNG(cg, "probe-full.png")
            profile(cg, label: "probe-full")
        } else {
            print("probe: composer output none")
        }
        composer.dispose()
    } catch {
        print("probe: composer error: \(error)")
    }
}
