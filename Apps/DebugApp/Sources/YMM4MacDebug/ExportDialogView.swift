import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YMM4Core

/// 「動画出力」ダイアログ（本家: ファイル→動画出力）。
///
/// 本家は専用の動画出力設定ウィンドウを開き、右下の「出力」ボタンで
/// 実行する形（UI-WEB-REFERENCE-CHECK.md §2-A6）。出力先と形式の
/// 選択は実動し、「出力」は既存の書き出し実行へ接続する。
/// 形式は MP4（ffmpeg）と PngWav（PNG 連番＋WAV、本家の
/// PngWavFileWriter に対応）の2種（R6-04）。
/// 音量正規化・コンプレッサの選択肢は形のみ（書き出し側の
/// ExportSettings への反映は接続フェーズ）。
struct ExportDialogView: View {
    let timeline: Timeline
    /// PngWav のファイル名接頭辞の初期値（プロジェクト名）。
    let defaultPngWavFileName: String
    /// 「出力」確定時に、選択された形式と出力先で呼ばれる。
    var onExport: ((ExportRequest) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var outputURL: URL?
    @State private var format: ExportFormat = .mp4
    @State private var pngWavFileName: String
    @State private var isPngOutputEnabled = true
    @State private var isWavOutputEnabled = true
    @State private var normalization: Normalization = .none
    @State private var useCompressor = false

    enum ExportFormat: String, CaseIterable {
        case mp4 = "mp4（H.264 / AAC）"
        case pngWav = "PNG+WAV（連番画像と音声）"
    }

    enum Normalization: String, CaseIterable {
        case none = "しない"
        case peak = "ピーク正規化"
        case loudness = "ラウドネス正規化"
    }

    init(
        timeline: Timeline,
        defaultPngWavFileName: String = "untitled",
        onExport: ((ExportRequest) -> Void)? = nil
    ) {
        self.timeline = timeline
        self.defaultPngWavFileName = defaultPngWavFileName
        self.onExport = onExport
        _pngWavFileName = State(initialValue: defaultPngWavFileName)
    }

    private var defaultFileName: String {
        "output.mp4"
    }

    private var canExport: Bool {
        guard outputURL != nil else { return false }
        if format == .pngWav {
            // 本家 PngWav は PNG / WAV のどちらか一方でも出力できる。
            // 両方無効と空の接頭辞は書き出し側が成果物を生まないため
            // ここで止める。
            if !isPngOutputEnabled && !isWavOutputEnabled { return false }
            if pngWavFileName.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("動画出力")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("出力先")
                    HStack(spacing: 6) {
                        Text(outputURL?.path ?? "（未選択）")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("参照…") { chooseOutput() }
                    }
                }
                GridRow {
                    Text("形式")
                    Picker("", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: format) { _, _ in
                        // 出力先の種類（ファイル／フォルダ）が変わるため
                        // 選択し直させる。
                        outputURL = nil
                    }
                }
                if format == .pngWav {
                    GridRow {
                        Text("ファイル名")
                        HStack(spacing: 6) {
                            TextField("", text: $pngWavFileName)
                                .frame(width: 180)
                            Text("＋連番")
                                .foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("出力内容")
                        HStack(spacing: 12) {
                            Toggle("PNG", isOn: $isPngOutputEnabled)
                            Toggle("WAV", isOn: $isWavOutputEnabled)
                        }
                    }
                }
                GridRow {
                    Text("解像度")
                    Text("\(timeline.videoInfo.width)×\(timeline.videoInfo.height) / \(timeline.videoInfo.fps) fps / \(timeline.length) フレーム")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("音量正規化")
                    Picker("", selection: $normalization) {
                        ForEach(Normalization.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                GridRow {
                    Text("コンプレッサ")
                    Toggle("音声コンプレッサを使う", isOn: $useCompressor)
                }
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("出力") {
                    if let outputURL {
                        onExport?(makeRequest(outputURL: outputURL))
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func makeRequest(outputURL: URL) -> ExportRequest {
        switch format {
        case .mp4:
            return .mp4(fileURL: outputURL)
        case .pngWav:
            return .pngWav(
                directoryURL: outputURL,
                settings: PngWavExportSettings(
                    fileName: pngWavFileName.trimmingCharacters(in: .whitespaces),
                    isPngOutputEnabled: isPngOutputEnabled,
                    isWavOutputEnabled: isWavOutputEnabled
                )
            )
        }
    }

    private func chooseOutput() {
        switch format {
        case .mp4:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.mpeg4Movie]
            panel.nameFieldStringValue = defaultFileName
            if panel.runModal() == .OK {
                outputURL = panel.url
            }
        case .pngWav:
            // PngWav の出力先は単一ファイルではなくフォルダ。
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "選択"
            if panel.runModal() == .OK {
                outputURL = panel.url
            }
        }
    }
}
