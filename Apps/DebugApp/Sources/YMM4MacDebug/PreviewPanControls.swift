import AppKit
import PreviewCore
import SwiftUI

/// プレビュー拡大時のパンの入力部品（FE-PREVIEW-PAN）。
///
/// 表示中心（viewCenter）の所有は ProjectView で、幾何とクランプは
/// PreviewLayout（PreviewCore）が正本である。本ファイルは入力の
/// 受け口だけを持つ:
/// - スクロールバー（両軸）: 表示枠の端に重ねるオーバーレイ。
///   つまみのドラッグと、トラックのクリックによるジャンプ。
/// - 中ボタンドラッグ: SwiftUI のジェスチャではボタンを区別
///   できないため、NSEvent のローカル監視で受ける小さなアダプタ。
///
/// パンは表示状態の操作であり、プロジェクトの編集ではない。
/// このファイルの部品は未保存フラグや Undo 履歴へ一切触れない
/// （書き込むのは呼び出し側が渡した表示中心の Binding だけ）。

// MARK: - スクロールバー

/// プレビューのスクロールバー（両軸のオーバーレイ）。
///
/// 形状の規則は本家 DrawPreviewScrollBars の画面寸法換算に合わせる:
/// 視覚バーの太さ 6pt、表示枠の端からの余白 4pt、当たり判定の帯は
/// 端から 14pt、両軸のバーが重なる隅では相手側のバーの分だけ
/// トラックを 10pt 短くする。つまみの割合・位置と、クリック時の
/// ジャンプ（つまみをクリック位置中心へ）の意味論は PreviewLayout
/// の幾何が正本で、本ビューはトラック長（ポイント）を渡すだけ。
struct PreviewScrollBarOverlay: View {
    let layout: PreviewCore.PreviewLayout
    @Binding var viewCenter: CGPoint

    private let edgeMargin = 4.0
    private let barThickness = 6.0
    private let hitThickness = 14.0
    private let cornerAvoidance = 10.0

    /// 横バーのつまみを掴んでいる位置（つまみ先頭からの距離）。
    /// nil はドラッグ中でないことを表す。
    @State private var horizontalGrabOffset: Double?
    @State private var verticalGrabOffset: Double?
    @State private var isHoveringHorizontal = false
    @State private var isHoveringVertical = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if layout.hasHorizontalScrollBar {
                horizontalBar
            }
            if layout.hasVerticalScrollBar {
                verticalBar
            }
        }
    }

    /// 横バーのトラック長（両端の余白と、縦バーがある場合の隅の
    /// 回避を差し引いた長さ）。
    private var horizontalTrackLength: Double {
        layout.boxSize.width - 2 * edgeMargin
            - (layout.hasVerticalScrollBar ? cornerAvoidance : 0)
    }

    private var verticalTrackLength: Double {
        layout.boxSize.height - 2 * edgeMargin
            - (layout.hasHorizontalScrollBar ? cornerAvoidance : 0)
    }

    private var horizontalBar: some View {
        let trackLength = horizontalTrackLength
        let geometry = layout.horizontalScrollBarGeometry(
            trackLength: trackLength
        )
        let active = isHoveringHorizontal || horizontalGrabOffset != nil
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: barThickness / 2)
                .fill(Color.black.opacity(0.18))
                .frame(width: trackLength, height: barThickness)
                .offset(
                    x: edgeMargin,
                    y: hitThickness - edgeMargin - barThickness
                )
            if let geometry {
                RoundedRectangle(cornerRadius: barThickness / 2)
                    .fill(Color.white.opacity(active ? 0.85 : 0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: barThickness / 2)
                            .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(width: geometry.thumbLength, height: barThickness)
                    .offset(
                        x: edgeMargin + geometry.thumbOffset,
                        y: hitThickness - edgeMargin - barThickness
                    )
            }
        }
        .frame(width: layout.boxSize.width, height: hitThickness)
        .contentShape(Rectangle())
        .offset(y: layout.boxSize.height - hitThickness)
        .gesture(horizontalDragGesture(trackLength: trackLength, geometry: geometry))
        .onHover { isHoveringHorizontal = $0 }
    }

    private var verticalBar: some View {
        let trackLength = verticalTrackLength
        let geometry = layout.verticalScrollBarGeometry(
            trackLength: trackLength
        )
        let active = isHoveringVertical || verticalGrabOffset != nil
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: barThickness / 2)
                .fill(Color.black.opacity(0.18))
                .frame(width: barThickness, height: trackLength)
                .offset(
                    x: hitThickness - edgeMargin - barThickness,
                    y: edgeMargin
                )
            if let geometry {
                RoundedRectangle(cornerRadius: barThickness / 2)
                    .fill(Color.white.opacity(active ? 0.85 : 0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: barThickness / 2)
                            .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(width: barThickness, height: geometry.thumbLength)
                    .offset(
                        x: hitThickness - edgeMargin - barThickness,
                        y: edgeMargin + geometry.thumbOffset
                    )
            }
        }
        .frame(width: hitThickness, height: layout.boxSize.height)
        .contentShape(Rectangle())
        .offset(x: layout.boxSize.width - hitThickness)
        .gesture(verticalDragGesture(trackLength: trackLength, geometry: geometry))
        .onHover { isHoveringVertical = $0 }
    }

    /// 横バーのドラッグ。つまみの上での開始は掴み位置を保持し、
    /// トラック上での開始はつまみをクリック位置中心へジャンプ
    /// させてからそのままドラッグへ入る（本家の MouseDown の規則）。
    private func horizontalDragGesture(
        trackLength: Double, geometry: PreviewCore.PreviewLayout.ScrollBarGeometry?
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let geometry else { return }
                let pointer = Double(value.location.x) - edgeMargin
                if horizontalGrabOffset == nil {
                    if pointer >= geometry.thumbOffset,
                       pointer <= geometry.thumbOffset + geometry.thumbLength {
                        horizontalGrabOffset = pointer - geometry.thumbOffset
                    } else {
                        viewCenter = layout.viewCenter(
                            forHorizontalScrollBarThumbOffset:
                                pointer - geometry.thumbLength / 2,
                            trackLength: trackLength
                        )
                        horizontalGrabOffset = geometry.thumbLength / 2
                        return
                    }
                }
                guard let grabOffset = horizontalGrabOffset else { return }
                viewCenter = layout.viewCenter(
                    forHorizontalScrollBarThumbOffset: pointer - grabOffset,
                    trackLength: trackLength
                )
            }
            .onEnded { _ in
                horizontalGrabOffset = nil
            }
    }

    /// 縦バーのドラッグ（横と対称）。
    private func verticalDragGesture(
        trackLength: Double, geometry: PreviewCore.PreviewLayout.ScrollBarGeometry?
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let geometry else { return }
                let pointer = Double(value.location.y) - edgeMargin
                if verticalGrabOffset == nil {
                    if pointer >= geometry.thumbOffset,
                       pointer <= geometry.thumbOffset + geometry.thumbLength {
                        verticalGrabOffset = pointer - geometry.thumbOffset
                    } else {
                        viewCenter = layout.viewCenter(
                            forVerticalScrollBarThumbOffset:
                                pointer - geometry.thumbLength / 2,
                            trackLength: trackLength
                        )
                        verticalGrabOffset = geometry.thumbLength / 2
                        return
                    }
                }
                guard let grabOffset = verticalGrabOffset else { return }
                viewCenter = layout.viewCenter(
                    forVerticalScrollBarThumbOffset: pointer - grabOffset,
                    trackLength: trackLength
                )
            }
            .onEnded { _ in
                verticalGrabOffset = nil }
    }
}

