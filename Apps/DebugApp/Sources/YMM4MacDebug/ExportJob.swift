import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YMM4Core
import YMM4GPU

/// 書き出しの進捗状態（バックグラウンド実行から MainActor 経由で更新する）。
@MainActor
final class ExportUIState: ObservableObject {
    @Published var isRunning = false
    @Published var framesDone = 0
    @Published var framesTotal = 0
    @Published var status: String?
    var cancellation: TimelineExportCancellation?
}

/// 書き出し要求（ダイアログで確定した出力形式と出力先）。
/// 音量正規化・コンプレッサは形式に依らず音声供給側へ効くため、
/// 両形式とも同じ設定対を持つ（FE-R1-017）。
enum ExportRequest: Sendable {
    /// MP4（H.264 / AAC、ffmpeg 経由）。出力先はファイル。
    case mp4(
        fileURL: URL,
        loudness: LoudnessNormalizationSettings,
        compressor: CompressorSettings
    )
    /// PNG 連番＋WAV（PngWav）。出力先はフォルダ。
    case pngWav(
        directoryURL: URL,
        settings: PngWavExportSettings,
        loudness: LoudnessNormalizationSettings,
        compressor: CompressorSettings
    )

    /// 音声処理設定（形式に依らない共通部）。
    var audioSettings: (
        loudness: LoudnessNormalizationSettings, compressor: CompressorSettings
    ) {
        switch self {
        case .mp4(_, let loudness, let compressor),
             .pngWav(_, _, let loudness, let compressor):
            return (loudness, compressor)
        }
    }

    /// 要約表示用の出力先 URL。
    var outputURL: URL {
        switch self {
        case .mp4(let fileURL, _, _): return fileURL
        case .pngWav(let directoryURL, _, _, _): return directoryURL
        }
    }
}

/// 書き出しジョブ。保持するモデルは、書き出し開始時に
/// `Project.makeExportSnapshot(of:)` で作ったジョブ専有の
/// スナップショットであり、編集中のプロジェクトとはインスタンスを
/// 共有しない（AUD-07）。モデルオブジェクト（Timeline 等）は Sendable
/// ではないが、スナップショットは生成後に単一のバックグラウンド
/// スレッドからのみ触れ、UI 状態へは MainActor 経由でのみ書き込む
/// ため unchecked とする。
final class ExportJob: @unchecked Sendable {
    private let timeline: Timeline
    private let timelines: [Timeline]
    private let baseDirectory: URL
    private let request: ExportRequest
    private let cancellation: TimelineExportCancellation
    private let state: ExportUIState

    init(
        timeline: Timeline, timelines: [Timeline], baseDirectory: URL,
        request: ExportRequest, cancellation: TimelineExportCancellation,
        state: ExportUIState
    ) {
        self.timeline = timeline
        self.timelines = timelines
        self.baseDirectory = baseDirectory
        self.request = request
        self.cancellation = cancellation
        self.state = state
    }

    func run() {
        let exporter: TimelineExporter
        do {
            let audio = request.audioSettings
            exporter = try TimelineExporter(
                timeline: timeline, timelines: timelines, baseDirectory: baseDirectory,
                loudness: audio.loudness, compressor: audio.compressor
            )
        } catch let error as MetalInitializationError {
            // 初期化失敗の理由をそのまま表示する（Issue #50）。
            finish { $0.status = "Metal の初期化に失敗しました: \(error.userMessage)" }
            return
        } catch {
            finish { $0.status = "書き出しを開始できませんでした: \(error)" }
            return
        }
        defer { exporter.dispose() }
        do {
            let progress: (Int, Int) -> Void = { [state] done, total in
                Task { @MainActor in
                    state.framesDone = done
                    state.framesTotal = total
                }
            }
            let outcome: ExportOutcome
            switch request {
            case .mp4(let fileURL, _, _):
                outcome = try exporter.run(
                    outputPath: fileURL.path, cancellation: cancellation,
                    onProgress: progress
                )
            case .pngWav(let directoryURL, let settings, _, _):
                outcome = try exporter.runPngWav(
                    outputDirectory: directoryURL.path, settings: settings,
                    cancellation: cancellation, onProgress: progress
                )
            }
            let summary = exportSummaryText(
                outcome: outcome, analysis: exporter.analysisResult,
                outputURL: request.outputURL
            )
            finish { $0.status = summary }
        } catch {
            finish { $0.status = "書き出しを開始できませんでした: \(error)" }
        }
    }

    private func finish(_ update: @escaping @MainActor (ExportUIState) -> Void) {
        Task { @MainActor in
            state.isRunning = false
            update(state)
        }
    }
}

/// 書き出し結果の要約文（UI 表示用）。
func exportSummaryText(
    outcome: ExportOutcome, analysis: LoudnessAnalysisResult, outputURL: URL
) -> String {
    var lines: [String] = []
    switch outcome.completion {
    case .completed:
        // finalize が成功しても、両ストリーム無効の構成では成果物
        // ファイルが生成されない（EX17-07）。パスを表示して
        // ファイルがあるかのように見せない。
        lines.append(
            outcome.outputProduced
                ? "完了: \(outputURL.path)"
                : "完了（成果物ファイルは生成されませんでした）"
        )
    case .cancelled:
        lines.append(
            outcome.outputProduced
                ? "キャンセルされました（出力は finalize 済み）"
                : "キャンセルされました"
        )
    case .failed:
        lines.append("失敗: \(outcome.error?.message ?? "不明なエラー")")
    }
    lines.append("書き出しフレーム数: \(outcome.framesWritten)")
    lines.append(
        "音声解析: ピーク \(String(format: "%.2f", analysis.peakDb)) dB / "
            + "ラウドネス \(String(format: "%.2f", analysis.averageLoudness)) LKFS / "
            + "音量倍率 \(String(format: "%.4f", analysis.volumeRate)) / "
            + "コンプレッサ倍率 \(String(format: "%.4f", analysis.compressorRate))"
    )
    if let warning = outcome.warning {
        lines.append("警告: \(warning.message)")
    }
    return lines.joined(separator: "\n")
}
