import Darwin
import Foundation

/// 全自動テストの測定レポート（MAC-0038、オーナー指示 2026-11-17 21:58）。
///
/// 測定値の正本はこの構造体を JSON 化したレポートファイル
/// （`~/ymm4-work/YMM4MacAutoTest/report-<日時>.json` と `latest.json`）であり、
/// 文書側へ数値を転記しない。人手の転記による齟齬（414/413 件の併記と
/// 同じ失敗）を構造的に避けるため、ファイル生成は測定コード自身が行う。
struct AutoTestReport: Codable {
    /// レポート形式の版。項目の意味を変えたら上げる。
    var formatVersion: Int = 1
    /// 生成時刻（ISO 8601、ローカルタイムゾーン）。
    var generatedAt: String
    /// 起動経路: "button"（画面のボタン）/ "environment"（環境変数）/
    /// "triggerFile"（トリガファイル）。
    var trigger: String
    /// ビルド構成: "debug" / "release"。CPU 処理の実時間比は構成で
    /// 大きく変わる（特にリサンプラは未最適化ビルドで桁違いに遅い）ため、
    /// ビルド間比較では必ずこの値を併記する。
    var buildConfiguration: String

    var machine: MachineInfo
    var project: ProjectInfo
    var composition: CompositionResult?
    var seek: SeekResult?
    var audio: AudioResult?
    var export: ExportResult?
    /// プロセス開始から最初の画面表示（ContentView の onAppear）まで。
    var startupSeconds: Double?
    /// 測定完了時点のメモリ使用量。
    var memoryResidentMB: Double
    var memoryFootprintMB: Double
    /// 測定条件・留保の注記。
    var notes: [String]

    struct MachineInfo: Codable {
        var model: String
        var chip: String
        var osVersion: String
        var cpuCount: Int
        var physicalMemoryGB: Double
    }

    struct ProjectInfo: Codable {
        /// "open"（開いていたプロジェクト）/ "sample"（同梱サンプル）。
        var source: String
        var path: String?
        var timelineIndex: Int
        var width: Int
        var height: Int
        var fps: Int
        var hz: Int
        var lengthFrames: Int
        var itemCount: Int
        /// 測定を書き出しと同じ専有スナップショットに対して行ったか。
        var snapshotUsed: Bool
    }

    struct Distribution: Codable {
        var average: Double
        var p95: Double
        var max: Double
    }

    struct CompositionResult: Codable {
        var error: String?
        /// 測定したフレーム番号。
        var frames: [Int] = []
        /// 合成器の update のみ（プレビューと同じ合成経路）。
        var updateOnlyMs: Distribution?
        /// update ＋ CGImage への読み戻し（このアプリのプレビュー表示の
        /// 実際の経路。予算 16.7ms との比較はこちらで行う）。
        var updateAndReadbackMs: Distribution?
        var budgetMs: Double = 16.7
        /// p95 が予算以内か（updateAndReadbackMs 基準）。
        var p95WithinBudget: Bool?
    }

    struct SeekResult: Codable {
        var error: String?
        var targetFrames: [Int] = []
        var responseMs: [Double] = []
        var averageMs: Double?
        var maxMs: Double?
    }

    struct Throughput: Codable {
        var error: String?
        /// 処理した素材の秒数。
        var materialSeconds: Double = 0
        var elapsedSeconds: Double = 0
        /// 実時間比（1.0 = 実時間ちょうど。大きいほど速い）。
        var realtimeRatio: Double = 0
    }

    struct AudioResult: Codable {
        /// タイムライン全体ミックス（書き出しと同じファクトリ構成）。
        var timelineMix: Throughput
        /// リサンプラ単体（Kaiser 正式形、44.1kHz → 48kHz）。
        var resampler44100To48000: Throughput
        /// リサンプラ単体（Kaiser 正式形、48kHz → 44.1kHz）。
        var resampler48000To44100: Throughput
    }

    struct ExportResult: Codable {
        var error: String?
        var ffmpegPath: String = ""
        var rangeStart: Int = 0
        var frameCount: Int = 0
        /// 供給側の構築（ラウドネス解析を含む）にかかった秒数。
        var preparationSeconds: Double = 0
        /// ExportSession のフレームループ実行秒数。
        var runSeconds: Double = 0
        var framesWritten: Int = 0
        var framesPerSecond: Double = 0
        var outputBytes: Int = 0
        var completion: String = ""
    }
}

