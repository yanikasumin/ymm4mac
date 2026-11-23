import XCTest
@testable import YMM4Core

/// プローブ実行のフェイク（決められた JSON を返す）。
private final class FakeProbeOutputRunner: ProcessOutputRunning, @unchecked Sendable {
    var output: ProcessOutput?

    func run(executablePath: String, arguments: [String]) throws -> ProcessOutput {
        guard let output else {
            throw NSError(domain: "FakeProbeOutputRunner", code: 1)
        }
        return output
    }
}

/// テスト用の偽時計（管理者の `now` へ渡す）。
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: Double) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// セッション管理者のテスト（Issue #70 段階2）。プロセスと
/// プローブはフェイクに差し替え、再試行方針・同時実行上限・
/// アイドル破棄・キャッシュ・利用可否の駆動を固定する。
final class FFmpegVideoSessionManagerTests: XCTestCase {
    private let mkvProbeJSON = """
        {
          "streams": [
            {
              "index": 0, "codec_name": "h264", "codec_type": "video",
              "width": 320, "height": 180,
              "r_frame_rate": "30/1", "avg_frame_rate": "30/1",
              "start_time": "0.000000", "duration": "2.000000",
              "disposition": {"default": 1, "attached_pic": 0}
            }
          ],
          "format": {
            "format_name": "matroska,webm",
            "start_time": "0.000000", "duration": "2.000000"
          }
        }
        """

    private let tsProbeJSON = """
        {
          "streams": [
            {
              "index": 0, "codec_name": "h264", "codec_type": "video",
              "width": 320, "height": 180,
              "r_frame_rate": "30/1", "avg_frame_rate": "30/1",
              "start_time": "1.466667", "duration": "2.000000",
              "disposition": {"default": 1, "attached_pic": 0}
            }
          ],
          "format": {
            "format_name": "mpegts",
            "start_time": "1.466667", "duration": "2.000000"
          }
        }
        """

