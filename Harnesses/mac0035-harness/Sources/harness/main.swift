import CoreGraphics
import Foundation
import YMM4Core
import YMM4GPU

// MAC-0035 検証ハーネス: AUD-02（画面遷移 TransitionSource の配線）。
// PreviewBox と同じ合成経路（TimelineComposer + MetalSourceProvider +
// MetalEffectPairProvider）で人工的な最小プロジェクトを合成し、
// 読み戻した画素で数値検証する。
// 画面は 64×48、30fps。赤の全面図形（frame 0〜99）と青の全面図形
// （frame 100〜199）をレイヤー0に置き、レイヤー1に frame 100・
// length 20 の TransitionItem を置く。
// 期待値は本家の各 TransitionSource の式からの解析値。

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
    print("  pixel(\(x),\(y)) = (\(p.r), \(p.g), \(p.b)) want (\(r), \(g), \(b)) ±\(tolerance)")
    check(ok, label)
}

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

/// PreviewBox（MAC-0028 配線）と同じ構成の合成器。
@MainActor
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
        let effectProvider = MetalEffectPairProvider(devices: devices)
        provider = MetalSourceProvider(
            devices: devices,
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

@MainActor
func makeTimeline() -> Timeline {
    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: 30, hz: 48000, width: 64, height: 48)
    return timeline
}

@MainActor
func fullScreenShape(color: Color, frame: Int, length: Int, layer: Int) -> ShapeItem {
    let item = ShapeItem()
    item.frame = frame
    item.length = length
    item.layer = layer
    let rectangle = RectangleShapeParameter()
    rectangle.sizeMode = .widthHeight
    rectangle.width = Animation(defaultValue: 200, minValue: 0, maxValue: 100_000)
    rectangle.height = Animation(defaultValue: 200, minValue: 0, maxValue: 100_000)
    let brush = SolidColorBrushParameter()
    brush.color = color
    rectangle.brush.parameter = .solidColor(brush)
    item.shapeParameter = .rectangle(rectangle)
    return item
}

@MainActor
func preservedParameter(
    _ className: String, _ fields: [(String, JSONValue)] = []
) -> PreservedObject {
    PreservedObject(.object(
        [(key: "$type", value: .string(
            "YukkuriMovieMaker.Transition.\(className), YukkuriMovieMaker"
        ))] + fields.map { (key: $0.0, value: $0.1) }
    ))
}

@MainActor
func transitionTimeline(
    parameter: PreservedObject?,
    beforeEffects: [PreservedObject] = []
) -> Timeline {
    let timeline = makeTimeline()
    let red = fullScreenShape(
        color: Color(alpha: 255, red: 255, green: 0, blue: 0),
        frame: 0, length: 100, layer: 0
    )
    let blue = fullScreenShape(
        color: Color(alpha: 255, red: 0, green: 0, blue: 255),
        frame: 100, length: 100, layer: 0
    )
    let transition = TransitionItem()
    transition.frame = 100
    transition.length = 20
    transition.layer = 1
    transition.transitionParameter = parameter
    transition.beforeVideoEffects = beforeEffects
    timeline.items = [red, blue, transition]
    return timeline
}

let linearFade = preservedParameter("FadeTransitionParameter", [
    ("EasingType", .string("Linear")), ("EasingMode", .string("In")),
])

// MARK: - ケース1: Fade の中点（受入検証）
// frame 110 は進行 10/20。Linear の率は 0.5 で、
// after × 0.5 + before × 0.5 = (127.5, 0, 127.5)。
do {
    let box = ComposerBox(timeline: transitionTimeline(parameter: linearFade))
    if let frame = box.render(frame: 110) {
        checkPixel(frame, 32, 24, r: 127, g: 0, b: 127, tolerance: 3, "fade-mid: center")
        checkPixel(frame, 2, 2, r: 127, g: 0, b: 127, tolerance: 3, "fade-mid: corner")
    } else { check(false, "fade-mid: rendered") }
    box.composer.dispose()
}

// MARK: - ケース2: Fade の端点
// frame 100 は率 0（before のみ = 赤）、frame 119 は率 0.95
// （R = 255 × 0.05 ≈ 13、B = 255 × 0.95 ≈ 242）。
do {
    let box = ComposerBox(timeline: transitionTimeline(parameter: linearFade))
    if let frame = box.render(frame: 100) {
        checkPixel(frame, 32, 24, r: 255, g: 0, b: 0, tolerance: 2, "fade-start: pure before")
    } else { check(false, "fade-start: rendered") }
    if let frame = box.render(frame: 119) {
        checkPixel(frame, 32, 24, r: 13, g: 0, b: 242, tolerance: 4, "fade-end: rate 0.95")
    } else { check(false, "fade-end: rendered") }
    box.composer.dispose()
}

