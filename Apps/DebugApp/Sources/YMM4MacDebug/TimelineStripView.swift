import AppKit
import SwiftUI
import YMM4Core

/// 本家 TimelineView の配置を再現したタイムライン帯。
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
/// 構造（FE-TIMELINE 再構築）:
/// - スクロールの所有者は NSScrollView（TimelineScrollView.swift）。
///   目盛りは同じクリップビューの原点から描き、ラベル列は縦方向を同期する。
/// - ドラッグ操作（移動・トリム・キーフレーム・範囲選択）は AppKit の
///   操作層（TimelineInteractionView.swift）が本家の確定規則で担う。
///   SwiftUI 側はアイテムの描画とコンテキストメニューに専念する。
/// - 選択の正本は Core の selectedItems（同一性）。selectedItemIndex は
///   ProjectView のインスペクタ向けの写し（先頭アイテムのインデックス）。
/// - アイテムビューは可視範囲（前後1画面分の余白つき）だけを生成する
///   （FE-R1-032 の仮想化）。
///
/// 本家との差（残っているもの）:
/// - 波形は形のみ: 音声デコードのピーク供給が Core に無いため、実波形では
///   なく決定的な疑似波形を描く（FE-R1-029。供給ができたら差し替える）
/// - 背景グラデーションは本家の生成規則が未確定のため単色で塗る
struct TimelineStripView: View {
    let timeline: Timeline
    /// 現在フレーム（再生ヘッド位置）。
    let currentFrame: Int
    @Binding var selectedItemIndex: Int?
    /// ルーラー／キャンバス背景のクリックで呼ばれるシーク。
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
    /// ドラッグセッションの開始通知（Undo 接続単位がここへ
    /// EditCoordinator のトランザクション開始を差す。現時点では未接続）。
    var onDragBegan: () -> Void = {}
    /// ドラッグセッションの確定通知。変更があった場合に1回だけ呼ばれる
    /// （Undo 接続単位の記録接続点）。
    var onDragCommitted: () -> Void = {}
    /// ドラッグセッションのキャンセル通知（復元済みの後に1回だけ）。
    var onDragCancelled: () -> Void = {}

    /// スクロール位置の写し（NSScrollView が所有者で、これは報告用）。
    /// 縦グリッドの間引き・仮想化の範囲・追加位置のレイヤー決定に使う。
    @State var horizontalOffset: CGFloat = 0
    @State var verticalOffset: CGFloat = 0
    /// ドラッグ中のモデル変更を再描画へ反映させるための世代カウンタ。
    @State private var dragRevision = 0
    /// レイヤー設定の変更を再描画へ反映させるための世代カウンタ。
    @State var layerRevision = 0
    /// レイヤー操作ポップオーバー（名前変更・音量）の対象レイヤー。
    @State var layerPopoverLayer: Int?
    @State var layerRenameText = ""
    /// レイヤー全体の音量（%）。Core の LayerSetting には音量が無いため
    /// 形のみのローカル状態（接続台帳に記録）。
    @State var layerVolumes: [Int: Double] = [:]
    /// 目盛り帯のウィンドウ座標（ホイールズームの当たり判定用）。
    /// 値の出所は AppKit 側の目盛りビュー（コンテナが報告する）。
    @State var rulerRectBox = WindowRectBox()
    /// ホイールイベントの監視トークン（目盛り上のホイール = ズーム）。
    @State var wheelMonitor: Any?

    let labelWidth: CGFloat = 80
    private let rulerHeight: CGFloat = 26
    /// 目盛り帯右端のフィラー幅（旧 SwiftUI 版の名残。配置は AppKit 側が
    /// スクロールビュー幅に揃えるため、計算には使わない）。
    private let rulerFillerWidth: CGFloat = 17

