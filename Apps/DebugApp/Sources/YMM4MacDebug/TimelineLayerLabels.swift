import SwiftUI
import YMM4Core

extension TimelineStripView {
    // MARK: - レイヤーラベル列

    func layerLabels(rowCount: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { layer in
                layerLabel(layer: layer)
            }
        }
        .offset(y: -verticalOffset)
        .frame(width: labelWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    func layerLabel(layer: Int) -> some View {
        let setting = timeline.layerSettings.setting(forLayer: layer)
        let hasColor = setting.color.alpha > 0
        return HStack(spacing: 2) {
            if hasColor {
                Rectangle()
                    .fill(swiftUIColor(setting.color))
                    .frame(width: 4, height: rowHeight - 8)
            }
            Text(setting.label ?? UIStrings.Timeline.defaultLayerLabel(layer))
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 0)
            // 表示切替（本家はラベル部のクリック操作。ここでは目アイコンの
            // ボタンで切り替える。LayerSetting への書き込みは実接続）。
            // 表示状態はプレビュー合成の対象選定に効くため、切替のたびに
            // 再合成を要求する（FE-R1-014）。
            Button {
                mutateLayerSetting(layer) { $0.isHidden.toggle() }
                onEdited()
            } label: {
                Image(systemName: setting.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(setting.isHidden ? .primary : .secondary)
            .help(setting.isHidden ? UIStrings.Timeline.showLayer : UIStrings.Timeline.hideLayer)
            // レイヤー操作メニュー（名前・背景色・音量・追加/削除）。
            Menu {
                Button(UIStrings.Timeline.renameLayer) { openLayerPopover(layer: layer) }
                Menu(UIStrings.Timeline.layerBackgroundColor) {
                    Button(UIStrings.Common.none) {
                        mutateLayerSetting(layer) {
                            $0.color = YMM4Core.Color(alpha: 0, red: 0, green: 0, blue: 0)
                        }
                    }
                    ForEach(Self.layerColorPresets, id: \.name) { preset in
                        Button(preset.name) {
                            mutateLayerSetting(layer) { $0.color = preset.color }
                        }
                    }
                }
                Button(UIStrings.Timeline.layerVolume) { openLayerPopover(layer: layer) }
                Divider()
                Button(UIStrings.Timeline.addLayerAbove) { insertLayer(at: layer) }
                Button(UIStrings.Timeline.addLayerBelow) { insertLayer(at: layer + 1) }
                Button(UIStrings.Timeline.deleteLayer) { deleteLayer(at: layer) }
                Divider()
                Button(setting.isHidden ? UIStrings.Timeline.showLayer : UIStrings.Timeline.hideLayer) {
                    mutateLayerSetting(layer) { $0.isHidden.toggle() }
                    onEdited()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 14)
            .help(UIStrings.Timeline.layerOperations)
        }
        .padding(.horizontal, 4)
        .frame(width: labelWidth, height: rowHeight, alignment: .leading)
        .background(
            setting.isHidden
                ? Color.primary.opacity(0.07)
                : (hasColor ? swiftUIColor(setting.color).opacity(0.18) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        // レイヤーラベルのコンテキストメニュー（本家 layerContextMenu
        // 13葉 — UI-FACTS-MENUS-CONTEXT.md §2.3。切り取り／コピー／
        // 貼り付けはレイヤー用クリップボードが無いため未収録）。
        .contextMenu {
            Button(UIStrings.Timeline.selectLayerItems) {
                selectItems { $0.layer == layer }
            }
            Divider()
            Button(UIStrings.Timeline.addLayerAbove) { insertLayer(at: layer) }
            Button(UIStrings.Timeline.addLayerBelow) { insertLayer(at: layer + 1) }
            Button(UIStrings.Timeline.deleteLayer) { deleteLayer(at: layer) }
            Divider()
            Button(UIStrings.Timeline.moveLayerUp) { swapLayers(layer, layer - 1) }
                .disabled(layer <= 0)
            Button(UIStrings.Timeline.moveLayerDown) { swapLayers(layer, layer + 1) }
            Divider()
            Button(setting.isHidden ? UIStrings.Timeline.showLayer : UIStrings.Timeline.hideLayer) {
                mutateLayerSetting(layer) { $0.isHidden.toggle() }
                onEdited()
            }
            Button(UIStrings.Timeline.enableAllLayers) {
                for index in timeline.layerSettings.items.indices {
                    timeline.layerSettings.items[index].isHidden = false
                }
                layerRevision += 1
                onEdited()
            }
            Button(UIStrings.Timeline.disableOtherLayers) {
                // 対象レイヤー以外を全て非表示にする。設定が無い
                // レイヤーは既定で表示のため、表示中レイヤー分は
                // 設定を作ってから非表示にする。
                let visibleLayers = Set(
                    timeline.items.map { $0.layer }
                ).union(timeline.layerSettings.items.map { $0.layer })
                for other in visibleLayers where other != layer {
                    mutateLayerSetting(other) { $0.isHidden = true }
                }
                mutateLayerSetting(layer) { $0.isHidden = false }
                onEdited()
            }
            Divider()
            Button(UIStrings.Timeline.resetLayerSettings) {
                timeline.layerSettings.items.removeAll()
                layerRevision += 1
                onEdited()
            }
            Divider()
            Button(UIStrings.Timeline.renameLayer) { openLayerPopover(layer: layer) }
        }
        .popover(isPresented: layerPopoverBinding(for: layer)) {
            layerPopover(layer: layer)
        }
    }

    /// レイヤー設定を書き換える（無ければ既定値から作って登録する）。
    /// Core の LayerSettings は参照型で items が公開されているため、
    /// ビュー側から直接書き換えられる。
    func mutateLayerSetting(_ layer: Int, _ mutate: (inout LayerSetting) -> Void) {
        var setting = timeline.layerSettings.setting(forLayer: layer)
        mutate(&setting)
        if let index = timeline.layerSettings.items.firstIndex(where: { $0.layer == layer }) {
            timeline.layerSettings.items[index] = setting
        } else {
            timeline.layerSettings.items.append(setting)
        }
        layerRevision += 1
    }

    func openLayerPopover(layer: Int) {
        let setting = timeline.layerSettings.setting(forLayer: layer)
        layerRenameText = setting.label ?? ""
        layerPopoverLayer = layer
    }

    func layerPopoverBinding(for layer: Int) -> Binding<Bool> {
        Binding(
            get: { layerPopoverLayer == layer },
            set: { if !$0, layerPopoverLayer == layer { layerPopoverLayer = nil } }
        )
    }

    /// 名前変更とレイヤー全体の音量のポップオーバー。
    /// 名前は LayerSetting へ実書き込み。音量は Core に保持先が無いため
    /// 形のみ（ローカル状態）。
    func layerPopover(layer: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UIStrings.Timeline.layerSettingsTitle(layer))
                .font(.headline)
            HStack {
                Text(UIStrings.Timeline.layerName)
                    .frame(width: 44, alignment: .leading)
                TextField(UIStrings.Timeline.layerNamePlaceholder, text: $layerRenameText)
                    .onSubmit { commitLayerRename(layer: layer) }
                Button(UIStrings.Timeline.apply) { commitLayerRename(layer: layer) }
            }
            HStack {
                Text(UIStrings.Timeline.volume)
                    .frame(width: 44, alignment: .leading)
                Slider(value: layerVolumeBinding(for: layer), in: 0...200)
                Text("\(Int(layerVolumes[layer] ?? 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            HStack {
                Spacer()
                Button(UIStrings.Common.close) { layerPopoverLayer = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    func commitLayerRename(layer: Int) {
        let name = layerRenameText.trimmingCharacters(in: .whitespaces)
        mutateLayerSetting(layer) { $0.label = name.isEmpty ? nil : name }
    }

    func layerVolumeBinding(for layer: Int) -> Binding<Double> {
        Binding(
            get: { layerVolumes[layer] ?? 100 },
            set: { layerVolumes[layer] = $0 }
        )
    }

    /// 背景色プリセット（本家は任意色を選べる。ここでは代表色のみ）。
    private static let layerColorPresets: [(name: String, color: YMM4Core.Color)] = [
        ("赤", YMM4Core.Color(alpha: 255, red: 213, green: 0, blue: 0)),
        ("橙", YMM4Core.Color(alpha: 255, red: 230, green: 126, blue: 34)),
        ("黄", YMM4Core.Color(alpha: 255, red: 220, green: 200, blue: 0)),
        ("緑", YMM4Core.Color(alpha: 255, red: 0, green: 170, blue: 60)),
        ("青", YMM4Core.Color(alpha: 255, red: 0, green: 0, blue: 213)),
        ("紫", YMM4Core.Color(alpha: 255, red: 140, green: 0, blue: 200)),
    ]
}
