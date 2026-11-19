import XCTest
@testable import YMM4Core

/// 実バイナリ依存の映像セッションテスト（分離・明示）。
///
/// 実物の ffmpeg / ffprobe が解決できる環境でのみ実行し、無い
/// 環境では XCTSkip で明示的に飛ばす。素材は実 ffmpeg で生成し、
/// フレームの正しさは着工前実測と同じ手法（フレーム番号を geq
/// のビット列ストリップとして焼き込み、機械読みする）で検証する。
final class FFmpegVideoRealBinaryTests: XCTestCase {
    private var directory: URL!
    private var resolution: FFmpegBinaryResolution!

    override func setUpWithError() throws {
        let resolved = FFmpegBinaryResolver().resolveAll()
        try XCTSkipUnless(
            resolved.isComplete,
            "ffmpeg / ffprobe が解決できない環境のため実バイナリテストを省略"
        )
        resolution = resolved
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFmpegVideoRealBinaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: 素材生成（実測スクリプトと同一の焼き込み方式）

    /// 焼き込みストリップの geq 式。上部24行に16ブロック×20pxで
    /// フレーム番号のビット列を描く（ブロック b = 第 b ビット）。
    private var stripExpression: String {
        "lum='if(lt(Y\\,24)\\,255*mod(floor(N/pow(2\\,floor(X/20)))\\,2)\\,lum(X\\,Y))'"
    }

    private func generate(arguments: [String], outputName: String) throws -> String {
        let ffmpegPath = try XCTUnwrap(resolution.ffmpeg?.path)
        let outputPath = directory.appendingPathComponent(outputName).path
        let result = try FoundationProcessOutputRunner().run(
            executablePath: ffmpegPath, arguments: arguments + [outputPath]
        )
        XCTAssertEqual(result.terminationStatus, 0, result.standardErrorText)
        return outputPath
    }

    private func generateCFR(container: String) throws -> String {
        try generate(arguments: [
            "-v", "error", "-y", "-f", "lavfi",
            "-i", "testsrc2=size=320x180:rate=30:duration=2,format=gray,geq=\(stripExpression),format=yuv420p",
            "-c:v", "libx264", "-crf", "15", "-preset", "veryfast", "-g", "250",
        ], outputName: "cfr.\(container)")
    }

    private func generateVFR() throws -> String {
        // 60fps ソースから select で間引く（実測と同じ方式。geq は
        // select の後段に置き、番号は残ったフレームの通し番号）。
        // 0–1秒: 30fps（30枚）、1–2秒: 10fps（10枚）、2–4秒: 60fps（120枚）。
        let select = "select='lt(n\\,60)*not(mod(n\\,2))+gte(n\\,60)*lt(n\\,120)*not(mod(n\\,6))+gte(n\\,120)'"
        return try generate(arguments: [
            "-v", "error", "-y", "-f", "lavfi",
            "-i", "testsrc2=size=320x180:rate=60:duration=4,format=gray,\(select),geq=\(stripExpression),format=yuv420p",
            "-c:v", "libx264", "-crf", "15", "-preset", "veryfast", "-fps_mode", "vfr",
        ], outputName: "vfr.mkv")
    }

    /// 焼き込まれたフレーム番号を機械読みする（実測の読み取りと
    /// 同じ: 行 6..17、ブロック b は列 b*20+5 ..< b*20+15 の平均）。
    private func burnedIndex(of frame: FFmpegVideoFrame) -> Int {
        var value = 0
        for block in 0..<16 {
            var sum = 0
            var count = 0
            for y in 6..<18 {
                for x in (block * 20 + 5)..<(block * 20 + 15) {
                    sum += Int(frame.pixelData[(y * frame.width + x) * 4])
                    count += 1
                }
            }
            if sum / max(1, count) > 128 {
                value |= (1 << block)
            }
        }
        return value
    }

    private func makeManager(registry: MediaAvailabilityRegistry) -> FFmpegVideoSessionManager {
        FFmpegVideoSessionManager(
            resolution: resolution, registry: registry, startsIdleTimer: false
        )
    }

    /// CFR: 区間途中の要求で正しいフレームが返り、前方・後方への
    /// 移動後もフレームが一致する（シーク後の一貫性）。
    func testRealCFRFrameSelectionAndSeekConsistency() throws {
        let path = try generateCFR(container: "mkv")
        let registry = MediaAvailabilityRegistry()
        let manager = makeManager(registry: registry)
        let key = MediaMaterialKey(filePath: path)
        let handle = manager.acquireSession(for: key)
        let mid = try handle.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(burnedIndex(of: mid), 1)
        XCTAssertEqual(mid.presentationStart.seconds, 1.0 / 30.0, accuracy: 0.001)
        let forward = try handle.frame(at: TimeSpanValue(seconds: 1.75))
        XCTAssertEqual(burnedIndex(of: forward), 52)
        let back = try handle.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(burnedIndex(of: back), 1)
        XCTAssertEqual(registry.state(for: key), .available)
        manager.shutdown()
    }

    /// VFR: 全フレームが順序どおり時刻と対応し、区間途中の要求で
    /// 正しいフレームが返る。表示終了時刻は次のフレームの開始。
    func testRealVFRFrameCorrespondence() throws {
        let path = try generateVFR()
        let registry = MediaAvailabilityRegistry()
        let manager = makeManager(registry: registry)
        let handle = manager.acquireSession(for: MediaMaterialKey(filePath: path))
        // 10fps 区間の途中（1.05 秒）→ フレーム30（開始 1.0、終了 1.1）。
        let tenFps = try handle.frame(at: TimeSpanValue(seconds: 1.05))
        XCTAssertEqual(burnedIndex(of: tenFps), 30)
        XCTAssertEqual(tenFps.presentationStart.seconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(tenFps.presentationEnd.seconds, 1.1, accuracy: 0.001)
        // 60fps 区間の途中（2.51 秒）→ フレーム70（開始 2.5）。
        let sixtyFps = try handle.frame(at: TimeSpanValue(seconds: 2.51))
        XCTAssertEqual(burnedIndex(of: sixtyFps), 70)
        manager.shutdown()
    }

    /// TS: 出力シーク経路で正しいフレームが返る（入力シークは
    /// 実測で信頼できないため、形式ごとの分岐の検証）。
    func testRealTSFrameSelection() throws {
        let path = try generateCFR(container: "ts")
        let registry = MediaAvailabilityRegistry()
        let manager = makeManager(registry: registry)
        let key = MediaMaterialKey(filePath: path)
        // TS の絶対時刻は開始オフセットを含むため、プローブで
        // 開始位置を得てから要求する。
        let probe = try manager.probeInfo(for: key)
        let start = try XCTUnwrap(probe.primaryVideoStream?.startTimeSeconds)
        let handle = manager.acquireSession(for: key)
        let mid = try handle.frame(at: TimeSpanValue(seconds: start + 0.05))
        XCTAssertEqual(burnedIndex(of: mid), 1)
        let forward = try handle.frame(at: TimeSpanValue(seconds: start + 1.5))
        XCTAssertEqual(burnedIndex(of: forward), 45)
        manager.shutdown()
    }
}
