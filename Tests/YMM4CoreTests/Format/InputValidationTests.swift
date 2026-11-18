import XCTest
@testable import YMM4Core

/// 入力検証の強化（セキュリティ監査の中所見2件への対応）。
///
/// 1. JSON パーサの入れ子深さ上限: 細工された深い入れ子で
///    スタックオーバーフローを起こさず、エラーで弾くこと。
/// 2. VideoInfo の値域と Length / MaxLayer の負値検証: 範囲外は
///    既定の扱いへ倒し、診断へ記録すること（ファイルは開ける）。
final class InputValidationTests: XCTestCase {
    // MARK: - ヘルパ

    /// VideoInfo フィールドとタイムライン直下の追加フィールドを持つ
    /// 最小プロジェクト JSON。
    private func projectText(videoInfoFields: String, timelineExtra: String = "") -> String {
        "{\"Timelines\":[{\"VideoInfo\":{\(videoInfoFields)}\(timelineExtra)}]}"
    }

    /// `{"a":` を depth 回重ねた入れ子オブジェクト文字列。
    private func nestedObjectText(depth: Int) -> String {
        String(repeating: "{\"a\":", count: depth) + "0" + String(repeating: "}", count: depth)
    }

    // MARK: - パーサの深さ上限

    func testParserRejectsNestingBeyondLimit() {
        let depth = JSONValue.maximumDepth + 1
        let text = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        var parser = JSONParser(text: text)
        XCTAssertThrowsError(try parser.parse()) { error in
            XCTAssertTrue(error is JSONParseError, "期待は JSONParseError、実際は \(error)")
        }
    }

    func testParserAcceptsNestingAtLimit() throws {
        let depth = JSONValue.maximumDepth
        let text = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        var parser = JSONParser(text: text)
        _ = try parser.parse()
    }

    func testDecodeRejectsDeeplyNestedProjectAsInvalidJSON() {
        // 未知フィールドに上限を超える入れ子を仕込んだ入力が、
        // クラッシュではなく invalidJSON になること。
        let text = "{\"FutureField\":\(nestedObjectText(depth: JSONValue.maximumDepth + 100))}"
        XCTAssertThrowsError(try YmmpCodec.decode(text)) { error in
            guard case YmmpError.invalidJSON = error else {
                XCTFail("期待は YmmpError.invalidJSON、実際は \(error)")
                return
            }
        }
    }

    func testDecodeAcceptsModeratelyDeepUnknownField() throws {
        // 上限未満の入れ子は従来どおり追加フィールドとして保持され、
        // 往復でも壊れないこと。
        let text = "{\"FutureField\":\(nestedObjectText(depth: 100))}"
        let (project, _) = try YmmpCodec.decode(text)
        XCTAssertEqual(project.additionalFields.count, 1)
        let first = YmmpCodec.encode(project)
        let (reloaded, _) = try YmmpCodec.decode(first)
        XCTAssertEqual(YmmpCodec.encode(reloaded), first)
    }

    // MARK: - 保存側の深さ上限

    /// JSONValue を object で包む回数だけ深くする。
    private func deeplyWrappedValue(wraps: Int) -> JSONValue {
        var value = JSONValue.number(0)
        for _ in 0..<wraps {
            value = .object([(key: "a", value: value)])
        }
        return value
    }

    func testSaveRejectsTreeBeyondDepthLimit() throws {
        // ルートオブジェクトの分（+1）を含めると上限を1つ超える深さ。
        let project = Project()
        project.additionalFields.append(
            (key: "FutureField", value: deeplyWrappedValue(wraps: JSONValue.maximumDepth))
        )
        let path = NSTemporaryDirectory() + "ymm4mac-depth-guard-\(UUID().uuidString).ymmp"
        XCTAssertThrowsError(try YmmpCodec.save(project, toFile: path)) { error in
            guard case YmmpError.verificationFailed = error else {
                XCTFail("期待は YmmpError.verificationFailed、実際は \(error)")
                return
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: path),
            "上限超過時はファイル自体を書かない"
        )
    }