// MARK: - ケース3: 遷移区間の外（主合成器のみ）
// frame 99 は赤の図形のみ、frame 120 は青の図形のみ。
do {
    let box = ComposerBox(timeline: transitionTimeline(parameter: linearFade))
    if let frame = box.render(frame: 99) {
        checkPixel(frame, 32, 24, r: 255, g: 0, b: 0, tolerance: 2, "outside-before: red")
    } else { check(false, "outside-before: rendered") }
    if let frame = box.render(frame: 120) {
        checkPixel(frame, 32, 24, r: 0, g: 0, b: 255, tolerance: 2, "outside-after: blue")
    } else { check(false, "outside-after: rendered") }
    box.composer.dispose()
}

// MARK: - ケース4: Switch（中点で切り替え）
// frame 105 は進行 5 < 20/2 で before、frame 115 は after。
do {
    let box = ComposerBox(timeline: transitionTimeline(
        parameter: preservedParameter("SwitchTransitionParameter")
    ))
    if let frame = box.render(frame: 105) {
        checkPixel(frame, 32, 24, r: 255, g: 0, b: 0, tolerance: 2, "switch-first-half: before")
    } else { check(false, "switch-first-half: rendered") }
    if let frame = box.render(frame: 115) {
        checkPixel(frame, 32, 24, r: 0, g: 0, b: 255, tolerance: 2, "switch-second-half: after")
    } else { check(false, "switch-second-half: rendered") }
    box.composer.dispose()
}

// MARK: - ケース5: Push（パラメータ未指定の既定、角度 0）
// frame 110 は Expo InOut の率 0.5。delta = (64, 0) で、
// after は −32、before は +32 にずれる: 左半分が青、右半分が赤。
do {
    let box = ComposerBox(timeline: transitionTimeline(parameter: nil))
    if let frame = box.render(frame: 110) {
        checkPixel(frame, 8, 24, r: 0, g: 0, b: 255, tolerance: 2, "push-mid: left is after")
        checkPixel(frame, 56, 24, r: 255, g: 0, b: 0, tolerance: 2, "push-mid: right is before")
    } else { check(false, "push-mid: rendered") }
    box.composer.dispose()
}

// MARK: - ケース6: BeforeVideoEffects が Before 側へ効く
// Before 側へ Invert を付けると赤 (255,0,0) が (0,255,255) になる。
// frame 100（率 0）は反転した before のみ、frame 110 は
// 反転 before × 0.5 + after × 0.5 = (0, 127.5, 255)。
do {
    let invert = PreservedObject(.object([
        (key: "$type", value: .string(
            "YukkuriMovieMaker.Project.Effects.InvertEffect, YukkuriMovieMaker"
        )),
        (key: "IsEnabled", value: .bool(true)),
    ]))
    let box = ComposerBox(timeline: transitionTimeline(
        parameter: linearFade, beforeEffects: [invert]
    ))
    if let frame = box.render(frame: 100) {
        checkPixel(frame, 32, 24, r: 0, g: 255, b: 255, tolerance: 3, "before-effects: inverted before")
    } else { check(false, "before-effects-start: rendered") }
    if let frame = box.render(frame: 110) {
        checkPixel(frame, 32, 24, r: 0, g: 127, b: 255, tolerance: 4, "before-effects: mid mix")
    } else { check(false, "before-effects-mid: rendered") }
    box.composer.dispose()
}

// MARK: - ケース7: Slide（Target = After、角度 0、Linear）
// frame 110（率 0.5）: before が下地、after が −32 ずれて左半分を覆う。
do {
    let slide = preservedParameter("SlideTransitionParameter", [
        ("Target", .string("After")),
        ("EasingType", .string("Linear")), ("EasingMode", .string("In")),
    ])
    let box = ComposerBox(timeline: transitionTimeline(parameter: slide))
    if let frame = box.render(frame: 110) {
        checkPixel(frame, 8, 24, r: 0, g: 0, b: 255, tolerance: 2, "slide-mid: left is after")
        checkPixel(frame, 56, 24, r: 255, g: 0, b: 0, tolerance: 2, "slide-mid: right is before")
    } else { check(false, "slide-mid: rendered") }
    box.composer.dispose()
}

