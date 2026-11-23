import XCTest
@testable import YMM4Core

/// showinfo 時刻項目の解析と、プロセス起動引数の純粋テスト
/// （Issue #70 段階2）。行の形式は着工前実測で ffmpeg 9.0.2 の
/// 実出力から採取したもの。
final class FFmpegShowinfoParserTests: XCTestCase {
    func testParsesCFRFrameLine() {
        let line = "[Parsed_showinfo_0 @ 0x12fe15180] n:   0 pts:      0 pts_time:0 duration: 1001 duration_time:0.033367 fmt:yuv420p cl:left sar:1/1 s:320x180 i:P iskey:1 type:I checksum:0x00000000 plane_checksum:[0x00000000] mean:[128] stdev:[0.0]"
        let entry = FFmpegShowinfoParser.parseTimeEntry(fromLine: line)
        XCTAssertEqual(entry?.startSeconds, 0)
        XCTAssertEqual(entry?.durationSeconds ?? -1, 0.033367, accuracy: 0.0000005)
    }

    func testParsesOffsetFrameLine() {
        // 開始オフセット付き素材（-copyts で絶対時刻が保持される）。
        let line = "[Parsed_showinfo_0 @ 0x12fe15180] n:   0 pts:   3500 pts_time:3.5 duration: 33 duration_time:0.033 fmt:yuv420p s:320x180"
        let entry = FFmpegShowinfoParser.parseTimeEntry(fromLine: line)
        XCTAssertEqual(entry?.startSeconds, 3.5)
        XCTAssertEqual(entry?.durationSeconds ?? -1, 0.033, accuracy: 0.0000005)
    }

    func testParsesMicrosecondPrecision() {
        // TS の開始オフセット（1.466667 秒）。
        let line = "[Parsed_showinfo_0 @ 0x12fe15180] n:   0 pts: 132000 pts_time:1.466667 duration: 3000 duration_time:0.033333 fmt:yuv420p s:320x180"
        let entry = FFmpegShowinfoParser.parseTimeEntry(fromLine: line)
        XCTAssertEqual(entry?.startSeconds ?? -1, 1.466667, accuracy: 0.0000005)
    }

    func testRejectsNonFrameLines() {
        // showinfo の設定行（pts_time を含まない）。
        let configLine = "[Parsed_showinfo_0 @ 0x12fe15180] config in time_base: 1/30, frame_rate: 30/1"
        XCTAssertFalse(FFmpegShowinfoParser.isFrameTimeLine(configLine))
        XCTAssertNil(FFmpegShowinfoParser.parseTimeEntry(fromLine: configLine))
        // 通常のログ行。
        let logLine = "[info] Output #0, rawvideo, to 'pipe:':"
        XCTAssertFalse(FFmpegShowinfoParser.isFrameTimeLine(logLine))
        XCTAssertNil(FFmpegShowinfoParser.parseTimeEntry(fromLine: logLine))
        // pts_time を含むが showinfo でない行は数えない。
        let otherLine = "[Parsed_metadata_0 @ 0x0] pts_time:1.0"
        XCTAssertFalse(FFmpegShowinfoParser.isFrameTimeLine(otherLine))
    }
}

final class FFmpegVideoProcessArgumentsTests: XCTestCase {
    private func request(
        seekTargetSeconds: Double?, seekStyle: FFmpegVideoSeekStyle,
        videoStreamIndex: Int = 0
    ) -> FFmpegVideoProcessRequest {
        FFmpegVideoProcessRequest(
            ffmpegPath: "/dev/ffmpeg", filePath: "/dev/movie.mkv",
            videoStreamIndex: videoStreamIndex, frameByteCount: 320 * 180 * 4,
            seekTargetSeconds: seekTargetSeconds, seekStyle: seekStyle
        )
    }

    func testInputSeekPlacesSeekBeforeInputAndAlwaysCopyts() {
        let arguments = FFmpegVideoProcessArguments.arguments(
            for: request(seekTargetSeconds: 2.5, seekStyle: .input)
        )
        let seekIndex = arguments.firstIndex(of: "-ss")
        let inputIndex = arguments.firstIndex(of: "-i")
        XCTAssertNotNil(seekIndex)
        XCTAssertNotNil(inputIndex)
        XCTAssertLessThan(seekIndex!, inputIndex!)
        XCTAssertEqual(arguments[seekIndex! + 1], "2.500000")
        XCTAssertTrue(arguments.contains("-copyts"))
    }

    func testOutputSeekPlacesSeekAfterInput() {
        let arguments = FFmpegVideoProcessArguments.arguments(
            for: request(seekTargetSeconds: 2.5, seekStyle: .output)
        )
        let seekIndex = arguments.firstIndex(of: "-ss")
        let inputIndex = arguments.firstIndex(of: "-i")
        XCTAssertNotNil(seekIndex)
        XCTAssertNotNil(inputIndex)
        XCTAssertGreaterThan(seekIndex!, inputIndex!)
        XCTAssertTrue(arguments.contains("-copyts"))
    }

    func testNoSeekStillCarriesCopyts() {
        // 先頭からの場合も -copyts は付く（絶対時刻の保持）。
        let arguments = FFmpegVideoProcessArguments.arguments(
            for: request(seekTargetSeconds: nil, seekStyle: .input)
        )
        XCTAssertFalse(arguments.contains("-ss"))
        XCTAssertTrue(arguments.contains("-copyts"))
    }

    func testStreamMappingAndOutputFormat() {
        let arguments = FFmpegVideoProcessArguments.arguments(
            for: request(seekTargetSeconds: nil, seekStyle: .input, videoStreamIndex: 2)
        )
        let mapIndex = arguments.firstIndex(of: "-map")
        XCTAssertNotNil(mapIndex)
        XCTAssertEqual(arguments[mapIndex! + 1], "0:2")
        // VFR は passthrough（cfr の複製は使わない）。
        let fpsIndex = arguments.firstIndex(of: "-fps_mode")
        XCTAssertNotNil(fpsIndex)
        XCTAssertEqual(arguments[fpsIndex! + 1], "passthrough")
        let formatIndex = arguments.firstIndex(of: "-pix_fmt")
        XCTAssertEqual(arguments[formatIndex! + 1], "bgra")
        XCTAssertTrue(arguments.contains("showinfo"))
        XCTAssertEqual(arguments.last, "-")
    }
}
