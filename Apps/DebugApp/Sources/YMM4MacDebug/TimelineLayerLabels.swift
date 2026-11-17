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
            Text(setting.label ?? String(format: "レイヤー %02d", layer))
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 0)
            // 表示切替（本家はラベル部のクリック操作。ここでは目アイコンの
            // ボタンで切り替える。LayerSetting への書き込みは実接続）。
            Button {
                mutateLayerSetting(layer) { $0.isHidden.toggle() }
            } label: {
                Image(systemName: setting.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(setting.isHidden ? .primary : .secondary)
            .help(setting.isHidden ? "レイヤーを表示" : "レイヤーを非表示")
            // レイヤー操作メニュー（名前・背景色・音量・追加/削除）。
            Menu {
                Button("名前を変更…") { openLayerPopover(layer: layer) }
                Menu("背景色") {
                    Button("なし") {
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
                Button("レイヤー全体の音量…") { openLayerPopover(layer: layer) }
                Divider()
                Button(setting.isHidden ? "レイヤーを表示" : "レイヤーを非表示") {
                    mutateLayerSetting(layer) { $0.isHidden.toggle() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 14)
            .help("レイヤー操作")
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
        .contextMenu {
            Button(setting.isHidden ? "レイヤーを表示" : "レイヤーを非表示") {
                mutateLayerSetting(layer) { $0.isHidden.toggle() }
            }
            Divider()
            // レイヤーの追加/削除はアイテムの付け替えを伴うため未接続。
            Button("レイヤーを追加") {}
            Button("レイヤーを削除") {}
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
            Text("レイヤー \(layer) の設定")
                .font(.headline)
            HStack {
                Text("名前")
                    .frame(width: 44, alignment: .leading)
                TextField("レイヤー名", text: $layerRenameText)
                    .onSubmit { commitLayerRename(layer: layer) }
                Button("設定") { commitLayerRename(layer: layer) }
            }
            HStack {
                Text("音量")
                    .frame(width: 44, alignment: .leading)
                Slider(value: layerVolumeBinding(for: layer), in: 0...200)
                Text("\(Int(layerVolumes[layer] ?? 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            HStack {
                Spacer()
                Button("閉じる") { layerPopoverLayer = nil }
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
