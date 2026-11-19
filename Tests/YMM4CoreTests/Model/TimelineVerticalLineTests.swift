import XCTest
@testable import YMM4Core

/// グリッド線（本家 TimelineVerticalLine）のパラメータ読み書きと
/// 線位置計算の固定（FE-UNIT5 で設定画面と描画を接続した際の根拠）。
final class TimelineVerticalLineTests: XCTestCase {

    // MARK: - パラメータの読み書き（保持 JSON の往復保全）

    func testBPMDefaultAndRoundTrip() {
        var line = TimelineVerticalLine()
        XCTAssertEqual(line.lineType, .bpm)
        XCTAssertEqual(line.bpm, 100)
        line.bpm = 128.5
        XCTAssertEqual(line.bpm, 128.5)
        // $type は保持され、BPM フィールドだけが書き換わる。
        XCTAssertEqual(
            line.line.typeName,
            "YukkuriMovieMaker.Project.VerticalBPMLine, YukkuriMovieMaker.Plugin"
        )
        let decoded = TimelineVerticalLine.decode(from: line.encodeToJSONValue())
        XCTAssertEqual(decoded.bpm, 128.5)
        XCTAssertEqual(decoded.lineType, .bpm)
    }

    func testFrameIntervalRoundTrip() {
        var line = TimelineVerticalLine()
        line.lineType = .frame
        XCTAssertEqual(line.frameInterval, 30)
        line.frameInterval = 45
        XCTAssertEqual(line.frameInterval, 45)
        let decoded = TimelineVerticalLine.decode(from: line.encodeToJSONValue())
        XCTAssertEqual(decoded.lineType, .frame)
        XCTAssertEqual(decoded.frameInterval, 45)
    }

    func testSpanTicksRoundTrip() {
        var line = TimelineVerticalLine()
        line.lineType = .time
        XCTAssertEqual(line.spanTicks, 5_000_000)
        line.spanTicks = 15_000_000
        XCTAssertEqual(line.spanTicks, 15_000_000)
        // 保持形式は .NET の TimeSpan 文字列。
        XCTAssertEqual(line.line.value.field("Span")?.stringValue, "00:00:01.5000000")
        let decoded = TimelineVerticalLine.decode(from: line.encodeToJSONValue())
        XCTAssertEqual(decoded.lineType, .time)
        XCTAssertEqual(decoded.spanTicks, 15_000_000)
    }

    func testSetterDoesNotPolluteOtherTypes() {
        var line = TimelineVerticalLine()
        line.lineType = .frame
        line.bpm = 200
        XCTAssertNil(line.line.value.field("BPM"))
        XCTAssertEqual(line.frameInterval, 30)
    }

    // MARK: - TimeSpan 文字列変換

    func testTimeSpanStringConversion() {
        XCTAssertEqual(
            TimelineVerticalLine.ticks(fromTimeSpanString: "00:00:00.5000000"),
            5_000_000
        )
        XCTAssertEqual(
            TimelineVerticalLine.ticks(fromTimeSpanString: "01:02:03"),
            3_723 * 10_000_000
        )
        XCTAssertEqual(
            TimelineVerticalLine.ticks(fromTimeSpanString: "1.02:00:00"),
            (86_400 + 7_200) * 10_000_000
        )
        XCTAssertEqual(
            TimelineVerticalLine.ticks(fromTimeSpanString: "02:30"),
            150 * 10_000_000
        )
        XCTAssertEqual(
            TimelineVerticalLine.ticks(fromTimeSpanString: "0.25"),
            2_500_000
        )
        XCTAssertNil(TimelineVerticalLine.ticks(fromTimeSpanString: "abc"))
        XCTAssertNil(TimelineVerticalLine.ticks(fromTimeSpanString: ""))
        XCTAssertEqual(
            TimelineVerticalLine.timeSpanString(fromTicks: 5_000_000),
            "00:00:00.5000000"
        )
        XCTAssertEqual(
            TimelineVerticalLine.timeSpanString(fromTicks: 3_723 * 10_000_000),
            "01:02:03"
        )
        XCTAssertEqual(
            TimelineVerticalLine.timeSpanString(fromTicks: (86_400 + 7_200) * 10_000_000),
            "1.02:00:00"
        )
    }

