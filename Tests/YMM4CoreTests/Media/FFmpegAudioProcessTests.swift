import XCTest
@testable import YMM4Core

/// ashowinfo の解析と音声プロセスの引数（純粋関数）のテスト
/// （Issue #70 段階3）。
final class FFmpegAudioProcessTests: XCTestCase {
    // MARK: - ashowinfo 解析

    func testParseEntryWithFractionalTime() {
        let line = "[Parsed_ashowinfo_0 @ 0x8b1048900] n:0 pts:0 pts_time:0 fmt:fltp channels:2 chlayout:stereo rate:48000 nb_samples:1024 checksum:00000000 plane_checksums: [ 00000000 00000000 ]"
        let entry = FFmpegAshowinfoParser.parseEntry(fromLine: line)
        XCTAssertEqual(entry?.startSeconds, 0)
        XCTAssertEqual(entry?.sampleCount, 1024)
    }

    func testParseEntryWithLongFraction() {
        let line = "[Parsed_ashowinfo_0 @ 0xae2c44900] n:0 pts:1105 pts_time:0.0230208 fmt:fltp channels:2 chlayout:stereo rate:48000 nb_samples:47 checksum:00000000 plane_checksums: [ 00000000 00000000 ]"
        let entry = FFmpegAshowinfoParser.parseEntry(fromLine: line)
        XCTAssertEqual(entry?.startSeconds ?? -1, 0.0230208, accuracy: 0.0000001)
        XCTAssertEqual(entry?.sampleCount, 47)
    }

    func testParseEntryRejectsOtherLines() {
        XCTAssertNil(FFmpegAshowinfoParser.parseEntry(
            fromLine: "[in#0 @ 0x123] Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'x.m4a':"
        ))
        XCTAssertNil(FFmpegAshowinfoParser.parseEntry(
            fromLine: "[aac @ 0x123] error while decoding stream"
        ))
        XCTAssertFalse(FFmpegAshowinfoParser.isFrameEntryLine("plain log line"))
        XCTAssertTrue(FFmpegAshowinfoParser.isFrameEntryLine(
            "[Parsed_ashowinfo_0 @ 0x1] n:0 pts:0 pts_time:0 nb_samples:1"
        ))
    }

    // MARK: - 起動引数

    private func makeRequest(
        seek: Double?, usesOutputSeek: Bool
    ) -> FFmpegAudioProcessRequest {
        FFmpegAudioProcessRequest(
            executablePath: "/dev/ffmpeg", filePath: "/media/a.mkv",
            audioStreamIndex: 2, seekTargetSeconds: seek,
            usesOutputSeek: usesOutputSeek
        )
    }

    func testArgumentsWithoutSeek() {
        let arguments = FFmpegAudioProcessArguments.arguments(
            for: makeRequest(seek: nil, usesOutputSeek: false)
        )
        XCTAssertEqual(arguments, [
            "-v", "info", "-nostdin",
            "-copyts", "-i", "/media/a.mkv",
            "-map", "0:2", "-af", "ashowinfo", "-ac", "2",
            "-vn", "-sn", "-dn", "-f", "f32le", "-",
        ])
    }

    func testArgumentsWithInputSeek() {
        let arguments = FFmpegAudioProcessArguments.arguments(
            for: makeRequest(seek: 12.5, usesOutputSeek: false)
        )
        XCTAssertEqual(arguments, [
            "-v", "info", "-nostdin",
            "-ss", "12.500000", "-copyts", "-i", "/media/a.mkv",
            "-map", "0:2", "-af", "ashowinfo", "-ac", "2",
            "-vn", "-sn", "-dn", "-f", "f32le", "-",
        ])
    }

    func testArgumentsWithOutputSeek() {
        let arguments = FFmpegAudioProcessArguments.arguments(
            for: makeRequest(seek: 12.5, usesOutputSeek: true)
        )
        XCTAssertEqual(arguments, [
            "-v", "info", "-nostdin",
            "-copyts", "-i", "/media/a.mkv", "-ss", "12.500000",
            "-map", "0:2", "-af", "ashowinfo", "-ac", "2",
            "-vn", "-sn", "-dn", "-f", "f32le", "-",
        ])
    }
}
