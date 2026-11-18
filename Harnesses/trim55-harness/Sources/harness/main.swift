import Foundation
import YMM4Core
import YMM4GPU

// TRIM55 ハーネス: 提示タイムスタンプとトリムの実測。
//
// 使い方: harness <素材ファイルのパス>
// 出力: hz / duration（秒・フレーム換算）/ 全読みでの最初の
// 非無音フレーム / 最後の非無音フレーム / 総フレーム数 /
// 論理 0.4s・0.5s・0.6s へシークした直後のサンプル値。
//
// 測定素材は「無音 0.5 秒 + 440Hz トーン 1.0 秒 + 無音 0.5 秒、
// 48kHz ステレオ」が正解（トーン区間 = 論理フレーム
// [24000, 72000)）であり、提示開始オフセットやエンコーダ遅延を
// 持つ素材でも、論理位置がこの区間に一致するかを測る。

let threshold: Float = 0.01

guard CommandLine.arguments.count >= 2 else {
    print("usage: harness <media file>")
    exit(2)
}
let path = CommandLine.arguments[1]

let factory = AVFoundationPCMProviderFactory()
guard let provider = factory.createProvider(filePath: path, audioTrackIndex: 0) else {
    print("RESULT openFailed")
    exit(1)
}

let hz = provider.hz
let durationSeconds = Double(provider.duration.ticks) / 10_000_000.0
let durationFrames = durationSeconds * Double(hz)
print("hz=\(hz) durationSeconds=\(durationSeconds) durationFrames=\(durationFrames)")

// 全読み（論理位置 0 から）。
provider.seek(toTime: .zero)
var buffer = [Float](repeating: 0, count: 8192)
var frame = 0
var firstAudible = -1
var lastAudible = -1
var totalFrames = 0
while true {
    let read = provider.read(into: &buffer, offset: 0, count: buffer.count)
    if read <= 0 { break }
    let frames = read / 2
    for index in 0..<frames {
        let l = abs(buffer[index * 2])
        let r = abs(buffer[index * 2 + 1])
        if l > threshold || r > threshold {
            if firstAudible < 0 { firstAudible = frame + index }
            lastAudible = frame + index
        }
    }
    frame += frames
    totalFrames += frames
}
print("totalFrames=\(totalFrames) firstAudible=\(firstAudible) lastAudible=\(lastAudible)")

// シーク着地: 論理 0.4s（無音のはず）/ 0.5s（トーン開始境界）/
// 0.6s（トーンのはず）/ 1.5s（トーン終了境界）へシークし、
// 直後の 8 フレームの最大振幅を出す。
for seconds in [0.4, 0.5, 0.6, 1.5] {
    let ticks = Int64(seconds * 10_000_000)
    provider.seek(toTime: TimeSpanValue(ticks: ticks))
    var small = [Float](repeating: 0, count: 16)
    let read = provider.read(into: &small, offset: 0, count: small.count)
    var peak: Float = 0
    for index in 0..<read { peak = max(peak, abs(small[index])) }
    print("seek \(seconds)s -> read=\(read) peak=\(peak)")
}

// シーク着地誤差の直接測定: 論理 0.4s へシークして 0.3 秒分読み、
// トーン開始（論理 0.5s = シーク後 4800 フレーム）までに現れる
// 無音フレーム数を数える。着地が正確なら 4800 に一致する。
provider.seek(toTime: TimeSpanValue(ticks: 4_000_000))
var runBuffer = [Float](repeating: 0, count: 8192)
var silentFrames = 0
var foundTone = false
outer: while silentFrames < hz / 2 {
    let read = provider.read(into: &runBuffer, offset: 0, count: runBuffer.count)
    if read <= 0 { break }
    for index in 0..<(read / 2) {
        if abs(runBuffer[index * 2]) > threshold || abs(runBuffer[index * 2 + 1]) > threshold {
            foundTone = true
            break outer
        }
        silentFrames += 1
    }
}
print("seekLanding: from 0.4s, silentFramesBeforeTone=\(silentFrames) expected=4800 found=\(foundTone)")
