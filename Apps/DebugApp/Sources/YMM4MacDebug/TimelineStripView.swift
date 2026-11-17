import SwiftUI
import YMM4Core

/// 本家 TimelineView の配置を再現したタイムライン帯（デバッグ用の殻）。
///
/// 配置の根拠は `analysis-notes/UI-LAYOUT-FACTS.md` §5（本家 v4.55.1.1 の
/// 実コード解析）:
/// - 目盛り帯の高さ 26、その左に幅80のレイヤーラベル列
/// - レイヤー行の高さは LayerHeight 既定値 32
/// - ズームは TimelineZoom（既定100 = 1px/フレーム）。目盛り間隔は
///   「約13px分のフレーム数」を目標に典型間隔へ寄せる本家の規則
/// - 目盛りの時刻ラベルは大目盛り（10本ごと）にのみ `hh:mm:ss.ff`
/// - 再生ヘッドは赤（#FFFF0000）幅1の線を目盛りとキャンバスに通す
/// - アイテムブロックは上端4pxをキーフレーム帯として空け、背景は
///   アイテム色（種別既定色／キャラクター色）で塗る。非表示は DarkGray、
///   選択時は白の破線枠、キーフレームは上端帯の赤い三角形
///
/// 本家との差（殻としての割り切り）:
/// - アイテムのドラッグ移動・リサイズは未接続（選択とシークのみ）
/// - 波形は形のみ: 音声デコード前のため、実波形ではなく決定的な
///   疑似波形を描く（接続時に実データへ差し替える）
/// - 背景グラデーションは本家の生成規則が未確定のため単色で塗る
/// - 目盛りと縦グリッド線は可視範囲分だけ描く（本家も仮想化している）
struct TimelineStripView: View {
    let timeline: Timeline
    /// 現在フレーム（再生ヘッド位置）。
    let currentFrame: Int
    @Binding var selectedItemIndex: Int?
    /// ルーラー／キャンバス背景のクリック・ドラッグで呼ばれるシーク。
    let onSeek: (Int) -> Void

    /// 本家 TimelineZoom 相当（100 = 1px/フレーム）。
    /// タイムラインのツールバー行からも操作するため外からバインドする。
    @Binding var zoomPercent: Double
    /// 本家 LayerHeight 相当（既定32、下限14）。ツールバー行の
    /// レイヤー高さボタンから変更できるよう外から渡す。
    var rowHeight: CGFloat = 32
    /// 波形表示の有無（本家の「波形を表示/非表示」相当）。
    var showWaveform: Bool = true
    /// キャンバスの表示幅をツールバー側（全体フィット計算用）へ伝える。
    @Binding var reportedCanvasWidth: CGFloat
    @State private var horizontalOffset: CGFloat = 0
    @State private var verticalOffset: CGFloat = 0
    /// レイヤー設定の変更を再描画へ反映させるための世代カウンタ。
    @State private var layerRevision = 0
    /// レイヤー操作ポップオーバー（名前変更・音量）の対象レイヤー。
    @State private var layerPopoverLayer: Int?
    @State private var layerRenameText = ""
    /// レイヤー全体の音量（%）。Core の LayerSetting には音量が無いため
    /// 形のみのローカル状態（接続台帳に記録）。
    @State private var layerVolumes: [Int: Double] = [:]

    private let labelWidth: CGFloat = 80
    private let rulerHeight: CGFloat = 26
    /// 目盛り帯右端のフィラー幅（本家の横スクロールバー幅ぶん）。
    private let rulerFillerWidth: CGFloat = 17

    private var pxPerFrame: CGFloat { CGFloat(zoomPercent) / 100 }
    private var contentWidth: CGFloat {
        max(CGFloat(timeline.length) * pxPerFrame, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let rowsViewportHeight = max(geometry.size.height - rulerHeight - 1, rowHeight)
            let rowCount = max(
                timeline.maxLayer + 2,
                Int(ceil(rowsViewportHeight / rowHeight))
            )
            let contentHeight = CGFloat(rowCount) * rowHeight
            let rulerViewportWidth = max(
                geometry.size.width - labelWidth - rulerFillerWidth, 1
            )
            let canvasViewportWidth = max(geometry.size.width - labelWidth, 1)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // 目盛り帯の左上隅（ラベル列の上）。
                    Text("レイヤー")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, height: rulerHeight)

                    ruler(viewportWidth: rulerViewportWidth)

                    // ズーム操作子は本家どおりツールバー側に置くため、
                    // ここは横スクロールバー幅ぶんのフィラー。
                    Color.clear
                        .frame(width: rulerFillerWidth, height: rulerHeight)
                }

