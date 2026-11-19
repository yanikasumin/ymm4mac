import CoreGraphics
import Foundation
import PreviewCore
import YMM4Core
import YMM4GPU

// FE-R1-031 計測ハーネス（計測のみ。製品コードは変更しない）。
//
// 監査で確定した計測仕様（docs/IMPLEMENTATION_LOG.md の FE-R1-031 節）:
// - スナップショット生成（Project.makeExportSnapshot）の内訳:
//   JSON エンコード（時間・バイト数）、JSON デコード＋参照再解決
//   （時間・生成オブジェクト数）、合計（p50 / p95 / 最大は集計側）。
// - アプリでは生成がメインスレッドで同期実行されるため、生成呼び出しの
//   所要時間そのものがメインスレッド連続占有時間になる（前提）。
// - モデル差し替え: PreviewRenderWorker.setModel から、差し替え後の
//   識別子で要求したフレームの画像（または失敗通知）が届くまでの往復。
// - 反映遅延の近似: makeExportSnapshot 開始から、差し替え＋1 フレーム
//   描画の配信までの連鎖合計（アプリ実機の表示遅延ではない。アプリの
//   100ms 間引き・遅延確定は含まない）。
//
// 使い方:
//   harness breakdown <project.ymmp> <label> <out.jsonl> <iterations>
//   harness cold-total <project.ymmp> <label> <out.jsonl>
//   harness worker <project.ymmp> <label> <out.jsonl> \
//       <renderReps> <swapReps> <chainReps>
//   harness detail <project.ymmp> <label> <out.jsonl> <iterations> <phase>
//   harness spin <project.ymmp> <seconds>
//
// detail は FE-R1-031 最適化・第一段階の詳細計測。エンコードを
// 「JSONValue ツリー構築」と「文字列化」へ、デコードを「JSON 解析」と
// 「オブジェクト構築＋参照再解決」へ分離する。公開 API だけでは
// エンコードのツリー構築を直接測れないため、文字列化は「エンコード
// 出力をパースして得た等価なツリーの serialized()」で代理計測し、
// ツリー構築は encodeMs − serializeMs の差分として扱う（セットアップ
// で serialized() の出力がエンコード結果と一致することを検証する）。
// デコード側は JSONParser.parse() が公開されているため直接測り、
// 構築側は decodeMs − parseMs の差分とする。参照再解決はデコードに
// 内包され分離できない（本計測の規模条件ではキャラクター数が
// 0〜2 件で、再解決は早期リターンまたは小規模走査に限られる）。
// spin は `sample` によるホットスポット特定用にエンコード＋デコードを
// 繰り返すだけのモード（記録はしない）。
//
// 記録は JSONL（1 行 = 1 測定）へ追記する。集計は aggregate.py。

func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func msBetween(_ a: UInt64, _ b: UInt64) -> Double {
    Double(b - a) / 1_000_000.0
}