extension AutoTestReport {
    /// アプリ内表示用の要約行（各項目の値と予算との合否）。
    var summaryLines: [String] {
        var lines: [String] = []
        if let composition, let error = composition.error {
            lines.append("フレーム合成: 失敗（\(error)）")
        } else if let composition,
                  let readback = composition.updateAndReadbackMs,
                  let update = composition.updateOnlyMs {
            let verdict = (composition.p95WithinBudget ?? false) ? "p95 予算内" : "p95 予算超過"
            lines.append(
                "フレーム合成（\(composition.frames.count)フレーム）: "
                    + "更新のみ 平均 \(format(update.average)) / p95 \(format(update.p95)) / 最大 \(format(update.max)) ms、"
                    + "読み戻し込み 平均 \(format(readback.average)) / p95 \(format(readback.p95)) / 最大 \(format(readback.max)) ms"
                    + "（予算 16.7ms: \(verdict)）"
            )
        }
        if let seek, let error = seek.error {
            lines.append("シーク応答: 失敗（\(error)）")
        } else if let seek, let average = seek.averageMs, let max = seek.maxMs {
            lines.append("シーク応答: 平均 \(format(average)) / 最大 \(format(max)) ms（\(seek.targetFrames.count)箇所）")
        }
        if let audio {
            lines.append(
                "音声ミックス: 実時間 ×\(format(audio.timelineMix.realtimeRatio)) / "
                    + "リサンプラ 44.1→48k ×\(format(audio.resampler44100To48000.realtimeRatio)) / "
                    + "48→44.1k ×\(format(audio.resampler48000To44100.realtimeRatio))"
            )
        }
        if let export, let error = export.error {
            lines.append("書き出し: 失敗（\(error)）")
        } else if let export {
            lines.append(
                "書き出し: \(format(export.framesPerSecond)) fps"
                    + "（\(export.framesWritten)フレーム、実行 \(format(export.runSeconds)) 秒）"
            )
        }
        if let startupSeconds {
            lines.append("起動（プロセス開始→画面表示）: \(format(startupSeconds)) 秒")
        }
        lines.append(
            "メモリ（測定完了時）: 常駐 \(format(memoryResidentMB)) MB / フットプリント \(format(memoryFootprintMB)) MB"
        )
        return lines
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// 全自動テストの実行環境（レポート出力先・起動トリガ・起動時間の記録）。
enum AutoTestEnvironment {
    /// レポートの固定出力先。Mac 上で SSH 回収できる場所として
    /// ホーム直下の作業用フォルダ `ymm4-work` の下に固定する
    /// （引き渡し時の回収手順は IMPLEMENTATION_LOG）。
    static var reportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("ymm4-work", isDirectory: true)
            .appendingPathComponent("YMM4MacAutoTest", isDirectory: true)
    }

    static func prepareReportDirectory() throws {
        try FileManager.default.createDirectory(
            at: reportDirectory, withIntermediateDirectories: true
        )
    }

    /// 自動実行トリガを確認する。環境変数 `YMM4MAC_AUTOTEST=1` が
    /// 最優先。次にトリガファイル `~/ymm4-work/YMM4MacAutoTest/RUN`（存在すれば
    /// 消費＝削除して1回だけ実行する）。どちらも無ければ nil。
    static func consumeTrigger() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if environment["YMM4MAC_AUTOTEST"] == "1" {
            return "environment"
        }
        let triggerFile = reportDirectory.appendingPathComponent("RUN")
        if FileManager.default.fileExists(atPath: triggerFile.path) {
            try? FileManager.default.removeItem(at: triggerFile)
            return "triggerFile"
        }
        return nil
    }

    /// 自動実行後にアプリを終了するか（SSH 検証用）。
    static var exitAfterRun: Bool {
        ProcessInfo.processInfo.environment["YMM4MAC_AUTOTEST_EXIT"] == "1"
    }

    // MARK: - 起動時間

    /// 最初の画面表示時刻の記録（ロックで保護した参照型に閉じ込め、
    /// 静的可変変数を持たない形にする）。
    private final class FirstAppearRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date?

        func record() {
            lock.lock()
            defer { lock.unlock() }
            if date == nil {
                date = Date()
            }
        }

        var recorded: Date? {
            lock.lock()
            defer { lock.unlock() }
            return date
        }
    }

    private static let firstAppearRecorder = FirstAppearRecorder()

    /// 最初の画面表示を記録する（ContentView の onAppear から呼ぶ）。
    static func recordFirstAppear() {
        firstAppearRecorder.record()
    }

    /// プロセス開始（sysctl の p_starttime）から最初の画面表示まで。
    static var startupSeconds: Double? {
        guard let appeared = firstAppearRecorder.recorded,
              let start = processStartDate()
        else { return nil }
        return appeared.timeIntervalSince(start)
    }

    static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            return nil
        }
        let start = info.kp_proc.p_starttime
        return Date(
            timeIntervalSince1970: Double(start.tv_sec)
                + Double(start.tv_usec) / 1_000_000
        )
    }

    // MARK: - 機械情報・メモリ

    static func machineInfo() -> AutoTestReport.MachineInfo {
        AutoTestReport.MachineInfo(
            model: sysctlString("hw.model") ?? "unknown",
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            cpuCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryGB: Double(ProcessInfo.processInfo.physicalMemory)
                / 1_073_741_824
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname(name, bytes.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        if let end = buffer.firstIndex(of: 0) {
            buffer = Array(buffer[..<end])
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    /// 現在のメモリ使用量（常駐サイズと物理フットプリント、バイト）。
    static func currentMemoryBytes() -> (resident: Int, footprint: Int) {
        var resident = 0
        var basic = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let basicResult = withUnsafeMutablePointer(to: &basic) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                task_info(
                    mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0, &basicCount
                )
            }
        }
        if basicResult == KERN_SUCCESS {
            resident = Int(basic.resident_size)
        }

        var footprint = 0
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(
                    mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount
                )
            }
        }
        if vmResult == KERN_SUCCESS {
            footprint = Int(vmInfo.phys_footprint)
        }
        return (resident, footprint)
    }
}
