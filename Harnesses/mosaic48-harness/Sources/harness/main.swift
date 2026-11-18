import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core
import YMM4GPU

// MOSAIC48 検証ハーネス: 非矩形モザイク (円形・三角形・六角形・
// ボロノイ・ドロネー) とモザイクサイズのアニメーション評価。
//
// 入力は画素座標を符号化した識別パターン (ident.png)。期待値は
// gen_expected.py が本家カスタムシェーダの逆アセンブルから抽出した
// 参照実装 + 線形サンプルの再現で生成した expected_*.bin (BGRA)。
// 実行前に `python3 gen_expected.py` で /tmp/mosaic48/ へ生成すること。
// 画面は 64x64、平面座標は中心原点・y 下向き。フレーム画素 (x, y) の
// 平面点は (-32 + x + 0.5, -32 + y + 0.5)。

var failures = 0
@MainActor
func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { failures += 1 }
}

let workDir = URL(fileURLWithPath: "/tmp/mosaic48")

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

/// 期待値ファイルとフレーム全体を照合する。量子化と float 精度の差で
/// 各成分 ±3 以内の画素は一致とみなし、それを超える画素 (セル境界の
/// 判定割れを含む) の件数と内訳を表示する。
@MainActor
func checkFrame(_ frame: Frame, expectedName: String, label: String, maxMismatchRatio: Double) {
    let url = workDir.appendingPathComponent("expected_\(expectedName).bin")
    guard let expected = try? Data(contentsOf: url), expected.count == frame.bytes.count else {
        check(false, "\(label): expected file \(expectedName) missing")
        return
    }
    var mismatches = 0
    var examples: [String] = []
    for i in 0..<(frame.width * frame.height) {
        let j = i * 4
        let d = max(
            abs(Int(frame.bytes[j]) - Int(expected[j])),
            abs(Int(frame.bytes[j + 1]) - Int(expected[j + 1])),
            abs(Int(frame.bytes[j + 2]) - Int(expected[j + 2])),
            abs(Int(frame.bytes[j + 3]) - Int(expected[j + 3]))
        )
        if d > 3 {
            mismatches += 1
            if examples.count < 5 {
                let x = i % frame.width
                let y = i / frame.width
                examples.append(
                    "(\(x),\(y)) got B\(frame.bytes[j]) G\(frame.bytes[j + 1]) R\(frame.bytes[j + 2]) A\(frame.bytes[j + 3])"
                        + " want B\(expected[j]) G\(expected[j + 1]) R\(expected[j + 2]) A\(expected[j + 3])"
                )
            }
        }
    }
    let ratio = Double(mismatches) / Double(frame.width * frame.height)
    print("  \(label): mismatch \(mismatches) px (\(String(format: "%.3f", ratio * 100))%)")
    for example in examples {
        print("    \(example)")
    }
    check(ratio <= maxMismatchRatio, label)
}

// MARK: - 合成 (mac0028-harness と同じ構成)

final class ComposerBox {
    let devices: MetalGraphicsDevices
    let context: MetalGraphicsContext
    let provider: MetalSourceProvider
    let composer: TimelineComposer