func iso8601String(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

final class JSONLWriter {
    private let handle: FileHandle

    init(path: String) throws {
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        _ = handle.seekToEndOfFile()
    }

    func write(_ record: [String: Any]) {
        var rec = record
        rec["ts"] = iso8601String(Date())
        rec["pid"] = ProcessInfo.processInfo.processIdentifier
        let data = try! JSONSerialization.data(
            withJSONObject: rec, options: [.sortedKeys])
        handle.write(data)
        handle.write("\n".data(using: .utf8)!)
    }

    func writeEnv(mode: String, label: String) {
        write([
            "kind": "env",
            "mode": mode,
            "label": label,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "host": ProcessInfo.processInfo.hostName,
            "processors": ProcessInfo.processInfo.processorCount,
        ])
    }
}

/// デコードで生成されたモデルオブジェクトの数え方（本ハーネスの定義）:
/// タイムライン数 + 全タイムラインの直下アイテム数の合計 + キャラクター数。
/// エフェクトやキーフレーム等の下位オブジェクトは、統一的な走査手段が
/// ないため数えない。
func countObjects(_ project: Project) -> [String: Any] {
    let timelines = project.timelines.count
    let items = project.timelines.reduce(0) { $0 + $1.items.count }
    let characters = project.characters.count
    return [
        "timelines": timelines,
        "items": items,
        "characters": characters,
        "total": timelines + items + characters,
    ]
}

func loadProject(_ path: String) throws -> (project: Project, loadMs: Double) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let text = String(decoding: data, as: UTF8.self)
    let start = nowNs()
    let project = try YmmpCodec.decode(text).project
    return (project, msBetween(start, nowNs()))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("ERROR: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - breakdown / cold-total

func runBreakdown(
    path: String, label: String, out: String, iterations: Int
) throws {
    let writer = try JSONLWriter(path: out)
    writer.writeEnv(mode: "breakdown", label: label)
    let (project, loadMs) = try loadProject(path)
    guard let timeline = project.timelines.first else {
        fail("タイムラインがありません: \(path)")
    }
    let counts = countObjects(project)
    writer.write([
        "kind": "setup", "label": label, "mode": "breakdown",
        "loadMs": loadMs, "objects": counts,
    ])
    for i in 0..<iterations {
        let e0 = nowNs()
        let encoded = YmmpCodec.encode(project)
        let e1 = nowNs()
        let d0 = nowNs()
        let decoded = try YmmpCodec.decode(encoded)
        let d1 = nowNs()
        let decodedCounts = countObjects(decoded.project)
        let t0 = nowNs()
        let snapshot = try project.makeExportSnapshot(of: timeline)
        let t1 = nowNs()
        writer.write([
            "kind": "snapshot",
            "label": label,
            "iter": i,
            "temp": i == 0 ? "cold" : "warm",
            "encodeMs": msBetween(e0, e1),
            "encodedBytes": encoded.utf8.count,
            "decodeMs": msBetween(d0, d1),
            "objects": decodedCounts,
            "totalMs": msBetween(t0, t1),
        ])
        // 解放は計測区間の外（記録の後）で行う。
        _ = snapshot.timelines.count
    }
}

func runColdTotal(path: String, label: String, out: String) throws {
    let writer = try JSONLWriter(path: out)
    writer.writeEnv(mode: "cold-total", label: label)
    let (project, loadMs) = try loadProject(path)
    guard let timeline = project.timelines.first else {
        fail("タイムラインがありません: \(path)")
    }
    // プロセス内で makeExportSnapshot を一度だけ呼ぶ。その初回所要時間を
    // 冷間合計とする（プロジェクト読み込みのデコードはセットアップとして
    // 先行する。この留保は台帳に明記する）。
    let t0 = nowNs()
    let snapshot = try project.makeExportSnapshot(of: timeline)
    let t1 = nowNs()
    writer.write([
        "kind": "snapshot-cold-total",
        "label": label,
        "setupLoadMs": loadMs,
        "objects": countObjects(project),
        "totalMs": msBetween(t0, t1),
    ])
    _ = snapshot.timelines.count
}

// MARK: - detail / spin

func runDetail(
    path: String, label: String, out: String, iterations: Int, phase: String
) throws {
    let writer = try JSONLWriter(path: out)
    writer.writeEnv(mode: "detail", label: label)
    let (project, loadMs) = try loadProject(path)
    guard let timeline = project.timelines.first else {
        fail("タイムラインがありません: \(path)")
    }
    let counts = countObjects(project)
    // 代理計測の前提検証: パースして得たツリーの文字列化が、エンコード
    // 結果とバイト単位で一致すること。一致しなければ文字列化の代理値が
    // ツリー構築側の差分として意味を持たないため、計測を中止する。
    let encodedOnce = YmmpCodec.encode(project)
    var parser = JSONParser(text: encodedOnce)
    let parsedTree = try parser.parse()
    let reserialized = parsedTree.serialized()
    guard reserialized == encodedOnce else {
        fail("代理計測の前提が崩れています: 再シリアライズ結果がエンコード結果と一致しません")
    }
    writer.write([
        "kind": "setup", "label": label, "mode": "detail", "phase": phase,
        "loadMs": loadMs, "objects": counts,
        "serializeMatchesEncode": true,
    ])
    for i in 0..<iterations {
        let e0 = nowNs()
        let encoded = YmmpCodec.encode(project)
        let e1 = nowNs()
        let s0 = nowNs()
        let serialized = parsedTree.serialized()
        let s1 = nowNs()
        let p0 = nowNs()
        var parseTarget = JSONParser(text: encoded)
        let reparsed = try parseTarget.parse()
        let p1 = nowNs()
        let d0 = nowNs()
        let decoded = try YmmpCodec.decode(encoded)
        let d1 = nowNs()
        let t0 = nowNs()
        let snapshot = try project.makeExportSnapshot(of: timeline)
        let t1 = nowNs()
        writer.write([
            "kind": "detail",
            "label": label,
            "phase": phase,
            "iter": i,
            "temp": i == 0 ? "cold" : "warm",
            "encodeMs": msBetween(e0, e1),
            "serializeMs": msBetween(s0, s1),
            "parseMs": msBetween(p0, p1),
            "decodeMs": msBetween(d0, d1),
            "totalMs": msBetween(t0, t1),
            "encodedBytes": encoded.utf8.count,
            "objects": countObjects(decoded.project),
        ])
        // 解放は計測区間の外（記録の後）で行う。
        _ = serialized.count
        _ = reparsed
        _ = snapshot.timelines.count
    }
}

func runSpin(path: String, seconds: Double) throws {
    let (project, _) = try loadProject(path)
    guard let timeline = project.timelines.first else {
        fail("タイムラインがありません: \(path)")
    }
    print("ready pid=\(ProcessInfo.processInfo.processIdentifier)")
    fflush(stdout)
    let deadline = Date().addingTimeInterval(seconds)
    var sink = 0
    while Date() < deadline {
        let encoded = YmmpCodec.encode(project)
        let decoded = try YmmpCodec.decode(encoded)
        let snapshot = try project.makeExportSnapshot(of: timeline)
        sink += encoded.count + decoded.project.timelines.count
            + snapshot.timelines.count
    }
    print("done sink=\(sink)")
}

// MARK: - worker

final class WorkerProbe: @unchecked Sendable {
    var deliveries: [(version: Int, frame: Int, atNs: UInt64, outcome: String)] = []

    func waitDelivery(
        version: Int, frame: Int, timeoutSec: Double
    ) -> (atNs: UInt64, outcome: String)? {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            if let hit = deliveries.first(where: {
                $0.version == version && $0.frame == frame
            }) {
                return (hit.atNs, hit.outcome)
            }
            RunLoop.main.run(
                mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return nil
    }
}

func runWorker(
    path: String, label: String, out: String,
    renderReps: Int, swapReps: Int, chainReps: Int
) throws {
    let writer = try JSONLWriter(path: out)
    writer.writeEnv(mode: "worker", label: label)
    let (project, loadMs) = try loadProject(path)
    guard let timeline = project.timelines.first else {
        fail("タイムラインがありません: \(path)")
    }
    writer.write([
        "kind": "setup", "label": label, "mode": "worker",
        "loadMs": loadMs, "objects": countObjects(project),
    ])
    let timelineEnd = timeline.items.map { $0.frame + $0.length }.max() ?? 0
    let frame = max(0, min(60, timelineEnd - 1))
    let url = URL(fileURLWithPath: path)
    let key = PreviewBox.SessionKey(url: url, timelineIndex: 0)
    let baseDirectory = url.deletingLastPathComponent()

    let probe = WorkerProbe()
    let worker = PreviewRenderWorker()
    worker.onImage = { _, identity, deliveredFrame, _, _ in
        probe.deliveries.append((
            version: identity.version, frame: deliveredFrame,
            atNs: nowNs(), outcome: "image"
        ))
    }
    worker.onRenderFailed = { identity, deliveredFrame, _, _ in
        probe.deliveries.append((
            version: identity.version, frame: deliveredFrame,
            atNs: nowNs(), outcome: "renderFailed"
        ))
    }
    worker.onModelFailed = { _, identity in
        probe.deliveries.append((
            version: identity.version, frame: frame,
            atNs: nowNs(), outcome: "modelFailed"
        ))
    }
    func identity(_ version: Int) -> PreviewRenderWorker.Identity {
        .init(key: key, generation: 1, version: version)
    }
    let timeoutSec = 120.0

    // 差し替え対象のスナップショットを 2 つ用意する（セットアップ）。
    let snapA = try project.makeExportSnapshot(of: timeline)
    let snapB = try project.makeExportSnapshot(of: timeline)

    // 初回設置: setModel から最初の配信までの往復。
    do {
        let t0 = nowNs()
        worker.setModel(
            identity: identity(1), timelines: snapA.timelines,
            timeline: snapA.timeline, baseDirectory: baseDirectory)
        worker.request(frame: frame, usage: .paused, identity: identity(1))
        guard let hit = probe.waitDelivery(
            version: 1, frame: frame, timeoutSec: timeoutSec)
        else { fail("初回設置の配信がタイムアウトしました") }
        writer.write([
            "kind": "worker-install", "label": label, "rep": 0,
            "frame": frame, "outcome": hit.outcome,
            "roundTripMs": msBetween(t0, hit.atNs),
        ])
    }
    // 定常描画: 同一モデル・同一フレームの要求→配信の往復。
    for rep in 0..<renderReps {
        probe.deliveries.removeAll()
        let t0 = nowNs()
        worker.request(frame: frame, usage: .paused, identity: identity(1))
        guard let hit = probe.waitDelivery(
            version: 1, frame: frame, timeoutSec: timeoutSec)
        else { fail("定常描画の配信がタイムアウトしました (rep \(rep))") }
        writer.write([
            "kind": "worker-render", "label": label, "rep": rep,
            "frame": frame, "outcome": hit.outcome,
            "roundTripMs": msBetween(t0, hit.atNs),
        ])
    }
    // 差し替え: 新しいスナップショットを setModel し、新識別子で要求して
    // 配信までの往復（設置＋旧セッション破棄＋1 フレーム描画を含む）。
    for rep in 0..<swapReps {
        let version = rep + 2
        let snap = rep % 2 == 0 ? snapB : snapA
        let t0 = nowNs()
        worker.setModel(
            identity: identity(version), timelines: snap.timelines,
            timeline: snap.timeline, baseDirectory: baseDirectory)
        worker.request(
            frame: frame, usage: .paused, identity: identity(version))
        guard let hit = probe.waitDelivery(
            version: version, frame: frame, timeoutSec: timeoutSec)
        else { fail("差し替えの配信がタイムアウトしました (rep \(rep))") }
        writer.write([
            "kind": "worker-swap", "label": label, "rep": rep,
            "frame": frame, "outcome": hit.outcome,
            "roundTripMs": msBetween(t0, hit.atNs),
        ])
    }
    // 反映遅延の近似: 編集確定（スナップショット生成開始）から、差し替え
    // ＋1 フレーム描画の配信までの連鎖。
    for rep in 0..<chainReps {
        let version = 100 + rep
        let t0 = nowNs()
        let snap = try project.makeExportSnapshot(of: timeline)
        let t1 = nowNs()
        worker.setModel(
            identity: identity(version), timelines: snap.timelines,
            timeline: snap.timeline, baseDirectory: baseDirectory)
        worker.request(
            frame: frame, usage: .paused, identity: identity(version))
        guard let hit = probe.waitDelivery(
            version: version, frame: frame, timeoutSec: timeoutSec)
        else { fail("反映連鎖の配信がタイムアウトしました (rep \(rep))") }
        writer.write([
            "kind": "reflect-chain", "label": label, "rep": rep,
            "frame": frame, "outcome": hit.outcome,
            "snapshotMs": msBetween(t0, t1),
            "afterSnapshotMs": msBetween(t1, hit.atNs),
            "chainTotalMs": msBetween(t0, hit.atNs),
        ])
        _ = snap.timelines.count
    }
}

// MARK: - entry

let args = CommandLine.arguments
let mode = args.count >= 2 ? args[1] : ""
if mode == "spin" {
    // spin だけは引数の並びが違う: spin <project.ymmp> <seconds>
    guard args.count >= 4, let seconds = Double(args[3]) else {
        fail("spin にはプロジェクトパスと秒数が必要です")
    }
    try runSpin(path: args[2], seconds: seconds)
    exit(0)
}
guard args.count >= 5 else {
    fail("引数が不足しています（使い方コメントを参照）")
}
let projectPath = args[2]
let label = args[3]
let outPath = args[4]
switch mode {
case "breakdown":
    guard args.count >= 6, let iterations = Int(args[5]) else {
        fail("breakdown には反復回数が必要です")
    }
    try runBreakdown(
        path: projectPath, label: label, out: outPath, iterations: iterations)
case "cold-total":
    try runColdTotal(path: projectPath, label: label, out: outPath)
case "worker":
    guard args.count >= 8,
          let renderReps = Int(args[5]),
          let swapReps = Int(args[6]),
          let chainReps = Int(args[7])
    else { fail("worker には renderReps swapReps chainReps が必要です") }
    try runWorker(
        path: projectPath, label: label, out: outPath,
        renderReps: renderReps, swapReps: swapReps, chainReps: chainReps)
case "detail":
    guard args.count >= 7, let iterations = Int(args[5]) else {
        fail("detail には反復回数と phase が必要です")
    }
    try runDetail(
        path: projectPath, label: label, out: outPath,
        iterations: iterations, phase: args[6])
default:
    fail("未知のモードです: \(mode)")
}
