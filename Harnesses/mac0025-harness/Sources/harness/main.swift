import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Metal
import YMM4Core
import YMM4GPU

var failures = 0
@MainActor
func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { failures += 1 }
}

// MARK: - テスト動画の生成（64×48, 30fps, 2秒, 前半赤・後半青）

func makePixelBuffer(width: Int, height: Int, b: UInt8, g: UInt8, r: UInt8) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer
    )
    let pixelBuffer = buffer!
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let base = CVPixelBufferGetBaseAddress(pixelBuffer)!
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for row in 0..<height {
        var p = base.advanced(by: row * bytesPerRow)
        for _ in 0..<width {
            p.storeBytes(of: b, as: UInt8.self)
            p = p.advanced(by: 1)
            p.storeBytes(of: g, as: UInt8.self)
            p = p.advanced(by: 1)
            p.storeBytes(of: r, as: UInt8.self)
            p = p.advanced(by: 1)
            p.storeBytes(of: 255, as: UInt8.self)
            p = p.advanced(by: 1)
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    return pixelBuffer
}

func writeTestVideo(url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 48,
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input, sourcePixelBufferAttributes: nil
    )
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<60 {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.005)
        }
        let isRed = frame < 30
        let buffer = isRed
            ? makePixelBuffer(width: 64, height: 48, b: 0, g: 0, r: 255)
            : makePixelBuffer(width: 64, height: 48, b: 255, g: 0, r: 0)
        let time = CMTime(value: CMTimeValue(frame), timescale: 30)
        adaptor.append(buffer, withPresentationTime: time)
    }
    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { semaphore.signal() }
    semaphore.wait()
    if writer.status != .completed {
        throw NSError(domain: "harness", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "video write failed: \(String(describing: writer.error))",
        ])
    }
}

// MARK: - 合成と読み戻し

final class ComposerBox {
    let devices: MetalGraphicsDevices
    let context: MetalGraphicsContext
    let provider: MetalSourceProvider
    let composer: TimelineComposer

    init(
        timeline: Timeline, timelines: [Timeline],
        tachieFactory: (any MetalTachieRendererFactory)? = nil
    ) {
        devices = try! MetalGraphicsDevices()
        context = devices.makeContext(
            targetSize: PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
        )
        provider = MetalSourceProvider(
            devices: devices,
            sceneResolver: { id in timelines.first { $0.id == id } },
            tachieRendererFactory: tachieFactory
        )
        composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider.source(for:)
        )
    }

    func render(frame: Int, fps: Int) -> CGImage? {
        do {
            try composer.update(
                time: TimeSpanValue(seconds: FrameTime.time(fromFrame: frame, fps: fps)),
                usage: .paused
            )
        } catch {
            print("composer update error: \(error)")
            return nil
        }
        guard let output = composer.output else { return nil }
        return devices.makeCGImage(from: output)
    }
}

struct PixelStats {
    var nonTransparent: Int
    var centerR: Int
    var centerG: Int
    var centerB: Int
    var centerA: Int
}

func stats(of image: CGImage) -> PixelStats {
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
    var count = 0
    for i in 0..<(width * height) where bytes[i * 4 + 3] > 10 {
        count += 1
    }
    let center = (height / 2 * width + width / 2) * 4
    return PixelStats(
        nonTransparent: count,
        centerR: Int(bytes[center + 2]), centerG: Int(bytes[center + 1]),
        centerB: Int(bytes[center]), centerA: Int(bytes[center + 3])
    )
}

func makeTimeline(width: Int, height: Int, fps: Int = 30) -> Timeline {
    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: fps, hz: 44_100, width: width, height: height)
    return timeline
}

// MARK: - ケース1: 動画

let videoURL = URL(fileURLWithPath: "/tmp/mac0025-test.mp4")
do {
    try writeTestVideo(url: videoURL)
    check(true, "test video written")
} catch {
    check(false, "test video written (\(error))")
}

