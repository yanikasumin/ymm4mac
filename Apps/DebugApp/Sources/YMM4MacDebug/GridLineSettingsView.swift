import SwiftUI
import YMM4Core

/// 「グリッド線の設定」シート（本家 TimelineVerticalLineSettingsView）。
///
/// 対象は編集中タイムラインの `TimelineVerticalLine` そのもの。
/// 項目と値域は本家どおり（種別 BPM / Frame / Time、開始フレーム、
/// グループ）。本家はモデルへの直接バインドで即時反映だが、こちらは
/// 「動画の設定」と同じく OK で一括適用する形に揃える（差異として
/// 台帳に記録）。種別を変えると線はその種別の既定へ差し替わる
/// （本家の LineType setter と同じ意味論が Core 側にある）。
struct GridLineSettingsView: View {
    let timeline: Timeline
    /// 適用後に呼ばれる（タイムラインの再描画等）。
    var onApplied: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isEnabled: Bool
    /// 種別の選択（Core の VerticalLineType は Hashable でないため、
    /// 本家名の文字列で保持し、使うときに変換する）。
    @State private var lineTypeName: String
    @State private var bpmText: String
    @State private var frameText: String
    @State private var spanText: String
    @State private var startFrameText: String
    @State private var groupText: String
    @State private var errorText: String?

    init(timeline: Timeline, onApplied: (() -> Void)? = nil) {
        self.timeline = timeline
        self.onApplied = onApplied
        let line = timeline.verticalLine
        _isEnabled = State(initialValue: line.isEnabled)
        // 未知の種別は本家に存在しないため、BPM として扱う。
        if case .unknown = line.lineType {
            _lineTypeName = State(initialValue: VerticalLineType.bpm.honkeName)
        } else {
            _lineTypeName = State(initialValue: line.lineType.honkeName)
        }
        _bpmText = State(initialValue: Self.bpmText(from: line.bpm))
        _frameText = State(initialValue: "\(line.frameInterval)")
        _spanText = State(
            initialValue: TimelineVerticalLine.timeSpanString(
                fromTicks: line.spanTicks
            )
        )
        _startFrameText = State(initialValue: "\(line.startFrame)")
        _groupText = State(initialValue: "\(line.group)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.Toolbar.gridLineSettingsTitle)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("表示")
                    Toggle(UIStrings.Toolbar.gridLine, isOn: $isEnabled)
                        .labelsHidden()
                }
                GridRow {
                    Text("間隔の種別")
                    Picker("", selection: $lineTypeName) {
                        Text("BPM").tag(VerticalLineType.bpm.honkeName)
                        Text("フレーム").tag(VerticalLineType.frame.honkeName)
                        Text("時間").tag(VerticalLineType.time.honkeName)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                GridRow {
                    Text(valueLabel)
                    switch lineType {
                    case .bpm:
                        HStack(spacing: 6) {
                            TextField("BPM", text: $bpmText)
                                .frame(width: 100)
                            Text("bpm（1–99999）")
                                .foregroundStyle(.secondary)
                        }
                    case .frame:
                        HStack(spacing: 6) {
                            TextField("フレーム", text: $frameText)
                                .frame(width: 100)
                            Text("f（1–99999）")
                                .foregroundStyle(.secondary)
                        }
                    case .time:
                        HStack(spacing: 6) {
                            TextField("時間", text: $spanText)
                                .frame(width: 140)
                            Text("（時:分:秒）")
                                .foregroundStyle(.secondary)
                        }
                    case .unknown:
                        Text("—")
                    }
                }
                GridRow {
                    Text("開始フレーム")
                    HStack(spacing: 6) {
                        TextField("開始フレーム", text: $startFrameText)
                            .frame(width: 100)
                        Text("f（−99999–99999）")
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("グループ")
                    HStack(spacing: 6) {
                        TextField("グループ", text: $groupText)
                            .frame(width: 100)
                        Text("本ごとに太線（0–99999）")
                            .foregroundStyle(.secondary)
                    }
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
        .frame(width: 400)
    }

    /// 選択中の種別（本家名から変換）。
    private var lineType: VerticalLineType {
        VerticalLineType(honkeName: lineTypeName)
    }

    private var valueLabel: String {
        switch lineType {
        case .bpm: return "BPM"
        case .frame: return "間隔"
        case .time: return "間隔"
        case .unknown: return "間隔"
        }
    }

    private func apply() {
        guard let startFrame = Int(startFrameText),
              let group = Int(groupText) else {
            errorText = "開始フレームとグループには数値を入力してください"
            return
        }
        var line = timeline.verticalLine
        // 種別を先に確定させる（setter が線を種別の既定へ差し替える
        // ため、パラメータの書き込みはその後に行う）。
        line.lineType = lineType
        switch lineType {
        case .bpm:
            guard let bpm = Double(bpmText) else {
                errorText = "BPM には数値を入力してください"
                return
            }
            line.bpm = min(max(bpm, 1), 99_999)
        case .frame:
            guard let interval = Int(frameText) else {
                errorText = "間隔には数値を入力してください"
                return
            }
            line.frameInterval = min(max(interval, 1), 99_999)
        case .time:
            guard let ticks = TimelineVerticalLine.ticks(
                fromTimeSpanString: spanText
            ), ticks > 0 else {
                errorText = "間隔には正の時間を入力してください（例: 00:00:00.5）"
                return
            }
            line.spanTicks = ticks
        case .unknown:
            break
        }
        line.startFrame = min(max(startFrame, -99_999), 99_999)
        line.group = min(max(group, 0), 99_999)
        line.isEnabled = isEnabled
        timeline.verticalLine = line
        onApplied?()
        dismiss()
    }

    /// BPM の表示形（整数値は小数部なし、それ以外は最短表記）。
    private static func bpmText(from value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return "\(Int(value))"
        }
        return "\(value)"
    }
}