                Divider()

                HStack(spacing: 0) {
                    layerLabels(rowCount: rowCount)
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                    canvas(
                        rowCount: rowCount,
                        contentHeight: contentHeight,
                        viewportWidth: canvasViewportWidth
                    )
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(proxy.size.width - labelWidth - 1, 1)
            } action: { _, newValue in
                reportedCanvasWidth = newValue
            }
        }
    }

    // MARK: - 目盛り

    private func ruler(viewportWidth: CGFloat) -> some View {
        let span = tickSpan()
        let firstIndex = max(
            0, Int(Double(horizontalOffset / pxPerFrame) / Double(span)) - 2
        )
        let lastFrame = min(
            timeline.length,
            Int((horizontalOffset + viewportWidth) / pxPerFrame) + span * 2
        )
        let ticks: [(index: Int, frame: Int)] = stride(
            from: firstIndex, through: max(firstIndex, lastFrame / span), by: 1
        ).map { (index: $0, frame: $0 * span) }

        return ZStack(alignment: .topLeading) {
            Color(nsColor: .controlBackgroundColor)

            // 目盛り本体。キャンバスの横スクロール量だけ左へずらし、
            // 枠側でクリップして追従させる（目盛り自体はスクロールしない）。
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.index) { tick in
                    let isLarge = tick.index % 10 == 0
                    let isMiddle = tick.index % 5 == 0
                    let tickHeight: CGFloat = isLarge ? 10 : (isMiddle ? 7 : 4)
                    Rectangle()
                        .fill(Color.primary.opacity(isLarge ? 1 : 0.7))
                        .frame(width: 1, height: tickHeight)
                        .offset(
                            x: CGFloat(tick.frame) * pxPerFrame,
                            y: rulerHeight - tickHeight
                        )
                    if isLarge {
                        Text(timeText(frame: tick.frame))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .offset(x: CGFloat(tick.frame) * pxPerFrame + 3, y: 1)
                    }
                }

                // 再生ヘッド（目盛り側）。
                Rectangle()
                    .fill(Color(red: 1, green: 0, blue: 0))
                    .frame(width: 1, height: rulerHeight)
                    .offset(x: CGFloat(currentFrame) * pxPerFrame)
            }
            .frame(width: contentWidth, height: rulerHeight, alignment: .topLeading)
            .offset(x: -horizontalOffset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: rulerHeight)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // ジェスチャ座標は枠（表示領域）基準なので、
                    // スクロール量を足してコンテンツ座標へ直す。
                    let frame = Int((value.location.x + horizontalOffset) / pxPerFrame)
                    onSeek(min(max(frame, 0), timeline.length))
                }
        )
    }

    // MARK: - レイヤーラベル列

    private func layerLabels(rowCount: Int) -> some View {
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

    private func layerLabel(layer: Int) -> some View {
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
    private func mutateLayerSetting(_ layer: Int, _ mutate: (inout LayerSetting) -> Void) {
        var setting = timeline.layerSettings.setting(forLayer: layer)
        mutate(&setting)
        if let index = timeline.layerSettings.items.firstIndex(where: { $0.layer == layer }) {
            timeline.layerSettings.items[index] = setting
        } else {
            timeline.layerSettings.items.append(setting)
        }
        layerRevision += 1
    }

    private func openLayerPopover(layer: Int) {
        let setting = timeline.layerSettings.setting(forLayer: layer)
        layerRenameText = setting.label ?? ""
        layerPopoverLayer = layer
    }

    private func layerPopoverBinding(for layer: Int) -> Binding<Bool> {
        Binding(
            get: { layerPopoverLayer == layer },
            set: { if !$0, layerPopoverLayer == layer { layerPopoverLayer = nil } }
        )
    }

    /// 名前変更とレイヤー全体の音量のポップオーバー。
    /// 名前は LayerSetting へ実書き込み。音量は Core に保持先が無いため
    /// 形のみ（ローカル状態）。
    private func layerPopover(layer: Int) -> some View {
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

    private func commitLayerRename(layer: Int) {
        let name = layerRenameText.trimmingCharacters(in: .whitespaces)
        mutateLayerSetting(layer) { $0.label = name.isEmpty ? nil : name }
    }

    private func layerVolumeBinding(for layer: Int) -> Binding<Double> {
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

    // MARK: - キャンバス

    private func canvas(
        rowCount: Int, contentHeight: CGFloat, viewportWidth: CGFloat
    ) -> some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // 背景（シーク用）。座標はコンテンツ座標そのもの。
                Rectangle()
                    .fill(Color(nsColor: .textBackgroundColor))
                    .frame(width: contentWidth, height: contentHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let frame = Int(value.location.x / pxPerFrame)
                                onSeek(min(max(frame, 0), timeline.length))
                            }
                    )

                // レイヤー行の区切りと縦グリッド線（大目盛り位置）。
                ForEach(0..<rowCount, id: \.self) { layer in
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: contentWidth, height: 1)
                        .offset(y: CGFloat(layer + 1) * rowHeight - 1)
                }
                ForEach(verticalGridFrames(viewportWidth: viewportWidth), id: \.self) { frame in
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: contentHeight)
                        .offset(x: CGFloat(frame) * pxPerFrame)
                }

                // アイテムブロック。
                ForEach(Array(timeline.items.enumerated()), id: \.offset) { index, item in
                    itemBlock(index: index, item: item)
                }

                // 再生ヘッド（キャンバス側）。
                Rectangle()
                    .fill(Color(red: 1, green: 0, blue: 0))
                    .frame(width: 1, height: contentHeight)
                    .offset(x: CGFloat(currentFrame) * pxPerFrame)
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
        }
        .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, newValue in
            horizontalOffset = newValue.x
            verticalOffset = newValue.y
        }
    }

    private func itemBlock(index: Int, item: BaseItem) -> some View {
        let width = max(CGFloat(item.length) * pxPerFrame, 2)
        let setting = timeline.layerSettings.setting(forLayer: item.layer)
        let isHidden = item.isHidden || setting.isHidden
        let fill = isHidden
            ? Color(nsColor: .darkGray)
            : swiftUIColor(honkeItemColor(for: item))
        let isSelected = selectedItemIndex == index

        return ZStack(alignment: .topLeading) {
            // 背景は上端4px（キーフレーム帯）を空けて塗る。
            Rectangle()
                .fill(fill)
                .frame(width: width, height: rowHeight - 4)
                .offset(y: 4)

            // 波形（本家は音のあるアイテムのブロック背景に描く）。
            // 実波形は音声デコード接続後。現状は形のみの疑似波形。
            if showWaveform, Self.hasAudioTrack(item) {
                Canvas { context, size in
                    var x: CGFloat = 1
                    while x < size.width {
                        let amplitude = Self.waveformAmplitude(item: item, x: x)
                        let barHeight = CGFloat(amplitude) * max(size.height - 8, 2)
                        let rect = CGRect(
                            x: x, y: size.height - barHeight,
                            width: 1.5, height: barHeight
                        )
                        context.fill(Path(rect), with: .color(.white.opacity(0.45)))
                        x += 3
                    }
                }
                .frame(width: width, height: rowHeight - 4)
                .offset(y: 4)
                .allowsHitTesting(false)
            }

            // キーフレームマーカー（上端帯の赤い三角形）。
            ForEach(item.keyFrames.frames, id: \.self) { keyFrame in
                Triangle()
                    .fill(Color(red: 1, green: 0, blue: 0))
                    .frame(width: 7, height: 5)
                    .offset(x: CGFloat(keyFrame) * pxPerFrame - 3.5, y: 0)
            }

            Text(item.label)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 0)
                .lineLimit(1)
                .frame(width: max(width - 6, 0), alignment: .leading)
                .offset(x: 3, y: 6)

            if item.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
                    .frame(width: max(width - 4, 0), alignment: .trailing)
                    .offset(y: 6)
            }
        }
        .frame(width: width, height: rowHeight, alignment: .topLeading)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedItemIndex = index }
        .offset(
            x: CGFloat(item.frame) * pxPerFrame,
            y: CGFloat(item.layer) * rowHeight
        )
    }

    /// 音声を持つアイテム種別か（波形表示の対象）。
    private static func hasAudioTrack(_ item: BaseItem) -> Bool {
        item is AudioItem || item is VideoItem || item is VoiceItem
    }

    /// 疑似波形の振幅（0.2–1.0）。アイテムと位置から決定的に求める。
    /// 実波形データへの差し替えは音声接続時に行う。
    private static func waveformAmplitude(item: BaseItem, x: CGFloat) -> Double {
        let seed = Double(item.frame &* 131 &+ item.length &* 17 &+ Int(x) &* 7)
        let value = sin(seed * 12.9898) * 43758.5453
        return 0.2 + 0.8 * abs(value - floor(value))
    }

    // MARK: - 目盛り計算（本家 TimelineScaleViewModel の規則）

    /// 典型間隔の候補から、目標（約13px分）の0.7倍以上で最も近いものを選ぶ。
    private func tickSpan() -> Int {
        let fps = max(timeline.videoInfo.fps, 1)
        let framesPerPixel = 100.0 / zoomPercent
        let target = max(Int(framesPerPixel * 13), 1)
        var candidates = Set<Int>()
        for frame in 1..<120 where fps % (frame * 10) == 0 {
            candidates.insert(frame)
        }
        for step in [1, 2, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1200,
                     1800, 3600, 7200, 14400, 21600, 43200, 86400] {
            let frames = step * fps
            if frames % 10 == 0 {
                candidates.insert(frames / 10)
            }
        }
        let floor = Double(target) * 0.7
        let eligible = candidates.filter { Double($0) >= floor }
        return eligible.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
    }

    /// 縦グリッド線を引くフレーム（大目盛り = 間隔×10 ごと、可視範囲のみ）。
    private func verticalGridFrames(viewportWidth: CGFloat) -> [Int] {
        let largeSpan = tickSpan() * 10
        let first = max(0, Int(horizontalOffset / pxPerFrame) - largeSpan)
        let last = min(
            timeline.length,
            Int((horizontalOffset + viewportWidth) / pxPerFrame) + largeSpan
        )
        guard largeSpan > 0, last >= first else { return [] }
        return Array(stride(from: (first / largeSpan) * largeSpan, through: last, by: largeSpan))
    }

    /// `hh:mm:ss.ff` 形式（本家のステータスバー・目盛りラベルと同じ書式）。
    private func timeText(frame: Int) -> String {
        let fps = max(timeline.videoInfo.fps, 1)
        let totalSeconds = Double(frame) / Double(fps)
        let whole = Int(totalSeconds)
        let hundredths = Int((totalSeconds - floor(totalSeconds)) * 100)
        return String(
            format: "%02d:%02d:%02d.%02d",
            whole / 3600, (whole % 3600) / 60, whole % 60, hundredths
        )
    }
}