    // MARK: - 線位置（本家 GetLineFrames）

    private var videoInfo: VideoInfo { VideoInfo(fps: 30, hz: 48_000, width: 640, height: 360) }

    func testFrameLineFrames() {
        var line = TimelineVerticalLine()
        line.lineType = .frame
        line.frameInterval = 30
        line.startFrame = 0
        let frames = line.lineFrames(
            videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 95
        )
        // フレーム 0 は本家規則で除外される。
        XCTAssertEqual(frames.map(\.frame), [30, 60, 90])
        XCTAssertEqual(frames.map(\.index), [1, 2, 3])
    }

    func testFrameLineWithStartFrameOffset() {
        var line = TimelineVerticalLine()
        line.lineType = .frame
        line.frameInterval = 30
        line.startFrame = 10
        let frames = line.lineFrames(
            videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 100
        )
        XCTAssertEqual(frames.map(\.frame), [10, 40, 70, 100])
    }

    func testBPMLineFrames() {
        var line = TimelineVerticalLine()
        line.bpm = 120
        line.startFrame = 0
        // 120 BPM / 30 fps: 1拍 = 0.5 秒 = 15 フレーム。
        let frames = line.lineFrames(
            videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 46
        )
        XCTAssertEqual(frames.map(\.frame), [15, 30, 45])
    }

    func testTimeLineFrames() {
        var line = TimelineVerticalLine()
        line.lineType = .time
        line.spanTicks = 10_000_000  // 1 秒
        line.startFrame = 0
        let frames = line.lineFrames(
            videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 65
        )
        XCTAssertEqual(frames.map(\.frame), [30, 60])
    }

    func testEnumerateFromStartsNearViewport() {
        var line = TimelineVerticalLine()
        line.lineType = .frame
        line.frameInterval = 30
        let frames = line.lineFrames(
            videoInfo: videoInfo, enumerateFrom: 100, throughFrame: 200
        )
        XCTAssertEqual(frames.map(\.frame), [90, 120, 150, 180])
        XCTAssertEqual(frames.first?.index, 3)
    }

    // MARK: - 間引きとサブ線（本家 UpdateLines）

    func testDisplayLinesDisabled() {
        var line = TimelineVerticalLine()
        line.lineType = .frame
        XCTAssertTrue(
            line.displayLines(
                videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 300,
                pxPerFrame: 1
            ).isEmpty
        )
    }

    func testDisplayLinesSubLineFlag() {
        var line = TimelineVerticalLine()
        line.isEnabled = true
        line.lineType = .frame
        line.frameInterval = 30
        line.group = 4
        let display = line.displayLines(
            videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 130,
            pxPerFrame: 1
        )
        XCTAssertEqual(display.map(\.frame), [30, 60, 90, 120])
        // 通し番号 4 の倍数（フレーム 120）だけが主線。
        XCTAssertEqual(display.map(\.isSubLine), [true, true, true, false])
    }

    func testDisplayLinesThinning() {
        var line = TimelineVerticalLine()
        line.isEnabled = true
        line.lineType = .frame
        line.frameInterval = 10
        line.group = 4
        // 間隔 10 フレーム × 0.5 px = 5px < 10px なので、
        // 4^1 = 4 本ごとに間引かれる（40 フレーム間隔になる）。
        let display = line.displayLines(
            videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 200,
            pxPerFrame: 0.5
        )
        XCTAssertEqual(display.map(\.frame), [40, 80, 120, 160, 200])
    }

    func testDisplayLinesThinningGroupOneHidesAll() {
        var line = TimelineVerticalLine()
        line.isEnabled = true
        line.lineType = .frame
        line.frameInterval = 10
        line.group = 1
        let display = line.displayLines(
            videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 200,
            pxPerFrame: 0.5
        )
        XCTAssertTrue(display.isEmpty)
    }
}
