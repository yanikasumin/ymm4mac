import XCTest
@testable import YMM4Core

final class VideoInfoTests: XCTestCase {
    func testDefaults() {
        let info = VideoInfo()
        XCTAssertEqual(info.width, 1920)
        XCTAssertEqual(info.height, 1080)
        XCTAssertEqual(info.fps, 30)
        XCTAssertEqual(info.hz, 48_000)
        XCTAssertEqual(info.backgroundColor, .transparent)
        XCTAssertTrue(info.isWithinValidRanges)
    }

    func testRangeBoundariesAreValid() {
        XCTAssertTrue(VideoInfo(fps: 1).isWithinValidRanges)
        XCTAssertTrue(VideoInfo(fps: 240).isWithinValidRanges)
        XCTAssertTrue(VideoInfo(hz: 8_000).isWithinValidRanges)
        XCTAssertTrue(VideoInfo(hz: 192_000).isWithinValidRanges)
        XCTAssertTrue(VideoInfo(width: 1, height: 16_384).isWithinValidRanges)
        XCTAssertTrue(VideoInfo(width: 16_384, height: 1).isWithinValidRanges)
    }

    func testOutOfRangeIsInvalidButStoredAsIs() {
        // 本家の setter はクランプしない。範囲外の値はそのまま保持され、
        // 検証でのみ弾かれる。
        let info = VideoInfo(fps: 0, hz: 7_999, width: 16_385, height: 0)
        XCTAssertEqual(info.fps, 0)
        XCTAssertEqual(info.hz, 7_999)
        XCTAssertEqual(info.width, 16_385)
        XCTAssertEqual(info.height, 0)
        XCTAssertFalse(info.isWithinValidRanges)
        XCTAssertFalse(VideoInfo(fps: 241).isWithinValidRanges)
    }

    func testFrameTimeConversion() {
        let info = VideoInfo() // 30fps
        XCTAssertEqual(info.frame(from: 1.0), 30)
        XCTAssertEqual(info.frame(from: 0.5), 15)
        XCTAssertEqual(info.time(fromFrame: 30), 1.0, accuracy: 1e-9)
        XCTAssertEqual(info.time(fromFrame: 0), 0.0, accuracy: 1e-9)
    }

    func testFrameTimeRoundingIsAwayFromZero() {
        // 2.5 フレーム相当は 3 へ丸める（銀行丸めなら 2）。
        XCTAssertEqual(FrameTime.frame(from: 2.5 / 30, fps: 30), 3)
        XCTAssertEqual(FrameTime.frame(from: -2.5 / 30, fps: 30), -3)
    }

    func testFrameToTimeUsesTickGranularity() {
        // 1フレーム@30fps は 10^7/30 = 333333.33… を丸めた 333333 tick。
        XCTAssertEqual(FrameTime.time(fromFrame: 1, fps: 30), 333_333.0 / 10_000_000, accuracy: 1e-12)
    }
}
