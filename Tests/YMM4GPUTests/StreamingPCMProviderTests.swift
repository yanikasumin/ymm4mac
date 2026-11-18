#if os(macOS)
import Compression
import Darwin
import Foundation
import XCTest
@testable import YMM4GPU
import YMM4Core

/// ストリーミング PCM 供給（Issue #54）の検証。
///
/// フィクスチャは PCM16 ステレオ WAV で、サンプル値はフレーム番号
/// から復元できる符号化にする（L = frame % 32768、R = (frame * 7)
/// % 32768 を int16 として格納）。AVFoundation の 16bit → float
/// 変換は /32768（Issue #51 のテストで実測済み）なので、読み値から
/// フレーム番号を復元してシークの着地位置を検証できる。
final class StreamingPCMProviderTests: XCTestCase {

    private let hz = 48_000

    // MARK: - WAV 生成

    /// 決定的なサンプル列の WAV を一時ファイルへ書く。生成は
    /// チャンク単位で逐次書き込み、全量をメモリに持たない。
    private func makeWAV(frameCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymm4-stream54-test-\(UUID().uuidString).wav")
        let dataSize = frameCount * 2 * 2
        var header = Data()
        func appendString(_ string: String) { header.append(string.data(using: .ascii)!) }
        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            header.append(Data(bytes: &little, count: 4))
        }
        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            header.append(Data(bytes: &little, count: 2))
        }
        appendString("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(2) // channels
        appendUInt32(UInt32(hz))
        appendUInt32(UInt32(hz * 4))
        appendUInt16(4) // block align
        appendUInt16(16) // bits
        appendString("data")
        appendUInt32(UInt32(dataSize))
        try header.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let chunkFrames = 48_000
        var frame = 0
        while frame < frameCount {
            let count = min(chunkFrames, frameCount - frame)
            var chunk = Data()
            chunk.reserveCapacity(count * 4)
            for index in 0..<count {
                let current = frame + index
                var left = Int16(current % 32768).littleEndian
                var right = Int16((current * 7) % 32768).littleEndian
                chunk.append(Data(bytes: &left, count: 2))
                chunk.append(Data(bytes: &right, count: 2))
            }
            try handle.write(contentsOf: chunk)
            frame += count
        }
        return url
    }

    private func makeProvider(frameCount: Int) throws -> (PCMProvider, URL) {
        let url = try makeWAV(frameCount: frameCount)
        let factory = AVFoundationPCMProviderFactory(baseDirectory: nil)
        let provider = factory.createProvider(filePath: url.path, audioTrackIndex: 0)
        let unwrapped = try XCTUnwrap(provider)
        return (unwrapped, url)
    }

    /// 読み値（float）から格納した int16 を復元する。
    private func decodedInt16(_ value: Float) -> Int {
        Int((value * 32768).rounded())
    }

    private func assertFrame(_ provider: PCMProvider, startsAt expectedFrame: Int, frames: Int) {
        var buffer = [Float](repeating: 0, count: frames * 2)
        let read = provider.read(into: &buffer, offset: 0, count: frames * 2)
        XCTAssertEqual(read, frames * 2)
        for index in 0..<frames {
            let frame = expectedFrame + index
            XCTAssertEqual(decodedInt16(buffer[index * 2]), frame % 32768,
                           "L mismatch at frame \(frame)")
            XCTAssertEqual(decodedInt16(buffer[index * 2 + 1]), (frame * 7) % 32768,
                           "R mismatch at frame \(frame)")
            if index > 8 { break } // 失敗時の出力抑制（先頭のみ詳細確認）
        }
        // 全フレームの照合（失敗は件数で報告する）
        var mismatches = 0
        for index in 0..<frames {
            let frame = expectedFrame + index
            if decodedInt16(buffer[index * 2]) != frame % 32768
                || decodedInt16(buffer[index * 2 + 1]) != (frame * 7) % 32768 {
                mismatches += 1
            }
        }
        XCTAssertEqual(mismatches, 0, "mismatched frames: \(mismatches)")
    }

    // MARK: - 基本読み取り

    func testReadsEntireFileSequentially() throws {
        let frameCount = 96_000 // 2 秒
        let (provider, url) = try makeProvider(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(provider.hz, hz)
        // 2 秒 = 20,000,000 ticks
        XCTAssertEqual(provider.duration.ticks, 20_000_000)

        var total = 0
        var buffer = [Float](repeating: 0, count: 8192)
        var mismatches = 0
        while true {
            let read = provider.read(into: &buffer, offset: 0, count: buffer.count)
            if read <= 0 { break }
            for index in 0..<read {
                let sampleIndex = total + index
                let frame = sampleIndex / 2
                let expected = sampleIndex % 2 == 0
                    ? frame % 32768 : (frame * 7) % 32768
                if decodedInt16(buffer[index]) != expected { mismatches += 1 }
            }
            total += read
        }
        XCTAssertEqual(total, frameCount * 2)
        XCTAssertEqual(mismatches, 0)
        // 終端後は 0 を返し続ける
        XCTAssertEqual(provider.read(into: &buffer, offset: 0, count: 100), 0)
    }

    func testSmallReadsStayContinuous() throws {
        let frameCount = 10_000
        let (provider, url) = try makeProvider(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }
        // 奇数 count を含む小さな読み取りでも列が連続すること。
        var collected: [Float] = []
        var buffer = [Float](repeating: 0, count: 3)
        while collected.count < frameCount * 2 {
            let read = provider.read(into: &buffer, offset: 0, count: 3)
            if read <= 0 { break }
            collected.append(contentsOf: buffer[..<read])
        }
        XCTAssertEqual(collected.count, frameCount * 2)
        var mismatches = 0
        for (index, value) in collected.enumerated() {
            let frame = index / 2
            let expected = index % 2 == 0 ? frame % 32768 : (frame * 7) % 32768
            if decodedInt16(value) != expected { mismatches += 1 }
        }
        XCTAssertEqual(mismatches, 0)
    }

    // MARK: - シーク

    func testSeekLandsOnRequestedFrame() throws {
        let frameCount = 96_000
        let (provider, url) = try makeProvider(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }
        for target in [0, 100, 1, 44_100, 47_999, 95_000] {
            provider.seek(toTime: TimeSpanValue(
                ticks: Int64(target) * 10_000_000 / Int64(hz)
            ))
            assertFrame(provider, startsAt: target, frames: 200)
        }
    }

    func testSeekBackwardAfterReading() throws {
        let frameCount = 96_000
        let (provider, url) = try makeProvider(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }
        // 末尾近くまで読んでから先頭へ戻る（リーダーの作り直し経路）。
        provider.seek(toTime: TimeSpanValue(ticks: 19_000_000))
        assertFrame(provider, startsAt: 91_200, frames: 100)
        provider.seek(toTime: .zero)
        assertFrame(provider, startsAt: 0, frames: 200)
        // 再度前方へ。
        provider.seek(toTime: TimeSpanValue(ticks: 10_000_000))
        assertFrame(provider, startsAt: 48_000, frames: 200)
    }

    // MARK: - メモリ使用量

    private func physicalFootprint() -> Int64 {
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

    /// 指定秒数の素材を読み切り、その間の常駐メモリ増加量（ピーク）を
    /// 返す。供給元は読み切り後も保持したまま測る（全デコード方式は
    /// この時点でサンプル列全体を保持し続けるため、方式差が出る）。
    private func memoryGrowthReadingFile(seconds: Int) throws -> Int64 {
        let frameCount = hz * seconds
        let (provider, url) = try makeProvider(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = physicalFootprint()
        var peak = before
        var buffer = [Float](repeating: 0, count: 96_000)
        var total = 0
        while true {
            let read = provider.read(into: &buffer, offset: 0, count: buffer.count)
            if read <= 0 { break }
            total += read
            let now = physicalFootprint()
            if now > peak { peak = now }
        }
        XCTAssertEqual(total, frameCount * 2)
        withExtendedLifetime(provider) {}
        return peak - before
    }

    /// 長い素材でも常駐メモリが素材長に比例して増えないこと
    /// （Issue #54 の完了条件）。180 秒（float 換算で約 66MiB）と
    /// その倍の 360 秒で増加量を比べる。従来の全デコード方式では
    /// 供給元がサンプル列全体を保持し続け、180 秒で約 165MB
    /// （性能監査の実測）増えた。
    func testMemoryDoesNotGrowWithLongFile() throws {
        let growth180 = try memoryGrowthReadingFile(seconds: 180)
        let growth360 = try memoryGrowthReadingFile(seconds: 360)
        print("STREAM54 memory: growth180=\(growth180) growth360=\(growth360)")
        // どちらも 180 秒素材の float 換算量（約 66MiB）の半分未満。
        XCTAssertLessThan(growth180, 33 * 1024 * 1024,
                          "memory grew by \(growth180) bytes for a 180s file")
        XCTAssertLessThan(growth360, 33 * 1024 * 1024,
                          "memory grew by \(growth360) bytes for a 360s file")
        // 長さが倍になっても増加量は比例して増えない（1.5 倍未満）。
        XCTAssertLessThan(growth360, max(growth180 * 3 / 2, growth180 + 4 * 1024 * 1024),
                          "growth360=\(growth360) vs growth180=\(growth180)")
    }

    // MARK: - 一時ファイルの寿命（VoiceCache 経路）

    func testTemporaryFileProviderDeletesFileOnRelease() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymm4-stream54-temp-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        var provider: TemporaryFilePCMProvider? = TemporaryFilePCMProvider(
            inner: InMemoryPCMProvider(samples: [0, 0], hz: hz), fileURL: url
        )
        XCTAssertEqual(provider?.hz, hz)
        provider = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// VoiceCache 経路: 供給元が生きている間は一時ファイルが残り、
    /// 解放後に消えること（ストリーミング化に伴う所有権の変更）。
    func testVoiceCacheTemporaryFileLifetime() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        func voiceTempFiles() -> Set<String> {
            let entries = (try? FileManager.default.contentsOfDirectory(
                atPath: temporaryDirectory.path
            )) ?? []
            return Set(entries.filter { $0.hasPrefix("ymm4-voice-") })
        }
        let beforeFiles = voiceTempFiles()

        // 小さな WAV を Brotli 圧縮して VoiceItem へ入れる。Brotli
        // 相互運用そのものの担保は VoiceAudioProviderTests が担い、
        // ここでは一時ファイルの寿命だけを見るため、圧縮は
        // Compression フレームワーク（解凍側と同じ実装）で自己完結
        // させる。
        let wavURL = try makeWAV(frameCount: 2400)
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let wavData = try Data(contentsOf: wavURL)
        let compressed = try XCTUnwrap(Self.brotliCompress(wavData))
        let item = VoiceItem()
        item.voiceCache = compressed
        let resolver = VoicePCMProviderResolver(
            providerFactory: AVFoundationPCMProviderFactory(baseDirectory: nil)
        )
        var provider = resolver.provider(for: item)
        XCTAssertNotNil(provider)
        // 供給元の生存中は一時ファイルが存在し、読み取りできる。
        XCTAssertTrue(!voiceTempFiles().subtracting(beforeFiles).isEmpty)
        var buffer = [Float](repeating: 0, count: 4800)
        let read = provider?.read(into: &buffer, offset: 0, count: 4800) ?? 0
        XCTAssertEqual(read, 4800)
        provider = nil
        // 解放後に一時ファイルが消える。
        XCTAssertTrue(voiceTempFiles().subtracting(beforeFiles).isEmpty)
    }

    /// Compression フレームワークで Brotli 圧縮する（テスト用）。
    private static func brotliCompress(_ data: Data) -> Data? {
        let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPointer.deallocate() }
        guard compression_stream_init(
            streamPointer, COMPRESSION_STREAM_ENCODE, COMPRESSION_BROTLI
        ) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPointer) }
        var output = Data()
        let chunkSize = 64 * 1024
        var destinationBuffer = [UInt8](repeating: 0, count: chunkSize)
        return data.withUnsafeBytes { (sourceRaw: UnsafeRawBufferPointer) -> Data? in
            guard let sourceBase = sourceRaw.baseAddress else { return nil }
            streamPointer.pointee.src_ptr = sourceBase.assumingMemoryBound(to: UInt8.self)
            streamPointer.pointee.src_size = data.count
            while true {
                let status: compression_status = destinationBuffer
                    .withUnsafeMutableBufferPointer { destination in
                        streamPointer.pointee.dst_ptr = destination.baseAddress!
                        streamPointer.pointee.dst_size = chunkSize
                        let flags: Int32 = streamPointer.pointee.src_size == 0
                            ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                        return compression_stream_process(streamPointer, flags)
                    }
                let produced = chunkSize - streamPointer.pointee.dst_size
                if produced > 0 {
                    output.append(contentsOf: destinationBuffer[0..<produced])
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    return output
                case COMPRESSION_STATUS_OK:
                    continue
                default:
                    return nil
                }
            }
        }
    }
}
#endif
