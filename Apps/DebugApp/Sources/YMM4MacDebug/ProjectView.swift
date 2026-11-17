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

/// プロジェクトのワークスペースを表示するデバッグ画面。
/// 配置は本家 v4.55.1.1 の実コード解析（analysis-notes/UI-LAYOUT-FACTS.md）
/// に基づく: 左カラムは上からプレビュー（主役・残り全域）→トランスポート帯
/// →タイムライン帯（固定高）、右カラムはアイテム詳細（本家の編集ペイン
/// 幅400・全高）。最下段に本家の並びのステータスバーを置き、書き出し・
/// 読み込み診断・往復チェックはその上の小タブ（固定高）に残す。
/// プレビューの高さを固定高さ領域が圧迫しないよう、サイズ配分は
/// 「プレビューだけが可変、他は全て固定高さ」で設計している。
/// 縦一列スクロールは廃止した（各領域が内部でスクロールする）。
struct ProjectView: View {
    let project: Project
    let diagnostics: YmmpLoadDiagnostics
    /// 読み込み元ファイル。未保存の新規プロジェクトでは nil。
    let sourceURL: URL?

    @State private var timelineIndex: Int
    @State private var selectedItemIndex: Int?
    @State private var roundTripResult: String?
    @State private var saveResult: String?
    @State private var previewFrame: Double = 0
    @State private var previewBox: PreviewBox?
    @State private var previewImage: CGImage?
    @State private var previewError: String?
    /// プレビュー上でのドラッグ移動の作業状態（開始時点の評価値と
    /// 開始点を保持し、移動量は常に開始時点からの差分で書き込む）。
    @State private var previewDrag: PreviewDragState?
    @StateObject private var exportState = ExportUIState()

    // MARK: 形の状態（トランスポート・タイムライン帯）
    // ここにあるのは UI 要素としての状態であり、再生エンジン等の
    // 実接続は接続フェーズで行う（台帳: UI-FRONTEND-DIFF.md）。
    /// 再生ボタンの表示状態（再生中かどうか）。エンジンは未接続。
    @State private var isPlayingForm = false
    /// 再生速度（倍率）。本家の速度コンボの選択値。
    @State private var playbackRate: Double = 1.0
    /// リピート再生トグル。
    @State private var isRepeatOn = false
    /// コントロールポイント表示モード（本家の3択）。
    @State private var controlPointVisibility: ControlPointVisibility = .selectedOnly
    /// プレビュー表示倍率（フィット倍率への乗数。1.0 = フィット）。
    @State private var previewDisplayZoom: Double = 1.0
    /// 音量（0–100%）とミュート。音声出力は未接続。
    @State private var volume: Double = 100
    @State private var isMuted = false
    /// タイムラインのズーム（TimelineStripView と共有）。
    @State private var timelineZoomPercent: Double = 100
    /// レイヤー行の高さ（本家 LayerHeight、既定32・下限14）。
    @State private var layerRowHeight: Double = 32
    /// ステータスバーの入力欄のフォーカスと編集中文字列。
    @FocusState private var statusFocus: StatusField?
    @State private var statusTimeText = ""
    @State private var statusFrameText = ""
    /// メニュー（アプリ側）からのダイアログ表示要求を受ける。
    @EnvironmentObject private var workspace: WorkspaceState
    /// 「動画の設定」シートの表示状態。
    @State private var isVideoSettingsPresented = false
    /// 「動画出力」シートの表示状態。
    @State private var isExportDialogPresented = false
    /// タイムラインキャンバスの表示幅（全体フィット計算用。
    /// TimelineStripView から受け取る）。
    @State private var canvasViewportWidth: CGFloat = 800
    /// 波形表示の有無（本家の「波形を表示/非表示」）。
    @State private var showWaveform = true

    init(project: Project, diagnostics: YmmpLoadDiagnostics, sourceURL: URL?) {
        self.project = project
        self.diagnostics = diagnostics
        self.sourceURL = sourceURL
        _timelineIndex = State(initialValue: project.selectedTimelineIndex)
    }

    /// ステータスバー等に出すプロジェクト名。
    private var displayName: String {
        sourceURL?.lastPathComponent ?? "新規プロジェクト（未保存）"
    }

