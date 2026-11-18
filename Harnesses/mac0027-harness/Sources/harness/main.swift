import CoreGraphics
import Foundation
import YMM4Core
import YMM4GPU

var failures = 0
@MainActor
func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { failures += 1 }
}

// MARK: - 合成と読み戻し（PreviewBox と同じ構成）

final class ComposerBox {
    let devices: MetalGraphicsDevices
    let context: MetalGraphicsContext
    let provider: MetalSourceProvider
    let composer: TimelineComposer

    init(timeline: Timeline) {
        devices = try! MetalGraphicsDevices()
        context = devices.makeContext(
            targetSize: PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
        )
        provider = MetalSourceProvider(devices: devices, timeline: timeline)
        composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider.source(for:),
            effectProvider: MetalEffectPairProvider(devices: devices)
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

/// 画像を BGRA プリマルチプライドのバイト列として読み出す。
func readPixels(of image: CGImage) -> [UInt8] {
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
    return bytes
}

func alpha(at bytes: [UInt8], width: Int, column: Int, row: Int) -> Int {
    Int(bytes[(row * width + column) * 4 + 3])
}

func red(at bytes: [UInt8], width: Int, column: Int, row: Int) -> Int {
    Int(bytes[(row * width + column) * 4 + 2])
}

func coverage(_ bytes: [UInt8]) -> Int {
    var count = 0
    for i in 0..<(bytes.count / 4) where bytes[i * 4 + 3] > 10 {
        count += 1
    }
    return count
}

func makeTimeline(width: Int, height: Int) -> Timeline {
    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: 30, hz: 44_100, width: width, height: height)
    return timeline
}

func makeGroup(layer: Int, range: Int, isComposite: Bool = true) -> GroupItem {
    let group = GroupItem()
    group.frame = 0
    group.length = 90
    group.layer = layer
    group.groupRange = range
    group.isComposite = isComposite
    return group
}

func makeShape(layer: Int) -> ShapeItem {
    let shape = ShapeItem()
    shape.frame = 0
    shape.length = 90
    shape.layer = layer
    return shape
}

// MARK: - ケース0: 回帰（グループなしの通常描画）

do {
    let timeline = makeTimeline(width: 200, height: 200)
    timeline.items = [makeShape(layer: 0)]
    let box = ComposerBox(timeline: timeline)
    if let image = box.render(frame: 0, fps: 30) {
        let bytes = readPixels(of: image)
        let count = coverage(bytes)
        print("  plain: coverage=\(count) centerA=\(alpha(at: bytes, width: 200, column: 100, row: 100))")
        check(abs(count - 10000) <= 400, "plain shape coverage ~10000")
        check(alpha(at: bytes, width: 200, column: 100, row: 100) > 250, "plain shape center opaque")
    } else {
        check(false, "plain shape rendered")
    }
    box.composer.dispose()
}

// MARK: - ケース1: 合成グループの子が描かれる

do {
    let timeline = makeTimeline(width: 200, height: 200)
    let group = makeGroup(layer: 0, range: 10)
    let child = makeShape(layer: 1)
    timeline.items = [group, child]
    let box = ComposerBox(timeline: timeline)
    let providerSource = box.provider.source(for: group)
    check(providerSource is MetalCompositeSource, "provider returns MetalCompositeSource for composite GroupItem")
    providerSource.dispose()

    if let image = box.render(frame: 0, fps: 30) {
        let bytes = readPixels(of: image)
        let count = coverage(bytes)
        print("  composite: coverage=\(count) centerA=\(alpha(at: bytes, width: 200, column: 100, row: 100)) centerR=\(red(at: bytes, width: 200, column: 100, row: 100))")
        check(abs(count - 10000) <= 400, "composite child coverage ~10000")
        check(alpha(at: bytes, width: 200, column: 100, row: 100) > 250, "composite center opaque")
        check(red(at: bytes, width: 200, column: 100, row: 100) > 200, "composite center is white")
    } else {
        check(false, "composite rendered")
    }
    box.composer.dispose()
}

// MARK: - ケース2: グループの不透明度が合成結果全体へ効く

do {
    let timeline = makeTimeline(width: 200, height: 200)
    let group = makeGroup(layer: 0, range: 10)
    group.opacity.values = [AnimationValue(50)]
    let child = makeShape(layer: 1)
    timeline.items = [group, child]
    let box = ComposerBox(timeline: timeline)
    if let image = box.render(frame: 0, fps: 30) {
        let bytes = readPixels(of: image)
        let centerAlpha = alpha(at: bytes, width: 200, column: 100, row: 100)
        print("  opacity: coverage=\(coverage(bytes)) centerA=\(centerAlpha)")
        check(abs(centerAlpha - 128) <= 16, "group opacity 50% -> center alpha ~128")
        check(abs(coverage(bytes) - 10000) <= 400, "opacity case coverage ~10000")
    } else {
        check(false, "opacity case rendered")
    }
    box.composer.dispose()
}

// MARK: - ケース3: グループの色反転エフェクトは全体へ一度だけ

do {
    let timeline = makeTimeline(width: 200, height: 200)
    let group = makeGroup(layer: 0, range: 10)
    group.videoEffects = [PreservedObject(.object([
        (key: "$type", value: .string("YukkuriMovieMaker.Project.Effects.InvertEffect, YukkuriMovieMaker")),
    ]))]
    let child = makeShape(layer: 1)
    timeline.items = [group, child]
    let box = ComposerBox(timeline: timeline)
    if let image = box.render(frame: 0, fps: 30) {
        let bytes = readPixels(of: image)
        let centerRed = red(at: bytes, width: 200, column: 100, row: 100)
        let centerAlpha = alpha(at: bytes, width: 200, column: 100, row: 100)
        print("  invert: centerR=\(centerRed) centerA=\(centerAlpha)")
        // 白い図形が一度だけ反転されれば黒になる（2回なら白へ戻る）。
        check(centerRed < 10 && centerAlpha > 250, "group invert applied once -> black opaque")
    } else {
        check(false, "invert case rendered")
    }
    box.composer.dispose()
}

// MARK: - ケース4: 合成中心（ImageCenter / ScreenCenter）の回転軸

do {
    let timeline = makeTimeline(width: 200, height: 200)
    let group = makeGroup(layer: 0, range: 10)
    let child = makeShape(layer: 1)
    child.x.values = [AnimationValue(50)]
    timeline.items = [group, child]
    let box = ComposerBox(timeline: timeline)

    // 較正: 回転なしでは図形は平面 x=+50 側（東）にある。読み戻しの
    // 左右対応を実測で決める。
    var eastColumn: Int?
    if let image = box.render(frame: 0, fps: 30) {
        let bytes = readPixels(of: image)
        let a150 = alpha(at: bytes, width: 200, column: 150, row: 100)
        let a50 = alpha(at: bytes, width: 200, column: 50, row: 100)
        print("  pivot baseline: alpha(150,100)=\(a150) alpha(50,100)=\(a50)")
        check((a150 > 250) != (a50 > 250), "baseline: shape on exactly one side")
        eastColumn = a150 > 250 ? 150 : 50
    } else {
        check(false, "pivot baseline rendered")
    }

    if let east = eastColumn {
        let west = east == 150 ? 50 : 150
        // ImageCenter + 180°: 内容中心が軸なので図形は東に残る。
        group.compositeCenter = .imageCenter
        group.rotation.values = [AnimationValue(180)]
        if let image = box.render(frame: 0, fps: 30) {
            let bytes = readPixels(of: image)
            let eastAlpha = alpha(at: bytes, width: 200, column: east, row: 100)
            let westAlpha = alpha(at: bytes, width: 200, column: west, row: 100)
            print("  imageCenter+180: east=\(eastAlpha) west=\(westAlpha)")
            check(eastAlpha > 250 && westAlpha < 10, "ImageCenter pivot keeps shape in place under 180 rotation")
        } else {
            check(false, "imageCenter case rendered")
        }
        // ScreenCenter + 180°: 画面中心が軸なので図形は西へ移る。
        group.compositeCenter = .screenCenter
        if let image = box.render(frame: 0, fps: 30) {
            let bytes = readPixels(of: image)
            let eastAlpha = alpha(at: bytes, width: 200, column: east, row: 100)
            let westAlpha = alpha(at: bytes, width: 200, column: west, row: 100)
            print("  screenCenter+180: east=\(eastAlpha) west=\(westAlpha)")
            check(westAlpha > 250 && eastAlpha < 10, "ScreenCenter pivot moves shape to opposite side under 180 rotation")
        } else {
            check(false, "screenCenter case rendered")
        }
    }
    box.composer.dispose()
}

// MARK: - ケース5: 入れ子（合成グループ内合成グループ）

do {
    let timeline = makeTimeline(width: 200, height: 200)
    let outer = makeGroup(layer: 0, range: 30)
    let inner = makeGroup(layer: 5, range: 10)
    inner.opacity.values = [AnimationValue(50)]
    let grandchild = makeShape(layer: 6)
    timeline.items = [outer, inner, grandchild]
    let box = ComposerBox(timeline: timeline)
    let providerSource = box.provider.source(for: outer)
    check(providerSource is MetalCompositeSource, "provider returns MetalCompositeSource for outer group")
    providerSource.dispose()

    if let image = box.render(frame: 0, fps: 30) {
        let bytes = readPixels(of: image)
        let centerAlpha = alpha(at: bytes, width: 200, column: 100, row: 100)
        print("  nested: coverage=\(coverage(bytes)) centerA=\(centerAlpha)")
        check(abs(coverage(bytes) - 10000) <= 400, "nested grandchild coverage ~10000")
        check(abs(centerAlpha - 128) <= 16, "inner group opacity 50% applies through nesting")
    } else {
        check(false, "nested case rendered")
    }
    box.composer.dispose()
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
