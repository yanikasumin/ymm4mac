import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YMM4Core
import YMM4GPU


/// プロジェクトのワークスペースを表示するデバッグ画面。
/// 配置は本家 v4.55.1.1 の DefaultLayout（実コード解析:
/// analysis-notes/UI-LAYOUT-FACTS.md §2）: 左カラムは上にプレビュー帯
/// （初期高さ 400、境界スプリッタで可変）＋下にタイムライン（残り全高）、
/// 右カラムはアイテム詳細（編集ペイン幅400・全高）。最下段に本家の
/// 並びのステータスバーを置く。書き出し・読み込み診断・往復チェックの
/// デバッグ帯は製品レイアウトから分離し、ステータスバーの下の
/// 折りたたみ抽斗に置く（Issue #37 / #38）。
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
    /// 表示中ビューポートの最上段レイヤー（本家 GetCurrentLayer() =
    /// Viewport.Top / LayerHeight）。追加・貼り付け・ドロップの
    /// 配置レイヤーは本家では全てこれで決まる。ストリップが報告する。
    @State private var topVisibleLayer: Int = 0
    /// レベルメーターの表示フラグ（本家 YMMSettings の
    /// PeakMeterSettings.IsEnabled / LoudnessMeterSettings.IsEnabled）。
    /// ピークメーターは既定 true、ラウドネスメーターは既定 false
    /// （SoundLevelMeterSettings のフィールド既定と YMMSettings の生成引数）。
    @State private var isPeakMeterEnabled = true
    @State private var isLoudnessMeterEnabled = false
    /// メーター帯へのホバー（本家はホバー時に目盛り数値ラベルを出す）。
    @State private var isMeterHovering = false
    /// プレビュー帯の高さ（本家 DefaultLayout のプレビュー DockHeight。
    /// 初期値 400、下のスプリッタで可変）。
    @State private var previewPaneHeight: CGFloat = 400
    /// スプリッタのドラッグ量の前回値（差分計算用）。
    @State private var splitterLastTranslation: CGFloat = 0
    /// デバッグ帯（書き出し・診断・往復チェック）の展開状態。
    /// 製品レイアウトとは分離し、既定では畳んでおく（Issue #38）。
    @State private var isDebugDrawerExpanded = false
    /// 波形表示モード（本家の TimelineWaveformVisibility:
    /// 常に表示／マウスオーバー時に表示／非表示）。
    @State private var waveformVisibility: WaveformVisibility = .always
    /// タイムラインキャンバスへのホバー（波形のマウスオーバーモード用）。
    @State private var isCanvasHovering = false
    /// 縦グリッド線の表示（本家の VerticalLines.IsEnabled 相当）。
    @State private var showVerticalLines = true
    /// シーン名変更シートの対象（nil で閉じている）。
    @State private var renamingTimelineIndex: Int?
    @State private var renameText = ""

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
                    // 左カラムは本家 DefaultLayout（DefaultLayout.cs）:
                    // 上にプレビュー帯（初期高さ 400、スプリッタで可変）、
                    // 下にタイムライン（残り全高）。右カラムは幅400・全高。
                    // レベルメーターは本家どおりタイムライン領域の左端に立つ。
                    VStack(alignment: .leading, spacing: 0) {
                        // プレビュー帯（映像＋トランスポート行）。
                        VStack(alignment: .leading, spacing: 0) {
                            previewView(timeline: timeline)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            transportBar(timeline: timeline)
                                .frame(height: 24)
                        }
                        .frame(height: previewPaneHeight)

                        // プレビュー帯とタイムラインの境界スプリッタ
                        // （本家はドッキングペインの境界で高さを変える）。
                        previewSplitter

                        HStack(alignment: .top, spacing: 0) {
                            levelMeters
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
                                    showWaveform: effectiveShowWaveform,
                                    showVerticalLines: $showVerticalLines,
                                    reportedCanvasWidth: $canvasViewportWidth,
                                    reportedTopLayer: $topVisibleLayer,
                                    onEdited: { renderPreview() }
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .onHover { isCanvasHovering = $0 }
                                .onDrop(
                                    of: [.fileURL],
                                    delegate: TimelineDropDelegate(
                                        onURLs: { handleDroppedURLs($0, timeline: timeline) }
                                    )
                                )

                                Divider()

                                SerifInputView(
                                    characters: project.characters,
                                    onAdd: { characterName, serif, seeksAfterAdd in
                                        addVoiceItem(
                                            characterName: characterName,
                                            serif: serif,
                                            seeksAfterAdd: seeksAfterAdd,
                                            timeline: timeline
                                        )
                                    }
                                )
                                .frame(minHeight: 26)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxHeight: .infinity)
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
                .onChange(of: workspace.pendingAction?.sequence) { _, _ in
                    if let pending = workspace.pendingAction {
                        executeWorkspaceAction(pending.action, timeline: timeline)
                    }
                }
                .sheet(item: renamingTimelineBinding) { target in
                    renameTimelineSheet(index: target.index)
                }

                Divider()

                statusBar(timeline: timeline)

                Divider()

                // デバッグ帯は製品レイアウトから分離し、ステータスバーの
                // 下に畳める抽斗として置く（Issue #38。既定は畳んだ状態で、
                // 左下に大きな空白を作らない）。
                debugDrawer(timeline: timeline)
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
                .contextMenu {
                    Button("名前を変更…") {
                        renameText = project.timelines[index].name
                        renamingTimelineIndex = index
                    }
                    Divider()
                    Button("シーンを追加") { addTimeline() }
                    Button("シーンを削除") { deleteTimeline(at: index) }
                        .disabled(project.timelines.count <= 1)
                }
            }
            Spacer()
        }
    }

    /// シーン（タイムライン）を末尾へ追加して切り替える。
    private func addTimeline() {
        let newTimeline = Timeline()
        newTimeline.videoInfo = timeline?.videoInfo
            ?? VideoInfo(fps: 60, hz: 48_000, width: 1920, height: 1080)
        newTimeline.name = "シーン \(project.timelines.count + 1)"
        project.timelines.append(newTimeline)
        timelineIndex = project.timelines.count - 1
        selectedItemIndex = nil
        resetPreview()
    }

    /// シーンを削除する（最低1つは残す）。
    private func deleteTimeline(at index: Int) {
        guard project.timelines.count > 1,
              project.timelines.indices.contains(index) else { return }
        project.timelines.remove(at: index)
        if timelineIndex >= project.timelines.count {
            timelineIndex = project.timelines.count - 1
        }
        selectedItemIndex = nil
        resetPreview()
    }

    /// シーン名変更シートの対象（.sheet(item:) 用）。
    private struct RenamingTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private var renamingTimelineBinding: Binding<RenamingTarget?> {
        Binding(
            get: { renamingTimelineIndex.map { RenamingTarget(index: $0) } },
            set: { renamingTimelineIndex = $0?.index }
        )
    }

    private func renameTimelineSheet(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("シーンの名前")
                .font(.headline)
            TextField("シーン名", text: $renameText)
                .frame(width: 260)
                .onSubmit { commitTimelineRename(index: index) }
            HStack {
                Spacer()
                Button(UIStrings.Common.cancel) { renamingTimelineIndex = nil }
                Button("変更") { commitTimelineRename(index: index) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func commitTimelineRename(index: Int) {
        guard project.timelines.indices.contains(index) else { return }
        project.timelines[index].name =
            renameText.trimmingCharacters(in: .whitespaces)
        renamingTimelineIndex = nil
    }

    /// プレビュー帯とタイムラインの境界スプリッタ（高さ6。
    /// ドラッグでプレビュー帯の高さを変える）。
    private var previewSplitter: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.6))
            .frame(height: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        previewPaneHeight = min(
                            max(previewPaneHeight + value.translation.height - splitterLastTranslation, 120),
                            900
                        )
                        splitterLastTranslation = value.translation.height
                    }
                    .onEnded { _ in splitterLastTranslation = 0 }
            )
            .help("プレビューとタイムラインの高さを調整")
    }

    /// 波形の実効表示（モードとキャンバスホバーの合成）。
    private var effectiveShowWaveform: Bool {
        switch waveformVisibility {
        case .always: return true
        case .onMouseOver: return isCanvasHovering
        case .hidden: return false
        }
    }

    /// デバッグ帯の抽斗（書き出し／読み込み診断／往復チェック）。
    /// 製品レイアウトの外（ステータスバーの下）に分離し、既定では
    /// 見出し行だけが見える。
    private func debugDrawer(timeline: Timeline) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isDebugDrawerExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isDebugDrawerExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("デバッグ（書き出し・診断・往復チェック）")
                        .font(.caption)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .frame(height: 20)
            if isDebugDrawerExpanded {
                bottomTabs(timeline: timeline)
                    .frame(height: 150)
            }
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
            }

            Color.clear
                .contentShape(Rectangle())
                .gesture(previewDragGesture(timeline: timeline, scale: scale))

            // 操作ハンドル（本家: 四隅▢ = 拡大率、辺の中点◯ = 回転角）。
            // 移動ジェスチャの層より上に置き、ハンドル上では拡大率／
            // 回転角のドラッグが優先される。
            if let item = selectedItem,
               let bounds = previewItemBounds(item: item, timeline: timeline) {
                selectionHandles(item: item, bounds: bounds, scale: scale, timeline: timeline)
            }
        }
        .coordinateSpace(name: "previewArea")
    }

    /// ハンドルのドラッグ種別（四隅 = 拡大率、辺の中点 = 回転角）。
    private enum HandleKind {
        case zoom
        case rotation
    }

    private struct HandleDragState {
        var kind: HandleKind
        var itemIndex: Int
        /// アイテム中心の表示座標。
        var center: CGPoint
        var startDistance: CGFloat
        var startAngle: Double
        var startZoom: Double
        var startRotation: Double
        var lastWritten: Double
    }

    @State private var handleDrag: HandleDragState?

    /// 選択アイテムの操作ハンドル群（表示は 9px、当たり判定は 18px）。
    private func selectionHandles(
        item: BaseItem, bounds: CGRect, scale: Double, timeline: Timeline
    ) -> some View {
        let scale = CGFloat(scale)
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
                handleView(
                    isCorner: true, item: item, bounds: bounds,
                    point: point, scale: scale, timeline: timeline
                )
            }
            ForEach(Array(edges.enumerated()), id: \.offset) { _, point in
                handleView(
                    isCorner: false, item: item, bounds: bounds,
                    point: point, scale: scale, timeline: timeline
                )
            }
        }
    }

    private func handleView(
        isCorner: Bool, item: BaseItem, bounds: CGRect,
        point: (CGFloat, CGFloat), scale: CGFloat, timeline: Timeline
    ) -> some View {
        let visualSize = 9.0
        let hitSize = 18.0
        return ZStack {
            Color.clear
                .frame(width: hitSize, height: hitSize)
            Group {
                if isCorner {
                    Rectangle()
                        .fill(.white)
                        .overlay(Rectangle().strokeBorder(.gray, lineWidth: 1))
                } else {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(.gray, lineWidth: 1))
                }
            }
            .frame(width: visualSize, height: visualSize)
        }
        .offset(
            x: point.0 * scale - hitSize / 2,
            y: point.1 * scale - hitSize / 2
        )
        .gesture(
            handleDragGesture(
                kind: isCorner ? .zoom : .rotation,
                item: item, bounds: bounds, scale: scale, timeline: timeline
            )
        )
        .help(isCorner ? "拡大率" : "回転角")
    }

    /// ハンドルのドラッグ。四隅は中心からの距離の比で拡大率を、
    /// 辺の中点は中心まわりの角度差で回転角を変える。書き込みは
    /// 移動ドラッグと同じ規則（定数なら定数化、それ以外は先頭値のみ）。
    private func handleDragGesture(
        kind: HandleKind, item: BaseItem, bounds: CGRect,
        scale: CGFloat, timeline: Timeline
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("previewArea"))
            .onChanged { value in
                if handleDrag == nil {
                    guard let index = timeline.items.firstIndex(where: { $0 === item }),
                          let props = item as? VideoItemProperties else { return }
                    let context = animationContext(for: item, timeline: timeline)
                    let center = CGPoint(
                        x: bounds.midX * scale, y: bounds.midY * scale
                    )
                    let dx = value.location.x - center.x
                    let dy = value.location.y - center.y
                    handleDrag = HandleDragState(
                        kind: kind,
                        itemIndex: index,
                        center: center,
                        startDistance: max(hypot(dx, dy), 1),
                        startAngle: atan2(Double(dy), Double(dx)) * 180 / .pi,
                        startZoom: context.value(of: props.zoom),
                        startRotation: context.value(of: props.rotation),
                        lastWritten: kind == .zoom
                            ? context.value(of: props.zoom)
                            : context.value(of: props.rotation)
                    )
                }
                guard let drag = handleDrag,
                      timeline.items.indices.contains(drag.itemIndex) else { return }
                let target = timeline.items[drag.itemIndex]
                let dx = value.location.x - drag.center.x
                let dy = value.location.y - drag.center.y
                var updated = drag
                switch drag.kind {
                case .zoom:
                    let factor = Double(hypot(dx, dy) / drag.startDistance)
                    let newZoom = drag.startZoom * factor
                    guard abs(newZoom - drag.lastWritten) >= 0.5 else { return }
                    writeAnimationProperty(item: target, displayName: "拡大率", value: newZoom)
                    updated.lastWritten = newZoom
                case .rotation:
                    let angle = atan2(Double(dy), Double(dx)) * 180 / .pi
                    var delta = angle - drag.startAngle
                    while delta > 180 { delta -= 360 }
                    while delta < -180 { delta += 360 }
                    let newRotation = drag.startRotation + delta
                    guard abs(newRotation - drag.lastWritten) >= 0.5 else { return }
                    writeAnimationProperty(item: target, displayName: "回転角", value: newRotation)
                    updated.lastWritten = newRotation
                }
                handleDrag = updated
                renderPreview()
            }
            .onEnded { _ in
                handleDrag = nil
            }
    }

    /// アニメーション付きプロパティへの書き込み（表示名で引く）。
    /// ドラッグ移動と同じ規則: 定数なら定数化、それ以外は先頭値のみ。
    private func writeAnimationProperty(item: BaseItem, displayName: String, value: Double) {
        for descriptor in ItemPropertyMetadata.descriptors(for: item)
        where descriptor.kind == .animation && descriptor.displayName == displayName {
            guard let animation = descriptor.animationValue else { continue }
            if animation.animationType == .none {
                descriptor.setAnimationConstantValue(value)
            } else {
                descriptor.setAnimationFirstValue(value)
            }
        }
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
                help: isPlayingForm ? UIStrings.Transport.pause : UIStrings.Transport.play
            ) {
                isPlayingForm.toggle()
            }
            transportButton("stop.fill", help: UIStrings.Transport.stop) {
                isPlayingForm = false
                seek(to: 0, timeline: timeline)
            }

            // 再生速度（本家は幅60のコンボ。x1.0 以外は赤字＋太字）。
            Picker("", selection: $playbackRate) {
                ForEach(Self.playbackRates, id: \.self) { rate in
                    Text("x\(rate, specifier: "%.2g")").tag(rate)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 60)
            .foregroundStyle(playbackRate == 1.0 ? Color.primary : Color.red)
            .fontWeight(playbackRate == 1.0 ? .regular : .bold)
            .help(UIStrings.Transport.playbackRate)

            transportToggle(
                "repeat", help: UIStrings.Transport.repeatPlay, isOn: $isRepeatOn
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
            .help(UIStrings.Transport.controlPointVisibility)

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
            .frame(width: 80)
            .help(UIStrings.Transport.previewZoom)
            transportButton("aspectratio", help: UIStrings.Transport.fit) {
                previewDisplayZoom = 1.0
            }

            transportButton("backward.end.fill", help: UIStrings.Transport.seekToStart) {
                seek(to: 0, timeline: timeline)
            }
            transportButton("chevron.backward.2", help: UIStrings.Transport.seekToPrevEditPoint) {
                seekToPreviousEditPoint(timeline: timeline)
            }
            transportButton("chevron.backward", help: UIStrings.Transport.seekToPrevFrame) {
                seek(to: Int(previewFrame) - 1, timeline: timeline)
            }

            Slider(value: $previewFrame, in: 0...Double(max(timeline.length, 1)), step: 1)
                .onChange(of: previewFrame) { _, _ in renderPreview() }
                .padding(.horizontal, 6)

            transportButton("chevron.forward", help: UIStrings.Transport.seekToNextFrame) {
                seek(to: Int(previewFrame) + 1, timeline: timeline)
            }
            transportButton("chevron.forward.2", help: UIStrings.Transport.seekToNextEditPoint) {
                seekToNextEditPoint(timeline: timeline)
            }
            transportButton("forward.end.fill", help: UIStrings.Transport.seekToEnd) {
                seek(to: timeline.length, timeline: timeline)
            }

            // 右端の並びは本家どおり「ミュート → 音量」。
            // 音量は幅150の TextBoxSlider（スライダ＋数値欄）、
            // 0–100% を F1 表示。
            transportToggle(
                isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                help: UIStrings.Transport.mute, isOn: $isMuted
            )
            Slider(value: $volume, in: 0...100)
                .frame(width: 100)
                .help(UIStrings.Transport.volume)
            Text(isMuted ? "0.0%" : "\(volume, specifier: "%.1f")%")
                .font(.callout)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
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

    // MARK: - 編集アクション（メニュー／ツールバーからの実行）

    /// UI 側の選択（インデックス）を Core の選択へ同期する。
    /// Core の編集操作は `Timeline.selectedItems` を対象にするため、
    /// 操作の直前に必ず通す。
    private func syncSelectionToTimeline(_ timeline: Timeline) {
        if let item = selectedItem {
            timeline.selectItems([item])
        } else {
            timeline.selectItems([])
        }
    }

    /// Core 側の選択を UI 側のインデックス選択へ写し戻す。
    private func reflectCoreSelection(_ timeline: Timeline) {
        if let first = timeline.selectedItems.first,
           let index = timeline.items.firstIndex(where: { $0 === first }) {
            selectedItemIndex = index
        } else {
            selectedItemIndex = nil
        }
    }

    /// メニュー／ツールバーからの編集アクションを実行する。
    /// いずれも Core の既存編集操作への接続であり、構造を変える操作の
    /// 後はプレビューを再合成する。
    private func executeWorkspaceAction(_ action: WorkspaceAction, timeline: Timeline) {
        switch action {
        case .addItem(let kind):
            addItem(kind: kind, timeline: timeline)
        case .splitAtCurrentPosition:
            splitAtPlayhead(timeline: timeline)
        case .deleteSelection:
            guard selectedItem != nil else { return }
            syncSelectionToTimeline(timeline)
            timeline.deleteSelectedAndGroupedItems()
            selectedItemIndex = nil
            renderPreview()
        case .deleteAndMoveAll:
            guard selectedItem != nil else { return }
            syncSelectionToTimeline(timeline)
            _ = timeline.deleteAndMoveAll()
            reflectCoreSelection(timeline)
            renderPreview()
        case .groupSelection:
            guard selectedItem != nil else { return }
            syncSelectionToTimeline(timeline)
            timeline.groupSelectedAndGroupedItems()
            renderPreview()
        case .ungroupSelection:
            guard selectedItem != nil else { return }
            syncSelectionToTimeline(timeline)
            timeline.ungroupSelectedAndGroupedItems()
            renderPreview()
        case .toggleLock:
            selectedItem?.isLocked.toggle()
            renderPreview()
        case .toggleClipping:
            if let visual = selectedItem as? VisualItem {
                visual.isClippingWithObjectAbove.toggle()
            } else if let voice = selectedItem as? VoiceItem {
                voice.isClippingWithObjectAbove.toggle()
            }
            renderPreview()
        case .toggleWaveform:
            waveformVisibility = waveformVisibility == .hidden ? .always : .hidden
        case .selectAll:
            timeline.selectItems(timeline.items)
            selectedItemIndex = timeline.items.isEmpty ? nil : 0
        case .selectLeftItems:
            let frame = Int(previewFrame)
            timeline.selectItems(timeline.items.filter { $0.frame + $0.length <= frame })
            reflectCoreSelection(timeline)
        case .selectRightItems:
            let frame = Int(previewFrame)
            timeline.selectItems(timeline.items.filter { $0.frame >= frame })
            reflectCoreSelection(timeline)
        case .seekToStart:
            seek(to: 0, timeline: timeline)
        case .seekToEnd:
            seek(to: timeline.length, timeline: timeline)
        case .layerHeightUp:
            // 本家 SizeUpLayer: Math.Max(14, LayerHeight + 1)。
            // 増減は ±1、下限 14、上限なし（MainViewModel.cs）。
            layerRowHeight += 1
        case .layerHeightDown:
            layerRowHeight = max(layerRowHeight - 1, 14)
        case .zoomInTimeline:
            // 本家 ZoomInTimeline: ×9/8、上限 4000。
            timelineZoomPercent = min(timelineZoomPercent * 1.125, 4000)
        case .zoomOutTimeline:
            // 本家 ZoomOutTimeline: ×7/8、下限 0.01。
            timelineZoomPercent = max(timelineZoomPercent * 0.875, 0.01)
        case .saveThumbnail(let format):
            saveThumbnail(format: format, timeline: timeline)
        case .resetLayout:
            previewPaneHeight = 400
            timelineZoomPercent = 100
            layerRowHeight = 32
            previewDisplayZoom = 1.0
        }
    }

    /// 再生ヘッド位置で、そこを跨ぐ全アイテムを分割する
    /// （本家 SplitCurrentPosition）。
    private func splitAtPlayhead(timeline: Timeline) {
        let frame = Int(previewFrame)
        let targets = timeline.items.filter {
            $0.frame < frame && frame < $0.frame + $0.length
        }
        guard !targets.isEmpty else { return }
        timeline.splitItems(targets, frame: frame, mode: .both)
        reflectCoreSelection(timeline)
        renderPreview()
    }

    /// 新規アイテムの仮の長さ（1秒分）。本家は素材の長さや生成音声から
    /// 長さを決めるが、デコード／音声供給が未接続の範囲では仮置きする
    /// （台帳に記録。接続時に実長へ差し替える）。
    private func placeholderItemLength(timeline: Timeline) -> Int {
        ItemFactory.placeholderLength(fps: timeline.videoInfo.fps)
    }

    /// アイテム種別から空のアイテムを生成する。
    private func makeItem(kind: AddItemKind) -> BaseItem {
        ItemFactory.makeItem(kind: kind)
    }

    /// アイテムを現在フレーム・表示最上段レイヤーへ追加し、選択する
    /// （配置は本家 GetCurrentLayer() の規則。MainViewModel.cs 4493）。
    private func addItem(kind: AddItemKind, timeline: Timeline) {
        let item = makeItem(kind: kind)
        item.frame = Int(previewFrame)
        item.layer = topVisibleLayer
        item.length = placeholderItemLength(timeline: timeline)
        timeline.addItems([item])
        timeline.refreshTimelineLengthAndMaxLayer()
        if let index = timeline.items.firstIndex(where: { $0 === item }) {
            selectedItemIndex = index
            timeline.selectItems([item])
        }
        renderPreview()
    }

    /// セリフ行からの VoiceItem 生成（本家 AddVoiceItem）。
    /// 本家では長さは生成された音声から決まる。音声供給（Issue #51）が
    /// 未接続のため、長さは仮置き（1秒）で、音声長は 0 のままにする
    /// （接続時に実長へ差し替える。台帳に記録）。
    private func addVoiceItem(
        characterName: String?, serif: String, seeksAfterAdd: Bool,
        timeline: Timeline
    ) {
        let item = VoiceItem()
        item.character = project.characters.first { $0.name == characterName }
        item.characterName = characterName ?? ""
        item.serif = serif
        item.frame = Int(previewFrame)
        item.layer = topVisibleLayer
        item.length = placeholderItemLength(timeline: timeline)
        timeline.addItems([item])
        timeline.refreshTimelineLengthAndMaxLayer()
        if let index = timeline.items.firstIndex(where: { $0 === item }) {
            selectedItemIndex = index
            timeline.selectItems([item])
        }
        if seeksAfterAdd {
            seek(to: item.frame + item.length, timeline: timeline)
        }
        renderPreview()
    }

    /// 現在のプレビュー画像をサムネイルとして保存する
    /// （本家 SaveThumbnail。保存先はダイアログで聞く）。
    private func saveThumbnail(format: ThumbnailFormat, timeline: Timeline) {
        renderPreview()
        guard let previewImage else {
            workspace.statusMessage = "サムネイルを保存できませんでした（プレビュー画像がありません）"
            return
        }
        let panel = NSSavePanel()
        switch format {
        case .png, .pngAlpha:
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "thumbnail.png"
        case .jpeg:
            panel.allowedContentTypes = [.jpeg]
            panel.nameFieldStringValue = "thumbnail.jpg"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let type: CFString = format == .jpeg ? UTType.jpeg.identifier as CFString
            : UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type, 1, nil
        ) else {
            workspace.statusMessage = "サムネイルを保存できませんでした"
            return
        }
        CGImageDestinationAddImage(destination, previewImage, nil)
        if CGImageDestinationFinalize(destination) {
            workspace.statusMessage = "サムネイルを保存しました: \(url.path)"
        } else {
            workspace.statusMessage = "サムネイルを保存できませんでした"
        }
    }

    // MARK: - ファイルのドロップイン

    /// タイムラインへドロップされたファイルを処理する。
    /// 本家の規則（UI-FACTS-DND-AND-PLUGIN-UI.md / MEDIA-IO-FACTS §8）:
    /// .ymmp 単独はプロジェクトを開く。素材ファイルは拡張子で種別を
    /// 分類（判定順は 動画→音声→画像）し、ドロップ位置は使わず
    /// 現在フレーム・表示最上段レイヤー（GetCurrentLayer()）へ追加する。
    private func handleDroppedURLs(_ urls: [URL], timeline: Timeline) {
        if urls.count == 1, urls[0].pathExtension.lowercased() == "ymmp" {
            workspace.load(url: urls[0])
            return
        }
        var added = false
        for url in urls {
            guard let kind = Self.itemKind(forFileExtension: url.pathExtension) else {
                continue
            }
            let item = makeItem(kind: kind)
            item.frame = Int(previewFrame)
            item.layer = topVisibleLayer
            item.length = placeholderItemLength(timeline: timeline)
            switch item {
            case let video as VideoItem: video.filePath = url.path
            case let audio as AudioItem: audio.filePath = url.path
            case let image as ImageItem: image.filePath = url.path
            default: break
            }
            timeline.addItems([item])
            added = true
        }
        if added {
            timeline.refreshTimelineLengthAndMaxLayer()
            renderPreview()
        }
    }

    /// 拡張子からアイテム種別を決める（本家 FileExtensions の既定分類。
    /// 判定順は 動画→音声→画像。字幕ファイルの分離処理は未実装）。
    private static func itemKind(forFileExtension ext: String) -> AddItemKind? {
        let ext = ext.lowercased()
        let videoExtensions: Set<String> = [
            "mp4", "avi", "wmv", "3g2", "3gp", "3gp2", "3gpp", "m4v", "mov",
            "qt", "m2ts", "m2t", "mts", "ts", "mkv", "mpg", "mpeg", "webm",
            "gif", "webp",
        ]
        if videoExtensions.contains(ext) { return .video }
        let audioOnlyExtensions: Set<String> = [
            "mp3", "wav", "wma", "m4a", "mka", "aac", "adts", "flac", "ogg",
            "mid", "midi",
        ]
        if audioOnlyExtensions.contains(ext) { return .audio }
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "jpe", "jfif", "bmp", "dib", "ico", "tiff",
            "tif", "hdp", "dds", "dng", "heic", "heif", "hif", "avif", "jxr",
            "wdp", "psd", "psb", "svg",
        ]
        if imageExtensions.contains(ext) { return .image }
        return nil
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
        // 本家のツールバートレイは5本（ズーム／アイテム／編集／
        // プロジェクト／フィードバック）。ボタンはアイコンのみで、
        // ツールチップは「コマンド名＋ショートカット」
        // （Command.TextWithShortcut）。根拠:
        // UI-FACTS-MENUS-CONTEXT.md §3。
        HStack(spacing: 2) {
            zoomToolbar(timeline: timeline)
            toolbarDivider
            itemToolbar(timeline: timeline)
            toolbarDivider
            editToolbar(timeline: timeline)
            toolbarDivider
            projectToolbar(timeline: timeline)
            toolbarDivider
            feedbackToolbar
        }
        .padding(.horizontal, 6)
    }

    // MARK: ツールバー: ズーム（本家は虫眼鏡＋対数スライダ1つ）

    private func zoomToolbar(timeline: Timeline) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "magnifyingglass")
                .frame(width: 18, height: 22)
                .foregroundStyle(.secondary)
            // 本家 TextBoxSlider（TimelineView.xaml 572）: 全幅120、
            // 数値欄41、スライダ範囲 0.1–150 の対数スケール。
            // 変換は TimelineLogScaleConverter の式そのもの:
            //   slider = log10(zoom × 10) × 100 / 3
            //   zoom   = 10^(slider / 100 × 3) / 10
            // 数値欄の表示はスライダ空間（単位なし。zoom 100% で 100）。
            Slider(value: zoomSliderBinding, in: 0.1...150)
                .frame(width: 71)
                .help(UIStrings.Toolbar.tip(UIStrings.Toolbar.zoomSlider))
            Text("\(Int(zoomSliderValue.rounded()))")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 41, alignment: .trailing)
            // 全体フィットは本家のズームツールバーには無い独自ボタン。
            toolbarButton("arrow.up.left.and.arrow.down.right", help: UIStrings.Toolbar.fitAll) {
                let fit = Double(canvasViewportWidth)
                    / Double(max(timeline.length, 1)) * 100
                timelineZoomPercent = min(max(fit, 0.01), 4000)
            }
        }
    }

    /// ズームスライダの表示値（対数スケール空間。0.1–150 に丸める）。
    private var zoomSliderValue: Double {
        min(max(log10(timelineZoomPercent * 10) * 100 / 3, 0.1), 150)
    }

    private var zoomSliderBinding: Binding<Double> {
        Binding(
            get: { zoomSliderValue },
            set: { newValue in
                timelineZoomPercent = pow(10, newValue / 100 * 3) / 10
            }
        )
    }

    // MARK: ツールバー: アイテム（追加13種＋テンプレート＋最近使ったファイル）

    private func itemToolbar(timeline: Timeline) -> some View {
        HStack(spacing: 2) {
            ForEach(AddItemKind.allCases, id: \.self) { kind in
                toolbarButton(
                    kind.systemImage,
                    help: UIStrings.Toolbar.tip(kind.displayName)
                ) {
                    addItem(kind: kind, timeline: timeline)
                }
            }
            // テンプレート／最近使ったファイルのドロップダウン。
            // テンプレートの保持先が無いため中身は空表示のみ。
            Menu {
                Text(UIStrings.Menu.noHistory)
            } label: {
                Image(systemName: "book")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help(UIStrings.Toolbar.tip(UIStrings.Toolbar.templateMenu))
            Menu {
                Text(UIStrings.Menu.noHistory)
            } label: {
                Image(systemName: "clock")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help(UIStrings.Toolbar.tip(UIStrings.Toolbar.recentFiles))
        }
    }

    // MARK: ツールバー: 編集

    private func editToolbar(timeline: Timeline) -> some View {
        HStack(spacing: 2) {
            // Undo/Redo は Core に履歴基盤が無いため未接続（無効表示）。
            toolbarButton("arrow.uturn.backward", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.undo, shortcut: UIStrings.Toolbar.shortcutUndo)) {}
                .disabled(true)
            toolbarButton("arrow.uturn.forward", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.redo, shortcut: UIStrings.Toolbar.shortcutRedo)) {}
                .disabled(true)
            toolbarDivider
            // 切り取り／コピー／貼り付けはアイテム用クリップボードが
            // 無いため未接続（無効表示）。
            toolbarButton("scissors", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.cut, shortcut: UIStrings.Toolbar.shortcutCut)) {}
                .disabled(true)
            toolbarButton("doc.on.doc", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.copy, shortcut: UIStrings.Toolbar.shortcutCopy)) {}
                .disabled(true)
            toolbarButton("doc.on.clipboard", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.paste, shortcut: UIStrings.Toolbar.shortcutPaste)) {}
                .disabled(true)
            toolbarButton("square.split.1x2", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.split, shortcut: UIStrings.Toolbar.shortcutSplit)) {
                splitAtPlayhead(timeline: timeline)
            }
            toolbarDivider
            // グループ化／グループ解除は本家ではトグル対（一方のみ表示）。
            if let item = selectedItem, item.group != 0 {
                toolbarButton("square.stack.3d.up.slash", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.ungroup)) {
                    executeWorkspaceAction(.ungroupSelection, timeline: timeline)
                }
            } else {
                toolbarButton("square.stack.3d.up", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.group)) {
                    executeWorkspaceAction(.groupSelection, timeline: timeline)
                }
            }
            // クリッピング／ロックも本家ではトグル対。
            if isSelectedItemClipping {
                toolbarButton("square.dashed.inset.filled", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.clippingOff)) {
                    executeWorkspaceAction(.toggleClipping, timeline: timeline)
                }
            } else {
                toolbarButton("square.dashed", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.clippingOn)) {
                    executeWorkspaceAction(.toggleClipping, timeline: timeline)
                }
            }
            if selectedItem?.isLocked == true {
                toolbarButton("lock.open", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.unlock)) {
                    executeWorkspaceAction(.toggleLock, timeline: timeline)
                }
            } else {
                toolbarButton("lock", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.lock)) {
                    executeWorkspaceAction(.toggleLock, timeline: timeline)
                }
            }
            waveformSplitButton
            gridSplitButton
            meterMenuButton
            toolbarDivider
            toolbarButton("trash", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.delete, shortcut: UIStrings.Toolbar.shortcutDelete)) {
                executeWorkspaceAction(.deleteSelection, timeline: timeline)
            }
            toolbarButton("trash.slash", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.deleteAndMove)) {
                executeWorkspaceAction(.deleteAndMoveAll, timeline: timeline)
            }
            toolbarDivider
            toolbarButton("arrow.left.to.line", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.selectLeft)) {
                executeWorkspaceAction(.selectLeftItems, timeline: timeline)
            }
            toolbarButton("arrow.right.to.line", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.selectRight)) {
                executeWorkspaceAction(.selectRightItems, timeline: timeline)
            }
            toolbarButton("selection.pin.in.out", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.selectAll, shortcut: UIStrings.Toolbar.shortcutSelectAll)) {
                executeWorkspaceAction(.selectAll, timeline: timeline)
            }
        }
    }

    /// 選択中アイテムのクリッピング状態（トグル対の表示切替用）。
    private var isSelectedItemClipping: Bool {
        if let visual = selectedItem as? VisualItem {
            return visual.isClippingWithObjectAbove
        }
        if let voice = selectedItem as? VoiceItem {
            return voice.isClippingWithObjectAbove
        }
        return false
    }

    /// 波形 SplitButton（本体 = 表示/非表示の切替、ドロップダウン =
    /// 3モードのラジオ。本家 §3.6(a)）。
    private var waveformSplitButton: some View {
        HStack(spacing: 0) {
            toolbarButton(
                waveformVisibility == .hidden ? "waveform.slash" : "waveform",
                help: UIStrings.Toolbar.tip(UIStrings.Toolbar.waveform)
            ) {
                waveformVisibility = waveformVisibility == .hidden ? .always : .hidden
            }
            Menu {
                waveformModeButton(.always, name: UIStrings.Toolbar.waveformAlways)
                waveformModeButton(.onMouseOver, name: UIStrings.Toolbar.waveformOnMouseOver)
                waveformModeButton(.hidden, name: UIStrings.Toolbar.waveformHidden)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .frame(width: 10, height: 22)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 10)
        }
    }

    private func waveformModeButton(
        _ mode: WaveformVisibility, name: String
    ) -> some View {
        Button {
            waveformVisibility = mode
        } label: {
            if waveformVisibility == mode {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }

    /// グリッド線 SplitButton（本体 = 表示切替、ドロップダウン =
    /// 切替＋設定。本家 §3.6(b)。設定画面は未実装のため無効表示）。
    private var gridSplitButton: some View {
        HStack(spacing: 0) {
            toolbarButton(
                "square.grid.3x3",
                help: UIStrings.Toolbar.tip(UIStrings.Toolbar.gridLine)
            ) {
                showVerticalLines.toggle()
            }
            Menu {
                Button {
                    showVerticalLines.toggle()
                } label: {
                    if showVerticalLines {
                        Label(UIStrings.Toolbar.gridLine, systemImage: "checkmark")
                    } else {
                        Text(UIStrings.Toolbar.gridLine)
                    }
                }
                Button(UIStrings.Toolbar.gridLineSettings) {}
                    .disabled(true)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .frame(width: 10, height: 22)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 10)
        }
    }

    /// メーター表示のドロップダウン（本家 §3.6(c)）。
    private var meterMenuButton: some View {
        Menu {
            Toggle(UIStrings.Toolbar.peakMeter, isOn: $isPeakMeterEnabled)
            Toggle(UIStrings.Toolbar.loudnessMeter, isOn: $isLoudnessMeterEnabled)
        } label: {
            Image(systemName: "gauge.with.needle")
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 22)
        .help(UIStrings.Toolbar.tip(UIStrings.Toolbar.meters))
    }

    // MARK: ツールバー: プロジェクト

    private func projectToolbar(timeline: Timeline) -> some View {
        HStack(spacing: 2) {
            toolbarButton("doc.badge.plus", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.newProject, shortcut: UIStrings.Toolbar.shortcutNew)) {
                workspace.newProject()
            }
            toolbarButton("folder", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.openProject, shortcut: UIStrings.Toolbar.shortcutOpen)) {
                workspace.isImporterPresented = true
            }
            toolbarButton("square.and.arrow.down", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.saveProject, shortcut: UIStrings.Toolbar.shortcutSave)) {
                workspace.saveCopy()
            }
            toolbarDivider
            toolbarButton("tuningfork", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.videoInfo)) {
                isVideoSettingsPresented = true
            }
            toolbarDivider
            toolbarButton("film", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.outputExo)) {}
                .disabled(true)
            toolbarButton("play.rectangle", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.outputVideo)) {
                isExportDialogPresented = true
            }
            toolbarDivider
            // サムネイル保存 SplitButton（本体 = PNG 保存、
            // ドロップダウン = 形式選択。本家 §3.6(d)(e)）。
            HStack(spacing: 0) {
                toolbarButton("camera", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.saveThumbnail)) {
                    saveThumbnail(format: .png, timeline: timeline)
                }
                Menu {
                    Button(UIStrings.Toolbar.saveThumbnailPng) {
                        saveThumbnail(format: .png, timeline: timeline)
                    }
                    Button(UIStrings.Toolbar.saveThumbnailPngAlpha) {
                        saveThumbnail(format: .pngAlpha, timeline: timeline)
                    }
                    Button(UIStrings.Toolbar.saveThumbnailJpeg) {
                        saveThumbnail(format: .jpeg, timeline: timeline)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .frame(width: 10, height: 22)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 10)
            }
        }
    }

    // MARK: ツールバー: フィードバック（本家はアイコン＋文言の1ボタン）

    private var feedbackToolbar: some View {
        Button {
            // フィードバック送信ウィンドウは未実装。押下したことが
            // 分かるようステータスへ未接続を出す。
            workspace.statusMessage =
                "フィードバック送信は未接続です（問い合わせはヘルプメニューから開けます）"
        } label: {
            Label(UIStrings.Toolbar.feedback, systemImage: "exclamationmark.bubble")
                .font(.callout)
        }
        .buttonStyle(.borderless)
        .help(UIStrings.Toolbar.tip(UIStrings.Toolbar.feedback))
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

    // MARK: - レベルメーター

    /// レベルメーターの色帯（dB 区間）。本家 SoundLevelMeterSettings の
    /// 帯定義（start が上端、end が下端）。
    private struct MeterZones {
        var redStart: Double
        var redEnd: Double
        var yellowStart: Double
        var yellowEnd: Double
        var greenStart: Double
        var greenEnd: Double
    }

    /// 本家 VerticalLevelMeter の帯色（VerticalLevelMeter.xaml のリソース）。
    private static let meterRed = SwiftUI.Color(red: 0xD5 / 255, green: 0, blue: 0)
    private static let meterYellow = SwiftUI.Color(red: 1, green: 0xC4 / 255, blue: 0)
    private static let meterGreen = SwiftUI.Color(
        red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)
    private static let meterGray = SwiftUI.Color(
        red: 0x54 / 255, green: 0x6E / 255, blue: 0x7A / 255)

    /// ピークメーターの帯（SoundLevelMeterSettings 引数なし生成時の既定）。
    private static let peakMeterZones = MeterZones(
        redStart: 0, redEnd: -3, yellowStart: -3, yellowEnd: -35,
        greenStart: -5, greenEnd: -15)
    /// ラウドネスメーターの帯（YMMSettings の LoudnessMeterSettings 生成引数）。
    private static let loudnessMeterZones = MeterZones(
        redStart: 0, redEnd: -12, yellowStart: -12, yellowEnd: -45,
        greenStart: -14, greenEnd: -25)

    /// レベルメーター帯（本家 TimelineView 左端）の形。構成は本家コードで
    /// 確定（REVIEW-DISPOSITION-MAC0028-FRONTEND UI32-01）:
    /// ピークメーター（コード側呼称はサウンドレベルメーター）は
    /// L/R ステレオ対の縦バー2本で、既定で表示される。
    /// ラウドネスメーターは BS.1770 単一値の1本で、既定は無効、
    /// 有効化したときだけ左側へ追加される。
    /// 表示の切り替えは本家どおりコンテキストメニューから行う
    /// （TimelineView.xaml の TogglePeakMeterVisibility /
    /// ToggleLoudnessMeterVisibility）。
    /// 音声レベルの供給は再生接続フェーズで行うため、現段階の値は
    /// 無信号（下限 −60 dB）で固定（台帳参照）。
    private var levelMeters: some View {
        HStack(alignment: .top, spacing: 0) {
            if isLoudnessMeterEnabled {
                meterColumn(
                    unitLabel: "LKFS",
                    zones: Self.loudnessMeterZones,
                    barCount: 1,
                    barWidth: 20,
                    helpText: "ラウドネスメーター（-∞ LUFS）")
            }
            if isPeakMeterEnabled {
                meterColumn(
                    unitLabel: "dB",
                    zones: Self.peakMeterZones,
                    barCount: 2,
                    barWidth: 10,
                    helpText: "ピークメーター（L: -∞ dB / R: -∞ dB）")
            }
        }
        .onHover { isMeterHovering = $0 }
        .contextMenu {
            Toggle(UIStrings.Toolbar.peakMeter, isOn: $isPeakMeterEnabled)
            Toggle(UIStrings.Toolbar.loudnessMeter, isOn: $isLoudnessMeterEnabled)
        }
    }

    /// メーター1カラム分。バーの上に目盛りの刻みを重ね、右上に単位表記、
    /// ホバー時に目盛り数値（−5…−60）を重ねる（本家 TimelineView の
    /// 各メーターグリッドの構造）。
    private func meterColumn(
        unitLabel: String, zones: MeterZones, barCount: Int,
        barWidth: CGFloat, helpText: String
    ) -> some View {
        let columnWidth = barWidth * CGFloat(barCount)
        return ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(0..<barCount, id: \.self) { _ in
                    levelMeterBar(zones: zones)
                        .frame(width: barWidth)
                }
            }
            meterTicks
            Text(unitLabel)
                .font(.system(size: 10))
                .frame(maxWidth: .infinity, alignment: .trailing)
            if isMeterHovering {
                meterScaleLabels
            }
        }
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity)
        .help(helpText)
    }

    /// 目盛りの刻み（5 dB ごと。本家の UniformGrid の刻み相当）。
    private var meterTicks: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(1...12, id: \.self) { step in
                    Rectangle()
                        .fill(SwiftUI.Color.primary.opacity(0.5))
                        .frame(width: 2, height: 1)
                        .offset(
                            y: geometry.size.height * CGFloat(step) / 12 - 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 目盛り数値 −5…−60（本家はホバー時または常時表示設定で出す）。
    private var meterScaleLabels: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(1...12, id: \.self) { step in
                    Text("-\(step * 5)")
                        .font(.system(size: 9))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(
                            y: geometry.size.height * CGFloat(step) / 12 - 11)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// VerticalLevelMeter 1本分。範囲は 0 dB（上端）〜 −60 dB（下端）の
    /// 線形。背景は色帯を不透明度0.2で常時表示し、Peak バーは
    /// 不透明度0.6で下から Peak 位置まで同じ色帯を重ねる。
    /// Average（RMS）は黒線、PeakHold はその値が属する帯の色の線
    /// （本家 VerticalLevelMeter.xaml）。
    /// 現段階は無信号のため peak / average / peakHold は下限で固定。
    private func levelMeterBar(
        zones: MeterZones, peak: Double = -60, average: Double = -60,
        peakHold: Double = -60
    ) -> some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                // 背景の色帯（不透明度0.2）
                meterBand(color: Self.meterGray, start: 0, end: -60, height: height)
                meterBand(
                    color: Self.meterRed, start: zones.redStart,
                    end: zones.redEnd, height: height)
                meterBand(
                    color: Self.meterYellow, start: zones.yellowStart,
                    end: zones.yellowEnd, height: height)
                meterBand(
                    color: Self.meterGreen, start: zones.greenStart,
                    end: zones.greenEnd, height: height)
            }
            .opacity(0.2)
            ZStack(alignment: .topLeading) {
                // Peak バー（帯の上端を peak でクランプ）
                meterBand(color: Self.meterGray, start: peak, end: -60, height: height)
                meterBand(
                    color: Self.meterRed, start: min(zones.redStart, peak),
                    end: zones.redEnd, height: height)
                meterBand(
                    color: Self.meterYellow, start: min(zones.yellowStart, peak),
                    end: zones.yellowEnd, height: height)
                meterBand(
                    color: Self.meterGreen, start: min(zones.greenStart, peak),
                    end: zones.greenEnd, height: height)
            }
            .opacity(0.6)
            if peak > 0 {
                // 0 dB 超過時は全面を赤で重ねる（本家の超過表示）。
                Rectangle()
                    .fill(Self.meterRed)
                    .opacity(0.8)
            }
            // Average（RMS）の黒線
            Rectangle()
                .fill(SwiftUI.Color.black)
                .frame(height: 2)
                .opacity(0.7)
                .offset(y: -average / 60 * height)
            // PeakHold の線（値が属する帯の色）
            Rectangle()
                .fill(meterZoneColor(zones: zones, value: peakHold))
                .frame(height: 2)
                .offset(y: -peakHold / 60 * height)
        }
        .clipped()
    }

    /// dB 区間 [end, start] の帯。start が上端（0 dB が y=0）。
    private func meterBand(
        color: SwiftUI.Color, start: Double, end: Double, height: CGFloat
    ) -> some View {
        let bandHeight = height * CGFloat(start - end) / 60
        return Rectangle()
            .fill(color)
            .frame(height: max(bandHeight, 0))
            .offset(y: -start / 60 * height)
    }

    /// 値が属する帯の色（描画順で上に来る帯を優先する）。
    private func meterZoneColor(zones: MeterZones, value: Double) -> SwiftUI.Color {
        if value <= zones.greenStart && value >= zones.greenEnd {
            return Self.meterGreen
        }
        if value <= zones.yellowStart && value >= zones.yellowEnd {
            return Self.meterYellow
        }
        if value <= zones.redStart && value >= zones.redEnd {
            return Self.meterRed
        }
        return Self.meterGray
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
                .help(UIStrings.StatusBar.currentTime)
            Text("/")
            Text(timeText(frame: timeline.length, fps: info.fps))
            statusDivider
            TextField("", text: $statusFrameText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .focused($statusFocus, equals: .frame)
                .onSubmit { commitStatusFrame(timeline: timeline) }
                .help(UIStrings.StatusBar.currentFrame)
            Text("/")
            Text("\(timeline.length)")
            statusDivider
            // 映像情報はボタンで、押すと「動画の設定」が開く（本家どおり）。
            // 本家に無い Hz 表示とアイテム件数は出さない。
            Button("\(info.width)×\(info.height) \(info.fps)FPS") {
                isVideoSettingsPresented = true
            }
            .buttonStyle(.borderless)
            .help(UIStrings.StatusBar.videoSettings)
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
        let box = PreviewBox(
            key: key, timeline: timeline, timelines: project.timelines,
            baseDirectory: baseDirectory
        )
        previewBox = box
        if let failure = box.initializationFailure {
            // 初期化失敗の理由をそのまま表示する（Issue #50）。
            previewError = failure
            return
        }
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
            Text(UIStrings.Inspector.item)
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
            Text(UIStrings.Inspector.noSelection)
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
    /// ジョブへ渡すモデルは開始時点のスナップショット（コーデック往復に
    /// よる専有複製）であり、書き出し中の編集とは競合しない（AUD-07）。
    /// スナップショットを作れない場合は、編集中のモデルを共有する形へ
    /// フォールバックせず、書き出し自体を中止する。
    private func runExport(timeline: Timeline, outputURL: URL) {
        let snapshot: (timelines: [Timeline], timeline: Timeline)
        do {
            snapshot = try project.makeExportSnapshot(of: timeline)
        } catch {
            exportState.status = "書き出しを開始できませんでした: \(error)"
            return
        }

        let cancellation = TimelineExportCancellation()
        exportState.cancellation = cancellation
        exportState.isRunning = true
        exportState.framesDone = 0
        exportState.framesTotal = snapshot.timeline.length
        exportState.status = "書き出し中（音声解析を含む）…"

        let job = ExportJob(
            timeline: snapshot.timeline,
            timelines: snapshot.timelines,
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

/// 波形表示モード（本家 YMMSettings.TimelineWaveformVisibility）。
enum WaveformVisibility {
    case always
    case onMouseOver
    case hidden
}

/// タイムラインへのファイルドロップの受け口。ドロップされた
/// ファイル URL を集めてコールバックへ渡す。
struct TimelineDropDelegate: DropDelegate {
    let onURLs: ([URL]) -> Void

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let collector = URLCollector()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                switch item {
                case let data as Data:
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        collector.append(url)
                    }
                case let url as URL:
                    collector.append(url)
                default:
                    break
                }
            }
        }
        group.notify(queue: .main) {
            let urls = collector.snapshot()
            if !urls.isEmpty {
                onURLs(urls)
            }
        }
        return true
    }
}

/// ドロップされた URL を並行コールバックから集める箱。
private final class URLCollector: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}
