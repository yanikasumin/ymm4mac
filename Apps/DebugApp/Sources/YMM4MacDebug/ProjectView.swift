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

/// 書き出しジョブ。モデルオブジェクト（Timeline 等）は Sendable では
/// ないが、ジョブは生成後に単一のバックグラウンドスレッドからのみ
/// 触れ、UI 状態へは MainActor 経由でのみ書き込むため unchecked とする。
final class ExportJob: @unchecked Sendable {
    private let timeline: Timeline
    private let timelines: [Timeline]
    private let baseDirectory: URL
    private let outputURL: URL
    private let cancellation: TimelineExportCancellation
    private let state: ExportUIState

    init(
        timeline: Timeline, timelines: [Timeline], baseDirectory: URL,
        outputURL: URL, cancellation: TimelineExportCancellation,
        state: ExportUIState
    ) {
        self.timeline = timeline
        self.timelines = timelines
        self.baseDirectory = baseDirectory
        self.outputURL = outputURL
        self.cancellation = cancellation
        self.state = state
    }

    func run() {
        guard let exporter = TimelineExporter(
            timeline: timeline, timelines: timelines, baseDirectory: baseDirectory
        ) else {
            finish { $0.status = "Metal デバイスを初期化できませんでした" }
            return
        }
        defer { exporter.dispose() }
        do {
            let outcome = try exporter.run(
                outputPath: outputURL.path, cancellation: cancellation
            ) { [state] done, total in
                Task { @MainActor in
                    state.framesDone = done
                    state.framesTotal = total
                }
            }
            let summary = exportSummaryText(
                outcome: outcome, analysis: exporter.analysisResult, outputURL: outputURL
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
        lines.append("完了: \(outputURL.path)")
    case .cancelled:
        lines.append("キャンセルされました（出力は finalize 済み）")
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

/// 読み込んだ .ymmp の中身を表示するデバッグ画面。
/// タイムラインとアイテムの一覧、メタデータ駆動のプロパティ
/// インスペクタ（MAC-0029）、読み込み診断（読み飛ばし・型移行）、
/// 往復保存の固定点チェックを行う。
struct ProjectView: View {
    let project: Project
    let diagnostics: YmmpLoadDiagnostics
    let sourceURL: URL

    @State private var timelineIndex: Int
    @State private var selectedItemIndex: Int?
    @State private var roundTripResult: String?
    @State private var saveResult: String?
    @State private var previewFrame: Double = 0
    @State private var previewBox: PreviewBox?
    @State private var previewImage: CGImage?
    @State private var previewError: String?
    @StateObject private var exportState = ExportUIState()

    init(project: Project, diagnostics: YmmpLoadDiagnostics, sourceURL: URL) {
        self.project = project
        self.diagnostics = diagnostics
        self.sourceURL = sourceURL
        _timelineIndex = State(initialValue: project.selectedTimelineIndex)
    }

    private var timeline: Timeline? {
        guard project.timelines.indices.contains(timelineIndex) else { return nil }
        return project.timelines[timelineIndex]
    }

    private var selectedItem: BaseItem? {
        guard let timeline, let selectedItemIndex,
              timeline.items.indices.contains(selectedItemIndex) else { return nil }
        return timeline.items[selectedItemIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sourceURL.lastPathComponent)
                .font(.headline)
            Text(sourceURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 16) {
                Text("タイムライン \(project.timelines.count)")
                Text("キャラクター \(project.characters.count)")
            }
            .font(.callout)

            if let timeline {
                Picker("タイムライン", selection: $timelineIndex) {
                    ForEach(project.timelines.indices, id: \.self) { index in
                        Text(project.timelines[index].name.isEmpty ? "タイムライン \(index + 1)" : project.timelines[index].name)
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: timelineIndex) { _, _ in
                    selectedItemIndex = nil
                    resetPreview()
                }

                let info = timeline.videoInfo
                HStack(spacing: 16) {
                    Text("\(info.width)×\(info.height)")
                    Text("\(info.fps) FPS")
                    Text("\(info.hz) Hz")
                    Text("現在フレーム \(timeline.currentFrame)")
                    Text("アイテム \(timeline.items.count)")
                }
                .font(.callout)

                HStack(alignment: .top, spacing: 16) {
                    List(selection: $selectedItemIndex) {
                        ForEach(Array(timeline.items.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 8) {
                                Text(String(describing: type(of: item)))
                                    .frame(width: 110, alignment: .leading)
                                Text(item.label)
                                    .lineLimit(1)
                                Spacer()
                                Text("F\(item.frame) L\(item.length) Layer\(item.layer) G\(item.group)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .tag(index)
                        }
                    }
                    .frame(minWidth: 380, minHeight: 180)

                    itemDetail(timeline: timeline)
                        .frame(minWidth: 260)
                }
            } else {
                Text("タイムラインがありません")
                    .foregroundStyle(.secondary)
            }

            if let timeline {
                previewView(timeline: timeline)
            }

            if let timeline {
                exportView(timeline: timeline)
            }

            diagnosticsView
            roundTripView
        }
        .onAppear { resetPreview() }
    }

    @ViewBuilder
    private func previewView(timeline: Timeline) -> some View {
        GroupBox("プレビュー（合成）") {
            VStack(alignment: .leading, spacing: 8) {
                if let previewImage {
                    Image(previewImage, scale: 1, label: Text("合成プレビュー"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 360)
                        .background(Color.black)
                } else {
                    Text(previewError ?? "合成結果なし")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("フレーム")
                    Slider(value: $previewFrame, in: 0...Double(max(timeline.length, 1)), step: 1)
                        .onChange(of: previewFrame) { _, _ in renderPreview() }
                    Text("\(Int(previewFrame)) / \(timeline.length)")
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - プレビュー

    /// セッション（ファイル＋タイムライン）が変わったときの初期化。
    /// フレームはタイムラインの現在フレームへ合わせる。
    private func resetPreview() {
        previewBox?.dispose()
        previewBox = nil
        previewImage = nil
        previewError = nil
        guard let timeline else { return }
        previewFrame = Double(timeline.currentFrame)
        let key = PreviewBox.SessionKey(url: sourceURL, timelineIndex: timelineIndex)
        guard let box = PreviewBox(
            key: key, timeline: timeline, timelines: project.timelines,
            baseDirectory: sourceURL.deletingLastPathComponent()
        ) else {
            previewError = "Metal デバイスを初期化できませんでした"
            return
        }
        previewBox = box
        renderPreview()
    }

    private func renderPreview() {
        guard let previewBox, let timeline else { return }
        if let image = previewBox.render(frame: Int(previewFrame), timeline: timeline) {
            previewImage = image
            previewError = nil
        } else {
            previewImage = nil
            previewError = "合成に失敗しました（例外または出力なし）"
        }
    }

    // MARK: - 書き出し

    @ViewBuilder
    private func exportView(timeline: Timeline) -> some View {
        GroupBox("書き出し（mp4 / FFmpeg）") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("現在のタイムラインを mp4 へ書き出す") {
                        startExport(timeline: timeline)
                    }
                    .disabled(exportState.isRunning)
                    if exportState.isRunning {
                        Button("キャンセル") {
                            exportState.cancellation?.cancel()
                        }
                    }
                }
                if exportState.isRunning {
                    ProgressView(
                        value: Double(exportState.framesDone),
                        total: Double(max(exportState.framesTotal, 1))
                    )
                    Text("書き出し中 \(exportState.framesDone) / \(exportState.framesTotal) フレーム")
                        .font(.callout)
                        .monospacedDigit()
                }
                if let status = exportState.status {
                    Text(status)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 保存先を聞いてから、バックグラウンドで書き出しを実行する。
    /// 供給側（Metal 合成・音声ミックス）はスレッド安全性を持たないため、
    /// TimelineExporter の構築から実行までを detached タスク内に閉じる。
    private func startExport(timeline: Timeline) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.mpeg4Movie]
        panel.nameFieldStringValue =
            sourceURL.deletingPathExtension().lastPathComponent + ".mp4"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let cancellation = TimelineExportCancellation()
        exportState.cancellation = cancellation
        exportState.isRunning = true
        exportState.framesDone = 0
        exportState.framesTotal = timeline.length
        exportState.status = "書き出し中（音声解析を含む）…"

        let job = ExportJob(
            timeline: timeline,
            timelines: project.timelines,
            baseDirectory: sourceURL.deletingLastPathComponent(),
            outputURL: outputURL,
            cancellation: cancellation,
            state: exportState
        )
        Task.detached { job.run() }
    }

    /// アイテム詳細。プロパティの編集はメタデータ駆動のインスペクタ
    /// （`PropertyInspectorView`）に委ね、編集が確定するたびに
    /// プレビューを再合成する。アニメーションの評価文脈はプレビューの
    /// 現在フレームに合わせる。
    @ViewBuilder
    private func itemDetail(timeline: Timeline) -> some View {
        GroupBox("アイテム詳細") {
            if let item = selectedItem {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(describing: type(of: item)))
                        .bold()
                    let context = animationContext(for: item, timeline: timeline)
                    PropertyInspectorView(
                        descriptors: ItemPropertyMetadata.descriptors(for: item),
                        animationContext: context,
                        onEdited: { renderPreview() }
                    )
                    EffectInspectorView(
                        item: item,
                        animationContext: context,
                        onEdited: { renderPreview() }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 選択が変わったら各行の入力途中の状態を破棄する。
                .id(selectedItemIndex)
            } else {
                Text("アイテムを選択してください")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// プレビューの現在フレームから、アイテム内相対の評価文脈を作る。
    private func animationContext(for item: BaseItem, timeline: Timeline) -> AnimationEvaluationContext {
        let relative = min(
            max(Int(previewFrame) - item.frame, 0),
            max(item.length - 1, 0)
        )
        return AnimationEvaluationContext(
            frame: relative, length: item.length, fps: timeline.videoInfo.fps
        )
    }

    private var diagnosticsView: some View {
        GroupBox("読み込み診断") {
            VStack(alignment: .leading, spacing: 4) {
                if diagnostics.skippedItems.isEmpty && diagnostics.migratedTypeNames.isEmpty {
                    Text("読み飛ばし・型移行なし")
                        .font(.callout)
                }
                ForEach(Array(diagnostics.skippedItems.enumerated()), id: \.offset) { _, skipped in
                    Text("読み飛ばし: タイムライン\(skipped.timelineIndex) アイテム\(skipped.itemIndex) 型 \(skipped.typeName ?? "(不明)")")
                        .font(.caption)
                }
                ForEach(Array(diagnostics.migratedTypeNames.enumerated()), id: \.offset) { _, migrated in
                    Text("型移行: \(migrated.from) → \(migrated.to)")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var roundTripView: some View {
        GroupBox("往復チェック") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("読み込み→保存→再読込→再保存の固定点を確認") {
                        roundTripResult = checkRoundTrip()
                    }
                    Button("コピーを保存") {
                        saveResult = saveCopy()
                    }
                }
                if let roundTripResult {
                    Text(roundTripResult)
                        .font(.callout)
                }
                if let saveResult {
                    Text(saveResult)
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 保存文字列が固定点に達しているか（1回目の保存と2回目の保存が一致するか）。
    private func checkRoundTrip() -> String {
        do {
            let first = YmmpCodec.encode(project)
            let (reloaded, _) = try YmmpCodec.decode(first)
            let second = YmmpCodec.encode(reloaded)
            if first == second {
                return "固定点に到達（\(first.utf8.count) バイト、往復で差分なし）"
            }
            return "差分あり: 1回目 \(first.utf8.count) バイト / 2回目 \(second.utf8.count) バイト"
        } catch {
            return "再読込でエラー: \(error)"
        }
    }

    private func saveCopy() -> String {
        let directory = sourceURL.deletingLastPathComponent()
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let destination = directory.appendingPathComponent(base + ".roundtrip.ymmp")
        do {
            try YmmpCodec.save(project, toFile: destination.path)
            return "保存しました: \(destination.path)"
        } catch {
            return "保存に失敗: \(error)"
        }
    }
}
