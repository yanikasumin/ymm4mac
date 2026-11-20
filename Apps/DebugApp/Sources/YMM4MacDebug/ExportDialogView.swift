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
/// 音量正規化・コンプレッサの選択は、書き出し要求を通じて
/// `TimelineExporter` の初期化引数（Core の
/// `LoudnessNormalizationSettings` / `CompressorSettings`）へ渡り、
/// 音声供給側の解析とダイナミクス処理へ実際に効く（FE-R1-017）。
/// 本家では両設定は永続設定（設定画面側）だが、こちらでは書き出し
/// ごとの選択としてダイアログに置く（差異として台帳に記録）。
struct ExportDialogView: View {
    let timeline: Timeline
    /// PngWav のファイル名接頭辞の初期値（プロジェクト名）。
    let defaultPngWavFileName: String
    /// 書き出し実行中か。実行中は「出力」を開始できない
    /// （FE-R1-007。開始関数側のガードと対で置く）。
    var isExportRunning: Bool = false
    /// 「出力」確定時に、選択された形式と出力先で呼ばれる。
    var onExport: ((ExportRequest) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var outputURL: URL?
    @State private var format: ExportFormat = .mp4
    @State private var pngWavFileName: String
    @State private var isPngOutputEnabled = true
    @State private var isWavOutputEnabled = true
    // 初期値は、未接続だった間も書き出し側で実際に効いていた値
    // （TimelineExporter の既定 = 本家の設定既定: 正規化は
    // DownMaximumVolume、コンプレッサは Auto で有効）に合わせる。
    // 形だけの初期値（しない／使わない）のままだと、配線した途端に
    // 既定の書き出し結果が黙って変わってしまうため（FE-R1-017）。
    @State private var normalization: Normalization = .peak
    @State private var useCompressor = true

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
        isExportRunning: Bool = false,
        onExport: ((ExportRequest) -> Void)? = nil
    ) {
        self.timeline = timeline
        self.defaultPngWavFileName = defaultPngWavFileName
        self.isExportRunning = isExportRunning
        self.onExport = onExport
        _pngWavFileName = State(initialValue: defaultPngWavFileName)
    }

    private var defaultFileName: String {
        "output.mp4"
    }

    private var canExport: Bool {
        guard !isExportRunning else { return false }
        guard outputURL != nil else { return false }
        if format == .pngWav {
            // 本家 PngWav は PNG / WAV のどちらか一方でも出力できる。
            // 両方無効と空の接頭辞は書き出し側が成果物を生まないため
            // ここで止める。接頭辞の安全性（単一のファイル名成分か）は
            // ライター側の検証と同じ述語で判定する（R10-01）。
            if !isPngOutputEnabled && !isWavOutputEnabled { return false }
            if !PngWavFileWriter.isValidFileName(
                pngWavFileName.trimmingCharacters(in: .whitespaces)
            ) { return false }
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

    /// ダイアログの3択を Core の補正モードへ写す。本家の表示名は
    /// しない=「音量調整しない」、ピーク=「最大音量を0dB以下にする」
    /// （DownMaximumVolume）、ラウドネス=「目標音量にする」（Both、
    /// 目標は Core 既定の −15 LKFS）。
    private var loudnessSettings: LoudnessNormalizationSettings {
        switch normalization {
        case .none:
            return LoudnessNormalizationSettings(mode: .disabled)
        case .peak:
            return LoudnessNormalizationSettings(mode: .downMaximumVolume)
        case .loudness:
            return LoudnessNormalizationSettings(mode: .both)
        }
    }

    /// コンプレッサの入切。使う場合は Core 既定（倍率はピークから
    /// 自動計算）、使わない場合は倍率決定モードだけを無効にする。
    private var compressorSettings: CompressorSettings {
        useCompressor
            ? CompressorSettings()
            : CompressorSettings(ratioMode: .disabled)
    }

    private func makeRequest(outputURL: URL) -> ExportRequest {
        switch format {
        case .mp4:
            return .mp4(
                fileURL: outputURL,
                loudness: loudnessSettings,
                compressor: compressorSettings
            )
        case .pngWav:
            return .pngWav(
                directoryURL: outputURL,
                settings: PngWavExportSettings(
                    fileName: pngWavFileName.trimmingCharacters(in: .whitespaces),
                    isPngOutputEnabled: isPngOutputEnabled,
                    isWavOutputEnabled: isWavOutputEnabled
                ),
                loudness: loudnessSettings,
                compressor: compressorSettings
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
