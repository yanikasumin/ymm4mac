import Foundation
import ImageIO
import YMM4Core
import YMM4GPU

// Issue #49（PngWav ライター）/ #50（Metal 初期化診断）の Mac 実機検証。
//
// - #50: 通常初期化の成功、壊れたシェーダでの shaderLibraryFailed、
//   関数不足での shaderFunctionMissing を人為的に起こし、
//   MetalInitializationError の種別と利用者向け理由文を確認する。
// - #49: 実合成経路（TimelineExporter）から 30 フレームを書き出し、
//   FFmpeg 経路（従来経路の回帰確認）と PngWav 経路（PNG 30 枚＋
//   WAV ちょうど 1 秒、PNG が ImageIO でデコード可能）を確認する。
//
// 使い方: swift run -c release [出力ルート]
// 標準出力に PASS: / FAIL: を出し、失敗があれば終了コード非 0。

nonisolated(unsafe) var failures = 0
func check(_ name: String, _ condition: Bool, detail: String = "") {
    if condition {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name) \(detail)")
        failures += 1
    }
}

let outputRoot = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/media4950-harness-out"
try? FileManager.default.removeItem(atPath: outputRoot)
try FileManager.default.createDirectory(
    atPath: outputRoot, withIntermediateDirectories: true
)

// MARK: - #50 Metal 初期化診断

do {
    let devices = try MetalGraphicsDevices()
    check("metal-init-normal", true)
    print("INFO: device = \(devices.device.name)")
} catch {
    check("metal-init-normal", false, detail: "\(error)")
}

do {
    _ = try MetalGraphicsDevices(shaderSource: "this is not metal {{{")
    check("metal-init-broken-shader", false, detail: "例外が出なかった")
} catch let error as MetalInitializationError {
    if case .shaderLibraryFailed = error {
        check("metal-init-broken-shader", true)
        print("INFO: userMessage = \(error.userMessage)")
        print("INFO: description = \(error.description)")
    } else {
        check("metal-init-broken-shader", false, detail: "種別違い: \(error)")
    }
} catch {
    check("metal-init-broken-shader", false, detail: "型違い: \(error)")
}

let missingFunctionShader = """
    #include <metal_stdlib>
    using namespace metal;
    struct VOut { float4 position [[position]]; float2 uv; };
    vertex VOut ymm4Vertex(uint vid [[vertex_id]]) {
        VOut o; o.position = float4(0); o.uv = float2(0); return o;
    }
    fragment float4 ymm4TexturedFragment(VOut in [[stage_in]]) { return float4(0); }
    fragment float4 ymm4SolidFragment(VOut in [[stage_in]]) { return float4(0); }
    fragment float4 ymm4ShapeFragment(VOut in [[stage_in]]) { return float4(0); }
    fragment float4 ymm4ColorEffectFragment(VOut in [[stage_in]]) { return float4(0); }
    fragment float4 ymm4BlurFragment(VOut in [[stage_in]]) { return float4(0); }
    fragment float4 ymm4WarpFragment(VOut in [[stage_in]]) { return float4(0); }
    fragment float4 ymm4CompositeFragment(VOut in [[stage_in]]) { return float4(0); }
    kernel void ymm4MorphologyKernel() {}
    """
do {
    _ = try MetalGraphicsDevices(shaderSource: missingFunctionShader)
    check("metal-init-missing-function", false, detail: "例外が出なかった")
} catch let error as MetalInitializationError {
    if case .shaderFunctionMissing(let name) = error {
        check(
            "metal-init-missing-function", name == "ymm4MosaicKernel",
            detail: "name = \(name)"
        )
        print("INFO: userMessage = \(error.userMessage)")
    } else {
        check("metal-init-missing-function", false, detail: "種別違い: \(error)")
    }
} catch {
    check("metal-init-missing-function", false, detail: "型違い: \(error)")
}

// MARK: - #49 書き出し（実合成経路）

func makeTimeline() -> Timeline {
    let timeline = Timeline()
    timeline.videoInfo = VideoInfo(fps: 30, hz: 48_000, width: 64, height: 64)
    let parameter = RectangleShapeParameter()
    parameter.sizeMode = .widthHeight
    parameter.width = Animation(defaultValue: 64, minValue: 0, maxValue: 100_000)
    parameter.height = Animation(defaultValue: 64, minValue: 0, maxValue: 100_000)
    let item = ShapeItem()
    item.frame = 0
    item.length = 30
    item.layer = 0
    item.shapeParameter = .rectangle(parameter)
    timeline.items = [item]
    timeline.refreshTimelineLengthAndMaxLayer()
    return timeline
}

let timeline = makeTimeline()
check("timeline-length", timeline.length == 30, detail: "length = \(timeline.length)")

do {
    let exporter = try TimelineExporter(
        timeline: timeline, timelines: [timeline], baseDirectory: nil
    )
    defer { exporter.dispose() }

    // 従来経路（FFmpeg）の回帰確認。長さの検証は呼び出し側で
    // ffprobe を使って行う（このハーネスはパスのみ出力する）。
    let mp4Path = "\(outputRoot)/out.mp4"
    let ffmpegOutcome = try exporter.run(
        outputPath: mp4Path, ffmpegPath: "/opt/homebrew/bin/ffmpeg"
    )
    check(
        "ffmpeg-export-completed",
        ffmpegOutcome.completion == .completed && ffmpegOutcome.framesWritten == 30,
        detail: "completion = \(ffmpegOutcome.completion), frames = \(ffmpegOutcome.framesWritten), error = \(String(describing: ffmpegOutcome.error))"
    )
    print("INFO: mp4 = \(mp4Path)")

    // PngWav 経路。
    let pngwavDir = "\(outputRoot)/pngwav"
    let pngwavOutcome = try exporter.runPngWav(
        outputDirectory: pngwavDir,
        settings: PngWavExportSettings(fileName: "proj")
    )
    check(
        "pngwav-export-completed",
        pngwavOutcome.completion == .completed && pngwavOutcome.framesWritten == 30,
        detail: "completion = \(pngwavOutcome.completion), frames = \(pngwavOutcome.framesWritten), error = \(String(describing: pngwavOutcome.error))"
    )

    let files = try FileManager.default.contentsOfDirectory(atPath: pngwavDir)
    let pngs = files.filter { $0.hasSuffix(".png") }
    check("pngwav-png-count", pngs.count == 30, detail: "count = \(pngs.count)")
    check(
        "pngwav-png-names",
        pngs.contains("proj_0.png") && pngs.contains("proj_29.png"),
        detail: "\(pngs.sorted().prefix(3))"
    )

    let wavData = try Data(
        contentsOf: URL(fileURLWithPath: "\(pngwavDir)/proj_0.wav")
    )
    let wavDataSize = wavData.withUnsafeBytes { raw in
        raw.loadUnaligned(fromByteOffset: 40, as: UInt32.self).littleEndian
    }
    check(
        "pngwav-wav-one-second",
        Int(wavDataSize) == 48_000 * 2 * 4,
        detail: "dataSize = \(wavDataSize)"
    )

    // PNG が実デコーダ（ImageIO）で開けて寸法が一致すること。
    let pngURL = URL(fileURLWithPath: "\(pngwavDir)/proj_0.png") as CFURL
    if let source = CGImageSourceCreateWithURL(pngURL, nil),
       let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
        check(
            "pngwav-png-decodable",
            image.width == 64 && image.height == 64,
            detail: "\(image.width)x\(image.height)"
        )
    } else {
        check("pngwav-png-decodable", false, detail: "ImageIO で開けなかった")
    }
} catch {
    check("exporter-setup", false, detail: "\(error)")
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
