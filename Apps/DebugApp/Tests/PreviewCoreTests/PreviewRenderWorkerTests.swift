import CoreGraphics
import XCTest
import YMM4Core
@testable import PreviewCore

/// 描画時間を門（セマフォ）で制御できる偽セッション。
private final class FakeSession: PreviewRenderSession {
    var initializationFailure: String?
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
        worker.onRenderFailed = { identity, frame in
            log.append(identity, frame)
            delivered.fulfill()
        }
        worker.setModel(
            identity: identity(generation: 1, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.request(frame: 0, usage: .paused)
        waitUntil("first render started") { session.renderedFrames == [0] }

        for frame in 1...10 {
            worker.request(frame: frame, usage: .paused)
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
        worker.onRenderFailed = { identity, frame in
            log.append(identity, frame)
            delivered.fulfill()
        }
        worker.setModel(
            identity: identity(generation: 1, version: 1),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.request(frame: 5, usage: .paused)
        waitUntil("A render started") { sessionA.renderedFrames == [5] }

        worker.setModel(
            identity: identity(generation: 1, version: 2),
            timelines: [], timeline: Timeline(), baseDirectory: nil
        )
        worker.request(frame: 7, usage: .paused)
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
        worker.request(frame: 3, usage: .paused)
        waitUntil("B rendered") { sessionB.renderedFrames == [3] }
        XCTAssertTrue(sessionA.disposed)
        XCTAssertTrue(sessionA.renderedFrames.isEmpty)
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
