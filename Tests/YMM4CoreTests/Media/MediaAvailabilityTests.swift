import XCTest
@testable import YMM4Core

/// 素材ごとの利用可否の状態モデルのテスト。
final class MediaAvailabilityRegistryTests: XCTestCase {
    private let keyA = MediaMaterialKey(filePath: "/media/a.mkv", itemIdentifier: "item-1")
    private let keyB = MediaMaterialKey(filePath: "/media/a.mkv", itemIdentifier: "item-2")
    private let keyC = MediaMaterialKey(filePath: "/media/b.mp4")
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    func testInitialRecordIsNotAttemptedAndNotRegistered() {
        let registry = MediaAvailabilityRegistry()
        let record = registry.record(for: keyA)
        XCTAssertEqual(record.state, .notAttempted)
        XCTAssertNil(record.lastEvidence)
        XCTAssertEqual(registry.count, 0)
    }

    func testBeginLoadingThenAvailable() {
        let registry = MediaAvailabilityRegistry()
        registry.beginLoading(for: keyA, at: t0)
        XCTAssertEqual(registry.state(for: keyA), .loading)
        XCTAssertEqual(registry.record(for: keyA).updatedAt, t0)

        let evidence = MediaDecodeEvidence(exitStatus: 0, producedFrameCount: 180, expectedFrameCount: 180)
        registry.markAvailable(for: keyA, evidence: evidence, at: t1)
        let record = registry.record(for: keyA)
        XCTAssertEqual(record.state, .available)
        XCTAssertTrue(record.state.isAvailable)
        XCTAssertEqual(record.lastEvidence, evidence)
        XCTAssertEqual(record.updatedAt, t1)
        XCTAssertEqual(registry.count, 1)
    }

    func testMarkFailedKeepsKindAndOccurrenceTime() {
        let registry = MediaAvailabilityRegistry()
        for kind: MediaAvailabilityFailureKind in [
            .fileNotFound, .unsupportedOrDecodeFailed, .ffmpegUnavailable, .midStreamFailure,
        ] {
            let failure = MediaAvailabilityFailure(kind: kind, detail: "詳細", occurredAt: t1)
            registry.markFailed(for: keyA, failure: failure)
            let record = registry.record(for: keyA)
            XCTAssertEqual(record.state.failure?.kind, kind)
            XCTAssertEqual(record.updatedAt, t1)
            registry.reset(for: keyA, at: t0)
        }
    }

    func testRecordEvidenceDoesNotChangeState() {
        let registry = MediaAvailabilityRegistry()
        registry.beginLoading(for: keyA, at: t0)
        let evidence = MediaDecodeEvidence(exitStatus: 0, producedFrameCount: 10)
        registry.recordEvidence(evidence, for: keyA, at: t1)
        let record = registry.record(for: keyA)
        XCTAssertEqual(record.state, .loading)
        XCTAssertEqual(record.lastEvidence, evidence)
        XCTAssertEqual(record.updatedAt, t1)
    }

    func testResetClearsStateAndEvidence() {
        let registry = MediaAvailabilityRegistry()
        registry.markAvailable(
            for: keyA, evidence: MediaDecodeEvidence(exitStatus: 0), at: t0
        )
        registry.reset(for: keyA, at: t1)
        let record = registry.record(for: keyA)
        XCTAssertEqual(record.state, .notAttempted)
        XCTAssertNil(record.lastEvidence)
        XCTAssertEqual(record.updatedAt, t1)
    }

    func testKeysAreIndependent() {
        // 同じパスでもアイテム識別が違えば別記録、識別なしとも別。
        let registry = MediaAvailabilityRegistry()
        registry.markAvailable(for: keyA, at: t0)
        XCTAssertEqual(registry.state(for: keyB), .notAttempted)
        XCTAssertEqual(registry.state(for: keyC), .notAttempted)
        XCTAssertEqual(registry.count, 1)
        registry.beginLoading(for: keyB, at: t0)
        XCTAssertEqual(registry.count, 2)
        XCTAssertEqual(registry.state(for: keyA), .available)
    }

