import CoreGraphics
import Foundation
import PreviewCore
import YMM4Core
import YMM4GPU

// R6-02 受け入れ実測（第11ラウンド R11-07 の処分）。
// 本物の PreviewRenderWorker を実プロジェクトの最重 30 秒区間
// （フレーム 9217..<11017、Phase A 全数調査で特定）で駆動する。
// 位置は音声マスターを模した経過時間ベースで進め、33 ms 周期で
// 要求だけを出す。記録するのは:
// - ティック数と間隔（位置通知の到達）
// - ワーカーの計数（要求数・上書き数・描画開始/完了数）
// - 配信数と実効 fps、配信フレームの音声位置からの遅延
// - 描画中のメインキュー応答プローブ（16 ms 周期で独立に投入）
// 使い方: harness <project.ymmp> <outDir>

func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func msBetween(_ a: UInt64, _ b: UInt64) -> Double { Double(b - a) / 1_000_000.0 }
func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
func percentile(_ sorted: [Double], _ p: Double) -> Double {
    if sorted.isEmpty { return 0 }
    let i = min(sorted.count - 1, max(0, Int((p * Double(sorted.count)).rounded(.up))))
    return sorted[i]
}

final class Runner: @unchecked Sendable {
    let projectPath: String
    let outDir: String
    var worker: PreviewRenderWorker!
    var identity: PreviewRenderWorker.Identity!
    /// 正常画像の配信（フレーム・配信時点の音声フレーム・到達時刻）。
    var imageDeliveries: [(frame: Int, audioFrame: Int, atNs: UInt64)] = []
    /// 描画失敗の配信数（正常画像と分けて数える。R12-05）。
    var failureDeliveries = 0
    /// 計測区間の終了時刻。これより後の配信はドレイン分として分ける。
    var windowEndNs: UInt64 = 0
    var probeLatencies: [Double] = []
    var tickIntervals: [Double] = []
    var ticks = 0
    var startNs: UInt64 = 0
    var lastTickNs: UInt64 = 0
    var finished = false
    var modelReady = false

    let windowStart = 9217
    let windowFrames = 1800
    let fps = 60

    init() {
        let args = CommandLine.arguments
        projectPath = args[1]
        outDir = args[2]
    }

    func audioFrame(at ns: UInt64) -> Int {
        let elapsedSec = msBetween(startNs, ns) / 1000.0
        return min(
            windowStart + Int(elapsedSec * Double(fps)),
            windowStart + windowFrames - 1
        )
    }

    func run() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: projectPath))
        let text = String(decoding: data, as: UTF8.self)
        let project = try YmmpCodec.decode(text).project
        guard let timeline = project.timelines.first else {
            throw NSError(domain: "harness", code: 1)
        }
        let snapshot = try project.makeExportSnapshot(of: timeline)
        let key = PreviewBox.SessionKey(
            url: URL(fileURLWithPath: projectPath), timelineIndex: 0
        )
        worker = PreviewRenderWorker()
        worker.onImage = { [self] _, _, frame in
            let t = nowNs()
            imageDeliveries.append((frame, audioFrame(at: t), t))
            modelReady = true
        }
        worker.onRenderFailed = { [self] _, _ in
            failureDeliveries += 1
            modelReady = true
        }
        worker.onModelFailed = { message, _ in
            FileHandle.standardError.write(
                "MODEL FAILED: \(message)\n".data(using: .utf8)!
            )
        }
        identity = .init(key: key, generation: 1, version: 1)
        worker.setModel(
            identity: identity,
            timelines: snapshot.timelines, timeline: snapshot.timeline,
            baseDirectory: URL(fileURLWithPath: projectPath)
                .deletingLastPathComponent()
        )
        // モデル設置と初回描画の完了を待つ（準備完了の合図）。
        worker.request(frame: windowStart, usage: .playing, identity: identity)
        let readyDeadline = Date().addingTimeInterval(20)
        while !modelReady && Date() < readyDeadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        guard modelReady else { throw NSError(domain: "harness", code: 2) }
        imageDeliveries.removeAll()
        failureDeliveries = 0

        let tickTimer = DispatchSource.makeTimerSource(queue: .main)
        tickTimer.schedule(
            deadline: .now() + .milliseconds(33), repeating: .milliseconds(33))
        tickTimer.setEventHandler { [self] in tick() }
        // プローブは背景キューから投入する。メインキュー上のタイマ
        // では、タイマ自体の遅延を観測できないため（R12-04）。
        let probeTimer = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .userInitiated))
        probeTimer.schedule(
            deadline: .now() + .milliseconds(16), repeating: .milliseconds(16))
        probeTimer.setEventHandler { [self] in
            let enqueued = nowNs()
            DispatchQueue.main.async { [self] in
                probeLatencies.append(msBetween(enqueued, nowNs()))
            }
        }
        tickTimer.resume()
        probeTimer.resume()
        while !finished {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        tickTimer.cancel()
        probeTimer.cancel()
        // 残りの配信を受け切ってから集計する（短時間だけ回す）。
        let drainDeadline = Date().addingTimeInterval(0.5)
        while Date() < drainDeadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        let stats = worker.stats
        let inWindow = imageDeliveries.filter { $0.atNs <= windowEndNs }
        let latencyFrames = inWindow.map { Double($0.audioFrame - $0.frame) }
        let summary: [String: Any] = [
            "windowStart": windowStart,
            "windowFrames": windowFrames,
            "ticks": ticks,
            "tickIntervalMeanMs": mean(tickIntervals),
            "tickIntervalP95Ms": percentile(tickIntervals.sorted(), 0.95),
            "tickIntervalMaxMs": tickIntervals.max() ?? 0,
            "requestsReceived": stats.requestsReceived,
            "requestsOverwritten": stats.requestsOverwritten,
            "rendersStarted": stats.rendersStarted,
            "rendersCompleted": stats.rendersCompleted,
            "imageDeliveries": imageDeliveries.count,
            "imageDeliveriesInWindow": inWindow.count,
            "failureDeliveries": failureDeliveries,
            "drainDeliveries": imageDeliveries.count - inWindow.count,
            "effectiveFps": Double(inWindow.count) / 30.0,
            "deliveryLagFramesMean": mean(latencyFrames),
            "deliveryLagFramesP95": percentile(latencyFrames.sorted(), 0.95),
            "deliveryLagFramesMax": latencyFrames.max() ?? 0,
            "probeLatencyMeanMs": mean(probeLatencies),
            "probeLatencyP95Ms": percentile(probeLatencies.sorted(), 0.95),
            "probeLatencyMaxMs": probeLatencies.max() ?? 0,
            "probeCount": probeLatencies.count,
        ]
        let json = try JSONSerialization.data(
            withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: outDir + "/phaseE.json"))
        print(String(data: json, encoding: .utf8)!)
    }

    private func tick() {
        let t = nowNs()
        if startNs == 0 { startNs = t; lastTickNs = t }
        if ticks > 0 { tickIntervals.append(msBetween(lastTickNs, t)) }
        lastTickNs = t
        ticks += 1
        worker.request(frame: audioFrame(at: t), usage: .playing, identity: identity)
        if msBetween(startNs, t) >= 30_000 {
            windowEndNs = t
            finished = true
        }
    }
}

try Runner().run()
