import Foundation
import YMM4Core
import YMM4GPU

/// MAC-0026 検証ハーネス。
///
/// ffmpeg が Mac に無いため、実書き出しの検証はスタブ ffmpeg
/// （引数を記録し stdin を捕捉するシェルスクリプト）に対して行う。
/// 検証範囲: 供給側の実接続（GPU 合成→BGRA 読み戻し→NV12 変換、
/// 実ミックス→ラウドネス→DynamicsProcessor→f32le）、ExportSession と
/// FFmpegProcessWriter のプロセス駆動（起動・書き込み・終了コード・
/// mux 呼び出し）。実エンコードと mp4 の再生可否は対象外。
///
/// 引数: <作業ディレクトリ> <スタブ ffmpeg のパス>

var failures = 0
@MainActor
func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { failures += 1 }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: harness <workDir> <stubFfmpegPath>")
    exit(2)
}
let workDir = arguments[1]
let stubPath = arguments[2]
let fm = FileManager.default
try! fm.createDirectory(atPath: workDir, withIntermediateDirectories: true)
let wavPath = workDir + "/sine.wav"
let outputPath = workDir + "/export.mp4"
let captureDir = workDir + "/capture"

// MARK: - WAV 生成（PCM16 ステレオ、440 Hz サイン、振幅 0.5、1 秒 @ 48kHz）

