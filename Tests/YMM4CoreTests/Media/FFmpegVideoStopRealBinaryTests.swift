import XCTest
@testable import YMM4Core

/// 実バイナリ依存の映像プロセス停止手順テスト（分離・明示）。
///
/// 段階3で音声側に判明した不具合（stdout パイプが満杯で書き込み
/// 待ちの ffmpeg には SIGTERM が処理されず、供給の破棄が止まる）
/// が映像側にも同型で存在するかを実バイナリで固定する。実物の
/// ffmpeg / ffprobe が解決できる環境でのみ実行し、無い環境では
/// XCTSkip で明示的に飛ばす。
final class FFmpegVideoStopRealBinaryTests: XCTestCase {
    private var directory: URL!
    private var resolution: FFmpegBinaryResolution!

    /// 720p の BGRA 1フレームは約3.7MB で、パイプ容量（macOS は
    /// 約64KB）をはるかに上回る。読みを止めれば ffmpeg はほぼ
    /// 即座に書き込み待ちで詰まる。
    private let width = 1280
    private let height = 720

    override func setUpWithError() throws {
        let resolved = FFmpegBinaryResolver().resolveAll()
        try XCTSkipUnless(
            resolved.isComplete,
            "ffmpeg / ffprobe が解決できない環境のため実バイナリテストを省略"
        )
        resolution = resolved
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFmpegVideoStopRealBinaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func generateVideo() throws -> String {
        let ffmpegPath = try XCTUnwrap(resolution.ffmpeg?.path)
        let outputPath = directory.appendingPathComponent("big.mkv").path
        let result = try FoundationProcessOutputRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-v", "error", "-y", "-f", "lavfi",
                "-i", "testsrc2=size=\(width)x\(height):rate=30:duration=5",
                "-c:v", "libx264", "-crf", "18", "-preset", "veryfast",
                "-pix_fmt", "yuv420p", outputPath,
            ]
        )
        XCTAssertEqual(result.terminationStatus, 0, result.standardErrorText)
        return outputPath
    }

    private func makeProcess(path: String) throws -> any FFmpegVideoProcess {
        let ffmpegPath = try XCTUnwrap(resolution.ffmpeg?.path)
        return try FoundationFFmpegVideoProcessFactory().makeProcess(
            request: FFmpegVideoProcessRequest(
                ffmpegPath: ffmpegPath,
                filePath: path,
                videoStreamIndex: 0,
                frameByteCount: width * height * 4,
                seekTargetSeconds: nil,
                seekStyle: .input
            )
        )
    }

    /// プロセスの終了を最大 seconds 秒までポーリングで待つ。
    private func waitForExit(
        of process: any FFmpegVideoProcess, timeout: TimeInterval
    ) -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = process.exitStatus { return status }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return process.exitStatus
    }

    /// パイプ詰まり状態（読みを止めて ffmpeg を書き込み待ちに
    /// した状態）からの terminate() で、プロセスが有限時間内に
    /// 終了すること。段階3の音声側の実測では SIGTERM のみでは
    /// 終了しなかった。
    func testTerminateEndsPipeBlockedProcess() throws {
        let path = try generateVideo()
        let process = try makeProcess(path: path)
        let first = try process.readNextFrame()
        XCTAssertNotNil(first)
        // 読みを止める。ffmpeg は次のフレームの書き込みで詰まる。
        Thread.sleep(forTimeInterval: 1.0)
        process.terminate()
        let status = waitForExit(of: process, timeout: 10)
        XCTAssertNotNil(
            status,
            "パイプ詰まり状態で terminate してもプロセスが終了しない"
        )
    }

    /// terminate() の後に読み取りを行うと、例外や切断エラーでは
    /// なく終端（nil）が返ること（停止手順の契約: ブロック中の
    /// 読み取りは終端として返る）。
    func testReadAfterTerminateReturnsEndOfStream() throws {
        let path = try generateVideo()
        let process = try makeProcess(path: path)
        let first = try process.readNextFrame()
        XCTAssertNotNil(first)
        Thread.sleep(forTimeInterval: 0.5)
        process.terminate()
        let finished = expectation(description: "read returns")
        var outcome: String = "unresolved"
        DispatchQueue.global().async {
            do {
                let frame = try process.readNextFrame()
                outcome = frame == nil ? "nil" : "frame"
            } catch {
                outcome = "error: \(error)"
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 15)
        XCTAssertEqual(outcome, "nil")
    }
}
