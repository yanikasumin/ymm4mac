import Foundation
import Metal
import XCTest
@testable import YMM4GPU
import YMM4Core

/// FFmpeg デコーダ供給の実機テスト（Issue #70 段階2）。
///
/// 実物の ffmpeg と Metal デバイスが要るため、どちらも使えない
/// 環境では XCTSkip で明示的に飛ばす。フレームの正しさは Core 側
/// の実バイナリテストと同じ焼き込みストリップの機械読みで検証し、
/// BGRA → テクスチャ転写までを通す。
final class FFmpegVideoDecoderSupplyTests: XCTestCase {
    func testSupplyDeliversTextureWithBurnedFrameNumber() throws {
        let resolution = FFmpegBinaryResolver().resolveAll()
        try XCTSkipUnless(
            resolution.isComplete,
            "ffmpeg / ffprobe が解決できない環境のため実バイナリテストを省略"
        )
        let devices: MetalGraphicsDevices
        do {
            devices = try MetalGraphicsDevices()
        } catch {
            throw XCTSkip("Metal デバイスを生成できない環境: \(error)")
        }
        let ffmpegPath = try XCTUnwrap(resolution.ffmpeg?.path)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFmpegVideoDecoderSupplyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let mediaPath = directory.appendingPathComponent("cfr.mkv").path
        let strip = "lum='if(lt(Y\\,24)\\,255*mod(floor(N/pow(2\\,floor(X/20)))\\,2)\\,lum(X\\,Y))'"
        let generation = try FoundationProcessOutputRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-v", "error", "-y", "-f", "lavfi",
                "-i", "testsrc2=size=320x180:rate=30:duration=2,format=gray,geq=\(strip),format=yuv420p",
                "-c:v", "libx264", "-crf", "15", "-preset", "veryfast", "-g", "250",
                mediaPath,
            ]
        )
        XCTAssertEqual(generation.terminationStatus, 0, generation.standardErrorText)

        let registry = MediaAvailabilityRegistry()
        let manager = FFmpegVideoSessionManager(
            resolution: resolution, registry: registry, startsIdleTimer: false
        )
        let supply = FFmpegVideoDecoderSupply(devices: devices, manager: manager)
        XCTAssertTrue(supply.open(filePath: mediaPath, url: URL(fileURLWithPath: mediaPath)))
        XCTAssertEqual(supply.duration, TimeSpanValue(seconds: 2.0))
        XCTAssertEqual(supply.presentationStartSeconds, 0, accuracy: 0.001)

        let frame = try XCTUnwrap(supply.frame(atAbsoluteSeconds: 0.05))
        XCTAssertEqual(frame.width, 320)
        XCTAssertEqual(frame.height, 180)
        XCTAssertEqual(frame.startSeconds, 1.0 / 30.0, accuracy: 0.001)
        XCTAssertEqual(frame.endSeconds, 2.0 / 30.0, accuracy: 0.001)

        var bytes = [UInt8](repeating: 0, count: 320 * 180 * 4)
        bytes.withUnsafeMutableBytes { raw in
            frame.texture.getBytes(
                raw.baseAddress!, bytesPerRow: 320 * 4,
                from: MTLRegionMake2D(0, 0, 320, 180), mipmapLevel: 0
            )
        }
        XCTAssertEqual(Self.burnedIndex(bytes: bytes, width: 320), 1)
        supply.close()
        manager.shutdown()
    }

    /// 焼き込みストリップの機械読み（Core 側の実バイナリテストと
    /// 同じ規則: 行 6..17、ブロック b は列 b*20+5 ..< b*20+15）。
    private static func burnedIndex(bytes: [UInt8], width: Int) -> Int {
        var value = 0
        for block in 0..<16 {
            var sum = 0
            var count = 0
            for y in 6..<18 {
                for x in (block * 20 + 5)..<(block * 20 + 15) {
                    sum += Int(bytes[(y * width + x) * 4])
                    count += 1
                }
            }
            if sum / max(1, count) > 128 {
                value |= (1 << block)
            }
        }
        return value
    }
}
