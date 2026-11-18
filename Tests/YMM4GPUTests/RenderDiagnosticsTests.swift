import XCTest
@testable import YMM4GPU

/// 描画診断の収集先（R6-06）の集約規則を検証する。
final class RenderDiagnosticsTests: XCTestCase {
    /// 同じ種別は集約され、回数と最新内容が更新される。
    func testSameKindIsAggregated() {
        let collector = RenderDiagnosticsCollector()
        collector.record(kind: "alphaMaskWarp", message: "first")
        collector.record(kind: "alphaMaskWarp", message: "second")
        collector.record(kind: "other", message: "other failure")

        let entries = collector.allEntries()
        XCTAssertEqual(entries.count, 2)
        let alpha = entries.first { $0.kind == "alphaMaskWarp" }
        XCTAssertEqual(alpha?.count, 2)
        XCTAssertEqual(alpha?.message, "second")
        XCTAssertEqual(collector.eventCount, 3)
    }

    /// 通し番号による切り分け: 描画の間に発生した分だけが返る
    /// （現在の失敗状態の判定に使う）。
    func testEntriesAfterMark() {
        let collector = RenderDiagnosticsCollector()
        collector.record(kind: "a", message: "before")
        let mark = collector.eventCount
        XCTAssertTrue(collector.entries(after: mark).isEmpty)

        collector.record(kind: "b", message: "during")
        let during = collector.entries(after: mark)
        XCTAssertEqual(during.map(\.kind), ["b"])
        // 履歴自体は両方残る。
        XCTAssertEqual(collector.allEntries().count, 2)
    }

    /// セッションの作り直しで履歴が消える。
    func testClear() {
        let collector = RenderDiagnosticsCollector()
        collector.record(kind: "a", message: "x")
        collector.clear()
        XCTAssertTrue(collector.allEntries().isEmpty)
        XCTAssertEqual(collector.eventCount, 0)
    }
}