    /// 素材の相対解決と保存先の基準ディレクトリ。
    private var baseDirectory: URL {
        sourceURL?.deletingLastPathComponent()
            ?? FileManager.default.temporaryDirectory
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
        VStack(alignment: .leading, spacing: 0) {
            headerStrip
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            Divider()

            if let timeline {
                HStack(alignment: .top, spacing: 0) {
                    // 左カラム: プレビュー（可変・主役）＋トランスポート（固定）
                    // ＋タイムライン帯（ツールバー・本体・セリフ行）。
                    // レベルメーターは本家どおりタイムライン領域の左端に立つ。
                    VStack(alignment: .leading, spacing: 0) {
                        previewView(timeline: timeline)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        transportBar(timeline: timeline)
                            .frame(height: 30)

                        Divider()

                        HStack(alignment: .top, spacing: 0) {
                            levelMeters
                                .frame(width: 24)
                                .frame(maxHeight: .infinity)

                            Divider()

                            VStack(alignment: .leading, spacing: 0) {
                                sceneTabs(timeline: timeline)
                                    .frame(height: 24)

                                Divider()

                                timelineToolbar(timeline: timeline)
                                    .frame(height: 26)

                                Divider()

                                TimelineStripView(
                                    timeline: timeline,
                                    currentFrame: Int(previewFrame),
                                    selectedItemIndex: $selectedItemIndex,
                                    onSeek: { seek(to: $0, timeline: timeline) },
                                    zoomPercent: $timelineZoomPercent,
                                    rowHeight: CGFloat(layerRowHeight),
                                    showWaveform: showWaveform,
                                    reportedCanvasWidth: $canvasViewportWidth
                                )
                                .frame(height: 232)

                                Divider()

                                SerifInputView(characters: project.characters)
                                    .frame(height: 32)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    inspectorPane(timeline: timeline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $isVideoSettingsPresented) {
                    VideoSettingsView(timeline: timeline) { resetPreview() }
                }
                .sheet(isPresented: $isExportDialogPresented) {
                    ExportDialogView(timeline: timeline) { url in
                        runExport(timeline: timeline, outputURL: url)
                    }
                }
                .onChange(of: workspace.isVideoSettingsPresented) { _, requested in
                    if requested {
                        isVideoSettingsPresented = true
                        workspace.isVideoSettingsPresented = false
                    }
                }
                .onChange(of: workspace.isExportPresented) { _, requested in
                    if requested {
                        isExportDialogPresented = true
                        workspace.isExportPresented = false
                    }
                }

                Divider()

                bottomTabs(timeline: timeline)
                    .frame(height: 150)

                Divider()

                statusBar(timeline: timeline)
            } else {
                Text("タイムラインがありません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { resetPreview() }
    }

    // MARK: - 上部ストリップ

    private var headerStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(displayName)
                    .font(.headline)
                if let sourceURL {
                    Text(sourceURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("タイムライン \(project.timelines.count)")
                Text("キャラクター \(project.characters.count)")
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// シーン（タイムライン）のタブ列。本家ではドキュメント=シーンが
    /// タイムライン領域の上部にタブとして並ぶ（UI-LAYOUT-FACTS.md
    /// §1・§16）。切替時の処理は従来の Picker と同じ。
    private func sceneTabs(timeline: Timeline) -> some View {
        HStack(spacing: 0) {
            ForEach(project.timelines.indices, id: \.self) { index in
                let name = project.timelines[index].name.isEmpty
                    ? "タイムライン \(index + 1)"
                    : project.timelines[index].name
                Button {
                    if timelineIndex != index {
                        timelineIndex = index
                        selectedItemIndex = nil
                        resetPreview()
                    }
                } label: {
                    Text(name)
                        .font(.callout)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            index == timelineIndex
                                ? Color(nsColor: .selectedControlColor)
                                : Color.clear
                        )
                        .overlay(alignment: .bottom) {
                            if index == timelineIndex {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
    }

    // MARK: - プレビュー

    /// 映像はプロジェクトの解像度比を保って領域に収める（本家
    /// PreviewViewModel のフィット計算: 倍率 = min(領域幅/映像幅,
    /// 領域高/映像高)）。背後に白い矩形＋影を置くのも本家どおり。
    /// 領域そのものは左カラムの残り全域を取り、固定高さの帯には
    /// 圧迫されない。
    private func previewView(timeline: Timeline) -> some View {
        GeometryReader { geometry in
            let info = timeline.videoInfo
            // 本家 PreviewViewModel の式そのまま:
            // AreaZoom = min(領域幅/映像幅, 領域高/映像高)、
            // 表示幅 = min(領域幅, 映像幅 × AreaZoom × 表示倍率)。
            let areaScale = min(
                geometry.size.width / Double(max(info.width, 1)),
                geometry.size.height / Double(max(info.height, 1))
            )
            let fittedWidth = min(
                geometry.size.width,
                Double(max(info.width, 1)) * areaScale * previewDisplayZoom
            )
            let fittedHeight = min(
                geometry.size.height,
                Double(max(info.height, 1)) * areaScale * previewDisplayZoom
            )
            // ヒットレイヤの逆変換に使う実効倍率（表示幅基準）。
            let scale = fittedWidth / Double(max(info.width, 1))

            ZStack {
                Rectangle()
                    .fill(.white)
                    .frame(width: fittedWidth, height: fittedHeight)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 0)

                if let previewImage {
                    Image(previewImage, scale: 1, label: Text("合成プレビュー"))
                        .resizable()
                        .frame(width: fittedWidth, height: fittedHeight)
                } else {
                    Rectangle()
                        .fill(.black)
                        .frame(width: fittedWidth, height: fittedHeight)
                    Text(
                        previewError
                            ?? (timeline.items.isEmpty ? "空のタイムライン" : "合成結果なし")
                    )
                    .font(.callout)
                    .foregroundStyle(.white)
                }

                // 選択輪郭とクリック選択／ドラッグ移動のヒットレイヤ。
                // 映像の表示矩形とぴったり重ね、座標は表示倍率で
                // 映像座標へ逆変換する（レターボックス分は含まない）。
                previewInteractionLayer(timeline: timeline, scale: scale)
                    .frame(width: fittedWidth, height: fittedHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - プレビュー上の選択と移動

    private struct PreviewDragState {
        /// 対象アイテムのインデックス。空白を押した場合は -1。
        var itemIndex: Int
        var startVideoPoint: CGPoint
        var originalX: Double
        var originalY: Double
        var lastWrittenX: Double
        var lastWrittenY: Double
    }

    private func previewInteractionLayer(timeline: Timeline, scale: Double) -> some View {
        ZStack(alignment: .topLeading) {
            if let item = selectedItem,
               let bounds = previewItemBounds(item: item, timeline: timeline) {
                // 選択輪郭（白背景でも見えるよう黒と白の二重破線）。
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [5, 4]))
                    .foregroundStyle(.black.opacity(0.55))
                    .frame(width: bounds.width * scale, height: bounds.height * scale)
                    .offset(x: bounds.minX * scale, y: bounds.minY * scale)
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.white)
                    .frame(width: bounds.width * scale, height: bounds.height * scale)
                    .offset(x: bounds.minX * scale, y: bounds.minY * scale)

                // 操作ハンドル（本家: 四隅▢ = 拡大率、辺の中点◯ =
                // 回転角）。ドラッグ操作は接続フェーズ。ここでは形のみ。
                selectionHandles(bounds: bounds, scale: scale)
            }

            Color.clear
                .contentShape(Rectangle())
                .gesture(previewDragGesture(timeline: timeline, scale: scale))
        }
    }

    /// 選択アイテムの操作ハンドル群（表示座標で 9px の正方形・円）。
    private func selectionHandles(bounds: CGRect, scale: Double) -> some View {
        let scale = CGFloat(scale)
        let size = 9.0
        let corners: [(CGFloat, CGFloat)] = [
            (bounds.minX, bounds.minY), (bounds.maxX, bounds.minY),
            (bounds.minX, bounds.maxY), (bounds.maxX, bounds.maxY),
        ]
        let edges: [(CGFloat, CGFloat)] = [
            (bounds.midX, bounds.minY), (bounds.midX, bounds.maxY),
            (bounds.minX, bounds.midY), (bounds.maxX, bounds.midY),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(Array(corners.enumerated()), id: \.offset) { _, point in
                Rectangle()
                    .fill(.white)
                    .overlay(Rectangle().strokeBorder(.gray, lineWidth: 1))
                    .frame(width: size, height: size)
                    .offset(
                        x: point.0 * scale - size / 2,
                        y: point.1 * scale - size / 2
                    )
            }
            ForEach(Array(edges.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.gray, lineWidth: 1))
                    .frame(width: size, height: size)
                    .offset(
                        x: point.0 * scale - size / 2,
                        y: point.1 * scale - size / 2
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func previewDragGesture(timeline: Timeline, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if var drag = previewDrag {
                    guard drag.itemIndex >= 0,
                          timeline.items.indices.contains(drag.itemIndex) else { return }
                    let item = timeline.items[drag.itemIndex]
                    let newX = drag.originalX
                        + Double(value.location.x - value.startLocation.x) / scale
                    let newY = drag.originalY
                        + Double(value.location.y - value.startLocation.y) / scale
                    // 再合成が追いつくよう、書き込みは映像座標で
                    // 0.5px 以上動いたときだけ行う。
                    guard abs(newX - drag.lastWrittenX) >= 0.5
                        || abs(newY - drag.lastWrittenY) >= 0.5 else { return }
                    writeItemPosition(item: item, x: newX, y: newY)
                    drag.lastWrittenX = newX
                    drag.lastWrittenY = newY
                    previewDrag = drag
                    renderPreview()
                    return
                }

                // 押し始め: 現在フレームで描画されているアイテムから
                // 当たり判定し、選択とドラッグ基準を決める。
                let startVideoPoint = CGPoint(
                    x: value.startLocation.x / scale,
                    y: value.startLocation.y / scale
                )
                if let index = hitTestPreviewItem(
                    timeline: timeline, videoPoint: startVideoPoint
                ), let props = timeline.items[index] as? VideoItemProperties {
                    selectedItemIndex = index
                    let item = timeline.items[index]
                    let context = animationContext(for: item, timeline: timeline)
                    let originalX = context.value(of: props.x)
                    let originalY = context.value(of: props.y)
                    previewDrag = PreviewDragState(
                        itemIndex: index,
                        startVideoPoint: startVideoPoint,
                        originalX: originalX, originalY: originalY,
                        lastWrittenX: originalX, lastWrittenY: originalY
                    )
                } else {
                    // 空白を押したら選択を外す（このドラッグでは
                    // それ以上何もしない）。
                    selectedItemIndex = nil
                    previewDrag = PreviewDragState(
                        itemIndex: -1, startVideoPoint: startVideoPoint,
                        originalX: 0, originalY: 0, lastWrittenX: 0, lastWrittenY: 0
                    )
                }
            }
            .onEnded { _ in
                previewDrag = nil
            }
    }

    /// プレビュー上の点（映像座標）にあるアイテムを探す。重なり時は
    /// 本家の描画順（DrawOrdering の3段キー: 手前に表示 → ZIndex →
    /// レイヤー の昇順で最後に描かれるもの＝最前面）を優先する。
    /// ZIndex は描画変換後の原点 Z が正本だが、ここでは Z 値の評価値で
    /// 近似する（Zオーダー有効時のみ影響する）。
    private func hitTestPreviewItem(timeline: Timeline, videoPoint: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestKey: (Int, Double, Int)?
        for (index, item) in timeline.items.enumerated() {
            guard let bounds = previewItemBounds(item: item, timeline: timeline),
                  bounds.contains(videoPoint),
                  let props = item as? VideoItemProperties else { continue }
            let context = animationContext(for: item, timeline: timeline)
            let zIndex = props.isZOrderEnabled ? context.value(of: props.z) : 0
            let key = (
                props.isAlwaysOnTop ? 1 : 0,
                zIndex.isFinite ? zIndex : 0,
                item.layer
            )
            if let current = bestKey {
                if key > current || (key == current && index > (bestIndex ?? -1)) {
                    bestKey = key
                    bestIndex = index
                }
            } else {
                bestKey = key
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// アイテムの当たり範囲（映像座標）。中心は現在フレームで評価した
    /// X/Y。大きさは素材の実寸が表示側からは取れないため、種別ごとの
    /// 妥当な大きさ（拡大率で比例）で代替する近似であり、回転は
    /// 考慮しない軸平行矩形である（制限として報告に明記）。
    private func previewItemBounds(item: BaseItem, timeline: Timeline) -> CGRect? {
        guard let props = item as? VideoItemProperties else { return nil }
        let frame = Int(previewFrame)
        guard frame >= item.frame, frame < item.frame + item.length else { return nil }
        if item.isHidden
            || timeline.layerSettings.setting(forLayer: item.layer).isHidden {
            return nil
        }
        let context = animationContext(for: item, timeline: timeline)
        let centerX = context.value(of: props.x)
        let centerY = context.value(of: props.y)
        let zoom = min(max(context.value(of: props.zoom) / 100, 0.05), 8)
        let info = timeline.videoInfo
        let size: CGSize
        if item is TextItem || item is VoiceItem {
            // 字幕・テキストは横長の帯として扱う。
            size = CGSize(
                width: Double(info.width) * 0.6 * zoom,
                height: Double(info.height) * 0.12 * zoom
            )
        } else {
            size = CGSize(
                width: Double(info.width) * 0.3 * zoom,
                height: Double(info.height) * 0.3 * zoom
            )
        }
        return CGRect(
            x: centerX - size.width / 2, y: centerY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    /// ドラッグ移動の書き込み。インスペクタの数値確定と同じ規則
    /// （定数なら定数化、それ以外は先頭値のみ書き換え）で、既存の
    /// 記述子経路を通して X/Y へ書き込む。
    private func writeItemPosition(item: BaseItem, x: Double, y: Double) {
        for descriptor in ItemPropertyMetadata.descriptors(for: item)
        where descriptor.kind == .animation {
            let value: Double
            switch descriptor.displayName {
            case "X": value = x
            case "Y": value = y
            default: continue
            }
            guard let animation = descriptor.animationValue else { continue }
            if animation.animationType == .none {
                descriptor.setAnimationConstantValue(value)
            } else {
                descriptor.setAnimationFirstValue(value)
            }
        }
    }

    // MARK: - トランスポート帯

    /// 本家 PreviewView の操作行（高さ24）の全構成要素を備えた帯。
    /// 並びは本家どおり（UI-LAYOUT-FACTS.md §3）: 左から 再生/一時停止、
    /// 停止、再生速度コンボ、リピート、コントロールポイント表示、
    /// プレビュー倍率コンボ、フィット、先頭、前の編集点、前フレーム、
    /// 中央に位置スライダ（残り全幅）、右に 次フレーム、次の編集点、
    /// 末尾、音量スライダ、ミュート。
    /// 再生エンジンと音声出力は未接続（形のみ。台帳参照）。シーク系と
    /// 表示倍率は実動する。
    private func transportBar(timeline: Timeline) -> some View {
        HStack(spacing: 2) {
            transportButton(
                isPlayingForm ? "pause.fill" : "play.fill",
                help: isPlayingForm ? "一時停止" : "再生"
            ) {
                isPlayingForm.toggle()
            }
            transportButton("stop.fill", help: "停止") {
                isPlayingForm = false
                seek(to: 0, timeline: timeline)
            }

            // 再生速度（x1.0 以外は赤字＋太字 — 本家の規則）。
            Picker("", selection: $playbackRate) {
                ForEach(Self.playbackRates, id: \.self) { rate in
                    Text("x\(rate, specifier: "%.2g")").tag(rate)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 64)
            .foregroundStyle(playbackRate == 1.0 ? Color.primary : Color.red)
            .fontWeight(playbackRate == 1.0 ? .regular : .bold)
            .help("再生速度")

            transportToggle(
                "repeat", help: "リピート再生", isOn: $isRepeatOn
            )

            // コントロールポイント表示（本家の3択）。
            Menu {
                ForEach(ControlPointVisibility.allCases, id: \.self) { mode in
                    Button {
                        controlPointVisibility = mode
                    } label: {
                        if controlPointVisibility == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("コントロールポイント表示")

            // プレビュー倍率（表示倍率は実動する）。
            Picker("", selection: $previewDisplayZoom) {
                Text("25%").tag(0.25)
                Text("50%").tag(0.5)
                Text("100%").tag(1.0)
                Text("150%").tag(1.5)
                Text("200%").tag(2.0)
                Text("400%").tag(4.0)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 76)
            .help("プレビュー倍率")
            transportButton("aspectratio", help: "フィット") {
                previewDisplayZoom = 1.0
            }

            transportButton("backward.end.fill", help: "先頭へ移動") {
                seek(to: 0, timeline: timeline)
            }
            transportButton("chevron.backward.2", help: "前の編集点へ移動") {
                seekToPreviousEditPoint(timeline: timeline)
            }
            transportButton("chevron.backward", help: "前フレーム") {
                seek(to: Int(previewFrame) - 1, timeline: timeline)
            }

            Slider(value: $previewFrame, in: 0...Double(max(timeline.length, 1)), step: 1)
                .onChange(of: previewFrame) { _, _ in renderPreview() }
                .padding(.horizontal, 6)

            transportButton("chevron.forward", help: "次フレーム") {
                seek(to: Int(previewFrame) + 1, timeline: timeline)
            }
            transportButton("chevron.forward.2", help: "次の編集点へ移動") {
                seekToNextEditPoint(timeline: timeline)
            }
            transportButton("forward.end.fill", help: "末尾へ移動") {
                seek(to: timeline.length, timeline: timeline)
            }

            // 音量（本家は幅150の TextBoxSlider、0–100% を F1 表示）。
            Slider(value: $volume, in: 0...100)
                .frame(width: 120)
                .help("音量")
            Text(isMuted ? "0.0%" : "\(volume, specifier: "%.1f")%")
                .font(.callout)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            transportToggle(
                isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                help: "ミュート", isOn: $isMuted
            )
        }
        .padding(.horizontal, 6)
    }

    /// 本家の速度コンボの選択肢（0.25刻みのうち整数と .5 のみが有効 —
    /// UI-LAYOUT-FACTS.md §3。x0.25 と x0.5 は下限側の代表として含む）。
    private static let playbackRates: [Double] = [
        0.25, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5,
        5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0,
    ]

    /// 状態を持つトグルボタン（トランスポート用）。
    private func transportToggle(
        _ systemImage: String, help: String, isOn: Binding<Bool>
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func transportButton(
        _ systemImage: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    /// シーク先を範囲内に丸めてプレビュー位置へ反映する
    /// （再合成はスライダの onChange 経由で行われる）。
    private func seek(to frame: Int, timeline: Timeline) {
        previewFrame = Double(min(max(frame, 0), timeline.length))
    }

    /// 編集点 = 全アイテムの開始/終了フレーム（＋両端）。
    private func editPoints(timeline: Timeline) -> [Int] {
        var points: Set<Int> = [0, timeline.length]
        for item in timeline.items {
            points.insert(min(max(item.frame, 0), timeline.length))
            points.insert(min(max(item.frame + item.length, 0), timeline.length))
        }
        return points.sorted()
    }

    private func seekToPreviousEditPoint(timeline: Timeline) {
        let current = Int(previewFrame)
        let target = editPoints(timeline: timeline).last { $0 < current } ?? 0
        seek(to: target, timeline: timeline)
    }

    private func seekToNextEditPoint(timeline: Timeline) {
        let current = Int(previewFrame)
        let target = editPoints(timeline: timeline).first { $0 > current } ?? timeline.length
        seek(to: target, timeline: timeline)
    }

    // MARK: - タイムラインのツールバーとレベルメーター

    /// 本家 TimelineView 上部のツールバートレイ（ズーム／アイテム／編集／
    /// プロジェクト／フィードバックの5系統）の形。ズームとレイヤー高さは
    /// 実動し、それ以外は未接続（台帳参照）。
    private func timelineToolbar(timeline: Timeline) -> some View {
        // 狭いウィンドウ幅では横スクロールにして、潰れ・はみ出しを防ぐ。
        ScrollView(.horizontal, showsIndicators: false) {
            timelineToolbarContent(timeline: timeline)
        }
    }

    private func timelineToolbarContent(timeline: Timeline) -> some View {
        HStack(spacing: 2) {
            toolbarButton("minus.magnifyingglass", help: "タイムラインを縮小") {
                timelineZoomPercent = max(timelineZoomPercent - 10, 10)
            }
            Slider(value: $timelineZoomPercent, in: 10...800)
                .frame(width: 90)
                .help("タイムラインズーム")
            toolbarButton("plus.magnifyingglass", help: "タイムラインを拡大") {
                timelineZoomPercent = min(timelineZoomPercent + 10, 800)
            }
            Text("\(Int(timelineZoomPercent))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
            toolbarTextButton("全体", help: "タイムライン全体を表示") {
                let fit = Double(canvasViewportWidth)
                    / Double(max(timeline.length, 1)) * 100
                timelineZoomPercent = min(max(fit, 10), 800)
            }

            toolbarDivider

            Menu {
                Button("テキスト") {}
                Button("画像") {}
                Button("動画") {}
                Button("音声") {}
                Button("ボイス") {}
                Button("図形") {}
                Button("シーン") {}
                Button("フレームバッファ") {}
                Button("エフェクト") {}
                Button("グループ") {}
                Button("トランジション") {}
            } label: {
                Label("アイテム追加", systemImage: "plus")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 118)
            .help("アイテムを追加（未接続）")

            toolbarButton("trash", help: "選択アイテムを削除（未接続）") {}

            toolbarDivider

            toolbarTextButton("分割", help: "現在位置で分割（未接続）") {}
            toolbarTextButton("グループ化", help: "グループ化（未接続）") {}
            toolbarTextButton("グループ解除", help: "グループ解除（未接続）") {}

            toolbarDivider

            toolbarTextButton("高さ+", help: "レイヤーの高さを拡大") {
                layerRowHeight = min(layerRowHeight + 4, 64)
            }
            toolbarTextButton("高さ−", help: "レイヤーの高さを縮小") {
                layerRowHeight = max(layerRowHeight - 4, 14)
            }

            toolbarDivider

            toolbarToggleTextButton("波形", help: "波形を表示/非表示", isOn: $showWaveform)

            toolbarDivider

            toolbarTextButton("映像情報", help: "動画の設定") {
                isVideoSettingsPresented = true
            }

            toolbarDivider

            toolbarTextButton("フィードバック", help: "フィードバックを送信（未接続）") {}
        }
        .padding(.horizontal, 6)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 4)
    }

    private func toolbarButton(
        _ systemImage: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func toolbarTextButton(
        _ title: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .font(.callout)
            .help(help)
    }

    /// 状態を持つテキストトグルボタン（ツールバー用）。
    private func toolbarToggleTextButton(
        _ title: String, help: String, isOn: Binding<Bool>
    ) -> some View {
        Button(title) { isOn.wrappedValue.toggle() }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.primary)
            .help(help)
    }

    /// レベルメーター（本家 TimelineView 左端）の形。既定表示は
    /// ピークメーターのみで、ラウドネスメーターは設定で有効化する
    /// （UI-LAYOUT-FACTS.md §16）。脇に dB 数値を出す。
    /// 音声レベルの供給は再生接続フェーズで行うため、現段階は
    /// 目盛りのある枠のみで信号は流れない（台帳参照）。
    private var levelMeters: some View {
        VStack(spacing: 2) {
            meterBar
                .help("ピークメーター")
            Text("-∞ dB")
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var meterBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(0.8))
                ForEach([0.25, 0.5, 0.75], id: \.self) { ratio in
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(height: 1)
                        .offset(y: -geometry.size.height * CGFloat(ratio))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(width: 8)
    }

    // MARK: - ステータスバー

    /// 本家 MainView のステータスバーの並び: 現在時刻 / 総時間、
    /// 現在フレーム / 総フレーム、映像情報、プロジェクト名。
    /// 現在時刻と現在フレームは入力欄で、確定するとシークする
    /// （本家は停止中のみ入力可。ここでは常時入力可とする）。
    private func statusBar(timeline: Timeline) -> some View {
        let info = timeline.videoInfo
        return HStack(spacing: 6) {
            TextField("", text: $statusTimeText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 84)
                .focused($statusFocus, equals: .time)
                .onSubmit { commitStatusTime(timeline: timeline) }
                .help("現在時刻（入力してシーク）")
            Text("/")
            Text(timeText(frame: timeline.length, fps: info.fps))
            statusDivider
            TextField("", text: $statusFrameText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .focused($statusFocus, equals: .frame)
                .onSubmit { commitStatusFrame(timeline: timeline) }
                .help("現在フレーム（入力してシーク）")
            Text("/")
            Text("\(timeline.length)")
            statusDivider
            // 映像情報はボタンで、押すと「動画の設定」が開く（本家どおり）。
            // 本家に無い Hz 表示とアイテム件数は出さない。
            Button("\(info.width)×\(info.height) \(info.fps)FPS") {
                isVideoSettingsPresented = true
            }
            .buttonStyle(.borderless)
            .help("動画の設定")
            statusDivider
            Text(displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.callout)
        .monospacedDigit()
        .padding(.horizontal, 10)
        .frame(height: 22)
        .onAppear { syncStatusTexts(timeline: timeline) }
        .onChange(of: previewFrame) { _, _ in
            // 編集中でないときだけ表示文字列を現在位置へ追随させる。
            if statusFocus == nil {
                syncStatusTexts(timeline: timeline)
            }
        }
    }

    /// ステータスバーの入力欄の表示を現在のプレビュー位置に合わせる。
    private func syncStatusTexts(timeline: Timeline) {
        statusTimeText = timeText(
            frame: Int(previewFrame), fps: timeline.videoInfo.fps
        )
        statusFrameText = "\(Int(previewFrame))"
    }

    private func commitStatusFrame(timeline: Timeline) {
        if let frame = Int(statusFrameText) {
            seek(to: frame, timeline: timeline)
        }
        statusFocus = nil
        syncStatusTexts(timeline: timeline)
    }

    private func commitStatusTime(timeline: Timeline) {
        if let frame = parseTimeText(statusTimeText, fps: timeline.videoInfo.fps) {
            seek(to: frame, timeline: timeline)
        }
        statusFocus = nil
        syncStatusTexts(timeline: timeline)
    }

    /// `hh:mm:ss.ff` / `mm:ss.ff` / 秒数 のいずれかをフレームへ変換する。
    private func parseTimeText(_ text: String, fps: Int) -> Int? {
        let parts = text.split(separator: ":")
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            seconds = seconds * 60 + value
        }
        return Int((seconds * Double(max(fps, 1))).rounded())
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 13)
            .padding(.horizontal, 4)
    }

    /// `hh:mm:ss.ff` 形式（本家のステータスバー・目盛りと同じ書式）。
    private func timeText(frame: Int, fps: Int) -> String {
        let safeFps = max(fps, 1)
        let totalSeconds = Double(frame) / Double(safeFps)
        let whole = Int(totalSeconds)
        let hundredths = Int((totalSeconds - floor(totalSeconds)) * 100)
        return String(
            format: "%02d:%02d:%02d.%02d",
            whole / 3600, (whole % 3600) / 60, whole % 60, hundredths
        )
    }

    /// セッション（ファイル＋タイムライン）が変わったときの初期化。
    /// フレームはタイムラインの現在フレームへ合わせる。
    private func resetPreview() {
        previewBox?.dispose()
        previewBox = nil
        previewImage = nil
        previewError = nil
        guard let timeline else { return }
        previewFrame = Double(timeline.currentFrame)
        // 未保存プロジェクトではセッションキー用に固定の番兵 URL を使う
        // （キーは同一性の判定にだけ使う）。
        let key = PreviewBox.SessionKey(
            url: sourceURL ?? URL(fileURLWithPath: "/untitled-project"),
            timelineIndex: timelineIndex
        )
        guard let box = PreviewBox(
            key: key, timeline: timeline, timelines: project.timelines,
            baseDirectory: baseDirectory
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
            // アイテム0件の空タイムラインで合成結果が得られない場合は
            // エラー表示にせず、プレースホルダ文言に任せる。
            previewError = timeline.items.isEmpty
                ? nil
                : "合成に失敗しました（例外または出力なし）"
        }
    }

    // MARK: - アイテム詳細（右ペイン）

    private func inspectorPane(timeline: Timeline) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("アイテム")
                .font(.headline)
            Divider()
            ScrollView {
                itemDetail(timeline: timeline)
            }
        }
        // 本家の編集ペインの既定幅（DefaultLayout の DockWidth = 400）。
        .frame(width: 400)
        .frame(maxHeight: .infinity)
    }

    /// アイテム詳細。プロパティの編集はメタデータ駆動のインスペクタ
    /// （`PropertyInspectorView`）に委ね、編集が確定するたびに
    /// プレビューを再合成する。アニメーションの評価文脈はプレビューの
    /// 現在フレームに合わせる。
    @ViewBuilder
    private func itemDetail(timeline: Timeline) -> some View {
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
            Text("アイテムが選択されていません")
                .foregroundStyle(.secondary)
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

    // MARK: - 下部タブ（書き出し・診断・往復チェック）

    private func bottomTabs(timeline: Timeline) -> some View {
        TabView {
            ScrollView {
                exportView(timeline: timeline)
            }
            .tabItem { Text("書き出し") }

            ScrollView {
                diagnosticsView
            }
            .tabItem { Text("読み込み診断") }

            roundTripView
                .tabItem { Text("往復チェック") }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 書き出し

    @ViewBuilder
    private func exportView(timeline: Timeline) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("動画出力…") {
                    isExportDialogPresented = true
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
        .padding(8)
    }

    /// 出力先が決まった状態で、バックグラウンドで書き出しを実行する。
    /// 供給側（Metal 合成・音声ミックス）はスレッド安全性を持たないため、
    /// TimelineExporter の構築から実行までを detached タスク内に閉じる。
    private func runExport(timeline: Timeline, outputURL: URL) {
        let cancellation = TimelineExportCancellation()
        exportState.cancellation = cancellation
        exportState.isRunning = true
        exportState.framesDone = 0
        exportState.framesTotal = timeline.length
        exportState.status = "書き出し中（音声解析を含む）…"

        let job = ExportJob(
            timeline: timeline,
            timelines: project.timelines,
            baseDirectory: baseDirectory,
            outputURL: outputURL,
            cancellation: cancellation,
            state: exportState
        )
        Task.detached { job.run() }
    }

    // MARK: - 診断・往復チェック

    private var diagnosticsView: some View {
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
        .padding(8)
    }

    private var roundTripView: some View {
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
        .padding(8)
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
        let destination: URL
        if let sourceURL {
            let directory = sourceURL.deletingLastPathComponent()
            let base = sourceURL.deletingPathExtension().lastPathComponent
            destination = directory.appendingPathComponent(base + ".roundtrip.ymmp")
        } else {
            // 未保存プロジェクトでは保存先を聞く。
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "ymmp") ?? .data]
            panel.nameFieldStringValue = "新規プロジェクト.ymmp"
            guard panel.runModal() == .OK, let url = panel.url else {
                return "保存をキャンセルしました"
            }
            destination = url
        }
        do {
            try YmmpCodec.save(project, toFile: destination.path)
            return "保存しました: \(destination.path)"
        } catch {
            return "保存に失敗: \(error)"
        }
    }
}

/// コントロールポイント表示モード（本家 PreviewView の3択 —
/// UI-STRUCTURE-FACTS.md §3.3）。
enum ControlPointVisibility: CaseIterable {
    case selectedOnly
    case onMouseOver
    case never

    var label: String {
        switch self {
        case .selectedOnly: return "選択中のアイテムのみ"
        case .onMouseOver: return "プレビューにマウスオーバー時"
        case .never: return "常に表示しない"
        }
    }
}

/// ステータスバーの入力欄の識別。
enum StatusField: Hashable {
    case time
    case frame
}
