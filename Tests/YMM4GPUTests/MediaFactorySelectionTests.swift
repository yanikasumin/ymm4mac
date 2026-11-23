import Foundation
import Metal
import XCTest
@testable import YMM4GPU
import YMM4Core

/// Factory 層のデコーダ選択の実機テスト（Issue #70 段階3）。
///
/// 選択規則（AVFoundation → FFmpeg、実際に開けて初回読み取り／
/// 初回フレームができることで確定）を、実素材で固定する:
/// - AVFoundation で開ける素材（WAV / MP4）は AVFoundation が選ばれる
/// - 開けない形式（MKV）は FFmpeg が選ばれる
/// - メタ情報だけ取れて復号できない素材（mdat を潰した M4A / MP4）は
///   FFmpeg へ落ちる（M4A は FFmpeg でも復号できず nil、MP4 映像は
///   両方で開けず open が false）
/// 映像の選択先は台帳（MediaAvailabilityRegistry）の記録で観測する:
/// FFmpeg 経路を通ればプローブの記録が残り、AVFoundation で完結
/// すれば台帳は未試行のままになる。
final class MediaFactorySelectionTests: XCTestCase {
    private struct Fixture {
        var directory: URL
        var support: FFmpegMediaSupport
        var devices: MetalGraphicsDevices
    }

    private func runFFmpeg(
        _ ffmpegPath: String, _ arguments: [String]
    ) throws {
        let result = try FoundationProcessOutputRunner().run(
            executablePath: ffmpegPath, arguments: arguments
        )
        XCTAssertEqual(
            result.terminationStatus, 0,
            "ffmpeg 失敗: \(result.standardErrorText)"
        )
    }

