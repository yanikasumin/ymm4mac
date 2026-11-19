#if os(macOS)
import XCTest
import YMM4Core
import YMM4GPU

/// 共有基盤の所有とリセット（Issue #70 段階4）。
///
/// 基盤はアプリのセッション単位で1つに保ち、プロジェクトの
/// 差し替えでは台帳と映像管理者を持ち越さないことを固定する。
final class FFmpegMediaSupportTests: XCTestCase {
    /// 差し替え時のリセットで台帳が空になり、映像管理者は
    /// 次回利用時に新しいインスタンスへ作り直される。
    func testResetForProjectSwitchClearsRegistryAndDropsManager() throws {
        let resolution = FFmpegBinaryResolver().resolveAll()
        try XCTSkipUnless(
            resolution.isComplete,
            "ffmpeg / ffprobe が解決できない環境のため省略"
        )
        let support = FFmpegMediaSupport(resolution: resolution)
        let key = MediaMaterialKey(filePath: "/tmp/material.mkv")
        support.registry.markFailed(
            for: key,
            failure: MediaAvailabilityFailure(
                kind: .fileNotFound, detail: "test", occurredAt: Date()
            )
        )
        XCTAssertEqual(support.registry.count, 1)
        let managerBefore = try XCTUnwrap(support.videoManager)

        support.resetForProjectSwitch()

        XCTAssertEqual(support.registry.count, 0)
        XCTAssertEqual(support.registry.state(for: key), .notAttempted)
        let managerAfter = try XCTUnwrap(support.videoManager)
        XCTAssertFalse(managerBefore === managerAfter)
    }

    /// リセットは映像管理者が未生成でも安全（音声だけの利用）。
    func testResetWithoutManagerIsSafe() {
        let support = FFmpegMediaSupport()
        support.registry.beginLoading(
            for: MediaMaterialKey(filePath: "/tmp/material.wav")
        )
        support.resetForProjectSwitch()
        XCTAssertEqual(support.registry.count, 0)
    }
}
#endif
