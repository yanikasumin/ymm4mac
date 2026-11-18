import Darwin
import Foundation
import YMM4Core
import YMM4GPU

// STREAM54 ハーネス: 1 時間の WAV（48kHz / PCM16 / ステレオ、
// ファイル約 663MB、float 換算で約 1.38GB）を生成し、
// AVFoundationPCMProviderFactory の供給元で全量を読み切る。
// 読み取り中の phys_footprint のピーク増加量を測り、素材長に
// 比例して増えていないことを確認する。従来の全デコード方式では
// 供給元が約 1.38GB のサンプル列を保持し続ける計算になる。
//
// サンプル値はテスト（StreamingPCMProviderTests）と同じ符号化
// （L = frame % 32768、R = (frame * 7) % 32768）で、読み取り中に
// 全サンプルの照合も併せて行う。

let hz = 48_000
let seconds = 3600
let frameCount = hz * seconds

func physicalFootprint() -> Int64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
}

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

// MARK: - WAV 生成（逐次書き込み）

let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("ymm4-stream54-harness-1hour.wav")
let dataSize = frameCount * 4
let header: Data = {
    var data = Data()
    func appendString(_ string: String) { data.append(string.data(using: .ascii)!) }
    func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 4))
    }
    func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 2))
    }
    appendString("RIFF")
    appendUInt32(UInt32(36 + dataSize))
    appendString("WAVE")
    appendString("fmt ")
    appendUInt32(16)
    appendUInt16(1)
    appendUInt16(2)
    appendUInt32(UInt32(hz))
    appendUInt32(UInt32(hz * 4))
    appendUInt16(4)
    appendUInt16(16)
    appendString("data")
    appendUInt32(UInt32(dataSize))
    return data
}()

let generateStart = Date()
if !FileManager.default.fileExists(atPath: url.path)
    || (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) != dataSize + 44 {
    try! header.write(to: url)
    let handle = try! FileHandle(forWritingTo: url)
    try! handle.seekToEnd()
    let chunkFrames = 480_000
    var frame = 0
    var chunk = Data()
    while frame < frameCount {
        let count = min(chunkFrames, frameCount - frame)
        chunk.removeAll(keepingCapacity: true)
        chunk.reserveCapacity(count * 4)
        for index in 0..<count {
            let current = frame + index
            var left = Int16(current % 32768).littleEndian
            var right = Int16((current * 7) % 32768).littleEndian
            chunk.append(Data(bytes: &left, count: 2))
            chunk.append(Data(bytes: &right, count: 2))
        }
        try! handle.write(contentsOf: chunk)
        frame += count
    }
    try! handle.close()
}
print("generated: \(url.path) (\(dataSize + 44) bytes) in \(Date().timeIntervalSince(generateStart))s")

// MARK: - 読み切りとメモリ実測

let factory = AVFoundationPCMProviderFactory(baseDirectory: nil)
guard let provider = factory.createProvider(filePath: url.path, audioTrackIndex: 0) else {
    fail("provider creation returned nil")
}
guard provider.hz == hz else { fail("hz mismatch: \(provider.hz)") }
let expectedTicks: Int64 = 3600 * 10_000_000
guard provider.duration.ticks == expectedTicks else {
    fail("duration mismatch: \(provider.duration.ticks) != \(expectedTicks)")
}
print("PASS: provider metadata (hz=\(provider.hz), duration=1h)")

let before = physicalFootprint()
var peak = before
var buffer = [Float](repeating: 0, count: 96_000)
var total = 0
var mismatches = 0
let readStart = Date()
while true {
    let read = provider.read(into: &buffer, offset: 0, count: buffer.count)
    if read <= 0 { break }
    for index in 0..<read {
        let sampleIndex = total + index
        let frame = sampleIndex / 2
        let expected = sampleIndex % 2 == 0 ? frame % 32768 : (frame * 7) % 32768
        if Int((buffer[index] * 32768).rounded()) != expected { mismatches += 1 }
    }
    total += read
    let now = physicalFootprint()
    if now > peak { peak = now }
}
let readSeconds = Date().timeIntervalSince(readStart)
guard total == frameCount * 2 else { fail("total samples \(total) != \(frameCount * 2)") }
guard mismatches == 0 else { fail("sample mismatches: \(mismatches)") }
print("PASS: read entire 1h file (\(total) samples, \(readSeconds)s)")

let growth = peak - before
print("memory: before=\(before) peak=\(peak) growth=\(growth) bytes (\(growth / 1024 / 1024) MiB)")
// float 換算の素材量（約 1.38GB）の 1/16（約 88MiB）未満であること。
if growth < 88 * 1024 * 1024 {
    print("PASS: memory growth does not scale with file length")
} else {
    fail("memory grew by \(growth) bytes")
}

// 終端付近へのシーク着地も確認する。
provider.seek(toTime: TimeSpanValue(ticks: expectedTicks - 10_000_000))
var tail = [Float](repeating: 0, count: 200)
let tailRead = provider.read(into: &tail, offset: 0, count: 200)
var tailOK = tailRead == 200
if tailOK {
    for index in 0..<100 {
        let frame = frameCount - hz + index
        if Int((tail[index * 2] * 32768).rounded()) != frame % 32768 { tailOK = false }
        if Int((tail[index * 2 + 1] * 32768).rounded()) != (frame * 7) % 32768 { tailOK = false }
    }
}
if tailOK {
    print("PASS: seek near end lands on the requested frame")
} else {
    fail("seek near end mismatch (read=\(tailRead))")
}

// 終端以降へのシークが終端を即座に返すこと（R6-05）。修正前は
// 時間範囲未設定のリーダーが素材全体を先頭からデコードして
// 全量を捨てる経路に退化しており、1 時間素材では読み切りと
// 同程度の時間がかかる。経過時間を実測値として出す。
provider.seek(toTime: TimeSpanValue(ticks: expectedTicks + 10_000_000))
let beyondStart = Date()
var beyondBuffer = [Float](repeating: 0, count: 200)
let beyondRead = provider.read(into: &beyondBuffer, offset: 0, count: 200)
let beyondSeconds = Date().timeIntervalSince(beyondStart)
guard beyondRead == 0 else { fail("seek beyond end returned \(beyondRead)") }
print("PASS: seek beyond end returns EOF in \(beyondSeconds)s")

// 終端以降の後に先頭へ戻しても通常どおり読めること。
provider.seek(toTime: .zero)
var head = [Float](repeating: 0, count: 200)
let headRead = provider.read(into: &head, offset: 0, count: 200)
var headOK = headRead == 200
if headOK {
    for index in 0..<100 {
        if Int((head[index * 2] * 32768).rounded()) != index % 32768 { headOK = false }
        if Int((head[index * 2 + 1] * 32768).rounded()) != (index * 7) % 32768 { headOK = false }
    }
}
if headOK {
    print("PASS: seek back to start after beyond-end seek")
} else {
    fail("seek back to start mismatch (read=\(headRead))")
}
print("ALL PASS")