// MARK: - ケース8: None（OverlayTarget = After）
// after が上へ重なるため、区間内は全面が青。
do {
    let none = preservedParameter("NoneTransitionParameter", [
        ("OverlayTarget", .string("After")),
    ])
    let box = ComposerBox(timeline: transitionTimeline(parameter: none))
    if let frame = box.render(frame: 110) {
        checkPixel(frame, 32, 24, r: 0, g: 0, b: 255, tolerance: 2, "none-after: after on top")
    } else { check(false, "none-after: rendered") }
    box.composer.dispose()
}

// MARK: - ケース9: DoubleSlideDoor（既定: Target = Before、角度 0）
// 角度 0 の扉マスクは左右の半面。frame 110 は Expo InOut の率 0.5、
// delta ≈ (32, 0) で左扉は −16、右扉は +16 へ動く: 両端が赤
// （before）、中央は下地の青が露出する。
do {
    let box = ComposerBox(timeline: transitionTimeline(
        parameter: preservedParameter("DoubleSlideDoorTransitionParameter")
    ))
    if let frame = box.render(frame: 110) {
        checkPixel(frame, 8, 24, r: 255, g: 0, b: 0, tolerance: 3, "slidedoor-mid: left door")
        checkPixel(frame, 24, 24, r: 0, g: 0, b: 255, tolerance: 3, "slidedoor-mid: center-left exposed")
        checkPixel(frame, 40, 24, r: 0, g: 0, b: 255, tolerance: 3, "slidedoor-mid: center-right exposed")
        checkPixel(frame, 56, 24, r: 255, g: 0, b: 0, tolerance: 3, "slidedoor-mid: right door")
    } else { check(false, "slidedoor-mid: rendered") }
    box.composer.dispose()
}

// MARK: - ケース10: DoubleOpenDoor（既定: Target = Before、角度 0）
// frame 110（率 0.5）: 扉は外端の蝶番で 45° 開く。蝶番近傍は赤のまま、
// 中央は下地の青が露出する。
do {
    let box = ComposerBox(timeline: transitionTimeline(
        parameter: preservedParameter("DoubleOpenDoorTransitionParameter")
    ))
    if let frame = box.render(frame: 110) {
        checkPixel(frame, 2, 24, r: 255, g: 0, b: 0, tolerance: 10, "opendoor-mid: left hinge")
        checkPixel(frame, 32, 24, r: 0, g: 0, b: 255, tolerance: 10, "opendoor-mid: center exposed")
        checkPixel(frame, 61, 24, r: 255, g: 0, b: 0, tolerance: 10, "opendoor-mid: right hinge")
    } else { check(false, "opendoor-mid: rendered") }
    box.composer.dispose()
}

// MARK: - ケース11: Slice（Slices = 2、Direction = Down、Linear）
// 角度 0 の帯は左右の半面（被覆矩形を π/2 回転）。frame 110（率 0.5）
// で帯は方向ベクトル (0, 48) × 0.5 = +24 へ動く: 上半分は下地の青、
// 下半分は入力の赤。frame 100（率 0）は全面が赤。
do {
    let slice = preservedParameter("SliceTransitionParameter", [
        ("Slices", .object([
            (key: "Values", value: .array([
                .object([(key: "Value", value: .number(2))]),
            ])),
        ])),
        ("Direction", .string("Down")),
        ("EasingType", .string("Linear")), ("EasingMode", .string("In")),
    ])
    let box = ComposerBox(timeline: transitionTimeline(parameter: slice))
    if let frame = box.render(frame: 100) {
        checkPixel(frame, 32, 24, r: 255, g: 0, b: 0, tolerance: 2, "slice-start: pure before")
    } else { check(false, "slice-start: rendered") }
    if let frame = box.render(frame: 110) {
        checkPixel(frame, 32, 4, r: 0, g: 0, b: 255, tolerance: 3, "slice-mid: top-right exposed")
        checkPixel(frame, 8, 4, r: 0, g: 0, b: 255, tolerance: 3, "slice-mid: top-left exposed")
        checkPixel(frame, 32, 44, r: 255, g: 0, b: 0, tolerance: 3, "slice-mid: bottom-right strip")
        checkPixel(frame, 8, 44, r: 255, g: 0, b: 0, tolerance: 3, "slice-mid: bottom-left strip")
    } else { check(false, "slice-mid: rendered") }
    box.composer.dispose()
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
