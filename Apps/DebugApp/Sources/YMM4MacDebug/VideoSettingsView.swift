import AppKit
import SwiftUI
import YMM4Core

/// 「動画の設定」ダイアログ（本家: ファイル→動画の設定）。
///
/// 解像度・フレームレート・サンプリングレート・背景色を変更する
/// プロファイル画面の再現。適用は `Timeline.videoInfo` への実書き込みで、
/// 値域は本家の Range 属性（`VideoInfo` の有効範囲）に丸める。
/// 根拠: UI-LAYOUT-FACTS.md §4（ステータスバーの映像情報ボタンが
/// この画面を開く）および UI-WEB-REFERENCE-CHECK.md §2-A7。
struct VideoSettingsView: View {
    let timeline: Timeline
    /// 適用後に呼ばれる（プレビューの作り直し等）。
    var onApplied: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var widthText: String
    @State private var heightText: String
    @State private var fpsText: String
    @State private var sampleRate: Int
    @State private var background: SwiftUI.Color
    @State private var errorText: String?

    /// サンプリングレートの候補（現在の値が含まれない場合は足す）。
    private var sampleRateOptions: [Int] {
        let base = [32_000, 44_100, 48_000, 88_200, 96_000, 192_000]
        return base.contains(sampleRate) ? base : (base + [sampleRate]).sorted()
    }

    init(timeline: Timeline, onApplied: (() -> Void)? = nil) {
        self.timeline = timeline
        self.onApplied = onApplied
        let info = timeline.videoInfo
        _widthText = State(initialValue: "\(info.width)")
        _heightText = State(initialValue: "\(info.height)")
        _fpsText = State(initialValue: "\(info.fps)")
        _sampleRate = State(initialValue: info.hz)
        _background = State(initialValue: swiftUIColor(info.backgroundColor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("動画の設定")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("解像度")
                    HStack(spacing: 6) {
                        TextField("幅", text: $widthText)
                            .frame(width: 70)
                        Text("×")
                        TextField("高さ", text: $heightText)
                            .frame(width: 70)
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("フレームレート")
                    HStack(spacing: 6) {
                        TextField("fps", text: $fpsText)
                            .frame(width: 70)
                        Text("fps（1–240）")
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("サンプリングレート")
                    Picker("", selection: $sampleRate) {
                        ForEach(sampleRateOptions, id: \.self) { rate in
                            Text("\(rate) Hz").tag(rate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                GridRow {
                    Text("背景色")
                    ColorPicker("", selection: $background, supportsOpacity: true)
                        .labelsHidden()
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func apply() {
        guard let width = Int(widthText), let height = Int(heightText),
              let fps = Int(fpsText) else {
            errorText = "解像度とフレームレートには数値を入力してください"
            return
        }
        var info = timeline.videoInfo
        info.width = min(max(width, VideoInfo.widthRange.lowerBound), VideoInfo.widthRange.upperBound)
        info.height = min(max(height, VideoInfo.heightRange.lowerBound), VideoInfo.heightRange.upperBound)
        info.fps = min(max(fps, VideoInfo.fpsRange.lowerBound), VideoInfo.fpsRange.upperBound)
        info.hz = min(max(sampleRate, VideoInfo.hzRange.lowerBound), VideoInfo.hzRange.upperBound)
        info.backgroundColor = coreColor(from: background)
        // 実際に変わる場合だけ代入と適用通知を行う。無変更のまま OK を
        // 押しても未保存フラグを立てないため（FE-INT-131-01 の洗い出しで
        // 記録した同型の処分）。クランプで現在値へ戻る入力も、組み立て後の
        // 比較では同値になるため無変更として扱われる。
        if info != timeline.videoInfo {
            timeline.videoInfo = info
            onApplied?()
        }
        dismiss()
    }

    /// SwiftUI.Color を YMM4Core.Color（ARGB 0–255）へ変換する。
    private func coreColor(from swiftColor: SwiftUI.Color) -> YMM4Core.Color {
        let ns = NSColor(swiftColor).usingColorSpace(.sRGB) ?? .black
        func byte(_ component: CGFloat) -> UInt8 {
            UInt8(min(max((component * 255).rounded(), 0), 255))
        }
        return YMM4Core.Color(
            alpha: byte(ns.alphaComponent),
            red: byte(ns.redComponent),
            green: byte(ns.greenComponent),
            blue: byte(ns.blueComponent)
        )
    }
}