    private func makeManager(
        factory: FakeVideoProcessFactory,
        probeJSON: String? = nil,
        registry: MediaAvailabilityRegistry,
        parameters: FFmpegVideoManagerParameters = FFmpegVideoManagerParameters(),
        ffmpegAvailable: Bool = true,
        fileExists: @escaping @Sendable (String) -> Bool = { _ in true },
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> FFmpegVideoSessionManager {
        let runner = FakeProbeOutputRunner()
        runner.output = ProcessOutput(
            terminationStatus: 0,
            standardOutput: Data((probeJSON ?? mkvProbeJSON).utf8),
            standardError: Data()
        )
        let resolution = FFmpegBinaryResolution(
            ffmpeg: ffmpegAvailable
                ? ResolvedFFmpegTool(toolName: "ffmpeg", path: "/dev/ffmpeg", source: .development)
                : nil,
            ffprobe: ResolvedFFmpegTool(toolName: "ffprobe", path: "/dev/ffprobe", source: .development)
        )
        return FFmpegVideoSessionManager(
            resolution: resolution,
            registry: registry,
            prober: FFmpegProber(runner: runner),
            processFactory: factory,
            parameters: parameters,
            fileExists: fileExists,
            now: now,
            startsIdleTimer: false
        )
    }

    private func cfrFactory() -> FakeVideoProcessFactory {
        FakeVideoProcessFactory { request in
            FakeVideoProcess(frames: cfrSpecs(), byteCount: request.frameByteCount)
        }
    }

    private func deadFactory() -> FakeVideoProcessFactory {
        FakeVideoProcessFactory { request in
            let process = FakeVideoProcess(frames: [], byteCount: request.frameByteCount)
            process.exitStatusValue = 1
            process.errorText = "Error while decoding stream #0:0: Invalid data found when processing input"
            return process
        }
    }

    func testSuccessfulServeMarksMaterialAvailable() throws {
        let registry = MediaAvailabilityRegistry()
        let manager = makeManager(factory: cfrFactory(), registry: registry)
        let key = MediaMaterialKey(filePath: "/dev/movie.mkv")
        let handle = manager.acquireSession(for: key)
        let frame = try handle.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(frame.pixelData.first, 1)
        XCTAssertEqual(registry.state(for: key), .available)
    }

    func testMissingFileFailsAndBlocks() {
        let registry = MediaAvailabilityRegistry()
        let factory = cfrFactory()
        let manager = makeManager(
            factory: factory, registry: registry, fileExists: { _ in false }
        )
        let key = MediaMaterialKey(filePath: "/dev/missing.mkv")
        let handle = manager.acquireSession(for: key)
        XCTAssertThrowsError(try handle.frame(at: TimeSpanValue(seconds: 0))) { error in
            guard case FFmpegVideoManagerError.fileNotFound = error else {
                return XCTFail("fileNotFound でない: \(error)")
            }
        }
        guard case .failed(let failure) = registry.state(for: key) else {
            return XCTFail("失敗として記録されていない")
        }
        XCTAssertEqual(failure.kind, .fileNotFound)
        // 以後の要求は即座に失敗し、プロセスは作られない。
        XCTAssertThrowsError(try handle.frame(at: TimeSpanValue(seconds: 0))) { error in
            guard case FFmpegVideoManagerError.materialFailed = error else {
                return XCTFail("materialFailed でない: \(error)")
            }
        }
        XCTAssertTrue(factory.processes.isEmpty)
    }

    func testMissingFFmpegFailsAsUnavailable() {
        let registry = MediaAvailabilityRegistry()
        let manager = makeManager(
            factory: cfrFactory(), registry: registry, ffmpegAvailable: false
        )
        let key = MediaMaterialKey(filePath: "/dev/movie.mkv")
        let handle = manager.acquireSession(for: key)
        XCTAssertThrowsError(try handle.frame(at: TimeSpanValue(seconds: 0))) { error in
            guard case FFmpegVideoManagerError.ffmpegUnavailable = error else {
                return XCTFail("ffmpegUnavailable でない: \(error)")
            }
        }
        guard case .failed(let failure) = registry.state(for: key) else {
            return XCTFail("失敗として記録されていない")
        }
        XCTAssertEqual(failure.kind, .ffmpegUnavailable)
    }

    /// 異常終了は次の要求で1回だけ再生成し、成功すれば利用可に
    /// なる（連続異常でなければ失敗に確定しない）。
    func testAbnormalTerminationRetriesOnceAndRecovers() throws {
        let registry = MediaAvailabilityRegistry()
        let factory = FakeVideoProcessFactory { request in
            FakeVideoProcess(frames: [], byteCount: request.frameByteCount)
        }
        var firstProcess: FakeVideoProcess?
        factory.maker = { request in
            if firstProcess == nil {
                let process = FakeVideoProcess(frames: [], byteCount: request.frameByteCount)
                process.exitStatusValue = 1
                firstProcess = process
                return process
            }
            return FakeVideoProcess(frames: cfrSpecs(), byteCount: request.frameByteCount)
        }
        let manager = makeManager(factory: factory, registry: registry)
        let key = MediaMaterialKey(filePath: "/dev/movie.mkv")
        let handle = manager.acquireSession(for: key)
        XCTAssertThrowsError(try handle.frame(at: TimeSpanValue(seconds: 0.5))) { error in
            guard case FFmpegVideoManagerError.decodeFailed = error else {
                return XCTFail("decodeFailed でない: \(error)")
            }
        }
        let frame = try handle.frame(at: TimeSpanValue(seconds: 0.5))
        XCTAssertEqual(frame.pixelData.first, 15)
        XCTAssertEqual(registry.state(for: key), .available)
        XCTAssertEqual(factory.processes.count, 2)
    }

    /// 異常終了が繰り返されたら失敗に確定し、以後はプロセスを
    /// 作らずに即座に失敗する。
    func testRepeatedAbnormalTerminationsBlockMaterial() {
        let registry = MediaAvailabilityRegistry()
        let factory = deadFactory()
        let manager = makeManager(factory: factory, registry: registry)
        let key = MediaMaterialKey(filePath: "/dev/movie.mkv")
        let handle = manager.acquireSession(for: key)
        XCTAssertThrowsError(try handle.frame(at: TimeSpanValue(seconds: 0.5))) { error in
            guard case FFmpegVideoManagerError.decodeFailed = error else {
                return XCTFail("1回目は decodeFailed のはず: \(error)")
            }
        }
        XCTAssertThrowsError(try handle.frame(at: TimeSpanValue(seconds: 0.5))) { error in
            guard case FFmpegVideoManagerError.materialFailed = error else {
                return XCTFail("2回目は materialFailed のはず: \(error)")
            }
        }
        XCTAssertThrowsError(try handle.frame(at: TimeSpanValue(seconds: 0.5))) { error in
            guard case FFmpegVideoManagerError.materialFailed = error else {
                return XCTFail("確定後は materialFailed のはず: \(error)")
            }
        }
        XCTAssertEqual(factory.processes.count, 2)
        guard case .failed(let failure) = registry.state(for: key) else {
            return XCTFail("失敗として記録されていない")
        }
        XCTAssertEqual(failure.kind, .unsupportedOrDecodeFailed)
    }

    /// 素材の差し替え（記録の破棄とレジストリの reset）で回復
    /// できる。
    func testMaterialRemovalAndRegistryResetRecover() throws {
        let registry = MediaAvailabilityRegistry()
        let factory = deadFactory()
        let manager = makeManager(factory: factory, registry: registry)
        let key = MediaMaterialKey(filePath: "/dev/movie.mkv")
        let handle = manager.acquireSession(for: key)
        _ = try? handle.frame(at: TimeSpanValue(seconds: 0.5))
        _ = try? handle.frame(at: TimeSpanValue(seconds: 0.5))
        guard case .failed = registry.state(for: key) else {
            return XCTFail("失敗に確定していない")
        }
        manager.removeMaterial(for: key)
        registry.reset(for: key)
        factory.maker = { request in
            FakeVideoProcess(frames: cfrSpecs(), byteCount: request.frameByteCount)
        }
        let frame = try handle.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(frame.pixelData.first, 1)
        XCTAssertEqual(registry.state(for: key), .available)
    }

    /// 同時実行数の上限: 3本目の開始で、使われていない最も古い
    /// プロセスが退避させられる。
    func testConcurrencyCapEvictsLeastRecentlyUsedIdleProcess() throws {
        let registry = MediaAvailabilityRegistry()
        let factory = cfrFactory()
        // 退避順序を決定的にするため偽時計で最終利用時刻をずらす。
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let manager = makeManager(
            factory: factory, registry: registry,
            parameters: FFmpegVideoManagerParameters(maxConcurrentProcesses: 2),
            now: clock.now
        )
        let handleA = manager.acquireSession(for: MediaMaterialKey(filePath: "/dev/a.mkv"))
        let handleB = manager.acquireSession(for: MediaMaterialKey(filePath: "/dev/b.mkv"))
        let handleC = manager.acquireSession(for: MediaMaterialKey(filePath: "/dev/c.mkv"))
        _ = try handleA.frame(at: TimeSpanValue(seconds: 0.05))
        clock.advance(by: 1)
        _ = try handleB.frame(at: TimeSpanValue(seconds: 0.05))
        clock.advance(by: 1)
        XCTAssertEqual(manager.liveProcessCount, 2)
        _ = try handleC.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(factory.processes.count, 3)
        XCTAssertTrue(factory.processes[0].terminated, "最も古いプロセスが退避されるはず")
        XCTAssertFalse(factory.processes[1].terminated)
        XCTAssertEqual(manager.liveProcessCount, 2)
    }

    /// アイドル破棄: 制限時間を超えたプロセスは退避し、次の
    /// 要求で作り直される。
    func testIdleSweepEvictsProcessAndNextRequestRecreates() throws {
        let registry = MediaAvailabilityRegistry()
        let factory = cfrFactory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let manager = makeManager(
            factory: factory, registry: registry,
            parameters: FFmpegVideoManagerParameters(idleTimeoutSeconds: 5),
            now: clock.now
        )
        let key = MediaMaterialKey(filePath: "/dev/movie.mkv")
        let handle = manager.acquireSession(for: key)
        _ = try handle.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(manager.liveProcessCount, 1)
        clock.advance(by: 10)
        manager.sweepIdleSessions()
        XCTAssertTrue(factory.processes[0].terminated)
        XCTAssertEqual(manager.liveProcessCount, 0)
        // キャッシュに無い時刻の要求で作り直される。
        _ = try handle.frame(at: TimeSpanValue(seconds: 0.5))
        XCTAssertEqual(factory.processes.count, 2)
    }

    /// フレームキャッシュ: 確定済みフレームの範囲への後方要求は、
    /// セッションが無効化された後でもプロセスを作らずに返る。
    func testFrameCacheServesBackwardRequestWithoutNewProcess() throws {
        let registry = MediaAvailabilityRegistry()
        let factory = cfrFactory()
        let manager = makeManager(factory: factory, registry: registry)
        let key = MediaMaterialKey(filePath: "/dev/movie.mkv")
        let handle = manager.acquireSession(for: key)
        _ = try handle.frame(at: TimeSpanValue(seconds: 1.0))
        XCTAssertEqual(factory.processes.count, 1)
        handle.invalidate()
        let secondHandle = manager.acquireSession(for: key)
        let frame = try secondHandle.frame(at: TimeSpanValue(seconds: 0.5))
        XCTAssertEqual(frame.pixelData.first, 15)
        XCTAssertEqual(factory.processes.count, 1, "キャッシュから返ればプロセスは増えない")
    }

    /// 打ち切られた素材: フレームは供給されるが、利用可否は
    /// 途中失敗として記録され、以後は自動で利用可へ戻らない。
    func testTruncatedMaterialLatchesFailureWhileServing() throws {
        let registry = MediaAvailabilityRegistry()
        let factory = FakeVideoProcessFactory { request in
            let process = FakeVideoProcess(
                frames: cfrSpecs(count: 2), byteCount: request.frameByteCount
            )
            process.exitStatusValue = 1
            process.errorText = "Error while decoding stream #0:0: Invalid data found when processing input"
            return process
        }
        let manager = makeManager(factory: factory, registry: registry)
        let key = MediaMaterialKey(filePath: "/dev/movie.mkv")
        let handle = manager.acquireSession(for: key)
        let frame = try handle.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(frame.pixelData.first, 1)
        guard case .failed(let failure) = registry.state(for: key) else {
            return XCTFail("途中失敗として記録されていない")
        }
        XCTAssertEqual(failure.kind, .midStreamFailure)
        // 供給は止まらない（キャッシュから返る）。
        let again = try handle.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(again.pixelData.first, 1)
        guard case .failed = registry.state(for: key) else {
            return XCTFail("利用可へ自動で戻ってはいけない")
        }
    }

    /// TS 素材ではセッションの要求が出力シークになる。
    func testTSMaterialUsesOutputSeek() throws {
        let registry = MediaAvailabilityRegistry()
        let factory = cfrFactory()
        let manager = makeManager(factory: factory, probeJSON: tsProbeJSON, registry: registry)
        let key = MediaMaterialKey(filePath: "/dev/movie.ts")
        let handle = manager.acquireSession(for: key)
        // TS の絶対時刻（開始オフセット 1.466667 + 0.05）。
        _ = try handle.frame(at: TimeSpanValue(seconds: 1.516667))
        XCTAssertEqual(factory.requests.first?.seekStyle, .output)
    }
}
