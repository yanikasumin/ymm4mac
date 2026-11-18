import CoreGraphics
import XCTest
import YMM4Core
import YMM4GPU
@testable import PreviewCore

/// 描画時間を門（セマフォ）で制御できる偽セッション。
private final class FakeSession: PreviewRenderSession {
    var initializationFailure: String?
    let diagnostics = RenderDiagnosticsCollector()
    /// render はこの門が開くまで待つ（blockRenders が真の間）。
    let gate = DispatchSemaphore(value: 0)
    var blockRenders = false
    private let lock = NSLock()
    private var frames: [Int] = []
    private(set) var disposed = false

    var renderedFrames: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    func render(frame: Int, timeline: Timeline, usage: TimelineSourceUsage) -> CGImage? {
        lock.lock()
        frames.append(frame)
        lock.unlock()
        if blockRenders {
            _ = gate.wait(timeout: .now() + 10)
        }
        return nil
    }

    func dispose() { disposed = true }
}

/// 完了通知の収集（メインキューから呼ばれる）。
private final class DeliveryLog {
    private let lock = NSLock()
    private var entries: [(PreviewRenderWorker.Identity, Int)] = []

    func append(_ identity: PreviewRenderWorker.Identity, _ frame: Int) {
        lock.lock()
        entries.append((identity, frame))
        lock.unlock()
    }

