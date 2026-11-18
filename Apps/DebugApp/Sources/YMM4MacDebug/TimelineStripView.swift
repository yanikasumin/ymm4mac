import AppKit
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
    /// 縦グリッド線の表示（本家の VerticalLines.IsEnabled 相当）。
    @Binding var showVerticalLines: Bool
    /// キャンバスの表示幅をツールバー側（全体フィット計算用）へ伝える。
    @Binding var reportedCanvasWidth: CGFloat
    /// 表示中ビューポートの最上段レイヤーを外へ伝える
    /// （本家 GetCurrentLayer() = Viewport.Top / LayerHeight）。
    @Binding var reportedTopLayer: Int
    /// コンテキストメニュー等の編集操作の後にプレビュー再合成を
    /// 促すための受け口。
    var onEdited: () -> Void = {}
    @State var horizontalOffset: CGFloat = 0
    @State var verticalOffset: CGFloat = 0
    /// レイヤー設定の変更を再描画へ反映させるための世代カウンタ。
    @State var layerRevision = 0
    /// レイヤー操作ポップオーバー（名前変更・音量）の対象レイヤー。
    @State var layerPopoverLayer: Int?
    @State var layerRenameText = ""
    /// レイヤー全体の音量（%）。Core の LayerSetting には音量が無いため
    /// 形のみのローカル状態（接続台帳に記録）。
    @State var layerVolumes: [Int: Double] = [:]
    /// 目盛り帯のウィンドウ座標（ホイールズームの当たり判定用）。
    @State var rulerRectBox = WindowRectBox()
    /// ホイールイベントの監視トークン（目盛り上のホイール = ズーム）。
    @State var wheelMonitor: Any?

    let labelWidth: CGFloat = 80
    private let rulerHeight: CGFloat = 26
    /// 目盛り帯右端のフィラー幅（本家の横スクロールバー幅ぶん）。
    private let rulerFillerWidth: CGFloat = 17

    var pxPerFrame: CGFloat { CGFloat(zoomPercent) / 100 }
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
                    Text(UIStrings.Timeline.layer)
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
            // 帯の外へ内容が描かれて下のセリフ行へ重なることを防ぐ
            // 構造的な上限（Issue #40）。
            .clipped()
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
        .background(WindowRectReporter(box: rulerRectBox))
        .onAppear { installWheelZoomMonitor() }
        .onDisappear { removeWheelZoomMonitor() }
        .contextMenu { rulerContextMenu() }
    }


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
                    .contextMenu { canvasContextMenu() }

                // レイヤー行の区切りと縦グリッド線（大目盛り位置）。
                ForEach(0..<rowCount, id: \.self) { layer in
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: contentWidth, height: 1)
                        .offset(y: CGFloat(layer + 1) * rowHeight - 1)
                }
                if showVerticalLines {
                    ForEach(verticalGridFrames(viewportWidth: viewportWidth), id: \.self) { frame in
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 1, height: contentHeight)
                            .offset(x: CGFloat(frame) * pxPerFrame)
                    }
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
            if rowHeight > 0 {
                reportedTopLayer = Int(newValue.y / rowHeight)
            }
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
            // 横ドラッグで位置を動かせる（隣を越えない範囲へ丸められ、
            // 値はインデックス対応のため動かない）。
            ForEach(item.keyFrames.frames, id: \.self) { keyFrame in
                Triangle()
                    .fill(Color(red: 1, green: 0, blue: 0))
                    .frame(width: 7, height: 5)
                    .offset(x: CGFloat(keyFrame) * pxPerFrame - 3.5, y: 0)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onEnded { gesture in
                                let delta = Int(
                                    (gesture.translation.width / pxPerFrame).rounded()
                                )
                                if item.moveKeyFrame(
                                    from: keyFrame, to: keyFrame + delta
                                ) {
                                    onEdited()
                                }
                            }
                    )
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
        .contextMenu { itemContextMenu(index: index, item: item) }
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

/// ウィンドウ座標の矩形を保持する箱（ホイールズームの当たり判定用）。
final class WindowRectBox {
    var rect: CGRect = .zero
}

/// 自分のウィンドウ座標矩形を箱へ報告するだけの NSView。
/// ヒットテストには参加しない（目盛りのドラッグ等を妨げない）。
struct WindowRectReporter: NSViewRepresentable {
    let box: WindowRectBox

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.box = box
        return view
    }

    func updateNSView(_ nsView: ReporterView, context: Context) {
        nsView.box = box
        nsView.report()
    }

    final class ReporterView: NSView {
        var box: WindowRectBox?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            report()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        func report() {
            box?.rect = convert(bounds, to: nil)
        }
    }
}
