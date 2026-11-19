import AppKit
import PreviewCore
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
    /// ファイル差し替えの非同期適用の世代（アイテムごと）。
    /// 古い取得結果が新しい変更を上書きしないための照合用（FE-R1-043）。
    @State private var fileChangeGenerations: [ObjectIdentifier: Int] = [:]
    /// Undo/Redo を適用するたびに増える版数。インスペクタの行は
    /// 入力途中の状態を持つため、履歴の適用後は作り直してモデルへ
    /// 追随させる（FE-UNDO-WIRING）。
    @State private var historyApplyRevision = 0
    /// タイムライン帯の再評価の契機（Undo/Redo 適用時）。帯はモデルを
    /// 直接読むため、版数を渡して body の再評価を促す。
    @State private var timelineDisplayRevision = 0
    /// タイムラインドラッグについて、この接続側が所有するセッション
    /// のトークン（監査 Round 10 の接続条件＋FE-R20-126-03）。開始して
    /// いないセッション（背景・範囲選択）の終了通知では Undo 処理を
    /// しない。
    @State private var dragUndoToken: EditSessionToken?
    /// ドラッグ開始時点のタイムライン写し（Undo 記録用）。
    @State private var dragUndoSnapshot: TimelineEditSnapshot?
    @State private var roundTripResult: String?
    @State private var saveResult: String?
    @State private var previewFrame: Double = 0
    @State private var previewImage: CGImage?
    @State private var previewError: String?
    /// プレビュー描画ワーカー（R6-02）。合成は専用キューで行い、
    /// 描画モデルは編集モデルから独立したスナップショットを使う。
    @State private var previewWorker = PreviewRenderWorker()
    /// ワーカーへ渡したモデルの版数。採番はここ（呼び出し側）で
    /// 一元的に行い、ワーカーは受け取った識別子をそのまま返す
    /// （第11ラウンド R11-04）。ビューの生存期間中は単調増加。
    @State private var previewModelVersion = 0
    /// セッションの世代。再初期化のたびに増やし、同じファイル＋
    /// タイムラインの再初期化でも旧セッションの結果と区別する
    /// （R11-04）。
    @State private var previewSessionGeneration = 0
    /// 現在のプレビューセッションキー（完成画像の新旧判定に使う）。
    @State private var previewSessionKey: PreviewBox.SessionKey?
    /// 編集が入ってスナップショットの作り直しが必要な状態か。
    @State private var previewModelDirty = true
    /// 直近のスナップショット生成時刻（連続編集時の間引き用）。
    @State private var lastPreviewSnapshotAt = Date.distantPast
    /// 間引き・失敗時の遅延確定はこの 1 件に集約する（R11-06）。
    /// セッション切替時に取り消す。
    @State private var pendingModelRefreshItem: DispatchWorkItem?
    /// 現在表示中の画像の識別子とフレーム（サムネイル保存が現在
    /// 位置・現在モデルの画像かを確認するために使う。R11-08）。
    @State private var displayedPreviewIdentity: PreviewRenderWorker.Identity?
    @State private var displayedPreviewFrame: Int?
    /// 対応画像の完成を待っているサムネイル保存。形式とフレームを
    /// 持ち、対象は「現在のモデルでそのフレームが完成した時点」に
    /// 結び直す。要求時点の識別子へ固定すると、モデルの作り直し
    /// 保留中に旧モデルの完成通知で旧画像を保存したり、作り直しで
    /// 要求自体が消えたりする（R12-06 の取消し規則を、モデル変更
    /// 時は結び直しへ改めたもの。R20-113-01）。
    @State private var pendingThumbnail: (
        format: ThumbnailFormat,
        frame: Int
    )?
    /// 直近の描画で効果の失敗があったか（R6-06 の現在の失敗状態）。
    /// 正常な描画が完了すると解消する。
    @State private var previewCurrentFailure = false
    /// 描画セッション中に発生した失敗の集約履歴（R6-06）。正常な
    /// 描画では消えず、セッションの作り直しでリセットする。
    @State private var previewDiagnostics: [RenderDiagnosticsCollector.Entry] = []
    /// プレビュー上でのドラッグ移動の作業状態（開始時点の評価値と
    /// 開始点を保持し、移動量は常に開始時点からの差分で書き込む）。
    @State private var previewDrag: PreviewDragState?
    @StateObject private var exportState = ExportUIState()

    // MARK: トランスポートの状態（実時間再生エンジンと同期）
    /// 実時間再生エンジン（Issue #52 で実接続）。セッションごとに
    /// resetPreview で作り直す。
    @State private var playbackEngine: RealtimePlaybackEngine?
    /// 再生ボタンの表示状態（再生中かどうか）。
    /// エンジンの状態変化通知で駆動する。
    @State private var isPlayingForm = false
    /// 直近の再生開始失敗の理由文（エンジンの開始失敗通知で駆動し、
    /// 診断タブに表示する。R6-03）。
    @State private var playbackError: String?
    /// 再生速度（倍率）。本家の速度コンボの選択値。
    @State private var playbackRate: Double = 1.0
    /// リピート再生トグル。
    @State private var isRepeatOn = false
    /// コントロールポイント表示モード（本家の3択）。
    @State private var controlPointVisibility: ControlPointVisibility = .selectedOnly
    /// プレビュー領域へのマウスホバー（「マウスオーバー時」モードの
    /// 表示条件。本家 isMouseOverPreviewArea に対応）。
    @State private var isPreviewHovering = false
    /// プレビュー表示倍率（フィット倍率への乗数。1.0 = フィット）。
    @State private var previewDisplayZoom: Double = 1.0
    /// 音量（0–100%）とミュート。エンジンへ即時反映される。
    @State private var volume: Double = 100
    @State private var isMuted = false
    /// レベルメーターの表示値（エンジンのポーリング通知で取り込む）。
    /// 無信号は本家どおり下限 −60 dB。
    @State private var peakMeterLeft: LevelMeterValue = .silent
    @State private var peakMeterRight: LevelMeterValue = .silent
    @State private var loudnessMeterValue: LevelMeterValue = .silent
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
        // 本家 OpenProjectAsync と同じく、保存済みインデックスは
        // 範囲内へ丸めてから初期値にする。
        _timelineIndex = State(initialValue: min(
            max(project.selectedTimelineIndex, 0),
            max(project.timelines.count - 1, 0)
        ))
        // 前回終了時のレイアウトを初期値へ反映する（FE-R1-036）。
        let layout = WorkspaceLayoutState.load()
        _previewPaneHeight = State(initialValue: layout.previewPaneHeight)
        _timelineZoomPercent = State(initialValue: layout.timelineZoomPercent)
        _layerRowHeight = State(initialValue: layout.layerRowHeight)
        _previewDisplayZoom = State(initialValue: layout.previewDisplayZoom)
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
                                    onEdited: { requestPreviewRender(modelChanged: true) },
                                    onUnrecordedEdit: { workspace.markEdited() },
                                    onDragBegan: {
                                        beginTimelineDragUndo(timeline: timeline)
                                    },
                                    onDragCommitted: {
                                        commitTimelineDragUndo(timeline: timeline)
                                    },
                                    onDragCancelled: {
                                        cancelTimelineDragUndo()
                                    },
                                    editRecorder: workspace.editRecorder,
                                    displayRevision: timelineDisplayRevision
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
                    VideoSettingsView(timeline: timeline) {
                        // 動画情報の書き込みはモデル変更（OK で適用した
                        // 時点で確定する）ため未保存フラグも立てる。
                        workspace.markEdited()
                        resetPreview()
                    }
                }
                .sheet(isPresented: $isExportDialogPresented) {
                    ExportDialogView(
                        timeline: timeline,
                        // 接頭辞の初期値は「今開いているファイル」の名前。
                        // project.filePath は .ymmp 内に保存された値で、
                        // 開いたファイルと一致するとは限らない（R10-02）。
                        defaultPngWavFileName: sourceURL?
                            .deletingPathExtension().lastPathComponent ?? "untitled",
                        isExportRunning: exportState.isRunning
                    ) { request in
                        runExport(timeline: timeline, request: request)
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
        .onChange(of: timelineIndex) { _, newIndex in
            // 保存対象の選択シーンを表示へ追随させる（FE-R1-012）。
            // 本家は保存時点の表示シーンから SelectedTimelineIndex を
            // 作る（MainModel.SaveProject）。Mac 側はモデル側の値を
            // 切替のたびに同期しておくことで同じ結果にする。
            // シーン切替そのものは本家でも未保存扱いにならない
            // （SelectScene は履歴へ記録されない）ため、編集フラグは
            // ここでは立てない。
            project.selectedTimelineIndex = newIndex
        }
        // レイアウト量が変わるたびにアプリ設定へ残す（FE-R1-036。
        // 次回起動・次にプロジェクトを開いた際の初期値になる）。
        .onChange(of: previewPaneHeight) { _, _ in persistLayout() }
        .onChange(of: timelineZoomPercent) { _, _ in persistLayout() }
        .onChange(of: layerRowHeight) { _, _ in persistLayout() }
        .onChange(of: previewDisplayZoom) { _, _ in persistLayout() }
    }

    /// 現在のレイアウト量をアプリ設定へ保存する（FE-R1-036）。
    private func persistLayout() {
        WorkspaceLayoutState(
            previewPaneHeight: previewPaneHeight,
            timelineZoomPercent: timelineZoomPercent,
            layerRowHeight: layerRowHeight,
            previewDisplayZoom: previewDisplayZoom
        ).save()
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
        workspace.markEdited()
        resetPreview()
    }

    /// シーンを削除する（最低1つは残す）。
    /// 表示対象の同一性は保つ（FE-R1-013）。本家は表示中シーンを
    /// 参照で保持するため、別シーンの削除では表示は移らない。Mac 側は
    /// インデックス保持のため、表示中より前を消したらインデックスを
    /// 詰め、表示中自体を消したときだけ後継（同位置の次、末尾なら
    /// 最後）へ移す。プレビューの作り直しと選択の解除は、表示対象が
    /// 実際に変わった場合だけ行う。
    private func deleteTimeline(at index: Int) {
        guard project.timelines.count > 1,
              project.timelines.indices.contains(index) else { return }
        // アイテムのあるシーンは、本家 DeleteSceneAsync と同じく
        // 確認を出してから削除する（空のシーンは確認なし。文言は
        // 本家 Texts.ConfirmDeleteMessage「{0}を削除しますか？」に
        // タブ表示名を当てたもの）。キャンセルでは削除しない。
        // 確認の要否と削除の成立は Core の規則へ寄せる
        // （Project.timelineDeletionRequiresConfirmation /
        // removeTimeline(at:confirmed:)）。
        var confirmed = false
        if project.timelineDeletionRequiresConfirmation(at: index) {
            let name = project.timelines[index].name.isEmpty
                ? "タイムライン \(index + 1)"
                : project.timelines[index].name
            let alert = NSAlert()
            alert.messageText = "\(name)を削除しますか？"
            alert.addButton(withTitle: "削除")
            alert.addButton(withTitle: "キャンセル")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            confirmed = true
        }
        let wasDisplayed = index == timelineIndex
        guard project.removeTimeline(at: index, confirmed: confirmed) else {
            return
        }
        if index < timelineIndex {
            timelineIndex -= 1
        } else if timelineIndex >= project.timelines.count {
            timelineIndex = project.timelines.count - 1
        }
        workspace.markEdited()
        if wasDisplayed {
            selectedItemIndex = nil
            resetPreview()
        }
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
        workspace.markEdited()
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
            // 表示枠・描画寸法・座標変換は PreviewLayout が正本
            // （本家 PreviewViewModel の表示枠の式 + 均一倍率での
            // 描画と中心切り抜き。FE-R1-022）。
            let layout = PreviewCore.PreviewLayout(
                areaSize: geometry.size,
                videoSize: CGSize(width: info.width, height: info.height),
                displayZoom: previewDisplayZoom
            )
            let fittedWidth = layout.boxSize.width
            let fittedHeight = layout.boxSize.height

            ZStack {
                Rectangle()
                    .fill(.white)
                    .frame(width: fittedWidth, height: fittedHeight)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 0)

                // 映像・操作層・診断通知は表示枠の中で重ね、映像が
                // 枠からはみ出す分は切り抜く。配置の原点は表示枠の
                // 左上（PreviewLayout の座標系の前提）であり、枠側の
                // frame で確定させる。frame の配置を .topLeading に
                // 明示するのは、拡大で映像が枠より大きくなっても
                // 内容の寸法が原点を動かさないため（既定の中央揃え
                // だと、枠より大きい内容が中心合わせでずれて画像・
                // 輪郭・ハンドル・当たり判定が互いにずれる。
                // FE-R18-001）。
                ZStack(alignment: .topLeading) {
                    if let previewImage {
                        Image(previewImage, scale: 1, label: Text("合成プレビュー"))
                            .resizable()
                            .frame(
                                width: layout.imageSize.width,
                                height: layout.imageSize.height
                            )
                            .offset(
                                x: layout.imageOrigin.x, y: layout.imageOrigin.y
                            )
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
                        .frame(width: fittedWidth, height: fittedHeight)
                    }

                    // 選択輪郭とクリック選択／ドラッグ移動のヒット
                    // レイヤ。座標は PreviewLayout で映像座標へ変換
                    // する（切り抜き時は原点が負になる）。
                    previewInteractionLayer(timeline: timeline, layout: layout)

                    // 描画診断の通知（R6-06）。直近の描画で効果の失敗が
                    // あった場合だけ出す。詳細は診断タブの履歴を見る。
                    // 操作の邪魔をしないようヒットテストは無効にする。
                    if previewCurrentFailure {
                        VStack {
                            Spacer()
                            HStack {
                                Text("描画診断: 一部の効果の描画に失敗しました（詳細は下部の診断タブ）")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.9))
                                    .foregroundStyle(.black)
                                Spacer()
                            }
                        }
                        .frame(width: fittedWidth, height: fittedHeight)
                        .allowsHitTesting(false)
                    }
                }
                .frame(
                    width: fittedWidth, height: fittedHeight,
                    alignment: .topLeading
                )
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { isPreviewHovering = $0 }
    }

    /// 操作ハンドル（コントロールポイント）を出すかどうか。
    /// 本家 TimelineVideoPlayer の描画条件どおり: 「選択中のアイテム
    /// のみ」なら選択時に常時、「プレビューにマウスオーバー時」なら
    /// 領域へホバー中のみ、「常に表示しない」なら出さない（FE-R1-015）。
    /// ハンドル自体がジェスチャを持つため、非表示は操作不可も兼ねる
    /// （本家も Never ではコントローラの当たり判定を行わない）。
    private var showsControlPoints: Bool {
        switch controlPointVisibility {
        case .selectedOnly: return true
        case .onMouseOver: return isPreviewHovering
        case .never: return false
        }
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

    private func previewInteractionLayer(
        timeline: Timeline, layout: PreviewCore.PreviewLayout
    ) -> some View {
        let scale = layout.uniformScale
        return ZStack(alignment: .topLeading) {
            if let item = selectedItem,
               let bounds = previewItemBounds(item: item, timeline: timeline) {
                // 選択輪郭（白背景でも見えるよう黒と白の二重破線）。
                let origin = layout.viewPoint(
                    fromVideoPoint: CGPoint(x: bounds.minX, y: bounds.minY)
                )
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [5, 4]))
                    .foregroundStyle(.black.opacity(0.55))
                    .frame(width: bounds.width * scale, height: bounds.height * scale)
                    .offset(x: origin.x, y: origin.y)
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.white)
                    .frame(width: bounds.width * scale, height: bounds.height * scale)
                    .offset(x: origin.x, y: origin.y)
            }

            Color.clear
                .contentShape(Rectangle())
                .gesture(previewDragGesture(timeline: timeline, layout: layout))

            // 操作ハンドル（本家: 四隅▢ = 拡大率、辺の中点◯ = 回転角）。
            // 移動ジェスチャの層より上に置き、ハンドル上では拡大率／
            // 回転角のドラッグが優先される。表示はコントロールポイント
            // 表示モードに従う（FE-R1-015）。
            if showsControlPoints, let item = selectedItem, !item.isLocked,
               let bounds = previewItemBounds(item: item, timeline: timeline) {
                selectionHandles(
                    item: item, bounds: bounds, layout: layout, timeline: timeline
                )
            }
        }
        // この frame の左上が名前付き座標空間 previewArea の原点で、
        // 輪郭・ハンドルは PreviewLayout の表示枠座標（左上原点）で
        // 配置される。選択アイテムの描画寸法が表示枠を超える場合
        // （全画面アイテムの拡大表示など）でも内容の寸法が原点を
        // 動かさないよう、配置は .topLeading に明示する（既定の
        // 中央揃えだと輪郭・ハンドルだけがジェスチャ座標から
        // ずれる。FE-R18-001）。
        .frame(
            width: layout.boxSize.width, height: layout.boxSize.height,
            alignment: .topLeading
        )
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
    /// プレビュー上の移動ドラッグ／ハンドルドラッグについての
    /// Undo セッションの状態（開始前・所有中・開始拒否。
    /// FE-R20-126-03、FE-R21-126-01）。
    @State private var previewDragSession: EditDragSession = .idle
    @State private var handleDragSession: EditDragSession = .idle

    /// 選択アイテムの操作ハンドル群（表示は 9px、当たり判定は 18px）。
    private func selectionHandles(
        item: BaseItem, bounds: CGRect, layout: PreviewCore.PreviewLayout, timeline: Timeline
    ) -> some View {
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
                    point: point, layout: layout, timeline: timeline
                )
            }
            ForEach(Array(edges.enumerated()), id: \.offset) { _, point in
                handleView(
                    isCorner: false, item: item, bounds: bounds,
                    point: point, layout: layout, timeline: timeline
                )
            }
        }
    }

    private func handleView(
        isCorner: Bool, item: BaseItem, bounds: CGRect,
        point: (CGFloat, CGFloat), layout: PreviewCore.PreviewLayout, timeline: Timeline
    ) -> some View {
        let visualSize = 9.0
        let hitSize = 18.0
        let viewPoint = layout.viewPoint(
            fromVideoPoint: CGPoint(x: point.0, y: point.1)
        )
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
            x: viewPoint.x - hitSize / 2,
            y: viewPoint.y - hitSize / 2
        )
        .gesture(
            handleDragGesture(
                kind: isCorner ? .zoom : .rotation,
                item: item, bounds: bounds, layout: layout, timeline: timeline
            )
        )
        .help(isCorner ? "拡大率" : "回転角")
    }

    /// ハンドルのドラッグ。四隅は中心からの距離の比で拡大率を、
    /// 辺の中点は中心まわりの角度差で回転角を変える。書き込みは
    /// 移動ドラッグと同じ規則（writeAnimationValue の振り分け）。
    private func handleDragGesture(
        kind: HandleKind, item: BaseItem, bounds: CGRect,
        layout: PreviewCore.PreviewLayout, timeline: Timeline
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("previewArea"))
            .onChanged { value in
                if handleDrag == nil {
                    guard let index = timeline.items.firstIndex(where: { $0 === item }),
                          let props = item as? VideoItemProperties else { return }
                    // ドラッグの書き込みを1履歴エントリへまとめる
                    // セッションを開く（FE-UNDO-WIRING）。開始でき
                    // なかった場合、そのドラッグは終了まで書き込み
                    // 禁止のままになり、書き込みは writeAnimationValue
                    // の入口確認で拒否され、モデルは変更されない
                    // （FE-R20-126-03、FE-R21-126-01）。
                    handleDragSession.begin(using: workspace.editRecorder)
                    let context = animationContext(for: item, timeline: timeline)
                    let center = layout.viewPoint(
                        fromVideoPoint: CGPoint(x: bounds.midX, y: bounds.midY)
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
                    writeAnimationProperty(item: target, displayName: "拡大率", value: newZoom, timeline: timeline, session: handleDragSession)
                    updated.lastWritten = newZoom
                case .rotation:
                    let angle = atan2(Double(dy), Double(dx)) * 180 / .pi
                    var delta = angle - drag.startAngle
                    while delta > 180 { delta -= 360 }
                    while delta < -180 { delta += 360 }
                    let newRotation = drag.startRotation + delta
                    guard abs(newRotation - drag.lastWritten) >= 0.5 else { return }
                    writeAnimationProperty(item: target, displayName: "回転角", value: newRotation, timeline: timeline, session: handleDragSession)
                    updated.lastWritten = newRotation
                }
                handleDrag = updated
                requestPreviewRender(modelChanged: true)
            }
            .onEnded { _ in
                handleDrag = nil
                handleDragSession.endCommitting(to: workspace.editRecorder)
                // ドラッグ中の間引きで残った未反映分を確定させる
                // （再生中なら単一入口の規則で dirty に保留される）。
                requestPreviewRender(modelChanged: true, forceModelRefresh: true)
            }
    }

    /// アニメーション付きプロパティへの書き込み（表示名で引く）。
    /// ドラッグ移動と同じ規則（writeAnimationValue に集約）。
    private func writeAnimationProperty(
        item: BaseItem, displayName: String, value: Double, timeline: Timeline,
        session: EditDragSession
    ) {
        for descriptor in ItemPropertyMetadata.descriptors(for: item)
        where descriptor.displayName == displayName {
            guard case .animation = descriptor.kind else { continue }
            writeAnimationValue(
                descriptor: descriptor, item: item, timeline: timeline,
                value: value, session: session)
        }
    }

    /// プレビュー操作からのアニメーション値の書き込み経路。
    /// インスペクタ（AnimationRowView.writeValue）と同一の振り分け:
    /// 定数は定数化、キーフレームがある場合は再生ヘッドが属する
    /// 区間の開始値、それ以外は先頭値（FE-R1-006。先頭値への固定
    /// 書き換えでは、表示中の区間と無関係な値が変わる）。
    /// 書き込みは Undo 記録の対象とし、ドラッグ中は呼び出し側が
    /// 開いたセッションへ蓄積される（FE-UNDO-WIRING）。書き込みの
    /// 入口で記録可否を確認し、セッションの所有者でない場合は
    /// モデルを変更しない（FE-R20-126-03）。開始を拒否された
    /// ドラッグ（`EditDragSession.refused`）は、他のセッションが
    /// 終了してもそのドラッグの間は書き込みできない
    /// （FE-R21-126-01）。
    private func writeAnimationValue(
        descriptor: PropertyDescriptor, item: BaseItem, timeline: Timeline,
        value: Double, session: EditDragSession
    ) {
        guard let animation = descriptor.animationValue else { return }
        let recorder = workspace.editRecorder
        guard session.writeAllowed(recorder: recorder)
        else { return }
        if animation.animationType == .none {
            let old = AnimationSliderScale.editValue(of: animation, valueIndex: 0)
            descriptor.setAnimationConstantValue(value)
            let new = descriptor.animationValue.map {
                AnimationSliderScale.editValue(of: $0, valueIndex: 0)
            } ?? value
            recorder.recordValueChange(
                target: EditTargetKey(item, key: "\(descriptor.id)#const"),
                oldValue: old, newValue: new,
                apply: { descriptor.setAnimationConstantValue($0) },
                sessionToken: session.token)
        } else if animation.animationType.isKeyFrameSupported,
                  !animation.keyFrames.frames.isEmpty {
            let context = animationContext(for: item, timeline: timeline)
            let segment = animation.segmentIndex(atFrame: context.frame)
            let old = AnimationSliderScale.editValue(
                of: animation, valueIndex: segment)
            descriptor.setAnimationValue(value, atSegment: segment)
            let new = descriptor.animationValue.map {
                AnimationSliderScale.editValue(of: $0, valueIndex: segment)
            } ?? value
            recorder.recordValueChange(
                target: EditTargetKey(item, key: "\(descriptor.id)#seg\(segment)"),
                oldValue: old, newValue: new,
                apply: { descriptor.setAnimationValue($0, atSegment: segment) },
                sessionToken: session.token)
        } else {
            let old = AnimationSliderScale.editValue(of: animation, valueIndex: 0)
            descriptor.setAnimationFirstValue(value)
            let new = descriptor.animationValue.map {
                AnimationSliderScale.editValue(of: $0, valueIndex: 0)
            } ?? value
            recorder.recordValueChange(
                target: EditTargetKey(item, key: "\(descriptor.id)#first"),
                oldValue: old, newValue: new,
                apply: { descriptor.setAnimationFirstValue($0) },
                sessionToken: session.token)
        }
    }

    private func previewDragGesture(
        timeline: Timeline, layout: PreviewCore.PreviewLayout
    ) -> some Gesture {
        let scale = layout.uniformScale
        return DragGesture(minimumDistance: 0)
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
                    writeItemPosition(item: item, x: newX, y: newY, timeline: timeline, session: previewDragSession)
                    drag.lastWrittenX = newX
                    drag.lastWrittenY = newY
                    previewDrag = drag
                    requestPreviewRender(modelChanged: true)
                    return
                }

                // 押し始め: 現在フレームで描画されているアイテムから
                // 当たり判定し、選択とドラッグ基準を決める。開始点は
                // 切り抜きの原点を含む変換で映像座標へ戻す。
                let startVideoPoint = layout.videoPoint(
                    fromViewPoint: value.startLocation
                )
                if let index = hitTestPreviewItem(
                    timeline: timeline, videoPoint: startVideoPoint
                ), let props = timeline.items[index] as? VideoItemProperties {
                    // 移動ドラッグの書き込みを1履歴エントリへまとめる
                    // セッションを開く（FE-UNDO-WIRING）。開始でき
                    // なかった場合、そのドラッグは終了まで書き込み
                    // 禁止のままになり、書き込みは writeAnimationValue
                    // の入口確認で拒否され、モデルは変更されない
                    // （FE-R20-126-03、FE-R21-126-01）。
                    previewDragSession.begin(using: workspace.editRecorder)
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
                previewDragSession.endCommitting(to: workspace.editRecorder)
                // ドラッグ中の間引きで残った未反映分を確定させる
                // （再生中なら単一入口の規則で dirty に保留される）。
                requestPreviewRender(modelChanged: true, forceModelRefresh: true)
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
            // ロックしたアイテムはプレビューで掴めない（本家の当たり
            // 判定はコントローラ経路・本体経路とも !IsLocked で除外
            // する。FE-R1-020）。
            guard !item.isLocked,
                  let bounds = previewItemBounds(item: item, timeline: timeline),
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
    /// （writeAnimationValue の振り分け）で、既存の記述子経路を
    /// 通して X/Y へ書き込む。
    private func writeItemPosition(
        item: BaseItem, x: Double, y: Double, timeline: Timeline,
        session: EditDragSession
    ) {
        for descriptor in ItemPropertyMetadata.descriptors(for: item) {
            guard case .animation = descriptor.kind else { continue }
            let value: Double
            switch descriptor.displayName {
            case "X": value = x
            case "Y": value = y
            default: continue
            }
            writeAnimationValue(
                descriptor: descriptor, item: item, timeline: timeline,
                value: value, session: session)
        }
    }

    // MARK: - トランスポート帯

    /// 本家 PreviewView の操作行（高さ24）の全構成要素を備えた帯。
    /// 並びは本家どおり（UI-LAYOUT-FACTS.md §3）: 左から 再生/一時停止、
    /// 停止、再生速度コンボ、リピート、コントロールポイント表示、
    /// プレビュー倍率コンボ、フィット、先頭、前の編集点、前フレーム、
    /// 中央に位置スライダ（残り全幅）、右に 次フレーム、次の編集点、
    /// 末尾、音量スライダ、ミュート。
    /// 再生・停止・速度・音量は実時間再生エンジン（Issue #52）に
    /// 接続済み。シーク系と表示倍率も実動する。
    private func transportBar(timeline: Timeline) -> some View {
        HStack(spacing: 2) {
            transportButton(
                isPlayingForm ? "pause.fill" : "play.fill",
                help: isPlayingForm ? UIStrings.Transport.pause : UIStrings.Transport.play
            ) {
                if let playbackEngine {
                    playbackEngine.togglePlay()
                } else {
                    isPlayingForm.toggle()
                }
            }
            transportButton("stop.fill", help: UIStrings.Transport.stop) {
                if let playbackEngine {
                    playbackEngine.stop()
                } else {
                    isPlayingForm = false
                    seek(to: 0, timeline: timeline)
                }
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
            .onChange(of: playbackRate) { _, newValue in
                playbackEngine?.playbackRate = newValue
            }

            transportToggle(
                "repeat", help: UIStrings.Transport.repeatPlay, isOn: $isRepeatOn
            )
            .onChange(of: isRepeatOn) { _, newValue in
                playbackEngine?.isRepeatEnabled = newValue
            }

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

            Slider(
                value: $previewFrame, in: 0...Double(max(timeline.length, 1)),
                step: 1
            ) { isEditing in
                // ドラッグ中はプレビューだけを追従させ、離した時点で
                // エンジンへシークする（再生中シークは本家どおり
                // 一時停止してから位置を移す）。
                if !isEditing {
                    seek(to: Int(previewFrame), timeline: timeline)
                }
            }
            // ドラッグ中のプレビュー追従はここで行う。再生中は位置通知
            // 側が描画要求を出すため、ここでは要求しない（二重要求と
            // 実行モードの食い違いを避ける — R6-02）。
            .onChange(of: previewFrame) { _, _ in
                if !isPlayingForm { requestPreviewRender() }
            }
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
            .onChange(of: isMuted) { _, newValue in
                playbackEngine?.isMuted = newValue
            }
            Slider(value: $volume, in: 0...100)
                .frame(width: 100)
                .help(UIStrings.Transport.volume)
                .onChange(of: volume) { _, newValue in
                    playbackEngine?.volume = newValue
                }
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
    /// エンジンがある場合はエンジン側も同じ位置へ移す。再生中の
    /// シークは本家どおり一時停止してから位置を移し、再開しない
    /// （SeekBehavior の既定 = Pause）。
    private func seek(to frame: Int, timeline: Timeline) {
        let clamped = min(max(frame, 0), timeline.length)
        previewFrame = Double(clamped)
        playbackEngine?.seek(toFrame: clamped)
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
    /// タイムライン側で作った複数選択（範囲選択・Commandトグル等）が
    /// UI 選択のアイテムを含んでいる場合は、その複数選択を正として
    /// 残す（FE-TIMELINE。再構築で Core 選択が複数を持てるようになった）。
    /// 含んでいない場合（プレビュー側のクリック等で UI 選択だけが
    /// 動いた場合）は従来どおり単一選択へ同期する。
    private func syncSelectionToTimeline(_ timeline: Timeline) {
        if let item = selectedItem,
           timeline.selectedItems.contains(where: { $0 === item }) {
            return
        }
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

    // MARK: - Undo/Redo の接続（FE-UNDO-WIRING）

    /// タイムラインドラッグの開始通知。トランザクションを開始し、
    /// 開始時点の写しを取る。開始可否を戻り値で操作層へ返し、拒否
    /// された場合は操作層がモデル変更セッション自体を開始しない
    /// （FE-R20-126-02。無記録のドラッグ変更を残さない）。開始して
    /// いないセッションの終了通知では何もしない（所有の追跡は
    /// 監査 Round 10 の接続条件）。
    @discardableResult
    private func beginTimelineDragUndo(timeline: Timeline) -> Bool {
        dragUndoToken = workspace.editRecorder.beginSession()
        dragUndoSnapshot = dragUndoToken != nil
            ? TimelineEditSnapshot(timeline: timeline) : nil
        return dragUndoToken != nil
    }

    /// タイムラインドラッグの確定通知。自分が開始したセッションに
    /// ついてだけ、開始時点との差分を記録して確定する。
    private func commitTimelineDragUndo(timeline: Timeline) {
        if let token = dragUndoToken, let snapshot = dragUndoSnapshot,
           let transaction = workspace.editRecorder.sessionTransaction(for: token) {
            snapshot.recordDiff(into: transaction, timeline: timeline)
            workspace.editRecorder.commitSession(token: token)
        }
        dragUndoToken = nil
        dragUndoSnapshot = nil
    }

    /// タイムラインドラッグのキャンセル通知。モデルは操作層が
    /// 開始時点へ復元済みであり、こちらは自分が開始したセッション
    /// のトランザクションを破棄するだけである。開始していない
    /// セッション（背景・範囲選択の Escape 等）の通知は対象外。
    private func cancelTimelineDragUndo() {
        if let token = dragUndoToken {
            workspace.editRecorder.cancelSession(token: token)
        }
        dragUndoToken = nil
        dragUndoSnapshot = nil
    }

    /// Undo を実行し、表示（選択・インスペクタ・タイムライン・
    /// プレビュー）をモデルへ追随させる。
    private func performUndo(timeline: Timeline) {
        guard workspace.editCoordinator.undo() else { return }
        afterHistoryApplied(timeline: timeline)
    }

    /// Redo を実行し、表示をモデルへ追随させる。
    private func performRedo(timeline: Timeline) {
        guard workspace.editCoordinator.redo() else { return }
        afterHistoryApplied(timeline: timeline)
    }

    private func afterHistoryApplied(timeline: Timeline) {
        historyApplyRevision += 1
        timelineDisplayRevision += 1
        reflectCoreSelection(timeline)
        requestPreviewRender(modelChanged: true)
    }

    /// メニュー／ツールバーからの編集アクションを実行する。
    /// いずれも Core の既存編集操作への接続であり、構造を変える操作の
    /// 後はプレビューを再合成する。
    private func executeWorkspaceAction(_ action: WorkspaceAction, timeline: Timeline) {
        switch action {
        case .undo:
            performUndo(timeline: timeline)
        case .redo:
            performRedo(timeline: timeline)
        case .addItem(let kind):
            addItem(kind: kind, timeline: timeline)
        case .splitAtCurrentPosition:
            splitAtPlayhead(timeline: timeline)
        case .deleteSelection:
            guard selectedItem != nil else { return }
            syncSelectionToTimeline(timeline)
            // 記録を開始できない間は削除自体を実行しない
            // （FE-R20-126-02。無記録の構造変更を残さない）。
            guard workspace.editRecorder.recordTimelineChange(timeline: timeline, {
                timeline.deleteSelectedAndGroupedItems()
            }) else { return }
            selectedItemIndex = nil
            requestPreviewRender(modelChanged: true)
        case .deleteAndMoveAll:
            guard selectedItem != nil else { return }
            syncSelectionToTimeline(timeline)
            guard workspace.editRecorder.recordTimelineChange(timeline: timeline, {
                _ = timeline.deleteAndMoveAll()
            }) else { return }
            reflectCoreSelection(timeline)
            requestPreviewRender(modelChanged: true)
        case .groupSelection:
            guard selectedItem != nil else { return }
            syncSelectionToTimeline(timeline)
            timeline.groupSelectedAndGroupedItems()
            // グループ化は Undo 記録の対象外のため個別に立てる
            // （FE-R32-131-03）。
            workspace.markEdited()
            requestPreviewRender(modelChanged: true)
        case .ungroupSelection:
            guard selectedItem != nil else { return }
            syncSelectionToTimeline(timeline)
            timeline.ungroupSelectedAndGroupedItems()
            workspace.markEdited()
            requestPreviewRender(modelChanged: true)
        case .toggleLock:
            // ロック切替は Undo 記録の対象外のため、実際に切り替えた
            // 場合だけ個別に立てる（FE-R32-131-03）。
            if let item = selectedItem {
                item.isLocked.toggle()
                workspace.markEdited()
            }
            requestPreviewRender(modelChanged: true)
        case .toggleClipping:
            if let visual = selectedItem as? VisualItem {
                visual.isClippingWithObjectAbove.toggle()
                workspace.markEdited()
            } else if let voice = selectedItem as? VoiceItem {
                voice.isClippingWithObjectAbove.toggle()
                workspace.markEdited()
            }
            requestPreviewRender(modelChanged: true)
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
        case .userDictionaryChanged:
            // 辞書は描画の入力だがモデルには含まれないため、変更を
            // モデルの作り直しとして扱う（R18-02）。版数が上がること
            // で、表示済み画像の識別子が現在のものと一致しなくなり、
            // 辞書変更前の画像がサムネイルとして保存される経路と、
            // 古い描画結果が採用される経路の両方が閉じる。保留中の
            // サムネイル保存は取り消さず、新しいモデルへ結び直す
            // （R20-113-01）。
            previewModelDirty = true
            requestPreviewRender()
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
        // 分割は Undo 記録の対象外のため、成功後に未保存フラグを
        // 個別に立てる（FE-R32-131-03）。
        workspace.markEdited()
        reflectCoreSelection(timeline)
        requestPreviewRender(modelChanged: true)
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
    /// 追加は Core の衝突解決つき追加（tryAddItems）を経由する
    /// （FE-R1-009）。配置位置は引数で渡し、アイテム側へ事前に
    /// 書き込まない（tryAddItems が差分で配置する）。選択の確定も
    /// tryAddItems 側が行うため、UI 側はインデックスを引き直す。
    private func addItem(kind: AddItemKind, timeline: Timeline) {
        // 動画・音声・画像は本家どおりファイル選択から始める
        // （FE-R1-043。それ以外の種別は従来どおり即時に追加する）。
        if let group = kind.fileGroup {
            addMediaItemsFromDialog(kind: kind, group: group, timeline: timeline)
            return
        }
        let item = makeItem(kind: kind)
        item.length = placeholderItemLength(timeline: timeline)
        var added = false
        workspace.editRecorder.recordTimelineChange(timeline: timeline) {
            added = timeline.tryAddItems(
                [item], frame: Int(previewFrame), layer: topVisibleLayer)
        }
        guard added else { return }
        if let index = timeline.items.firstIndex(where: { $0 === item }) {
            selectedItemIndex = index
        }
        requestPreviewRender(modelChanged: true)
    }

    /// メディアアイテム追加の入口（本家 MainViewModel の Add*Item
    /// コマンド）。複数選択可のファイルダイアログを開き、選択された
    /// ファイルを現在フレーム・表示最上段レイヤーへ追加する。
    /// キャンセルした場合は何も追加しない（本家の既定設定
    /// AddFileItemMode の Default は Cancel に解決される）。
    private func addMediaItemsFromDialog(
        kind: AddItemKind, group: PropertyFileGroup, timeline: Timeline
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let types = MediaFileInfoFetcher.contentTypes(for: group)
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let frame = Int(previewFrame)
        let layer = topVisibleLayer
        let baseDirectory = baseDirectory
        let entries = panel.urls.map { (url: $0, kind: kind, group: group) }
        Task {
            await addMediaFiles(
                entries,
                frame: frame, layer: layer, timeline: timeline,
                baseDirectory: baseDirectory
            )
        }
    }

    /// ファイル群からメディアアイテムを組み立て、一括で確定する。
    ///
    /// 層の分担（FE-R1-043）: 情報取得（供給層）が成功したファイル
    /// だけを対象に、長さの決定（編集操作層）を行ってから、
    /// Timeline の確定操作（tryAddItems）へ渡す。取得に失敗した
    /// ファイルは追加しない（空アイテムを残さない）。
    ///
    /// 取得は非同期で、その間にタイムラインの切り替えや削除が
    /// 起き得る。確定時は対象タイムラインがまだプロジェクトに
    /// 属していることを確認し（FE-R15-002）、選択の写し戻しは
    /// 追加先が現在表示中のタイムラインの場合だけ行う（別タイム
    /// ラインへの追加で表示中の選択状態を書き換えない）。
    private func addMediaFiles(
        _ entries: [(url: URL, kind: AddItemKind, group: PropertyFileGroup)],
        frame: Int, layer: Int, timeline: Timeline, baseDirectory: URL
    ) async {
        var newItems: [BaseItem] = []
        for entry in entries {
            guard let info = await MediaFileInfoFetcher.fetch(
                path: entry.url.path, group: entry.group,
                audioTrackIndex: 0, baseDirectory: baseDirectory
            ) else { continue }
            let item = makeItem(kind: entry.kind)
            setFilePath(entry.url.path, on: item)
            prepareMediaItem(item, info: info, fps: timeline.videoInfo.fps)
            newItems.append(item)
        }
        guard !newItems.isEmpty,
              project.timelines.contains(where: { $0 === timeline })
        else { return }
        // 記録のスナップショットは確定の直前に取る（取得の非同期の
        // 間に起きた他の変更を差分へ含めないため）。
        var added = false
        workspace.editRecorder.recordTimelineChange(timeline: timeline) {
            added = timeline.tryAddItems(newItems, frame: frame, layer: layer)
        }
        guard added else { return }
        if self.timeline === timeline {
            reflectCoreSelection(timeline)
        }
        requestPreviewRender(modelChanged: true)
    }

    /// 取得済み情報からアイテムの長さを決める（編集操作層）。
    /// 動画・音声は素材の長さから決め直し（オフセットは 0 から）、
    /// 画像は素材から長さを決めないため既定の長さを使う
    /// （本家 AddImageItem は Length を既定アイテムのままにする）。
    private func prepareMediaItem(_ item: BaseItem, info: MediaFileInfo, fps: Int) {
        switch item {
        case is VideoItem, is AudioItem:
            item.recordMediaInfo(info)
            item.resetLength(fps: fps, resetContentOffset: true)
        default:
            item.length = BaseItem.defaultItemLength
        }
    }

    private func setFilePath(_ path: String, on item: BaseItem) {
        switch item {
        case let video as VideoItem: video.filePath = path
        case let audio as AudioItem: audio.filePath = path
        case let image as ImageItem: image.filePath = path
        default: break
        }
    }

    private func filePath(of item: BaseItem) -> String {
        switch item {
        case let video as VideoItem: return video.filePath ?? ""
        case let audio as AudioItem: return audio.filePath ?? ""
        case let image as ImageItem: return image.filePath ?? ""
        default: return ""
        }
    }

    private func fileGroup(of item: BaseItem) -> PropertyFileGroup? {
        switch item {
        case is VideoItem: return .video
        case is AudioItem: return .audio
        case is ImageItem: return .image
        default: return nil
        }
    }

    /// 再生速度の編集セッション開始時の基点捕捉（FE-R15-004 /
    /// FE-R27-129-03）。
    ///
    /// 行がセッションの開始を受理した直後、最初の書き込みより
    /// 前に呼ばれ、編集開始時点の値を Core の基点として返す。
    /// 基点の所有は行のセッション状態へ移り、寿命がセッションと
    /// 一致する。旧実装の ProjectView 側の辞書は、終了通知の欠落
    /// で基点が後続セッションへ残り、符号反転を挟むと合成結果が
    /// 誤る問題（FE-R27-129-03）のため廃止した。対象は再生速度の
    /// 記述子だけ。
    private func capturePlaybackRateEditBaseline(
        descriptor: PropertyDescriptor, item: BaseItem
    ) -> PlaybackRateEditBaseline? {
        guard descriptor.id == "PlaybackRate2" else { return nil }
        return item.capturePlaybackRateEditBaseline()
    }

    /// 再生速度の編集セッション終了時の調整（FE-R15-004 の
    /// 編集終了時調整、FE-R27-129-01 / 04）。
    ///
    /// 行がセッションを確定する前に呼ばれ、分岐の優先判定と比率
    /// 換算を Core（`finishPlaybackRateEdit`）で行い、長さ・
    /// オフセットの変更を同じセッション（トークン提示）へ記録
    /// する。これにより速度の変更と調整が履歴1エントリへ収まる。
    /// 適用クロージャは配置値の書き戻しと同じく、書き戻しの直後
    /// にタイムライン長のキャッシュを再計算する
    /// （FE-R20-126-01 と同じ不変条件）。失効したトークン
    /// （プロジェクト切替でセッションが破棄済み等）では、調整
    /// 自体を行わない。
    private func finishPlaybackRateEditSession(
        descriptor: PropertyDescriptor, baseline: PlaybackRateEditBaseline,
        token: EditSessionToken?, item: BaseItem, timeline: Timeline
    ) {
        guard descriptor.id == "PlaybackRate2" else { return }
        let recorder = workspace.editRecorder
        guard recorder.canRecordValueChange(sessionToken: token)
        else { return }
        let oldLength = item.length
        let oldContentOffset = item.contentOffset
        guard item.finishPlaybackRateEdit(
            baseline: baseline, fps: timeline.videoInfo.fps
        ) else { return }
        if item.length != oldLength {
            recorder.recordValueChange(
                target: EditTargetKey(item, key: "Length"),
                oldValue: oldLength, newValue: item.length,
                apply: { value in
                    item.length = value
                    timeline.refreshTimelineLengthAndMaxLayer()
                },
                sessionToken: token)
        }
        if item.contentOffset != oldContentOffset {
            recorder.recordValueChange(
                target: EditTargetKey(item, key: "ContentOffset"),
                oldValue: oldContentOffset, newValue: item.contentOffset,
                apply: { value in
                    item.contentOffset = value
                    timeline.refreshTimelineLengthAndMaxLayer()
                },
                sessionToken: token)
        }
        timeline.refreshTimelineLengthAndMaxLayer()
        requestPreviewRender(modelChanged: true)
    }

    /// インスペクタでのファイル差し替え（FE-R1-043）。
    ///
    /// 通知は記述子が新しいパスを書き込むより前に届くため、ここで
    /// 変更前のパスと素材長を捕捉できる。情報取得（供給層）を
    /// 非同期に行い、対象の同一性と要求世代、タイムラインが
    /// まだプロジェクトに属していることを照合してから、素材
    /// 情報を記録して編集終了時相当の長さ調整（編集操作層）を
    /// 行う。ファイルが存在しない場合は長さに触らず、状態表示で
    /// 知らせる（利用者のトリムを守る。パス文字列自体は記述子が
    /// 保持する）。
    private func applyFileChange(item: BaseItem, newPath: String, timeline: Timeline) {
        guard let group = fileGroup(of: item) else { return }
        let oldPath = filePath(of: item)
        let recordedOriginal = item.originalContentLength
        let key = ObjectIdentifier(item)
        let generation = (fileChangeGenerations[key] ?? 0) + 1
        fileChangeGenerations[key] = generation
        let baseDirectory = baseDirectory
        let audioTrackIndex: Int
        switch item {
        case let video as VideoItem: audioTrackIndex = video.audioTrackIndex
        case let audio as AudioItem: audioTrackIndex = audio.audioTrackIndex
        default: audioTrackIndex = 0
        }
        Task {
            // 変更前の素材長が未記録（プロジェクト読み込み直後など）
            // なら、旧ファイルの情報から基準を立てる。同じファイルの
            // 選び直しでトリムが消えないようにするため。
            var previousOriginal = recordedOriginal
            if previousOriginal == .zero, !oldPath.isEmpty {
                previousOriginal = await MediaFileInfoFetcher.fetch(
                    path: oldPath, group: group,
                    audioTrackIndex: audioTrackIndex, baseDirectory: baseDirectory
                )?.duration ?? .zero
            }
            let info = await MediaFileInfoFetcher.fetch(
                path: newPath, group: group,
                audioTrackIndex: audioTrackIndex, baseDirectory: baseDirectory
            )
            guard fileChangeGenerations[key] == generation,
                  project.timelines.contains(where: { $0 === timeline }),
                  timeline.items.contains(where: { $0 === item })
            else { return }
            guard let info else {
                workspace.statusMessage =
                    "ファイルが見つからないため、長さを更新できませんでした: \(newPath)"
                return
            }
            // 未保存の記録は行側の書き込み成立時点に一本化した
            // （FE-R33-131-01）。ここは素材長の調整だけを担い、
            // 記録には関与しない。取得失敗で戻る経路でも、書き込み
            // 時点で立ったフラグは消えない。
            item.recordMediaInfo(info)
            // 長さが決め直されたら、タイムライン長のキャッシュも
            // 追随させる（FE-R16-001）。キャッシュは自動追随せず、
            // 書き出し範囲の決定にも使われるため、所属タイムラインを
            // 把握しているアプリ層が再計算する。長さが変わらなかった
            // 場合は再計算しない。
            if item.adjustLengthAfterFileChange(
                previousOriginalContentLength: previousOriginal,
                fps: timeline.videoInfo.fps
            ) {
                timeline.refreshTimelineLengthAndMaxLayer()
            }
            requestPreviewRender(modelChanged: true)
        }
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
        item.length = placeholderItemLength(timeline: timeline)
        // 追加は衝突解決つきの tryAddItems を経由する（FE-R1-009）。
        // 配置後の item.frame がシーク先になる。
        var added = false
        workspace.editRecorder.recordTimelineChange(timeline: timeline) {
            added = timeline.tryAddItems(
                [item], frame: Int(previewFrame), layer: topVisibleLayer)
        }
        guard added else { return }
        if let index = timeline.items.firstIndex(where: { $0 === item }) {
            selectedItemIndex = index
        }
        if seeksAfterAdd {
            seek(to: item.frame + item.length, timeline: timeline)
        }
        requestPreviewRender(modelChanged: true)
    }

    /// 現在のプレビュー画像をサムネイルとして保存する
    /// （本家 SaveThumbnail。保存先はダイアログで聞く）。
    /// 合成は非同期のため、現在位置・現在モデルに対応する画像が
    /// 表示済みのときだけ即時に保存し、未完成なら完成を待ってから
    /// 保存する（シーク直後の旧フレームを誤って保存しない。R11-08）。
    private func saveThumbnail(format: ThumbnailFormat, timeline: Timeline) {
        // モデルの作り直しが保留されている間は、表示中の画像が古い
        // 状態（例: 辞書変更の反映前）であり得るため再利用しない
        // （R18-02 の残存競合への対処。作り直しは 100ms 間引かれる
        // ことがあり、版数が上がる前でも旧画像を保存しない）。
        if displayedPreviewIdentity == currentPreviewIdentity,
           displayedPreviewFrame == Int(previewFrame), previewImage != nil,
           !previewModelDirty {
            writeThumbnail(format: format, timeline: timeline)
            return
        }
        // 識別子へは固定しない。モデルが作り直されても、要求は
        // 新しいモデルの同じフレームへ結び直される（R20-113-01）。
        pendingThumbnail = (format: format, frame: Int(previewFrame))
        requestPreviewRender()
    }

    /// 表示中の画像をファイルへ書き出す（保存先はダイアログで聞く）。
    private func writeThumbnail(format: ThumbnailFormat, timeline: Timeline) {
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
            // プロジェクトを開く操作と同じく、未保存の変更があれば
            // 破棄確認を出してから読み込む（FE-R1-001）。
            guard workspace.confirmDiscardUnsavedChanges() else { return }
            workspace.load(url: urls[0])
            return
        }
        // 情報取得（供給層）と長さの決定（編集操作層）を済ませて
        // から、衝突解決つきの tryAddItems で一括確定する
        // （FE-R1-009 / FE-R1-043）。分類は MediaFileInfoFetcher の
        // 共有表（判定順は 動画→音声→画像。字幕ファイルの分離処理は
        // 未実装）。
        let frame = Int(previewFrame)
        let layer = topVisibleLayer
        let baseDirectory = baseDirectory
        let entries: [(url: URL, kind: AddItemKind, group: PropertyFileGroup)] =
            urls.compactMap { url in
                guard let group = MediaFileInfoFetcher.fileGroup(
                    forFileExtension: url.pathExtension
                ), let kind = AddItemKind(fileGroup: group) else { return nil }
                return (url: url, kind: kind, group: group)
            }
        guard !entries.isEmpty else { return }
        Task {
            await addMediaFiles(
                entries,
                frame: frame, layer: layer, timeline: timeline,
                baseDirectory: baseDirectory
            )
        }
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
            // Undo/Redo は Core の EditCoordinator へ接続済み
            // （FE-UNDO-WIRING）。有効条件は履歴の有無に加えて
            // 操作状態（編集中は不可）も見る（WorkspaceState 側）。
            toolbarButton("arrow.uturn.backward", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.undo, shortcut: UIStrings.Toolbar.shortcutUndo)) {
                performUndo(timeline: timeline)
            }
            .disabled(!workspace.canPerformUndo)
            toolbarButton("arrow.uturn.forward", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.redo, shortcut: UIStrings.Toolbar.shortcutRedo)) {
                performRedo(timeline: timeline)
            }
            .disabled(!workspace.canPerformRedo)
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
                workspace.requestOpenProject()
            }
            toolbarButton("square.and.arrow.down", help: UIStrings.Toolbar.tip(UIStrings.Toolbar.saveProject, shortcut: UIStrings.Toolbar.shortcutSave)) {
                workspace.save()
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
            .disabled(exportState.isRunning)
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
    /// 値は再生エンジンのレベルメーターから供給される（Issue #52）。
    /// ツールチップの書式は本家 SoundLevelMeter の LevelMeterText /
    /// LoudnessText そのまま。
    private var levelMeters: some View {
        HStack(alignment: .top, spacing: 0) {
            if isLoudnessMeterEnabled {
                meterColumn(
                    unitLabel: "LKFS",
                    zones: Self.loudnessMeterZones,
                    values: [loudnessMeterValue],
                    barWidth: 20,
                    helpText: String(
                        format: "%.1fLUFS", loudnessMeterValue.current.peak
                    ))
            }
            if isPeakMeterEnabled {
                meterColumn(
                    unitLabel: "dB",
                    zones: Self.peakMeterZones,
                    values: [peakMeterLeft, peakMeterRight],
                    barWidth: 10,
                    helpText: String(
                        format: "L: %.1fdB\nR: %.1fdB",
                        peakMeterLeft.current.peak, peakMeterRight.current.peak
                    ))
            }
        }
        .onHover { isMeterHovering = $0 }
        .onChange(of: isPeakMeterEnabled) { _, newValue in
            playbackEngine?.levelMeter.isSoundLevelMeterEnabled = newValue
        }
        .onChange(of: isLoudnessMeterEnabled) { _, newValue in
            playbackEngine?.levelMeter.isLoudnessMeterEnabled = newValue
        }
        .contextMenu {
            Toggle(UIStrings.Toolbar.peakMeter, isOn: $isPeakMeterEnabled)
            Toggle(UIStrings.Toolbar.loudnessMeter, isOn: $isLoudnessMeterEnabled)
        }
    }

    /// メーター1カラム分。バーの上に目盛りの刻みを重ね、右上に単位表記、
    /// ホバー時に目盛り数値（−5…−60）を重ねる（本家 TimelineView の
    /// 各メーターグリッドの構造）。バーの本数は values の件数で決まる。
    private func meterColumn(
        unitLabel: String, zones: MeterZones, values: [LevelMeterValue],
        barWidth: CGFloat, helpText: String
    ) -> some View {
        let columnWidth = barWidth * CGFloat(values.count)
        return ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    let value = values[index]
                    levelMeterBar(
                        zones: zones,
                        peak: value.current.peak,
                        average: value.current.rms,
                        peakHold: value.hold.peak
                    )
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
    /// 値はエンジンのレベルメーターの現在値（無信号時は下限 −60 dB）。
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
    /// Double は "nan" / "inf" も受理するため、有限でない値は各段階で
    /// 弾く（FE-R1-005。NaN や無限大の Int 変換は trap する）。有限でも
    /// Int の範囲を超える結果は nil を返す。
    private func parseTimeText(_ text: String, fps: Int) -> Int? {
        let parts = text.split(separator: ":")
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part), value.isFinite else { return nil }
            seconds = seconds * 60 + value
            guard seconds.isFinite else { return nil }
        }
        let frames = (seconds * Double(max(fps, 1))).rounded()
        guard frames.isFinite else { return nil }
        // 範囲判定を Double の上限比較で行わない。Double(Int.max) は
        // 2^63 へ丸められるため、2^63 ちょうどの値が比較をすり抜けて
        // Int 変換で trap する（FE-R3-118-01）。変換はこの1か所のみで、
        // 失敗は nil として扱う。
        return Int(exactly: frames)
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
        previewWorker.invalidate(generation: previewSessionGeneration)
        previewSessionGeneration += 1
        pendingModelRefreshItem?.cancel()
        pendingModelRefreshItem = nil
        pendingThumbnail = nil
        displayedPreviewIdentity = nil
        displayedPreviewFrame = nil
        previewImage = nil
        previewError = nil
        previewSessionKey = nil
        previewModelDirty = true
        previewCurrentFailure = false
        previewDiagnostics = []
        guard let timeline else { return }
        previewFrame = Double(timeline.currentFrame)
        // 未保存プロジェクトではセッションキー用に固定の番兵 URL を使う
        // （キーは同一性の判定にだけ使う）。
        previewSessionKey = PreviewBox.SessionKey(
            url: sourceURL ?? URL(fileURLWithPath: "/untitled-project"),
            timelineIndex: timelineIndex
        )
        wirePreviewWorker()
        resetPlaybackEngine(timeline: timeline)
        refreshPreviewModel(force: true)
        requestPreviewRender()
    }

    /// ワーカーからの完成通知を、識別子（セッションキー・世代・
    /// モデル版数）が現在のものと一致する場合だけ表示へ反映する
    /// （古いセッション・編集前のモデルの結果は捨てる。それ以外は、
    /// 後続の要求があっても採用する — 第9ラウンドの二段階規則）。
    private func wirePreviewWorker() {
        previewWorker.onImage = { image, identity, frame, failures, history in
            guard identity.key == previewSessionKey,
                  identity.generation == previewSessionGeneration,
                  identity.version == previewModelVersion
            else { return }
            // 停止中は現在位置と一致するフレームだけを採用する
            // （シーク前に始まった描画の結果で表示が巻き戻らない。
            // R12-02）。再生中は多少古いフレームも採用する
            // （第9ラウンドの二段階規則）。
            if !isPlayingForm, frame != Int(previewFrame) { return }
            previewImage = image
            previewError = nil
            displayedPreviewIdentity = identity
            displayedPreviewFrame = frame
            // 現在の失敗状態はこの描画の結果で更新し、履歴は
            // セッションの集約で置き換える（R6-06）。
            previewCurrentFailure = !failures.isEmpty
            previewDiagnostics = history
            // サムネイル保存が対応画像を待っている場合はここで進める
            // （R11-08）。発火条件は「現在のモデルの画像であり、作り
            // 直し保留中でなく、フレームが一致すること」。旧モデルの
            // 完成通知では発火せず待ち続け、現在のモデルで別フレーム
            // が先に完成したら（利用者が移動したということなので）
            // 別フレームを保存せず取り消す（R12-06／R20-113-01）。
            if let pending = pendingThumbnail,
               identity == currentPreviewIdentity, !previewModelDirty {
                if pending.frame == frame, let timeline {
                    pendingThumbnail = nil
                    writeThumbnail(format: pending.format, timeline: timeline)
                } else {
                    pendingThumbnail = nil
                }
            }
        }
        previewWorker.onRenderFailed = { identity, frame, failures, history in
            guard identity.key == previewSessionKey,
                  identity.generation == previewSessionGeneration,
                  identity.version == previewModelVersion
            else { return }
            // 正常画像と同じ採用条件にそろえる: 停止中は現在位置と
            // 一致するフレームの失敗だけを採用する（シーク前の失敗
            // 通知で現在の表示を消さない。R14-03）。
            if !isPlayingForm, frame != Int(previewFrame) { return }
            previewImage = nil
            displayedPreviewIdentity = nil
            displayedPreviewFrame = nil
            // アイテム0件の空タイムラインで合成結果が得られない場合は
            // エラー表示にせず、プレースホルダ文言に任せる。
            // 合成例外の理由が診断に残っている場合はそれを表示する
            // （FE-R1-037）。
            if (timeline?.items.isEmpty ?? true) {
                previewError = nil
            } else if let composition = failures.first(
                where: { $0.kind == PreviewBox.compositionFailureKind }
            ) {
                previewError = "合成に失敗しました: \(composition.message)"
            } else {
                previewError = "合成に失敗しました（例外または出力なし）"
            }
            previewCurrentFailure = !failures.isEmpty
            previewDiagnostics = history
        }
        previewWorker.onModelFailed = { message, identity in
            // 識別子が現在のモデルと一致する場合だけ表示する
            // （旧モデルの失敗が新モデルを上書きしない。R11-03）。
            guard identity.key == previewSessionKey,
                  identity.generation == previewSessionGeneration,
                  identity.version == previewModelVersion
            else { return }
            // 初期化失敗の理由をそのまま表示する（Issue #50）。
            // 旧モデルの画像が残ると理由文より画像が優先表示され、
            // 失敗が見えなくなるため、描画失敗時と同じく画像を消す
            // （FE-R1-024）。
            previewImage = nil
            displayedPreviewIdentity = nil
            displayedPreviewFrame = nil
            previewError = message
        }
    }


    private var currentPreviewIdentity: PreviewRenderWorker.Identity? {
        guard let key = previewSessionKey else { return nil }
        return PreviewRenderWorker.Identity(
            key: key, generation: previewSessionGeneration,
            version: previewModelVersion
        )
    }

    /// 遅延確定を 1 件に集約して登録する（R11-06）。既存の予約は
    /// 取り消して置き換え、セッション切替時は resetPreview で消す。
    /// 発火時に再生状態を再判定するため、再生中に発火してもモデル
    /// には触らない。
    private func scheduleTrailingModelRefresh(delay: TimeInterval = 0.1) {
        // 既に予約がある場合は延期しない（スロットル）。呼ばれる
        // たびに先送りすると、編集が続く間は確定が永遠に来ない
        // デバウンスになる（R12-03）。発火時に予約を空へ戻すため、
        // 連続編集でも一定間隔で最新状態が反映される。
        guard pendingModelRefreshItem == nil else { return }
        let item = DispatchWorkItem {
            pendingModelRefreshItem = nil
            if previewModelDirty { requestPreviewRender(modelChanged: true) }
        }
        pendingModelRefreshItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// 編集モデルのスナップショットを作り直してワーカーへ渡す。
    /// JSON 往復のコストは実プロジェクト（158 アイテム）で約 28 ms
    /// （実測）あるため、連続編集時は 100 ms 未満の間隔では間引き、
    /// 間引いた場合は少し遅れて確実に反映する。生成に失敗した場合は
    /// 理由を利用者へ示し、dirty のまま遅延再試行を予約する
    /// （失敗を無言で消さない。R11-06）。
    private func refreshPreviewModel(force: Bool = false) {
        guard let timeline, previewSessionKey != nil else { return }
        if !force, Date().timeIntervalSince(lastPreviewSnapshotAt) < 0.1 {
            scheduleTrailingModelRefresh()
            return
        }
        let snapshot: (timelines: [Timeline], timeline: Timeline)
        do {
            snapshot = try project.makeExportSnapshot(of: timeline)
        } catch {
            workspace.statusMessage =
                "プレビューモデルの生成に失敗しました: \(error)"
            scheduleTrailingModelRefresh(delay: 0.3)
            return
        }
        lastPreviewSnapshotAt = Date()
        previewModelDirty = false
        previewModelVersion += 1
        // 保留中のサムネイル保存は取り消さない。対象は新しいモデル
        // の同じフレームへ結び直され、その完成通知で発火する
        // （R20-113-01。R12-06 の取消しはモデル変更については
        // 結び直しへ改めた）。
        // 診断の表示も旧モデルのものを持ち越さない。診断の所有者
        // は描画セッション（モデルごとに作り直される）ため、表示
        // 状態もモデル版数の変更でリセットする（R14-02）。
        previewCurrentFailure = false
        previewDiagnostics = []
        guard let identity = currentPreviewIdentity else { return }
        previewWorker.setModel(
            identity: identity, timelines: snapshot.timelines,
            timeline: snapshot.timeline, baseDirectory: baseDirectory
        )
    }

    /// プレビュー再合成の単一の入口（R6-02）。位置の変更と描画要求を
    /// 分離し、全ての経路をここへ集約する。モデルへ触るかどうかは
    /// 要求の属性ではなく実際の再生状態で決める（R11-02）。
    /// - 再生中: モデルには触らず、フレーム要求だけを出す（編集は
    ///   previewModelDirty に残り、停止への遷移時に反映される）。
    /// - 停止中: 編集が入っていればスナップショットを作り直してから
    ///   要求する。
    private func requestPreviewRender(
        usage: TimelineSourceUsage = .paused, modelChanged: Bool = false,
        forceModelRefresh: Bool = false
    ) {
        if modelChanged {
            previewModelDirty = true
            // 未保存フラグはここでは立てない（FE-R32-131-03）。
            // この合流点は遅延プレビュー更新や無変更のドラッグ終了
            // でも通るため、フラグの駆動は履歴変更通知（記録される
            // 編集）と、各操作の成功後の個別の markEdited()（記録
            // されない編集）へ分けた。WorkspaceState 側を参照。
        }
        if isPlayingForm {
            // 再生中はモデルに触らないため、識別子は現在設置済みの
            // もののまま（版数は再生中に上がらない）。
            guard let identity = currentPreviewIdentity else { return }
            previewWorker.request(
                frame: Int(previewFrame), usage: .playing, identity: identity
            )
            return
        }
        if previewModelDirty { refreshPreviewModel(force: forceModelRefresh) }
        // モデルを作り直した場合は版数が上がっているため、識別子は
        // ここで取り直す（要求は発行時点のモデルに結び付く。R12-01）。
        guard let identity = currentPreviewIdentity else { return }
        previewWorker.request(
            frame: Int(previewFrame), usage: usage, identity: identity
        )
    }

    /// 実時間再生エンジンをセッションに合わせて作り直す。
    /// 音声工場の組み立てはアプリ内自動テストと同じ生成パターン
    /// （実ファイル工場＋ボイス供給リゾルバ＋シーン解決）。
    private func resetPlaybackEngine(timeline: Timeline) {
        playbackEngine?.dispose()
        playbackEngine = nil
        peakMeterLeft = .silent
        peakMeterRight = .silent
        loudnessMeterValue = .silent
        let pcmProviderFactory = AVFoundationPCMProviderFactory(
            baseDirectory: baseDirectory
        )
        let timelines = project.timelines
        let factory = AudioSourceFactory(
            providerFactory: pcmProviderFactory,
            sceneTimelineResolver: { id in timelines.first { $0.id == id } },
            voiceProviderResolver: VoicePCMProviderResolver(
                providerFactory: pcmProviderFactory
            ).makeResolver()
        )
        let levelMeter = SoundLevelMeter()
        levelMeter.isSoundLevelMeterEnabled = isPeakMeterEnabled
        levelMeter.isLoudnessMeterEnabled = isLoudnessMeterEnabled
        let source = PlaybackAudioSource(
            mixer: TimelineAudioMixer(timeline: timeline, factory: factory),
            levelMeter: levelMeter
        )
        let engine = RealtimePlaybackEngine(timeline: timeline, source: source)
        engine.volume = volume
        engine.isMuted = isMuted
        engine.playbackRate = playbackRate
        engine.isRepeatEnabled = isRepeatOn
        engine.onPlayingStateChanged = { isPlaying in
            isPlayingForm = isPlaying
            if isPlaying { playbackError = nil }
            if !isPlaying {
                syncMeterValues()
                // 再生中に保留した編集をここで確定する。末尾到達の
                // 自然終了ではこの後の位置通知が来ないため、遷移の
                // 時点で明示的に反映と最終フレーム要求を行う
                // （R11-05）。
                if previewModelDirty {
                    refreshPreviewModel(force: true)
                    requestPreviewRender()
                }
            }
        }
        engine.onStartFailed = { error in
            // 開始失敗の理由をそのまま診断タブへ表示する（R6-03）。
            playbackError = error.userMessage
        }
        engine.onPositionChanged = { [weak engine] _ in
            guard let engine else { return }
            previewFrame = Double(engine.currentFrame)
            requestPreviewRender(
                usage: engine.isPlaying ? .playing : .paused
            )
            syncMeterValues()
        }
        playbackEngine = engine
    }

    /// エンジンのレベルメーターの現在値を表示用に取り込む。
    private func syncMeterValues() {
        guard let meter = playbackEngine?.levelMeter else { return }
        peakMeterLeft = meter.left
        peakMeterRight = meter.right
        loudnessMeterValue = meter.loudness
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
                    onEdited: { requestPreviewRender(modelChanged: true) },
                    onFilePathChanged: { _, newPath in
                        applyFileChange(item: item, newPath: newPath, timeline: timeline)
                    },
                    onFilePathCommitted: {
                        // パスの書き込みが成立した時点で未保存に
                        // する（FE-R33-131-01）。情報取得の成否は
                        // applyFileChange 側で扱い、記録には関与
                        // させない。
                        workspace.markEdited()
                    },
                    editRecorder: workspace.editRecorder,
                    editTargetOwner: item,
                    onPlaybackRateSessionBegan: { descriptor in
                        capturePlaybackRateEditBaseline(
                            descriptor: descriptor, item: item)
                    },
                    onPlaybackRateSessionEnding: { descriptor, baseline, token in
                        finishPlaybackRateEditSession(
                            descriptor: descriptor, baseline: baseline,
                            token: token, item: item, timeline: timeline)
                    }
                )
                EffectInspectorView(
                    item: item,
                    animationContext: context,
                    // エフェクト編集は Undo 記録の対象外のため、編集の
                    // 確定通知で未保存フラグも個別に立てる
                    // （FE-R32-131-03）。
                    onEdited: {
                        requestPreviewRender(modelChanged: true)
                        workspace.markEdited()
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 選択が変わったら各行の入力途中の状態を破棄する。
            // Undo/Redo の適用後も同様に作り直し、表示値をモデルへ
            // 追随させる（FE-UNDO-WIRING）。
            .id("\(selectedItemIndex ?? -1)-\(historyApplyRevision)")
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
    private func runExport(timeline: Timeline, request: ExportRequest) {
        // 書き出し中の再入を関数側でも弾く（FE-R1-007）。開始ボタンの
        // 無効化だけでは、シート再表示などの経路から二重に開始でき、
        // 取消トークンの上書きと供給側（スレッド安全性なし）の
        // 同時実行を招く。
        guard !exportState.isRunning else { return }
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
            request: request,
            cancellation: cancellation,
            state: exportState
        )
        Task.detached { job.run() }
    }

    // MARK: - 診断・往復チェック

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let playbackError {
                Text("再生開始失敗: \(playbackError)")
                    .font(.callout)
            }
            if !previewDiagnostics.isEmpty {
                Text("描画診断（このセッションで発生した効果の失敗）")
                    .font(.callout)
                ForEach(Array(previewDiagnostics.enumerated()), id: \.offset) { _, entry in
                    Text("\(entry.message)（\(entry.count) 回）")
                        .font(.caption)
                }
            }
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