    var pxPerFrame: CGFloat { CGFloat(zoomPercent) / 100 }
    private var contentWidth: CGFloat {
        max(CGFloat(timeline.length) * pxPerFrame, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let rowsViewportHeight = max(
                geometry.size.height - rulerHeight - 1, rowHeight)
            let rowCount = max(
                timeline.maxLayer + 2,
                Int(ceil(rowsViewportHeight / rowHeight))
            )
            let contentHeight = CGFloat(rowCount) * rowHeight
            let canvasViewportWidth = max(geometry.size.width - labelWidth, 1)
            // dragRevision を読むことで、ドラッグ中のモデル変更のたびに
            // body が再評価され、コンテンツが新しい位置で描かれる。
            let _ = dragRevision
            let _ = layerRevision

            TimelineScrollContainerRepresentable(
                configuration: TimelineScrollConfiguration(
                    canvasContent: AnyView(canvasContent(
                        rowCount: rowCount,
                        contentHeight: contentHeight,
                        viewportWidth: canvasViewportWidth,
                        viewportHeight: rowsViewportHeight
                    )),
                    labelsContent: AnyView(layerLabels(
                        rowCount: rowCount, contentHeight: contentHeight)),
                    headerContent: AnyView(
                        Text(UIStrings.Timeline.layer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, height: rulerHeight)
                    ),
                    labelWidth: labelWidth,
                    rulerHeight: rulerHeight,
                    contentWidth: contentWidth,
                    contentHeight: contentHeight,
                    timeline: timeline,
                    currentFrame: currentFrame,
                    pxPerFrame: pxPerFrame,
                    onSeek: onSeek,
                    rulerActions: TimelineRulerActions(
                        addItem: { addItemAtPlayhead(kind: $0) },
                        splitAtPlayhead: { splitAtPlayhead() },
                        selectLeftItems: {
                            selectItems { $0.frame + $0.length <= currentFrame }
                        },
                        selectRightItems: {
                            selectItems { $0.frame >= currentFrame }
                        },
                        selectAllItems: { selectItems { _ in true } }
                    ),
                    interaction: TimelineInteractionConfiguration(
                        timeline: timeline,
                        pxPerFrame: pxPerFrame,
                        rowHeight: rowHeight,
                        onSelectionChanged: {
                            reflectSelection()
                            dragRevision += 1
                        },
                        onModelChanged: {
                            dragRevision += 1
                            onEdited()
                        },
                        onSeek: onSeek,
                        onDragBegan: onDragBegan,
                        onDragCommitted: onDragCommitted,
                        onDragCancelled: onDragCancelled
                    ),
                    onScrollOffsetChange: { offset in
                        horizontalOffset = offset.x
                        verticalOffset = offset.y
                        if rowHeight > 0 {
                            reportedTopLayer = Int(offset.y / rowHeight)
                        }
                    },
                    onCanvasViewportWidthChange: { reportedCanvasWidth = $0 },
                    onRulerWindowRectChange: { rulerRectBox.rect = $0 }
                )
            )
            .onAppear { installWheelZoomMonitor() }
            .onDisappear { removeWheelZoomMonitor() }
            // 帯の外へ内容が描かれて下のセリフ行へ重なることを防ぐ
            // 構造的な上限（Issue #40）。
            .clipped()
        }
    }

    // MARK: - キャンバスのコンテンツ（描画専用。操作は AppKit 側）