    func testRemoveAndRemoveAll() {
        let registry = MediaAvailabilityRegistry()
        registry.beginLoading(for: keyA, at: t0)
        registry.beginLoading(for: keyC, at: t0)
        registry.remove(for: keyA)
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.state(for: keyA), .notAttempted)
        registry.removeAll()
        XCTAssertEqual(registry.count, 0)
        XCTAssertTrue(registry.allRecords().isEmpty)
    }

    func testAllRecordsSortedByPathThenIdentifier() {
        let registry = MediaAvailabilityRegistry()
        registry.beginLoading(for: keyC, at: t0)
        registry.beginLoading(for: keyB, at: t0)
        registry.beginLoading(for: keyA, at: t0)
        XCTAssertEqual(registry.allRecords().map(\.key), [keyA, keyB, keyC])
    }
}

// MARK: - デコード証拠の兆候抽出（実測 系統6 の反映）

final class MediaDecodeEvidenceTests: XCTestCase {
    func testCleanEvidenceHasNoIndicators() {
        let evidence = MediaDecodeEvidence(
            exitStatus: 0, producedFrameCount: 180, expectedFrameCount: 180,
            standardErrorExcerpt: ""
        )
        XCTAssertTrue(evidence.failureIndicators.isEmpty)
        XCTAssertFalse(evidence.suggestsFailureDespiteSuccessExit)
        XCTAssertFalse(evidence.standardErrorReportsDecodeError)
    }

    func testNonZeroExitIndicator() {
        let evidence = MediaDecodeEvidence(exitStatus: 1)
        XCTAssertEqual(evidence.failureIndicators, [.exitStatusNonZero])
        // 終了コードが非 0 の場合は「成功終了なのに兆候」ではない。
        XCTAssertFalse(evidence.suggestsFailureDespiteSuccessExit)
    }

    func testCorruptPayloadCaseFromMeasurement() {
        // 実測: ペイロード破損 MP4 は rc=0・全フレーム出力でも
        // stderr にデコードエラーが出た。終了コードだけの判定では
        // 成功と誤る形を、兆候として拾えることを固定する。
        let evidence = MediaDecodeEvidence(
            exitStatus: 0, producedFrameCount: 180, expectedFrameCount: 180,
            standardErrorExcerpt: "[h264 @ 0x123] error while decoding stream 0: Invalid data found when processing input"
        )
        XCTAssertTrue(evidence.standardErrorReportsDecodeError)
        XCTAssertEqual(evidence.failureIndicators, [.standardErrorReportsDecodeError])
        XCTAssertTrue(evidence.suggestsFailureDespiteSuccessExit)
    }

    func testTruncatedCaseFromMeasurement() {
        // 実測: 切断 MKV は rc=0 のまま途中終了した（フレーム不足）。
        let evidence = MediaDecodeEvidence(
            exitStatus: 0, producedFrameCount: 42, expectedFrameCount: 180,
            standardErrorExcerpt: ""
        )
        XCTAssertEqual(evidence.failureIndicators, [.frameCountShortfall])
        XCTAssertTrue(evidence.suggestsFailureDespiteSuccessExit)
    }

    func testNoFramesProduced() {
        let evidence = MediaDecodeEvidence(exitStatus: 0, producedFrameCount: 0, expectedFrameCount: 180)
        XCTAssertEqual(
            Set(evidence.failureIndicators), [.frameCountShortfall, .noFramesProduced]
        )
    }

    func testUnknownCountsGiveNoShortfallIndicator() {
        // 期待数が不明なら不足とは言わない。
        let evidence = MediaDecodeEvidence(exitStatus: 0, producedFrameCount: 42)
        XCTAssertTrue(evidence.failureIndicators.isEmpty)
    }
}