    /// MP4 系のトップレベル box を走査し、mdat のペイロードを
    /// ゼロで潰す（moov は無事なためメタ情報は読めるが復号できない
    /// 素材になる）。
    private func zeroMDATPayload(of url: URL) throws {
        var data = try Data(contentsOf: url)
        var offset = 0
        while offset + 8 <= data.count {
            var size = (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16)
                | (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
            var headerSize = 8
            if size == 1 {
                var wide = 0
                for index in 0..<8 {
                    wide = (wide << 8) | Int(data[offset + 8 + index])
                }
                size = wide
                headerSize = 16
            }
            let type = String(
                bytes: data[(offset + 4)..<(offset + 8)], encoding: .ascii
            )
            if type == "mdat" {
                for index in (offset + headerSize)..<min(offset + size, data.count) {
                    data[index] = 0
                }
            }
            if size == 0 { break }
            offset += size
        }
        try data.write(to: url)
    }

    private func makeFixture() throws -> Fixture {
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
            .appendingPathComponent("MediaFactorySelectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let wav = directory.appendingPathComponent("tone.wav")
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-f", "lavfi",
            "-i", "sine=frequency=440:duration=2:sample_rate=48000",
            "-c:a", "pcm_s16le", wav.path,
        ])
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-i", wav.path, "-c:a", "flac",
            directory.appendingPathComponent("tone.mkv").path,
        ])
        let m4a = directory.appendingPathComponent("tone.m4a")
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-i", wav.path, "-c:a", "aac", m4a.path,
        ])
        let corruptAudio = directory.appendingPathComponent("corrupt.m4a")
        try FileManager.default.copyItem(at: m4a, to: corruptAudio)
        try zeroMDATPayload(of: corruptAudio)

        let videoMP4 = directory.appendingPathComponent("video.mp4")
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-f", "lavfi",
            "-i", "testsrc2=size=320x180:rate=30:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", videoMP4.path,
        ])
        try runFFmpeg(ffmpegPath, [
            "-v", "error", "-y", "-f", "lavfi",
            "-i", "testsrc2=size=320x180:rate=30:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            directory.appendingPathComponent("video.mkv").path,
        ])
        let corruptVideo = directory.appendingPathComponent("corrupt.mp4")
        try FileManager.default.copyItem(at: videoMP4, to: corruptVideo)
        try zeroMDATPayload(of: corruptVideo)

        return Fixture(
            directory: directory,
            support: FFmpegMediaSupport(resolution: resolution),
            devices: devices
        )
    }

    // MARK: - 音声の選択

    func testAudioSelectsAVFoundationForWAV() throws {
        let fixture = try makeFixture()
        let factory = fixture.support.makePCMProviderFactory(
            baseDirectory: fixture.directory
        )
        let provider = try XCTUnwrap(
            factory.createProvider(filePath: "tone.wav", audioTrackIndex: 0)
        )
        XCTAssertTrue(
            provider is AVFoundationStreamingPCMProvider,
            "WAV は AVFoundation が選ばれるはず: \(type(of: provider))"
        )
    }

    func testAudioSelectsFFmpegForMKV() throws {
        let fixture = try makeFixture()
        let factory = fixture.support.makePCMProviderFactory(
            baseDirectory: fixture.directory
        )
        let provider = try XCTUnwrap(
            factory.createProvider(filePath: "tone.mkv", audioTrackIndex: 0)
        )
        XCTAssertTrue(
            provider is FFmpegPCMProvider,
            "MKV は FFmpeg が選ばれるはず: \(type(of: provider))"
        )
        XCTAssertEqual(provider.hz, 48000)
        var buffer = [Float](repeating: 0, count: 9600)
        XCTAssertGreaterThan(
            provider.read(into: &buffer, offset: 0, count: buffer.count), 0
        )
    }

    func testAudioFallsThroughWhenAVFoundationCannotDecode() throws {
        let fixture = try makeFixture()
        let factory = fixture.support.makePCMProviderFactory(
            baseDirectory: fixture.directory
        )
        // mdat を潰した M4A: AVFoundation はメタ情報を読めて供給を
        // 返すが復号できず、FFmpeg でも復号できないため nil になる
        // （AVFoundation の供給がそのまま採用されないことが要点）。
        let provider = factory.createProvider(
            filePath: "corrupt.m4a", audioTrackIndex: 0
        )
        XCTAssertNil(provider)
        let key = MediaMaterialKey(
            filePath: fixture.directory.appendingPathComponent("corrupt.m4a").path
        )
        guard case .failed = fixture.support.registry.state(for: key) else {
            return XCTFail("FFmpeg 側の失敗が台帳に記録されるはず")
        }
    }

    // MARK: - 映像の選択

    func testVideoSelectsAVFoundationForMP4() throws {
        let fixture = try makeFixture()
        let supply = fixture.support.makeVideoSupply(devices: fixture.devices)
        let url = fixture.directory.appendingPathComponent("video.mp4")
        XCTAssertTrue(supply.open(filePath: url.path, url: url))
        XCTAssertNotNil(supply.frame(atAbsoluteSeconds: supply.presentationStartSeconds))
        // FFmpeg 経路を通っていないことは台帳が未試行であることで
        // 観測する（プローブが走れば記録が残る）。
        XCTAssertEqual(
            fixture.support.registry.state(
                for: MediaMaterialKey(filePath: url.path)
            ),
            .notAttempted
        )
        supply.close()
    }

    func testVideoSelectsFFmpegForMKV() throws {
        let fixture = try makeFixture()
        let supply = fixture.support.makeVideoSupply(devices: fixture.devices)
        let url = fixture.directory.appendingPathComponent("video.mkv")
        XCTAssertTrue(supply.open(filePath: url.path, url: url))
        let frame = try XCTUnwrap(
            supply.frame(atAbsoluteSeconds: supply.presentationStartSeconds)
        )
        XCTAssertEqual(frame.width, 320)
        XCTAssertEqual(frame.height, 180)
        XCTAssertNotEqual(
            fixture.support.registry.state(
                for: MediaMaterialKey(filePath: url.path)
            ),
            .notAttempted
        )
        supply.close()
    }

    func testVideoRejectsCorruptMP4() throws {
        let fixture = try makeFixture()
        let supply = fixture.support.makeVideoSupply(devices: fixture.devices)
        let url = fixture.directory.appendingPathComponent("corrupt.mp4")
        XCTAssertFalse(supply.open(filePath: url.path, url: url))
        supply.close()
    }

    // MARK: - MetalVideoSource への接続

    private func makeDescription() -> TimelineItemSourceDescription {
        let base = TimelineSourceDescription(
            screenSize: PixelSize(width: 320, height: 180),
            timelinePosition: FramePosition(frame: 0, fps: 30),
            timelineDuration: FramePosition(frame: 60, fps: 30),
            fps: 30,
            usage: .paused,
            sceneId: UUID(),
            scenes: []
        )
        return TimelineItemSourceDescription(
            base, itemFrame: 0, itemLength: 60, layer: 0
        )
    }

    func testMetalVideoSourceOpensMKVThroughSupport() throws {
        let fixture = try makeFixture()
        let support = fixture.support
        let devices = fixture.devices
        let item = VideoItem()
        item.filePath = fixture.directory.appendingPathComponent("video.mkv").path
        let source = MetalVideoSource(
            devices: devices, item: item, baseDirectory: fixture.directory,
            supplyFactory: { support.makeVideoSupply(devices: devices) }
        )
        try source.update(makeDescription())
        // 開ければ contentLength に供給の長さが反映される（開けない
        // 場合は .zero のまま）。
        XCTAssertEqual(item.contentLength.seconds, 2.0, accuracy: 0.05)
        source.dispose()
    }

    func testMetalVideoSourceOpensMP4ThroughSupport() throws {
        let fixture = try makeFixture()
        let support = fixture.support
        let devices = fixture.devices
        let item = VideoItem()
        item.filePath = fixture.directory.appendingPathComponent("video.mp4").path
        let source = MetalVideoSource(
            devices: devices, item: item, baseDirectory: fixture.directory,
            supplyFactory: { support.makeVideoSupply(devices: devices) }
        )
        try source.update(makeDescription())
        XCTAssertEqual(item.contentLength.seconds, 2.0, accuracy: 0.05)
        source.dispose()
    }
}