    var all: [(PreviewRenderWorker.Identity, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

/// PreviewRenderWorker の順序制御（第11ラウンドのマージ条件）を
/// 決定論的に検証する。完了通知はメインキュー経由のため、待ちは
/// XCTest の期待（メインランループを回す）で行う。
final class PreviewRenderWorkerTests: XCTestCase {
    private let key = PreviewBox.SessionKey(
        url: URL(fileURLWithPath: "/test.ymmp"), timelineIndex: 0
    )

    private func makeWorker(
        sessions: [FakeSession]
    ) -> PreviewRenderWorker {
        var index = 0
        return PreviewRenderWorker(makeSession: { _, _, _, _ in
            defer { index += 1 }
            return sessions[min(index, sessions.count - 1)]
        })
    }

    private func identity(generation: Int, version: Int) -> PreviewRenderWorker.Identity {
        PreviewRenderWorker.Identity(
            key: key, generation: generation, version: version
        )
    }

    /// 背景側の状態（描画開始・破棄）のポーリング待ち。
    private func waitUntil(
        _ description: String, timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.005)
        }
        XCTFail("timed out waiting for: \(description)")
    }

    /// 描画が止まっている間に 10 件要求しても、保留は最後の 1 件
    /// だけになり、蓄積しない（latest-wins の必須試験）。
    func testLatestWinsCoalescesPendingRequests() {
        let session = FakeSession()
        session.blockRenders = true
        let worker = makeWorker(sessions: [session])
        let log = DeliveryLog()
        let delivered = expectation(description: "two deliveries")
        delivered.expectedFulfillmentCount = 2
        worker.onRenderFailed = { identity, frame, _, _ in
            log.append(identity, frame)
            delivered.fulfill()
        }
        worker.setModel(
            identity: identity(generation: 1, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.request(frame: 0, usage: .paused, identity: identity(generation: 1, version: 1))
        waitUntil("first render started") { session.renderedFrames == [0] }

        for frame in 1...10 {
            worker.request(frame: frame, usage: .paused, identity: identity(generation: 1, version: 1))
        }
        XCTAssertEqual(worker.stats.requestsReceived, 11)
        XCTAssertEqual(worker.stats.requestsOverwritten, 9)

        session.blockRenders = false
        session.gate.signal()
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(session.renderedFrames, [0, 10])
        XCTAssertEqual(log.all.map { $0.1 }, [0, 10])
        XCTAssertEqual(worker.stats.rendersStarted, 2)
        XCTAssertEqual(worker.stats.rendersCompleted, 2)
    }

    /// 描画中のモデル差し替え: 旧モデルは安全に破棄され、新モデルが
    /// 最終的に描画される。完了通知の識別子で新旧を区別できる。
    func testModelSwapDuringRender() {
        let sessionA = FakeSession()
        sessionA.blockRenders = true
        let sessionB = FakeSession()
        let worker = makeWorker(sessions: [sessionA, sessionB])
        let log = DeliveryLog()
        let delivered = expectation(description: "two deliveries")
        delivered.expectedFulfillmentCount = 2
        worker.onRenderFailed = { identity, frame, _, _ in
            log.append(identity, frame)
            delivered.fulfill()
        }
        worker.setModel(
            identity: identity(generation: 1, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.request(frame: 5, usage: .paused, identity: identity(generation: 1, version: 1))
        waitUntil("A render started") { sessionA.renderedFrames == [5] }

        worker.setModel(
            identity: identity(generation: 1, version: 2),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.request(frame: 7, usage: .paused, identity: identity(generation: 1, version: 2))
        sessionA.gate.signal()

        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(log.all.map { $0.0.version }, [1, 2])
        XCTAssertEqual(log.all.map { $0.1 }, [5, 7])
        XCTAssertEqual(sessionB.renderedFrames, [7])
        XCTAssertTrue(sessionA.disposed)
    }

    /// 無効化した世代のセッションは破棄され、その後の世代だけが
    /// 描画される（連続リセットで旧世代が混入しない）。
    func testInvalidateDropsOldGeneration() {
        let sessionA = FakeSession()
        let sessionB = FakeSession()
        let worker = makeWorker(sessions: [sessionA, sessionB])
        worker.setModel(
            identity: identity(generation: 1, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.invalidate(generation: 1)
        worker.setModel(
            identity: identity(generation: 2, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.request(frame: 3, usage: .paused, identity: identity(generation: 2, version: 1))
        waitUntil("B rendered") { sessionB.renderedFrames == [3] }
        XCTAssertTrue(sessionA.disposed)
        XCTAssertTrue(sessionA.renderedFrames.isEmpty)
    }

    /// 新しい版数向けに先行して出された要求は、旧モデルでは描かれ
    /// ず、新モデルの設置完了後にそのモデルで描かれる（R12-01 の
    /// 必須試験1: モデル切替前の描画ブロックが新モデル向け要求を
    /// 消費しない）。
    func testRequestForNewVersionWaitsForItsModel() {
        let sessionA = FakeSession()
        let sessionB = FakeSession()
        let worker = makeWorker(sessions: [sessionA, sessionB])
        let log = DeliveryLog()
        let delivered = expectation(description: "delivery on new model")
        worker.onRenderFailed = { identity, frame, _, _ in
            log.append(identity, frame)
            delivered.fulfill()
        }
        worker.setModel(
            identity: identity(generation: 1, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        // 版数2向けの要求を、モデル設置より先に出す。
        worker.request(
            frame: 7, usage: .paused, identity: identity(generation: 1, version: 2)
        )
        // 旧モデルでは描かれないことを、短い観察で確認する。
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            XCTAssertTrue(sessionA.renderedFrames.isEmpty)
            Thread.sleep(forTimeInterval: 0.005)
        }
        worker.setModel(
            identity: identity(generation: 1, version: 2),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(sessionB.renderedFrames, [7])
        XCTAssertTrue(sessionA.renderedFrames.isEmpty)
        XCTAssertEqual(log.all.map { $0.0.version }, [2])
    }

    /// セッション無効化と新世代の設置の途中で出された新世代向けの
    /// 要求は、旧世代に消費されず、新世代で描かれる（R12-01 の
    /// 必須試験2）。
    func testRequestIssuedDuringResetSurvivesToNewGeneration() {
        let sessionA = FakeSession()
        let sessionB = FakeSession()
        let worker = makeWorker(sessions: [sessionA, sessionB])
        worker.setModel(
            identity: identity(generation: 1, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.invalidate(generation: 1)
        // 無効化の呼び出しより後・新世代の設置より前に要求する
        // （呼び出し側のリセット手順と同じ順序）。
        worker.request(
            frame: 9, usage: .paused, identity: identity(generation: 2, version: 1)
        )
        worker.setModel(
            identity: identity(generation: 2, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        waitUntil("B rendered frame 9") { sessionB.renderedFrames == [9] }
        XCTAssertTrue(sessionA.renderedFrames.isEmpty)
        XCTAssertTrue(sessionA.disposed)
    }

    /// ループの停止境界で要求を出しても、追加の要求やモデル設置
    /// なしに描画が再開される（lost wake-up の回帰試験。R13-01）。
    /// 停止判定の前後どちらに要求が入っても、最終的に全ての要求
    /// が順に描かれることを、多数回の往復で確認する。
    func testLoopRestartsAcrossStopBoundary() {
        let session = FakeSession()
        let worker = makeWorker(sessions: [session])
        let id = identity(generation: 1, version: 1)
        worker.setModel(
            identity: id, timelines: [], timeline: Timeline(),
            baseDirectory: nil
        )
        let rounds = 100
        for frame in 0..<rounds {
            // 要求は別スレッドからも出す（停止判定との競合を広げる）。
            if frame % 2 == 0 {
                worker.request(frame: frame, usage: .paused, identity: id)
            } else {
                DispatchQueue.global().sync {
                    worker.request(frame: frame, usage: .paused, identity: id)
                }
            }
            // 描画はワーカーのキューで起きるため、背景側の状態を
            // ポーリングで待てる（メインキューの配信待ちではない）。
            waitUntil("render of frame \(frame)") {
                session.renderedFrames.last == frame
            }
        }
        XCTAssertEqual(session.renderedFrames, Array(0..<rounds))
    }

    /// 初期化失敗の通知には識別子が付き、どのモデルの失敗か
    /// 呼び出し側で照合できる（R11-03）。
    func testModelFailureCarriesIdentity() {
        let failing = FakeSession()
        failing.initializationFailure = "初期化できませんでした"
        let worker = makeWorker(sessions: [failing])
        let notified = expectation(description: "model failure notified")
        var received: (String, PreviewRenderWorker.Identity)?
        worker.onModelFailed = { message, identity in
            received = (message, identity)
            notified.fulfill()
        }
        worker.setModel(
            identity: identity(generation: 3, version: 9),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        wait(for: [notified], timeout: 5)
        XCTAssertEqual(received?.0, "初期化できませんでした")
        XCTAssertEqual(received?.1, identity(generation: 3, version: 9))
        XCTAssertTrue(failing.disposed)
    }
}