    private func canvasContent(
        rowCount: Int, contentHeight: CGFloat,
        viewportWidth: CGFloat, viewportHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // 背景。操作（シーク・範囲選択）は操作層が担い、ここは
            // 右クリックメニューの受け口としてだけ残す。
            Rectangle()
                .fill(Color(nsColor: .textBackgroundColor))
                .frame(width: contentWidth, height: contentHeight)
                .contentShape(Rectangle())
                .contextMenu { canvasContextMenu() }

            // レイヤー行の区切りと縦グリッド線（大目盛り位置）。
            ForEach(0..<rowCount, id: \.self) { layer in
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: contentWidth, height: 1)
                    .offset(y: CGFloat(layer + 1) * rowHeight - 1)
            }
            if showVerticalLines {
                ForEach(
                    verticalGridFrames(viewportWidth: viewportWidth), id: \.self
                ) { frame in
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: contentHeight)
                        .offset(x: CGFloat(frame) * pxPerFrame)
                }
            }

            // アイテムブロック（可視範囲のみ生成する）。
            ForEach(
                visibleItemEntries(
                    viewportWidth: viewportWidth,
                    viewportHeight: viewportHeight)
            ) { entry in
                itemBlock(index: entry.index, item: entry.item)
            }

            // 再生ヘッド（キャンバス側）。
            Rectangle()
                .fill(Color(red: 1, green: 0, blue: 0))
                .frame(width: 1, height: contentHeight)
                .offset(x: CGFloat(currentFrame) * pxPerFrame)
        }
        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
    }

    /// 可視範囲（前後1画面分の余白つき）に入るアイテムと、その
    /// 全体でのインデックス。ビュー生成の仮想化（FE-R1-032）であり、
    /// 操作層の当たり判定は全アイテムを対象にする（モデル側で完結）。
    private func visibleItemEntries(
        viewportWidth: CGFloat, viewportHeight: CGFloat
    ) -> [TimelineItemEntry] {
        let marginFrames = Int(viewportWidth / pxPerFrame)
        let firstFrame = max(0, Int(horizontalOffset / pxPerFrame) - marginFrames)
        let lastFrame = Int((horizontalOffset + viewportWidth) / pxPerFrame)
            + marginFrames
        let firstLayer = max(0, Int(verticalOffset / rowHeight) - 2)
        let lastLayer = Int((verticalOffset + viewportHeight) / rowHeight) + 2
        return timeline.items.enumerated().compactMap { index, item in
            guard item.frame + item.length >= firstFrame,
                  item.frame <= lastFrame,
                  item.layer >= firstLayer, item.layer <= lastLayer
            else { return nil }
            return TimelineItemEntry(
                id: ObjectIdentifier(item), index: index, item: item)
        }
    }

    private func itemBlock(index: Int, item: BaseItem) -> some View {
        let width = max(CGFloat(item.length) * pxPerFrame, 2)
        let setting = timeline.layerSettings.setting(forLayer: item.layer)
        let isHidden = item.isHidden || setting.isHidden
        let fill = isHidden
            ? Color(nsColor: .darkGray)
            : swiftUIColor(honkeItemColor(for: item))
        // 選択の正本は Core の同一性選択。インデックス側の選択
        // （プレビュー操作など）は Core 未同期の間だけ見た目に残す。
        let isSelected = timeline.selectedItems.contains(where: { $0 === item })
            || selectedItemIndex == index

        return ZStack(alignment: .topLeading) {
            // 背景は上端4px（キーフレーム帯）を空けて塗る。
            Rectangle()
                .fill(fill)
                .frame(width: width, height: rowHeight - 4)
                .offset(y: 4)

            // 波形（本家は音のあるアイテムのブロック背景に描く）。
            // 実波形は音声デコードのピーク供給ができてから。現状は形のみ。
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

            // キーフレームマーカー（上端帯の赤い三角形）。表示専用で、
            // ドラッグは操作層がキーフレームモードとして担う。
            ForEach(item.keyFrames.frames, id: \.self) { keyFrame in
                Triangle()
                    .fill(Color(red: 1, green: 0, blue: 0))
                    .frame(width: 7, height: 5)
                    .offset(x: CGFloat(keyFrame) * pxPerFrame - 3.5, y: 0)
                    .allowsHitTesting(false)
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

/// 仮想化したアイテム列の要素（同一性でビューを追跡する）。
private struct TimelineItemEntry: Identifiable {
    let id: ObjectIdentifier
    let index: Int
    let item: BaseItem
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
