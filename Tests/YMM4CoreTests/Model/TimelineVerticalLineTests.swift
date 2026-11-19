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

    /// FE-R35-132-02: 同じ種別への代入では、読み込んだ線オブジェクトの
    /// 未知フィールドが維持されること。種別を変えた場合は従来どおり
    /// 既定インスタンスへ差し替わること。
    func testSameTypeAssignmentPreservesUnknownLineFields() {
        var line = TimelineVerticalLine()
        line.line = PreservedObject(.object([
            (key: "$type", value: .string(
                "YukkuriMovieMaker.Project.VerticalBPMLine, YukkuriMovieMaker.Plugin")),
            (key: "BPM", value: .number(120)),
            (key: "FutureField", value: .string("keep-me")),
        ]))
        XCTAssertEqual(line.lineType, .bpm)
        line.lineType = .bpm
        XCTAssertEqual(line.bpm, 120)
        XCTAssertEqual(
            line.line.value.field("FutureField")?.stringValue, "keep-me")
        line.lineType = .frame
        XCTAssertEqual(line.frameInterval, 30)
        XCTAssertNil(line.line.value.field("FutureField"))
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

    /// FE-R35-132-01: 表現できない巨大入力はトラップせず nil になる
    /// こと。表現できる上限（Int64.max）までは従来どおり変換できる
    /// こと。Int64.min の書式化が落ちないこと。
    func testTimeSpanOverflowSafety() {
        // 時の要素自体は Int64 に収まるが、tick 換算で溢れる。
        XCTAssertNil(
            TimelineVerticalLine.ticks(fromTimeSpanString: "999999999999:00:00"))
        // 日数の秒換算で溢れる。
        XCTAssertNil(
            TimelineVerticalLine.ticks(fromTimeSpanString: "200000000000000.00:00:00"))
        // 要素自体が Int64 に収まらない。
        XCTAssertNil(
            TimelineVerticalLine.ticks(fromTimeSpanString: "99999999999999999999:00:00"))
        // Int64.max ちょうどの tick は表現できる。
        XCTAssertEqual(
            TimelineVerticalLine.ticks(fromTimeSpanString: "10675199.02:48:05.4775807"),
            Int64.max
        )
        // Int64.min の書式化（abs のトラップ回避）。
        XCTAssertEqual(
            TimelineVerticalLine.timeSpanString(fromTicks: Int64.min),
            "-10675199.02:48:05.4775808"
        )
        // 通常範囲の往復は従来どおり。
        XCTAssertEqual(
            TimelineVerticalLine.ticks(
                fromTimeSpanString: TimelineVerticalLine.timeSpanString(
                    fromTicks: -15_000_000)),
            -15_000_000
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

    /// FE-R35-132-03: 広域表示（ズーム 0.01%、可視範囲 1,000 万
    /// フレーム）でも、間引き後の線が可視範囲の右端まで生成される
    /// こと。候補列挙の上限で打ち切られていた従来方式では、線は
    /// 約300万フレーム付近までしか届かなかった。
    /// 間隔 30 フレーム × 0.0001 px = 0.003px なので、間引きは
    /// 4^6 = 4096 本ごと（実効間隔 122,880 フレーム）になる。
    func testDisplayLinesReachEndOfWideRange() {
        var line = TimelineVerticalLine()
        line.isEnabled = true
        line.lineType = .frame
        line.frameInterval = 30
        line.group = 4
        let display = line.displayLines(
            videoInfo: videoInfo, enumerateFrom: 0, throughFrame: 10_000_000,
            pxPerFrame: 0.0001
        )
        // 件数は表示線数の桁（81 本）に収まり、最後の線は右端
        // （10,000,000 フレーム）付近まで届く。
        XCTAssertEqual(display.count, 81)
        XCTAssertEqual(display.first?.frame, 122_880)
        XCTAssertEqual(display.last?.frame, 9_953_280)
        // 間引き後の線はすべて主線。
        XCTAssertTrue(display.allSatisfy { !$0.isSubLine })
    }
}
