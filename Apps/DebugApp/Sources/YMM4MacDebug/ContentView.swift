import SwiftUI
import UniformTypeIdentifiers
import YMM4Core

/// YMM4Core のデバッグ画面。製品 UI ではなく検証用の殻。
/// - VideoInfo の既定値表示
/// - Animation 評価のスクラブ確認（サンプル）
/// - .ymmp を開いて ProjectView で中身・診断・往復チェックを確認
struct ContentView: View {
    @State private var selectedType: AnimationType = .linear
    @State private var frame: Double = 0
    @State private var isImporterPresented = false
    @State private var loadedProject: Project?
    @State private var loadedDiagnostics: YmmpLoadDiagnostics?
    @State private var loadedURL: URL?
    @State private var loadError: String?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("YMM4 for Mac — デバッグ")
                    .font(.title2)
                    .bold()

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

                GroupBox(".ymmp") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("ファイルを開く…") {
                            isImporterPresented = true
                        }
                        if let loadError {
                            Text(loadError)
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let loadedProject, let loadedDiagnostics, let loadedURL {
                    ProjectView(project: loadedProject, diagnostics: loadedDiagnostics, sourceURL: loadedURL)
                }
            }
            .padding()
        }
        .frame(minWidth: 900, minHeight: 560)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "ymmp") ?? .data]
        ) { result in
            switch result {
            case .success(let url):
                load(url)
            case .failure(let error):
                loadError = "ファイル選択に失敗: \(error)"
            }
        }
    }

    private func load(_ url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let (project, diagnostics) = try YmmpCodec.load(fromFile: url.path)
            loadedProject = project
            loadedDiagnostics = diagnostics
            loadedURL = url
            loadError = nil
        } catch {
            loadError = "読み込みに失敗: \(error)"
        }
    }
}
