#if os(macOS)
import Foundation
import XCTest
@testable import YMM4GPU
import YMM4Core

/// 提示タイムスタンプとトリム（Issue #55）の検証。
///
/// 本家のファイルソースは論理時刻 0 を素材の提示開始位置
/// （`streamStartTime`）に置き、シークはプリロール（前方から
/// 読み直す）＋提示時刻での着地で行う。移植側も同じ方式に
/// そろえたため、ここでは方式変更で従来素材の結果が変わらない
/// ことを固定する:
/// - プリロール（1 秒）より短い素材でもシークがサンプル単位で
///   着地すること（プリロールのクランプ境界）
/// - 終端付近へのシークと終端後の読みが壊れないこと
///
/// 提示開始オフセットを持つ実素材（ffmpeg で生成した開始時刻
/// 付き MP4 / MOV、AAC、MP3）での開始位置の実測は
/// `Harnesses/trim55-harness` が担う（テスト内で生成できない
/// 形式のため）。フィクスチャの符号化は
/// `StreamingPCMProviderTests` と同じ（L = frame % 32768、
/// R = (frame * 7) % 32768、読み値は /32768 で復元）。
final class PresentationTimestampTests: XCTestCase {

    private let hz = 48_000

    private func makeWAV(frameCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymm4-trim55-test-\(UUID().uuidString).wav")
        let dataSize = frameCount * 4
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
        data.reserveCapacity(44 + dataSize)
        for frame in 0..<frameCount {
            var left = Int16(frame % 32768).littleEndian
            var right = Int16((frame * 7) % 32768).littleEndian
            data.append(Data(bytes: &left, count: 2))
            data.append(Data(bytes: &right, count: 2))
        }
        try data.write(to: url)
        return url
    }

    private func makeProvider(frameCount: Int) throws -> (PCMProvider, URL) {
        let url = try makeWAV(frameCount: frameCount)
        let factory = AVFoundationPCMProviderFactory(baseDirectory: nil)
        let provider = try XCTUnwrap(
            factory.createProvider(filePath: url.path, audioTrackIndex: 0)
        )
        return (provider, url)
    }

    private func decodedInt16(_ value: Float) -> Int {
        Int((value * 32768).rounded())
    }

    private func assertFrame(_ provider: PCMProvider, startsAt expectedFrame: Int, frames: Int) {
        var buffer = [Float](repeating: 0, count: frames * 2)
        let read = provider.read(into: &buffer, offset: 0, count: frames * 2)
        XCTAssertEqual(read, frames * 2)
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

    private func seek(_ provider: PCMProvider, toFrame target: Int) {
        provider.seek(toTime: TimeSpanValue(
            ticks: Int64(target) * 10_000_000 / Int64(hz)
        ))
    }

    /// プリロール（1 秒）より短い素材でのシーク着地。プリロールの
    /// 開始位置は素材先頭でクランプされる。
    func testSeekWithinPrerollSizedFile() throws {
        let frameCount = 24_000 // 0.5 秒
        let (provider, url) = try makeProvider(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(provider.duration.ticks, 5_000_000)
        for target in [0, 1, 12_000, 23_900] {
            seek(provider, toFrame: target)
            assertFrame(provider, startsAt: target, frames: 100)
        }
    }

    /// プリロール境界（ちょうど 1 秒前後）をまたぐシーク着地。
    func testSeekAcrossPrerollBoundary() throws {
        let frameCount = 144_000 // 3 秒
        let (provider, url) = try makeProvider(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }
        for target in [47_999, 48_000, 48_001, 96_000, 143_000] {
            seek(provider, toFrame: target)
            assertFrame(provider, startsAt: target, frames: 200)
        }
        // 後方への大きなシーク（リーダー作り直し＋プリロール）。
        seek(provider, toFrame: 10)
        assertFrame(provider, startsAt: 10, frames: 200)
    }

    /// 終端付近へのシーク: 残りが正確に返り、その後は 0 を返す。
    func testSeekNearEnd() throws {
        let frameCount = 96_000 // 2 秒
        let (provider, url) = try makeProvider(frameCount: frameCount)
        defer { try? FileManager.default.removeItem(at: url) }
        seek(provider, toFrame: frameCount - 100)
        assertFrame(provider, startsAt: frameCount - 100, frames: 100)
        var buffer = [Float](repeating: 0, count: 200)
        XCTAssertEqual(provider.read(into: &buffer, offset: 0, count: 200), 0)
    }
}
#endif
