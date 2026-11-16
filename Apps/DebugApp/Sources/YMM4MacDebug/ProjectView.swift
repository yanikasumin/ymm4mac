import SwiftUI
import YMM4Core

/// 読み込んだ .ymmp の中身を表示するデバッグ画面。
/// タイムラインとアイテムの一覧、VisualItem のアニメーション評価、
/// 読み込み診断（読み飛ばし・型移行）、往復保存の固定点チェックを行う。
struct ProjectView: View {
    let project: Project
    let diagnostics: YmmpLoadDiagnostics
    let sourceURL: URL

    @State private var timelineIndex: Int
    @State private var selectedItemIndex: Int?
    @State private var scrubFrame: Double = 0
    @State private var roundTripResult: String?
    @State private var saveResult: String?

    init(project: Project, diagnostics: YmmpLoadDiagnostics, sourceURL: URL) {
        self.project = project
        self.diagnostics = diagnostics
        self.sourceURL = sourceURL
        _timelineIndex = State(initialValue: project.selectedTimelineIndex)
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
        VStack(alignment: .leading, spacing: 12) {
            Text(sourceURL.lastPathComponent)
                .font(.headline)
            Text(sourceURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 16) {
                Text("タイムライン \(project.timelines.count)")
                Text("キャラクター \(project.characters.count)")
            }
            .font(.callout)

            if let timeline {
                Picker("タイムライン", selection: $timelineIndex) {
                    ForEach(project.timelines.indices, id: \.self) { index in
                        Text(project.timelines[index].name.isEmpty ? "タイムライン \(index + 1)" : project.timelines[index].name)
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: timelineIndex) { _, _ in
                    selectedItemIndex = nil
                    scrubFrame = 0
                }

                let info = timeline.videoInfo
                HStack(spacing: 16) {
                    Text("\(info.width)×\(info.height)")
                    Text("\(info.fps) FPS")
                    Text("\(info.hz) Hz")
                    Text("現在フレーム \(timeline.currentFrame)")
                    Text("アイテム \(timeline.items.count)")
                }
                .font(.callout)

                HStack(alignment: .top, spacing: 16) {
                    List(selection: $selectedItemIndex) {
                        ForEach(Array(timeline.items.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 8) {
                                Text(String(describing: type(of: item)))
                                    .frame(width: 110, alignment: .leading)
                                Text(item.label)
                                    .lineLimit(1)
                                Spacer()
                                Text("F\(item.frame) L\(item.length) Layer\(item.layer) G\(item.group)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .tag(index)
                        }
                    }
                    .frame(minWidth: 380, minHeight: 180)

                    itemDetail(timeline: timeline)
                        .frame(minWidth: 260)
                }
            } else {
                Text("タイムラインがありません")
                    .foregroundStyle(.secondary)
            }

            diagnosticsView
            roundTripView
        }
    }

    @ViewBuilder
    private func itemDetail(timeline: Timeline) -> some View {
        GroupBox("アイテム詳細") {
            if let item = selectedItem {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(describing: type(of: item)))
                        .bold()
                    Text("Frame \(item.frame) / Length \(item.length) / Layer \(item.layer) / Group \(item.group)")
                        .font(.caption)
                    if !item.remark.isEmpty {
                        Text("備考: \(item.remark)")
                            .font(.caption)
                    }
                    if let visual = item as? VisualItem {
                        Divider()
                        Slider(value: $scrubFrame, in: 0...Double(max(item.length, 1)), step: 1)
                        Text("アイテム内フレーム \(Int(scrubFrame))")
                            .font(.caption)
                        let fps = timeline.videoInfo.fps
                        let frame = Int(scrubFrame)
                        Text("X \(visual.x.value(atFrame: frame, length: item.length, fps: fps), specifier: "%.3f")")
                            .monospacedDigit()
                        Text("Y \(visual.y.value(atFrame: frame, length: item.length, fps: fps), specifier: "%.3f")")
                            .monospacedDigit()
                        Text("Z \(visual.z.value(atFrame: frame, length: item.length, fps: fps), specifier: "%.3f")")
                            .monospacedDigit()
                    } else {
                        Text("VisualItem ではないため座標アニメーションはありません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("アイテムを選択してください")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsView: some View {
        GroupBox("読み込み診断") {
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
        }
    }

    private var roundTripView: some View {
        GroupBox("往復チェック") {
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
        }
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
        let directory = sourceURL.deletingLastPathComponent()
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let destination = directory.appendingPathComponent(base + ".roundtrip.ymmp")
        do {
            try YmmpCodec.save(project, toFile: destination.path)
            return "保存しました: \(destination.path)"
        } catch {
            return "保存に失敗: \(error)"
        }
    }
}
