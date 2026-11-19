import SwiftUI
import UniformTypeIdentifiers
import YMM4Core

/// ワークスペースのルート画面。
/// - 起動直後から新規の空プロジェクト（1920×1080 / 60 FPS / 48,000 Hz）
///   を開いた状態でワークスペース全体を表示する（本家は起動した時点で
///   新規プロジェクトの作業画面が揃っている）。ファイルを開く操作は
///   メニュー／上部バーの一機能として残す
/// - プロジェクトの保持・読み込み・保存は WorkspaceState が担い、
///   メニューコマンド（App の .commands）からも操作できる
/// - VideoInfo の既定値表示と Animation 評価のスクラブ確認（サンプル）は
///   下部の折りたたみ領域に残す（検証用）
struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceState
    @StateObject private var autoTest = AutoTestState()
    @State private var selectedType: AnimationType = .linear
    @State private var frame: Double = 0
    @State private var isSampleExpanded = false
    @State private var hasConsumedAutoTestTrigger = false

    private let totalFrames = 90
    private let videoInfo = VideoInfo()

    private var animation: YMM4Core.Animation {
        YMM4Core.Animation(
            defaultValue: 0,
            minValue: -1000,
            maxValue: 1000,
            animationType: selectedType,
            values: [AnimationValue(0), AnimationValue(100)],
            length: totalFrames,
            videoFPS: videoInfo.fps
        )
    }

    private var evaluatedValue: Double {
        animation.value(atFrame: Int(frame), length: totalFrames, fps: videoInfo.fps)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if autoTest.isRunning || autoTest.report != nil
                || autoTest.errorMessage != nil {
                Divider()
                autoTestSummary
            }

            Divider()

            // 識別子を付けないと、別ファイルを開いても ProjectView の
            // @State（プレビューの合成セッション等）が前のファイルの
            // まま残り、表示が切り替わらない。
            ProjectView(
                project: workspace.project,
                diagnostics: workspace.diagnostics,
                sourceURL: workspace.sourceURL
            )
            .id(workspace.loadSequence)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            samplePanel
        }
        // 既定サイズはシーン側（YMM4MacDebugApp の .defaultSize）が持つ。
        // ここで ideal サイズを指定するとウィンドウのリサイズ可否判定と
        // 競合するため、最小サイズだけを残す。
        .frame(
            minWidth: 1100, maxWidth: .infinity,
            minHeight: 700, maxHeight: .infinity
        )
        .onAppear {
            // 起動時間（プロセス開始→画面表示）の終点を記録する。
            AutoTestEnvironment.recordFirstAppear()
            // 自動実行トリガ（環境変数 / トリガファイル）は起動時に
            // 1回だけ消費する（SSH からの無人検証用）。
            guard !hasConsumedAutoTestTrigger else { return }
            hasConsumedAutoTestTrigger = true
            if let trigger = AutoTestEnvironment.consumeTrigger() {
                autoTest.run(workspace: workspace, trigger: trigger)
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { workspace.isImporterPresented },
                set: { workspace.isImporterPresented = $0 }
            ),
            allowedContentTypes: [UTType(filenameExtension: "ymmp") ?? .data]
        ) { result in
            switch result {
            case .success(let url):
                workspace.load(url: url)
            case .failure(let error):
                workspace.loadError = "ファイル選択に失敗: \(error)"
            }
        }
        .alert(
            "YMM4 for Mac",
            isPresented: Binding(
                get: { workspace.isAboutPresented },
                set: { workspace.isAboutPresented = $0 }
            )
        ) {
            Button("OK") {}
        } message: {
            Text("YMM4 for Mac（デバッグ版）\n本家 YMM4 v4.55.1.1 のフロントエンド再現シェル")
        }
    }

    // MARK: - 上部バー

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("YMM4 for Mac — デバッグ")
                    .font(.title3)
                    .bold()
                Spacer()
                Button("全自動テスト") {
                    autoTest.run(workspace: workspace, trigger: "button")
                }
                .disabled(autoTest.isRunning)
                Button("新規プロジェクト") {
                    workspace.newProject()
                }
                Button("ファイルを開く…") {
                    workspace.requestOpenProject()
                }
            }
            if let loadError = workspace.loadError {
                Text(loadError)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let statusMessage = workspace.statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 全自動テストの要約

    /// 全自動テストの結果要約（測定値の正本はレポートファイル側。
    /// ここは画面での目視確認用）。
    private var autoTestSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            if autoTest.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("全自動テストを実行中…")
                        .font(.callout)
                }
            }
            if let errorMessage = autoTest.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let report = autoTest.report {
                ForEach(
                    Array(report.summaryLines.enumerated()), id: \.offset
                ) { _, line in
                    Text(line)
                        .font(.callout)
                        .monospacedDigit()
                }
                if let reportFilePath = autoTest.reportFilePath {
                    Text("レポート: \(reportFilePath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 検証サンプル（折りたたみ）

    private var samplePanel: some View {
        DisclosureGroup(
            "検証サンプル（VideoInfo 既定値 / Animation 評価）",
            isExpanded: $isSampleExpanded
        ) {
            HStack(alignment: .top, spacing: 16) {
                GroupBox("VideoInfo（既定値）") {
                    HStack(spacing: 24) {
                        Text("\(videoInfo.width)×\(videoInfo.height)")
                        Text("\(videoInfo.fps) FPS")
                        Text("\(videoInfo.hz) Hz")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Animation 評価（サンプル）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("種別", selection: $selectedType) {
                            Text("直線移動").tag(AnimationType.linear)
                            Text("瞬間移動").tag(AnimationType.instant)
                            Text("補間移動").tag(AnimationType.interpolation)
                            Text("加減速移動").tag(AnimationType.accelerationDeceleration)
                            Text("Quad In（_Int）").tag(AnimationType.quadInInt)
                            Text("Quad In").tag(AnimationType.quadIn)
                            Text("反復移動").tag(AnimationType.repetitive)
                            Text("ランダム移動").tag(AnimationType.random)
                        }
                        .pickerStyle(.menu)

                        Slider(value: $frame, in: 0...Double(totalFrames), step: 1)
                        HStack {
                            Text("フレーム \(Int(frame)) / \(totalFrames)")
                            Spacer()
                            Text("評価値 \(evaluatedValue, specifier: "%.4f")")
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 420, maxWidth: .infinity)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
