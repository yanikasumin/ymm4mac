import XCTest
@testable import YMM4Core

/// テスト用のフェイクデコードプロセス。決められた開始時刻列の
/// フレームを順に返し、終端で nil を返す。シーク目標は無視する
/// （セッション側の読み進め・張り替え判断を見るため）。
final class FakeVideoProcess: FFmpegVideoProcess, @unchecked Sendable {
    struct Spec {
        var start: Double
        var fill: UInt8
    }

    let frames: [Spec]
    let byteCount: Int
    var exitStatusValue: Int32 = 0
    var errorText = ""
    /// true なら読み取りは terminate() されるまでブロックする。
    var blocksUntilTerminate = false

    private let lock = NSLock()
    private var index = 0
    private(set) var terminated = false
    private let condition = NSCondition()
    private var released = false

    init(frames: [Spec], byteCount: Int) {
        self.frames = frames
        self.byteCount = byteCount
    }

    func readNextFrame() throws -> (pixelData: Data, startSeconds: Double)? {
        if blocksUntilTerminate {
            condition.lock()
            while !released { condition.wait() }
            condition.unlock()
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        guard index < frames.count else { return nil }
        let spec = frames[index]
        index += 1
        return (Data(repeating: spec.fill, count: byteCount), spec.start)
    }

    var producedFrameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return index
    }

    var exitStatus: Int32? { exitStatusValue }
    var collectedStandardError: String { errorText }

    func terminate() {
        lock.lock()
        terminated = true
        lock.unlock()
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

/// フェイクプロセスの生成を記録する工場。
final class FakeVideoProcessFactory: FFmpegVideoProcessFactory, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [FFmpegVideoProcessRequest] = []
    private(set) var processes: [FakeVideoProcess] = []
    var maker: (FFmpegVideoProcessRequest) -> FakeVideoProcess

    init(maker: @escaping (FFmpegVideoProcessRequest) -> FakeVideoProcess) {
        self.maker = maker
    }

    func makeProcess(request: FFmpegVideoProcessRequest) throws -> any FFmpegVideoProcess {
        let process = maker(request)
        lock.lock()
        requests.append(request)
        processes.append(process)
        lock.unlock()
        return process
    }
}

/// CFR 30fps のフレーム列（fill = フレーム番号）。
func cfrSpecs(count: Int = 60) -> [FakeVideoProcess.Spec] {
    (0..<count).map { FakeVideoProcess.Spec(start: Double($0) / 30.0, fill: UInt8($0 % 256)) }
}

final class FFmpegVideoDecodeSessionTests: XCTestCase {
    private func makeConfiguration(
        usesOutputSeek: Bool = false,
        skipAheadThresholdSeconds: Double = 2.0,
        seekPrerollSeconds: Double = 0.5,
        materialDurationSeconds: Double? = 2.0,
        expectedFrameCount: Int? = 60
    ) -> FFmpegVideoSessionConfiguration {
        FFmpegVideoSessionConfiguration(
            materialKey: MediaMaterialKey(filePath: "/dev/cfr.mkv"),
            filePath: "/dev/cfr.mkv", ffmpegPath: "/dev/ffmpeg",
            videoStreamIndex: 0, width: 4, height: 2,
            usesOutputSeek: usesOutputSeek,
            materialStartSeconds: 0,
            materialDurationSeconds: materialDurationSeconds,
            nominalFrameDurationSeconds: 1.0 / 30.0,
            expectedFrameCount: expectedFrameCount,
            skipAheadThresholdSeconds: skipAheadThresholdSeconds,
            seekPrerollSeconds: seekPrerollSeconds
        )
    }

    private func makeSession(
        factory: FakeVideoProcessFactory,
        gate: FFmpegProcessSlotGate,
        configuration: FFmpegVideoSessionConfiguration
    ) -> FFmpegVideoDecodeSession {
        let session = FFmpegVideoDecodeSession(
            configuration: configuration, processFactory: factory, slotGate: gate
        )
        gate.register(id: session.id, session: session)
        return session
    }