// MARK: - 中ボタンドラッグ

/// 中ボタンドラッグによるパンのイベントアダプタ。
///
/// タイムラインのホイールズーム監視（TimelineContextMenus）と同じ
/// NSEvent ローカル監視の形で、既存の AppKit 入力境界に沿わせる。
/// このビュー自体は当たり判定を持たず（hitTest は nil を返す）、
/// 表示枠の矩形を与える錨としてだけ置かれるため、SwiftUI 側の
/// 既存のプレビュー操作経路（左ドラッグ・ハンドル）は妨げない。
/// 監視は「自ウィンドウ宛・表示枠内・中ボタン・表示倍率 > 1」の
/// イベントだけを消費し、それ以外は素通しする（本家 Child_MouseDown
/// の開始条件どおり）。
struct PreviewMiddleButtonPanAdapter: NSViewRepresentable {
    let layout: PreviewCore.PreviewLayout
    let onPan: (CGPoint) -> Void

    func makeNSView(context: Context) -> PreviewMiddleButtonPanView {
        let view = PreviewMiddleButtonPanView()
        view.layout = layout
        view.onPan = onPan
        return view
    }

    func updateNSView(_ nsView: PreviewMiddleButtonPanView, context: Context) {
        nsView.layout = layout
        nsView.onPan = onPan
    }
}

final class PreviewMiddleButtonPanView: NSView {
    var layout: PreviewCore.PreviewLayout?
    var onPan: ((CGPoint) -> Void)?

    private var monitor: Any?
    /// パン開始時のカーソル位置（自ビューの座標）と表示中心。
    private var panStart: (location: CGPoint, center: CGPoint)?

    /// 座標系を表示枠の座標（左上原点）へ合わせる。
    override var isFlipped: Bool { true }

    /// 当たり判定を持たない（イベントは下の SwiftUI 側へ通す）。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitor()
        } else {
            removeMonitor()
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.otherMouseDown, .otherMouseDragged, .otherMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        panStart = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, window.isKeyWindow,
              let layout
        else { return event }
        switch event.type {
        case .otherMouseDown:
            guard event.buttonNumber == 2 else {
                panStart = nil
                return event
            }
            guard layout.displayZoom > 1 else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }
            panStart = (location, layout.viewCenter)
            return nil
        case .otherMouseDragged:
            guard let panStart else { return event }
            // 中ボタンが離されているのにドラッグだけ届く場合は
            // セッションを畳む（ウィンドウ外で離した場合の残留防止）。
            guard NSEvent.pressedMouseButtons & (1 << 2) != 0 else {
                self.panStart = nil
                return event
            }
            let location = convert(event.locationInWindow, from: nil)
            let delta = CGPoint(
                x: location.x - panStart.location.x,
                y: location.y - panStart.location.y
            )
            onPan?(
                layout.pannedViewCenter(
                    from: panStart.center, byViewDelta: delta
                )
            )
            return nil
        case .otherMouseUp:
            // パンを終えるのは中ボタンの解放だけ（本家 Child_MouseUp）。
            guard event.buttonNumber == 2, panStart != nil else { return event }
            panStart = nil
            return nil
        default:
            return event
        }
    }
}