/// キーフレームマーカー用の下向き三角形。
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 本家 `BaseItem.ItemColor` の規則（ItemColors 既定値＋キャラクター色）。
/// Core には色を持たないため、表示側で種別から求める。
/// 根拠: UI-LAYOUT-FACTS.md §5.4。
func honkeItemColor(for item: BaseItem) -> YMM4Core.Color {
    let characterFallback = YMM4Core.Color(alpha: 255, red: 213, green: 0, blue: 0)
    switch item {
    case let voice as VoiceItem:
        return voice.character?.color ?? characterFallback
    case let tachie as TachieItem:
        return tachie.character?.color ?? characterFallback
    case let face as TachieFaceItem:
        return face.character?.color ?? characterFallback
    case is AudioItem:
        return YMM4Core.Color(alpha: 255, red: 213, green: 0, blue: 0)
    case is EffectItem, is TransitionItem:
        return YMM4Core.Color(alpha: 255, red: 0, green: 255, blue: 0)
    case is GroupItem:
        return YMM4Core.Color(alpha: 255, red: 0, green: 220, blue: 200)
    default:
        // Text / Video / Image / Shape / Scene / FrameBuffer と未知の種別。
        return YMM4Core.Color(alpha: 255, red: 0, green: 0, blue: 213)
    }
}

/// YMM4Core.Color（0–255）を SwiftUI.Color へ変換する。
func swiftUIColor(_ color: YMM4Core.Color) -> SwiftUI.Color {
    SwiftUI.Color(
        red: Double(color.red) / 255,
        green: Double(color.green) / 255,
        blue: Double(color.blue) / 255,
        opacity: Double(color.alpha) / 255
    )
}