    init(timeline: Timeline) {
        devices = MetalGraphicsDevices()!
        context = devices.makeContext(
            targetSize: PixelSize(
                width: timeline.videoInfo.width, height: timeline.videoInfo.height
            )
        )
        let effectProvider = MetalEffectPairProvider(devices: devices)
        provider = MetalSourceProvider(
            devices: devices, baseDirectory: workDir,
            sceneResolver: { _ in nil },
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

@MainActor
func renderImage(
    effects: [PreservedObject] = [], frame: Int = 0, length: Int = 90
) -> Frame? {
    let timeline = makeTimeline()
    let item = ImageItem()
    item.filePath = "ident.png"
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

func mosaicEffect(
    shape: MosaicType, sizeValues: [Double], animationType: String = "なし"
) -> PreservedObject {
    let definition = MosaicEffectDefinition()
    definition.mosaicType = shape
    let parameter = SizedMosaicParameter(shape: shape)
    parameter.size.values = sizeValues.map { AnimationValue($0) }
    if animationType != "なし", let type = AnimationType(honkeName: animationType) {
        parameter.size.animationType = type
    }
    definition.mosaicParameter = .sized(parameter)
    return VideoEffectRegistry.encode(definition)
}

// MARK: - ケース0: 対照 (エフェクトなしで識別パターンがそのまま出る)

if let frame = renderImage() {
    let p = frame.pixel(10, 20)
    check(p.r == 40 && p.g == 80 && p.b == (10 + 40) % 256 && p.a == 255, "control: ident pattern")
} else { check(false, "control: rendered") }

// MARK: - ケース1〜5: 非矩形モザイク (Size 16 固定)
// 閾値について: 円形・三角形・六角形は決定的な式で、参照と全画素一致
// (0px) が実測値。ボロノイ・ドロネーは特徴点ハッシュ
// fract(sin(dot)*43758.546875) の float32 丸め差に選択全体が敏感で、
// 独立実装の参照とは数%の画素が境界で割れる (実測 0.27〜5.4%)。
// 特徴点を実測値で揃えた照合では全ケース 0px になることを別途確認
// 済みで、差はアルゴリズムではなくハッシュ値の丸めにのみ由来する。
// なお本家は Seed がオブジェクトのハッシュ値 (実行ごとに不定) の
// ため、これら2形状に安定した「本家の出力」自体が存在しない。

let shapeCases: [(MosaicType, String, String, Double)] = [
    (.circle, "circle16", "circle size16", 0.01),
    (.triangle, "triangle16", "triangle size16", 0.01),
    (.hexagon, "hexagon16", "hexagon size16", 0.01),
    (.voronoi, "voronoi16", "voronoi size16", 0.06),
    (.delaunay, "delaunay16", "delaunay size16", 0.06),
]
for (shape, expected, label, threshold) in shapeCases {
    if let frame = renderImage(effects: [mosaicEffect(shape: shape, sizeValues: [16])]) {
        checkFrame(frame, expectedName: expected, label: label, maxMismatchRatio: threshold)
    } else { check(false, "\(label): rendered") }
}

// MARK: - ケース6〜9: サイズ違い

let sizeCases: [(MosaicType, Double, String, String, Double)] = [
    (.circle, 10, "circle10", "circle size10", 0.01),
    (.voronoi, 13, "voronoi13", "voronoi size13", 0.06),
    (.triangle, 20, "triangle20", "triangle size20", 0.01),
    (.hexagon, 12, "hexagon12", "hexagon size12", 0.01),
    (.delaunay, 18, "delaunay18", "delaunay size18", 0.06),
]
for (shape, size, expected, label, threshold) in sizeCases {
    if let frame = renderImage(effects: [mosaicEffect(shape: shape, sizeValues: [size])]) {
        checkFrame(frame, expectedName: expected, label: label, maxMismatchRatio: threshold)
    } else { check(false, "\(label): rendered") }
}

// MARK: - ケース10: サイズアニメーション (直線移動 8 -> 24、長さ90)
// フレーム 0 では Size 8、最終フレーム (89) では Size 24 の評価になる。

do {
    let effect = mosaicEffect(shape: .circle, sizeValues: [8, 24], animationType: "直線移動")
    if let frame = renderImage(effects: [effect], frame: 0) {
        checkFrame(frame, expectedName: "circle8", label: "anim size frame0 (=8)", maxMismatchRatio: 0.01)
    } else { check(false, "anim size frame0: rendered") }
    if let frame = renderImage(effects: [effect], frame: 89) {
        checkFrame(frame, expectedName: "circle24", label: "anim size frame89 (=24)", maxMismatchRatio: 0.01)
    } else { check(false, "anim size frame89: rendered") }
}

// MARK: - ケース11: 未知の形状パラメータは素通し

do {
    let definition = MosaicEffectDefinition()
    definition.mosaicType = .hexagon
    definition.mosaicParameter = .preserved(PreservedObject(.object([
        (key: "$type", value: .string("Some.Plugin.CustomMosaicParameter, SomePlugin")),
        (key: "Size", value: .number(16)),
    ])))
    if let frame = renderImage(effects: [VideoEffectRegistry.encode(definition)]) {
        let p = frame.pixel(10, 20)
        check(p.r == 40 && p.g == 80 && p.a == 255, "preserved parameter: passthrough")
    } else { check(false, "preserved parameter: rendered") }
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