    private func makeGate() -> FFmpegProcessSlotGate {
        FFmpegProcessSlotGate(capacity: 4, now: { Date() })
    }

    private func cfrFactory() -> FakeVideoProcessFactory {
        FakeVideoProcessFactory { request in
            FakeVideoProcess(frames: cfrSpecs(), byteCount: request.frameByteCount)
        }
    }

    /// PTS 基準の選択: 区間途中（0.05 秒 = フレーム1の区間）の
    /// 要求ではフレーム1が返る（ffmpeg の生のシーク挙動である
    /// 「次のフレーム」にはならない）。
    func testMidIntervalRequestReturnsContainingFrame() throws {
        let factory = cfrFactory()
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        let frame = try session.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(frame.pixelData.first, 1)
        XCTAssertEqual(frame.presentationStart.seconds, 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(frame.presentationEnd.seconds, 2.0 / 30.0, accuracy: 0.0001)
        // 先頭からの開始では -ss は付かない。
        XCTAssertNil(factory.requests.first?.seekTargetSeconds)
    }

    func testExactBoundaryRequestReturnsFrameStartingThere() throws {
        let factory = cfrFactory()
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        let frame = try session.frame(at: TimeSpanValue(seconds: 0))
        XCTAssertEqual(frame.pixelData.first, 0)
        XCTAssertEqual(frame.presentationStart.seconds, 0, accuracy: 0.0001)
    }

    /// VFR: 不規則な開始時刻列でも、順序と時刻の対応が保たれ、
    /// 要求を含む区間のフレームが返る。
    func testVFRFramesKeepOrderAndTimes() throws {
        let starts = [0.0, 0.033, 0.066, 0.166, 0.266, 0.283, 0.3]
        let factory = FakeVideoProcessFactory { request in
            FakeVideoProcess(
                frames: starts.enumerated().map {
                    FakeVideoProcess.Spec(start: $0.element, fill: UInt8($0.offset))
                },
                byteCount: request.frameByteCount
            )
        }
        var configuration = makeConfiguration(materialDurationSeconds: 0.32, expectedFrameCount: 7)
        configuration.nominalFrameDurationSeconds = 1.0 / 60.0
        let session = makeSession(factory: factory, gate: makeGate(), configuration: configuration)
        let first = try session.frame(at: TimeSpanValue(seconds: 0.1))
        XCTAssertEqual(first.pixelData.first, 2)
        XCTAssertEqual(first.presentationStart.seconds, 0.066, accuracy: 0.0001)
        XCTAssertEqual(first.presentationEnd.seconds, 0.166, accuracy: 0.0001)
        let second = try session.frame(at: TimeSpanValue(seconds: 0.2))
        XCTAssertEqual(second.pixelData.first, 3)
        XCTAssertEqual(second.presentationEnd.seconds, 0.266, accuracy: 0.0001)
        XCTAssertEqual(factory.processes.count, 1)
    }

    /// 前方への小さな移動は同じプロセスで読み進める。
    func testSmallForwardMoveContinuesSameProcess() throws {
        let factory = cfrFactory()
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        _ = try session.frame(at: TimeSpanValue(seconds: 0.05))
        let frame = try session.frame(at: TimeSpanValue(seconds: 0.2))
        XCTAssertEqual(frame.pixelData.first, 6)
        XCTAssertEqual(factory.processes.count, 1)
    }

    /// 前方への大きな移動はプロセスを張り替え、手前余裕を引いた
    /// 位置をシーク目標にする。
    func testFarForwardMoveRestartsProcessWithPrerollTarget() throws {
        let factory = cfrFactory()
        let session = makeSession(
            factory: factory, gate: makeGate(),
            configuration: makeConfiguration(skipAheadThresholdSeconds: 0.5)
        )
        _ = try session.frame(at: TimeSpanValue(seconds: 0.05))
        let frame = try session.frame(at: TimeSpanValue(seconds: 1.5))
        XCTAssertEqual(frame.pixelData.first, 45)
        XCTAssertEqual(factory.processes.count, 2)
        XCTAssertEqual(factory.requests[1].seekTargetSeconds ?? -1, 1.0, accuracy: 0.0001)
    }

    /// 後方への移動はプロセスを張り替える。
    func testBackwardMoveRestartsProcess() throws {
        let factory = cfrFactory()
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        _ = try session.frame(at: TimeSpanValue(seconds: 1.0))
        let frame = try session.frame(at: TimeSpanValue(seconds: 0.1))
        XCTAssertEqual(frame.pixelData.first, 3)
        XCTAssertEqual(factory.processes.count, 2)
    }

    /// TS 設定では出力シーク、通常は入力シークが選ばれる。
    func testSeekStyleFollowsConfiguration() throws {
        let tsFactory = cfrFactory()
        let tsSession = makeSession(
            factory: tsFactory, gate: makeGate(),
            configuration: makeConfiguration(usesOutputSeek: true)
        )
        _ = try tsSession.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(tsFactory.requests.first?.seekStyle, .output)

        let normalFactory = cfrFactory()
        let normalSession = makeSession(
            factory: normalFactory, gate: makeGate(), configuration: makeConfiguration()
        )
        _ = try normalSession.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(normalFactory.requests.first?.seekStyle, .input)
    }

    /// 終端後は最終フレームで答え続け、終了時刻は素材終端になる。
    func testEndOfStreamServesLastFrame() throws {
        let factory = FakeVideoProcessFactory { request in
            FakeVideoProcess(frames: cfrSpecs(count: 3), byteCount: request.frameByteCount)
        }
        let session = makeSession(
            factory: factory, gate: makeGate(),
            configuration: makeConfiguration(
                materialDurationSeconds: 0.1, expectedFrameCount: 3
            )
        )
        let frame = try session.frame(at: TimeSpanValue(seconds: 0.09))
        XCTAssertEqual(frame.pixelData.first, 2)
        XCTAssertEqual(frame.presentationEnd.seconds, 0.1, accuracy: 0.0001)
        let beyond = try session.frame(at: TimeSpanValue(seconds: 5.0))
        XCTAssertEqual(beyond.pixelData.first, 2)
    }

    /// フレームを1つも出さずに異常終了した場合は、証拠つきの
    /// 異常終了になる。
    func testAbnormalTerminationWithoutFramesThrowsWithEvidence() {
        let factory = FakeVideoProcessFactory { request in
            let process = FakeVideoProcess(frames: [], byteCount: request.frameByteCount)
            process.exitStatusValue = 1
            process.errorText = "Error while decoding stream #0:0: Invalid data found when processing input"
            return process
        }
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        XCTAssertThrowsError(try session.frame(at: TimeSpanValue(seconds: 0.5))) { error in
            guard case FFmpegVideoSessionError.abnormalTermination(let evidence) = error
            else {
                return XCTFail("異常終了でない: \(error)")
            }
            XCTAssertEqual(evidence.exitStatus, 1)
            XCTAssertEqual(evidence.producedFrameCount, 0)
            XCTAssertTrue(evidence.failureIndicators.contains(.exitStatusNonZero))
            XCTAssertTrue(evidence.failureIndicators.contains(.standardErrorReportsDecodeError))
            XCTAssertTrue(evidence.failureIndicators.contains(.noFramesProduced))
        }
    }

    /// 途中で打ち切られた素材: 最終フレームは供給されるが、
    /// 証拠には異常の兆候が残る（管理者が失敗として記録する材料）。
    func testTruncatedStreamServesLastFrameButLeavesAbnormalEvidence() throws {
        let factory = FakeVideoProcessFactory { request in
            let process = FakeVideoProcess(
                frames: cfrSpecs(count: 2), byteCount: request.frameByteCount
            )
            process.exitStatusValue = 1
            process.errorText = "Error while decoding stream #0:0: Invalid data found when processing input"
            return process
        }
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        let frame = try session.frame(at: TimeSpanValue(seconds: 0.05))
        XCTAssertEqual(frame.pixelData.first, 1)
        let evidence = try XCTUnwrap(session.takePendingEvidence())
        XCTAssertEqual(evidence.producedFrameCount, 2)
        XCTAssertTrue(evidence.failureIndicators.contains(.exitStatusNonZero))
        XCTAssertTrue(evidence.failureIndicators.contains(.frameCountShortfall))
        XCTAssertTrue(evidence.failureIndicators.contains(.standardErrorReportsDecodeError))
    }

    /// 無効化はブロック中の読み取りを起こし、要求を superseded
    /// に倒す（世代による古い結果の破棄）。
    func testInvalidateDuringBlockedReadThrowsSuperseded() {
        let factory = FakeVideoProcessFactory { request in
            let process = FakeVideoProcess(frames: [], byteCount: request.frameByteCount)
            process.blocksUntilTerminate = true
            return process
        }
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        let semaphore = DispatchSemaphore(value: 0)
        var thrown: Error?
        DispatchQueue.global().async {
            do {
                _ = try session.frame(at: TimeSpanValue(seconds: 0))
            } catch {
                thrown = error
            }
            semaphore.signal()
        }
        // プロセスが作られるまで待つ。
        let deadline = Date().addingTimeInterval(5)
        while factory.processes.isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(factory.processes.count, 1)
        session.invalidate()
        XCTAssertEqual(semaphore.wait(timeout: .now() + 5), .success)
        guard case FFmpegVideoSessionError.superseded? = thrown as? FFmpegVideoSessionError
        else {
            return XCTFail("superseded でない: \(String(describing: thrown))")
        }
    }

    /// 最初のフレームが要求より後から始まる（シークで含む
    /// フレームが捨てられた）場合は、手前余裕を広げて再試行し、
    /// 上限まで届かなければ得られる最も早いフレームを返す。
    func testPrerollEscalationReturnsEarliestAvailableFrame() throws {
        let factory = FakeVideoProcessFactory { request in
            FakeVideoProcess(
                frames: [1.0, 1.0 + 1.0 / 30.0, 1.0 + 2.0 / 30.0].map {
                    FakeVideoProcess.Spec(start: $0, fill: 7)
                },
                byteCount: request.frameByteCount
            )
        }
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        let frame = try session.frame(at: TimeSpanValue(seconds: 0.8))
        XCTAssertEqual(frame.presentationStart.seconds, 1.0, accuracy: 0.0001)
        // 初回 + 拡大3回。
        XCTAssertEqual(factory.processes.count, 4)
    }

    /// 時刻表に既知の開始時刻があれば、シーク目標はその位置に
    /// 合う（pts ちょうどのシークではそのフレームが残る）。
    func testSeekTargetUsesKnownFrameStart() throws {
        let factory = cfrFactory()
        let session = makeSession(
            factory: factory, gate: makeGate(), configuration: makeConfiguration()
        )
        let observer = StubSessionObserver()
        observer.knownStart = 0.9
        session.observer = observer
        _ = try session.frame(at: TimeSpanValue(seconds: 1.0))
        XCTAssertEqual(factory.requests.first?.seekTargetSeconds ?? -1, 0.9, accuracy: 0.0001)
        withExtendedLifetime(observer) {}
    }
}

final class StubSessionObserver: FFmpegVideoSessionObserver, @unchecked Sendable {
    var knownStart: Double?

    func videoSession(
        _ session: FFmpegVideoDecodeSession,
        didReadFrame frame: FFmpegVideoFrame, endIsFinal: Bool
    ) {}

    func videoSession(
        _ session: FFmpegVideoDecodeSession,
        knownFrameStartAtOrBefore time: TimeSpanValue
    ) -> Double? {
        knownStart
    }
}
