import SwiftUI
import YMM4Core

extension TimelineStripView {
    // MARK: - レイヤーラベル列

    /// ラベル列のコンテンツ。縦位置は専用 NSScrollView がキャンバス側へ
    /// 同期させるため、ここではオフセットを持たず内容の高さだけを決める
    /// （FE-TIMELINE 再構築。従来は表示側が手動オフセットで追従していた）。
    func layerLabels(rowCount: Int, contentHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { layer in
                layerLabel(layer: layer)
            }
        }
        .frame(width: labelWidth, height: contentHeight, alignment: .topLeading)
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
    /// 名前・音量とも LayerSetting へ実書き込みする。音量は Core の
    /// ミキサ（TimelineAudioMixer / GroupAudioBusSource）が
    /// volume / 100 を乗算するため、保存と再生・書き出しの両方に効く
    /// （FE-UNIT5 で接続。従来はローカル状態の形のみだった）。
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
                // スライダの上限は通常の操作範囲 200%。それを超える
                // 値が保存されている場合は、その値まで広げて表示が
                // 実値と食い違わないようにする（本家の値域は
                // 0–10000% で、数値入力欄は持たない形にした）。
                Slider(
                    value: layerVolumeBinding(for: layer),
                    in: 0...max(200, layerVolume(for: layer))
                ) { editing in
                    if !editing { onEdited() }
                }
                Text(volumePercentText(for: layer))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
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

    /// レイヤー全体の音量（%）の現在値（LayerSetting.volume）。
    func layerVolume(for layer: Int) -> Double {
        timeline.layerSettings.setting(forLayer: layer).volume
    }

    /// 音量表示（本家は小数1桁。整数値は小数部なし）。
    func volumePercentText(for layer: Int) -> String {
        let volume = layerVolume(for: layer)
        if volume == volume.rounded() {
            return "\(Int(volume))%"
        }
        return String(format: "%.1f%%", volume)
    }

    /// 音量の読み書きを LayerSetting.volume へ接続するバインディング。
    /// 値域は本家どおり 0–10000% に丸める。
    func layerVolumeBinding(for layer: Int) -> Binding<Double> {
        Binding(
            get: { layerVolume(for: layer) },
            set: { newValue in
                mutateLayerSetting(layer) {
                    $0.volume = min(max(newValue, 0), 10_000)
                }
            }
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