do {
    let timeline = makeTimeline(width: 128, height: 96)
    let item = VideoItem()
    item.filePath = videoURL.path
    item.frame = 0
    item.length = 60
    item.layer = 0
    timeline.items = [item]
    let box = ComposerBox(timeline: timeline, timelines: [timeline])

    let providerSource = box.provider.source(for: item)
    check(providerSource is MetalVideoSource, "provider returns MetalVideoSource for VideoItem")
    providerSource.dispose()

    if let image = box.render(frame: 0, fps: 30) {
        let s = stats(of: image)
        print("  frame0: nonTransparent=\(s.nonTransparent) center=(\(s.centerR),\(s.centerG),\(s.centerB),\(s.centerA))")
        check(abs(s.nonTransparent - 3072) <= 128, "video frame 0 coverage ~3072")
        check(s.centerR > 200 && s.centerG < 60 && s.centerB < 60, "video frame 0 center is red")
    } else {
        check(false, "video frame 0 rendered")
    }
    if let image = box.render(frame: 45, fps: 30) {
        let s = stats(of: image)
        print("  frame45: nonTransparent=\(s.nonTransparent) center=(\(s.centerR),\(s.centerG),\(s.centerB),\(s.centerA))")
        check(s.centerB > 200 && s.centerR < 60 && s.centerG < 60, "video frame 45 center is blue")
    } else {
        check(false, "video frame 45 rendered")
    }
    box.composer.dispose()
}

// MARK: - ケース2: シーン入れ子

do {
    let timelineB = makeTimeline(width: 200, height: 200)
    let shape = ShapeItem()
    shape.frame = 0
    shape.length = 90
    shape.layer = 0
    timelineB.items = [shape]

    let timelineA = makeTimeline(width: 200, height: 200)
    let sceneItem = SceneItem()
    sceneItem.sceneId = timelineB.id
    sceneItem.frame = 0
    sceneItem.length = 90
    sceneItem.layer = 0
    timelineA.items = [sceneItem]

    let box = ComposerBox(timeline: timelineA, timelines: [timelineA, timelineB])
    let providerSource = box.provider.source(for: sceneItem)
    check(providerSource is MetalSceneSource, "provider returns MetalSceneSource for SceneItem")
    providerSource.dispose()

    if let image = box.render(frame: 0, fps: 30) {
        let s = stats(of: image)
        print("  scene: nonTransparent=\(s.nonTransparent) center=(\(s.centerR),\(s.centerG),\(s.centerB),\(s.centerA))")
        check(abs(s.nonTransparent - 10000) <= 400, "scene coverage ~10000")
        check(s.centerA > 250 && s.centerR > 200, "scene center is opaque white shape")
    } else {
        check(false, "scene rendered")
    }
    box.composer.dispose()
}

// MARK: - ケース3: フレームバッファ

do {
    let timeline = makeTimeline(width: 200, height: 200)
    let shape = ShapeItem()
    shape.frame = 0
    shape.length = 90
    shape.layer = 0
    let frameBuffer = FrameBufferItem()
    frameBuffer.frame = 0
    frameBuffer.length = 90
    frameBuffer.layer = 1
    frameBuffer.clearBackground = true
    frameBuffer.isAlphaEnabled = true
    timeline.items = [shape, frameBuffer]

    let box = ComposerBox(timeline: timeline, timelines: [timeline])
    let providerSource = box.provider.source(for: frameBuffer)
    check(providerSource is MetalFrameBufferSource, "provider returns MetalFrameBufferSource for FrameBufferItem")
    providerSource.dispose()

    if let image = box.render(frame: 0, fps: 30) {
        let s = stats(of: image)
        print("  framebuffer: nonTransparent=\(s.nonTransparent) center=(\(s.centerR),\(s.centerG),\(s.centerB),\(s.centerA))")
        check(abs(s.nonTransparent - 10000) <= 400, "framebuffer keeps accumulated ~10000")
        check(s.centerA > 250, "framebuffer center is opaque")
    } else {
        check(false, "framebuffer rendered")
    }
    box.composer.dispose()
}

// MARK: - ケース4: 立ち絵（テストレンダラ注入）

final class TestTachieRenderer: MetalTachieRenderer {
    let reference = ImageReference(label: "test-tachie")
    private(set) var lastDescription: MetalTachieUpdateDescription?