func writeWAV(path: String) {
    let hz = 48_000
    let frames = hz
    var data = Data()
    func appendU16(_ value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    func appendU32(_ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    func appendTag(_ tag: String) { data.append(contentsOf: tag.utf8) }
    let dataBytes = frames * 2 * 2
    appendTag("RIFF")
    appendU32(UInt32(36 + dataBytes))
    appendTag("WAVE")
    appendTag("fmt ")
    appendU32(16)
    appendU16(1) // PCM
    appendU16(2) // channels
    appendU32(UInt32(hz))
    appendU32(UInt32(hz * 4))
    appendU16(4) // block align
    appendU16(16) // bits
    appendTag("data")
    appendU32(UInt32(dataBytes))
    for frame in 0..<frames {
        let value = sin(2 * Double.pi * 440 * Double(frame) / Double(hz)) * 0.5
        let intValue = Int16((value * 32767).rounded())
        var v = intValue.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    try! data.write(to: URL(fileURLWithPath: path))
}
writeWAV(path: wavPath)

// MARK: - プロジェクト構築（64×48 / 30fps / 48kHz、30 フレーム）

let timeline = Timeline()
var info = VideoInfo()
info.width = 64
info.height = 48
info.fps = 30
info.hz = 48_000
timeline.videoInfo = info

let shape = ShapeItem()
shape.frame = 0
shape.length = 30
shape.layer = 0
if case .rectangle(let rect) = shape.shapeParameter {
    rect.sizeMode = .widthHeight
    rect.width = Animation(defaultValue: 32, minValue: 0, maxValue: 100_000)
    rect.height = Animation(defaultValue: 24, minValue: 0, maxValue: 100_000)
}

let audio = AudioItem()
audio.frame = 0
audio.length = 30
audio.layer = 1
audio.filePath = wavPath
audio.volume = Animation(
    defaultValue: 100, minValue: -100_000, maxValue: 100_000,
    animationType: .none, values: [AnimationValue(100)]
)
audio.pan = Animation(
    defaultValue: 0, minValue: -100_000, maxValue: 100_000,
    animationType: .none, values: [AnimationValue(0)]
)

timeline.items = [shape, audio]
timeline.refreshTimelineLengthAndMaxLayer()
check(timeline.length == 30, "timeline length == 30 (actual \(timeline.length))")

// MARK: - 書き出し実行

guard let exporter = TimelineExporter(
    timeline: timeline, timelines: [timeline], baseDirectory: nil
) else {
    print("FAIL: TimelineExporter を初期化できませんでした")
    exit(1)
}
let analysis = exporter.analysisResult
print(
    "analysis: peakDb=\(analysis.peakDb) loudness=\(analysis.averageLoudness) "
        + "volumeRate=\(analysis.volumeRate) compressorRate=\(analysis.compressorRate)"
)
check(abs(analysis.peakDb - (-6.02)) < 0.05, "peak ≈ -6.02 dB")
check(abs(analysis.volumeRate - 1) < 1e-6, "volumeRate == 1")
check(abs(analysis.compressorRate - 1) < 1e-6, "compressorRate == 1")

let outcome: ExportOutcome
do {
    outcome = try exporter.run(outputPath: outputPath, ffmpegPath: stubPath)
} catch {
    print("FAIL: run が例外: \(error)")
    exit(1)
}
print(
    "outcome: completion=\(outcome.completion) frames=\(outcome.framesWritten) "
        + "output=\(outcome.outputProduced) error=\(outcome.error?.message ?? "-")"
)
check(outcome.completion == .completed, "completion == .completed")
check(outcome.framesWritten == 30, "framesWritten == 30")
check(outcome.outputProduced, "outputProduced == true")
check(fm.fileExists(atPath: outputPath), "mux output file exists")

// MARK: - 映像 stdin の検証（NV12、フレーム 15）

let frameBytes = 64 * 48 * 3 / 2
let videoCapturePath = captureDir + "/export.mp4.video.tmp.stdin"
let videoData = (try? Data(contentsOf: URL(fileURLWithPath: videoCapturePath))) ?? Data()
check(
    videoData.count == frameBytes * 30,
    "video stdin bytes == \(frameBytes * 30) (actual \(videoData.count))"
)
if videoData.count == frameBytes * 30 {
    let frameOffset = 15 * frameBytes
    let centerY = Int(videoData[frameOffset + 24 * 64 + 32])
    let cornerY = Int(videoData[frameOffset])
    print("frame15 NV12: centerY=\(centerY) cornerY=\(cornerY)")
    check(abs(centerY - 235) <= 3, "center Y ≈ 235 (white shape)")
    check(abs(cornerY - 16) <= 3, "corner Y ≈ 16 (transparent black)")

    // プレビュー合成（同じ合成経路）との画素一致。
    if let provider = MetalExportVideoProvider(
        timeline: timeline, timelines: [timeline], baseDirectory: nil
    ) {
        let buffer = ExportVideoFrameBuffer(byteCount: 64 * 48 * 4)
        do {
            try provider.fillFrame(15, into: buffer)
            let expected = NV12Conversion.convert(bgra: buffer.bytes, width: 64, height: 48)
            var maxDiff = 0
            var totalDiff = 0
            for index in 0..<(64 * 48) {
                let diff = abs(Int(videoData[frameOffset + index]) - Int(expected[index]))
                maxDiff = max(maxDiff, diff)
                totalDiff += diff
            }
            let meanDiff = Double(totalDiff) / Double(64 * 48)
            print("preview vs export Y plane: maxDiff=\(maxDiff) meanDiff=\(meanDiff)")
            check(maxDiff <= 2, "Y plane max diff <= 2")
            check(meanDiff < 0.5, "Y plane mean diff < 0.5")
        } catch {
            check(false, "preview fillFrame threw: \(error)")
        }
        provider.dispose()
    } else {
        check(false, "MetalExportVideoProvider を初期化できませんでした")
    }
}

// MARK: - 音声 stdin の検証（f32le、サイン波）

let audioCapturePath = captureDir + "/export.mp4.audio.tmp.stdin"
let audioData = (try? Data(contentsOf: URL(fileURLWithPath: audioCapturePath))) ?? Data()
check(
    audioData.count == 96_000 * 4,
    "audio stdin bytes == \(96_000 * 4) (actual \(audioData.count))"
)
if audioData.count == 96_000 * 4 {
    let floats: [Float] = audioData.withUnsafeBytes { source in
        Array(source.bindMemory(to: Float.self))
    }
    var sumSquares = 0.0
    var peak: Float = 0
    for sample in floats {
        sumSquares += Double(sample) * Double(sample)
        peak = max(peak, abs(sample))
    }
    let rms = sqrt(sumSquares / Double(floats.count))
    print("audio: rms=\(rms) peak=\(peak) first=\(floats[0])")
    check(abs(rms - 0.3536) < 0.01, "RMS ≈ 0.3536 (sine amp 0.5)")
    check(abs(peak - 0.5) < 0.02, "peak ≈ 0.5")
    check(abs(floats[0]) < 0.01, "first sample ≈ 0 (sine start)")
}

// MARK: - スタブの呼び出し記録（音声・映像・mux の 3 起動）

let logPath = workDir + "/stub.log"
let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
let callCount = log.components(separatedBy: "CALL:").count - 1
print("stub calls: \(callCount)")
check(callCount == 3, "ffmpeg stub invoked 3 times (audio, video, mux)")
check(log.contains("-c copy") || log.contains("copy"), "mux invocation used -c copy")

exporter.dispose()
print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