    func testSaveAcceptsTreeAtDepthLimit() throws {
        // ルートオブジェクトの分（+1）を含めて、ちょうど上限の深さ。
        let project = Project()
        project.additionalFields.append(
            (key: "FutureField", value: deeplyWrappedValue(wraps: JSONValue.maximumDepth - 1))
        )
        let path = NSTemporaryDirectory() + "ymm4mac-depth-limit-\(UUID().uuidString).ymmp"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try YmmpCodec.save(project, toFile: path)
        let (loaded, _) = try YmmpCodec.load(fromFile: path)
        XCTAssertEqual(loaded.additionalFields.count, 1)
    }

    // MARK: - VideoInfo の値域検証

    func testOutOfRangeVideoInfoFallsBackToDefaultsWithDiagnostics() throws {
        let text = projectText(
            videoInfoFields: "\"FPS\":100000,\"Hz\":10,\"Width\":100000,\"Height\":-5"
        )
        let (project, diagnostics) = try YmmpCodec.decode(text)
        let info = project.timelines[0].videoInfo
        XCTAssertEqual(info, VideoInfo())
        XCTAssertTrue(info.isWithinValidRanges)
        XCTAssertEqual(diagnostics.correctedValues.count, 4)
    }

    func testMixedVideoInfoPreservesValidFields() throws {
        let text = projectText(
            videoInfoFields: "\"FPS\":60,\"Hz\":44100,\"Width\":20000,\"Height\":720"
        )
        let (project, diagnostics) = try YmmpCodec.decode(text)
        let info = project.timelines[0].videoInfo
        XCTAssertEqual(info.fps, 60)
        XCTAssertEqual(info.hz, 44_100)
        XCTAssertEqual(info.width, 1920, "範囲外の Width のみ既定値へ倒れる")
        XCTAssertEqual(info.height, 720)
        XCTAssertEqual(diagnostics.correctedValues.count, 1)
    }

    func testVideoInfoBoundaryValuesAreKept() throws {
        let text = projectText(
            videoInfoFields: "\"FPS\":240,\"Hz\":192000,\"Width\":16384,\"Height\":1"
        )
        let (project, diagnostics) = try YmmpCodec.decode(text)
        XCTAssertEqual(
            project.timelines[0].videoInfo,
            VideoInfo(fps: 240, hz: 192_000, width: 16_384, height: 1)
        )
        XCTAssertTrue(diagnostics.correctedValues.isEmpty)
    }

    // MARK: - Length / MaxLayer の負値検証

    func testNegativeLengthAndMaxLayerFallBackToComputedWithDiagnostics() throws {
        let text = projectText(
            videoInfoFields: "\"FPS\":30",
            timelineExtra: ",\"Length\":-100,\"MaxLayer\":-1"
        )
        let (project, diagnostics) = try YmmpCodec.decode(text)
        // アイテムが無い場合の再計算値は Length = 1 / MaxLayer = 0。
        XCTAssertEqual(project.timelines[0].length, 1)
        XCTAssertEqual(project.timelines[0].maxLayer, 0)
        XCTAssertEqual(diagnostics.correctedValues.count, 2)
    }

    func testValidCachedLengthIsRestoredAsIs() throws {
        let text = projectText(
            videoInfoFields: "\"FPS\":30",
            timelineExtra: ",\"Length\":500,\"MaxLayer\":3"
        )
        let (project, diagnostics) = try YmmpCodec.decode(text)
        XCTAssertEqual(project.timelines[0].length, 500)
        XCTAssertEqual(project.timelines[0].maxLayer, 3)
        XCTAssertTrue(diagnostics.correctedValues.isEmpty)
    }

    // MARK: - 正常な入力への影響なし

    func testNormalProjectDecodesWithoutCorrectionsAndRoundTrips() throws {
        let text = projectText(
            videoInfoFields: "\"FPS\":30,\"Hz\":48000,\"Width\":1920,\"Height\":1080",
            timelineExtra: ",\"Length\":120,\"MaxLayer\":2"
        )
        let (project, diagnostics) = try YmmpCodec.decode(text)
        XCTAssertEqual(project.timelines[0].videoInfo, VideoInfo())
        XCTAssertTrue(diagnostics.correctedValues.isEmpty)
        XCTAssertTrue(diagnostics.skippedItems.isEmpty)
        let first = YmmpCodec.encode(project)
        let (reloaded, reloadedDiagnostics) = try YmmpCodec.decode(first)
        XCTAssertEqual(YmmpCodec.encode(reloaded), first)
        XCTAssertTrue(reloadedDiagnostics.correctedValues.isEmpty)
    }
}