    init(devices: MetalGraphicsDevices) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 50, height: 50, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        let texture = devices.device.makeTexture(descriptor: descriptor)!
        var bytes = [UInt8](repeating: 0, count: 50 * 50 * 4)
        for i in 0..<(50 * 50) {
            bytes[i * 4] = 255      // B
            bytes[i * 4 + 1] = 0    // G
            bytes[i * 4 + 2] = 255  // R
            bytes[i * 4 + 3] = 255  // A
        }
        bytes.withUnsafeBytes { buffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 50, 50), mipmapLevel: 0,
                withBytes: buffer.baseAddress!, bytesPerRow: 50 * 4
            )
        }
        devices.register(
            reference,
            image: MetalImage(
                texture: texture,
                bounds: RectF(left: -25, top: -25, right: 25, bottom: 25)
            )
        )
    }

    var output: ImageReference? { reference }

    func update(_ description: MetalTachieUpdateDescription) {
        lastDescription = description
    }

    func dispose() {}
}

final class TestTachieFactory: MetalTachieRendererFactory {
    var renderer: TestTachieRenderer?
    func makeRenderer(
        devices: MetalGraphicsDevices, tachieType: String?
    ) -> (any MetalTachieRenderer)? {
        let renderer = TestTachieRenderer(devices: devices)
        self.renderer = renderer
        return renderer
    }
}

do {
    let character = Character()
    character.name = "テスト"
    character.tachieType = "test-type"

    let timeline = makeTimeline(width: 200, height: 200)
    let tachieItem = TachieItem()
    tachieItem.character = character
    tachieItem.characterName = "テスト"
    tachieItem.frame = 0
    tachieItem.length = 90
    tachieItem.layer = 0
    let faceItem = TachieFaceItem()
    faceItem.character = character
    faceItem.characterName = "テスト"
    faceItem.frame = 0
    faceItem.length = 90
    faceItem.layer = 5
    let voiceItem = VoiceItem()
    voiceItem.character = character
    voiceItem.characterName = "テスト"
    voiceItem.frame = 0
    voiceItem.length = 90
    voiceItem.layer = 3
    timeline.items = [tachieItem, faceItem, voiceItem]

    let factory = TestTachieFactory()
    let box = ComposerBox(timeline: timeline, timelines: [timeline], tachieFactory: factory)
    let providerSource = box.provider.source(for: tachieItem)
    check(providerSource is MetalTachieSource, "provider returns MetalTachieSource for TachieItem")
    providerSource.dispose()

    if let image = box.render(frame: 10, fps: 30) {
        let s = stats(of: image)
        print("  tachie: nonTransparent=\(s.nonTransparent) center=(\(s.centerR),\(s.centerG),\(s.centerB),\(s.centerA))")
        check(abs(s.nonTransparent - 2500) <= 200, "tachie coverage ~2500")
        check(s.centerR > 200 && s.centerB > 200 && s.centerG < 60, "tachie center is magenta")
    } else {
        check(false, "tachie rendered")
    }
    if let description = factory.renderer?.lastDescription {
        print("  tachie desc: faces=\(description.faces.count) volume=\(description.volume) mouth=\(description.mouthShape)")
        check(description.faces.count == 2, "tachie received 2 face descriptions")
        check(description.volume == 0, "tachie volume fallback is 0 in voice range")
        check(description.mouthShape == .silent, "tachie mouth shape is silent (unevaluated)")
    } else {
        check(false, "tachie renderer received a description")
    }
    box.composer.dispose()
}

// MARK: - ケース5: 自己参照シーン（入れ子上限で打ち切られること）

do {
    let timeline = makeTimeline(width: 100, height: 100)
    let sceneItem = SceneItem()
    sceneItem.sceneId = timeline.id
    sceneItem.frame = 0
    sceneItem.length = 30
    sceneItem.layer = 0
    timeline.items = [sceneItem]
    let box = ComposerBox(timeline: timeline, timelines: [timeline])
    let image = box.render(frame: 0, fps: 30)
    check(image != nil, "self-referencing scene terminates (nesting limit)")
    box.composer.dispose()
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
