import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YMM4Core

/// 「動画出力」ダイアログ（本家: ファイル→動画出力）。
///
/// 本家は専用の動画出力設定ウィンドウを開き、右下の「出力」ボタンで
/// 実行する形（UI-WEB-REFERENCE-CHECK.md §2-A6）。出力先と形式の
/// 選択は実動し、「出力」は既存の書き出し実行へ接続する。
/// 音量正規化・コンプレッサの選択肢は形のみ（書き出し側の
/// ExportSettings への反映は接続フェーズ）。
struct ExportDialogView: View {
    let timeline: Timeline
    /// 「出力」確定時に、選択された出力先で呼ばれる。
    var onExport: ((URL) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var outputURL: URL?
    @State private var normalization: Normalization = .none
    @State private var useCompressor = false

    enum Normalization: String, CaseIterable {
        case none = "しない"
        case peak = "ピーク正規化"
        case loudness = "ラウドネス正規化"
    }

    private var defaultFileName: String {
        "output.mp4"
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
                    Text("mp4（H.264 / AAC）")
                        .foregroundStyle(.secondary)
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
                        onExport?(outputURL)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(outputURL == nil)
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.mpeg4Movie]
        panel.nameFieldStringValue = defaultFileName
        if panel.runModal() == .OK {
            outputURL = panel.url
        }
    }
}
