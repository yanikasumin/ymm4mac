import AppKit
import PreviewCore
import SwiftUI

/// プレビューの連続ズーム（ホイール／ピンチ）の入力部品
/// （FE-ZOOM-INPUT）。
///
/// 表示倍率と表示中心の所有は ProjectView で、倍率への換算は
/// PreviewCore の PreviewZoomInput、カーソル固定の中心計算は
/// PreviewLayout が正本である。本ファイルは入力の受け口だけを持つ:
/// SwiftUI のジェスチャではホイールの入力元や修飾キーを区別
/// できないため、中ボタンドラッグ（PreviewPanControls）と同じ
/// NSEvent のローカル監視の小さなアダプタで受ける。
///
/// 本家の入力規則（TimelineVideoPlayer.cs の Child_MouseWheel /
/// ShouldZoomPreviewArea）:
/// - プレビュー領域のズームは「Ctrl + マウスホイール（タッチ
///   パッドでない）」のときだけ起きる。修飾なしのホイールと
///   タッチパッドのスクロールはズームに使わない（本家では
///   コントロールポイント側のホイール処理へ回る）。
/// - 本家は入力元のデバイス種別でタッチパッドを判定する。Mac では
///   hasPreciseScrollingDeltas（トラックパッド等の精密デバイスで
///   true、マウスホイールで false）を対応させる。
/// - ピンチは本家に無いため、Mac の標準的な振る舞いとして修飾
///   なしで受ける（換算と制限はホイールと共通）。
///
/// ズームは表示状態の操作であり、プロジェクトの編集ではない。
/// この部品は未保存フラグや Undo 履歴へ一切触れない（書き込むのは
/// 呼び出し側が渡した倍率と中心だけ）。

/// ホイール／ピンチによる連続ズームのイベントアダプタ。
///
/// 中ボタンパンと同じく、ビュー自体は当たり判定を持たず（hitTest
/// は nil を返す）、表示枠の矩形を与える錨としてだけ置かれるため、
/// SwiftUI 側の既存のプレビュー操作経路は妨げない。監視は
/// 「自ウィンドウ宛・キーウィンドウ・表示枠内」のイベントだけを
/// 扱い、ズーム対象と判定したものだけを消費する。それ以外
/// （枠外、Ctrl なしのホイール、タッチパッドのスクロール）は
/// 素通しし、タイムライン側の監視や通常のスクロールと競合しない。
struct PreviewZoomInputAdapter: NSViewRepresentable {
    let layout: PreviewCore.PreviewLayout
    /// 新しい表示倍率と、カーソル固定で解いた新しい表示中心。
    let onZoom: (_ newZoom: Double, _ newCenter: CGPoint) -> Void

    func makeNSView(context: Context) -> PreviewZoomInputView {
        let view = PreviewZoomInputView()
        view.layout = layout
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: PreviewZoomInputView, context: Context) {
        nsView.layout = layout
        nsView.onZoom = onZoom
    }
}

final class PreviewZoomInputView: NSView {
    var layout: PreviewCore.PreviewLayout?
    var onZoom: ((Double, CGPoint) -> Void)?

    private var monitor: Any?

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
            matching: [.scrollWheel, .magnify]
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
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, window.isKeyWindow,
              let layout
        else { return event }
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return event }
        // PreviewLayout のカーソル固定ズームは基準点をプレビュー
        // 領域座標で受ける。表示枠は領域の中央に置かれるため、
        // 枠内座標へ枠の原点（領域内位置）を加えて渡す。
        let areaPoint = CGPoint(
            x: location.x + (layout.areaSize.width - layout.boxSize.width) / 2,
            y: location.y + (layout.areaSize.height - layout.boxSize.height) / 2
        )
        // 領域倍率 = 均一倍率 / 表示倍率（レイアウトの入力値同士の比）。
        let areaZoom = layout.uniformScale / layout.displayZoom
        switch event.type {
        case .scrollWheel:
            // 本家 ShouldZoomPreviewArea: ズームは Ctrl + マウス
            // ホイールだけ。タッチパッド（精密デルタ）と修飾なしは
            // ズームに使わず素通しする。
            guard !event.hasPreciseScrollingDeltas,
                  event.modifierFlags.contains(.control),
                  event.deltaY != 0
            else { return event }
            // Mac のマウスホイールは 1 ノッチ = deltaY 1 行。
            // 本家の Delta（1 ノッチ = 120）へ換算して渡す。
            let newZoom = PreviewCore.PreviewZoomInput.zoom(
                current: layout.displayZoom,
                wheelDelta: Double(event.deltaY)
                    * PreviewCore.PreviewZoomInput.wheelDeltaPerNotch,
                areaZoom: areaZoom
            )
            apply(newZoom, layout: layout, areaPoint: areaPoint)
            // Ctrl + ホイールは表示枠内ではプレビューの入力として
            // 確定させる（倍率が制限で動かなかった場合も、他の
            // スクロール等へ回さない。本家でもホイールはプレビュー
            // 側の子コントロールが受ける）。
            return nil
        case .magnify:
            let newZoom = PreviewCore.PreviewZoomInput.zoom(
                current: layout.displayZoom,
                magnification: Double(event.magnification),
                areaZoom: areaZoom
            )
            apply(newZoom, layout: layout, areaPoint: areaPoint)
            return nil
        default:
            return event
        }
    }

    /// 倍率が実際に変わる場合だけ、カーソル固定の中心と組で
    /// 呼び出し側へ渡す（中心のクランプは PreviewLayout 側が担う）。
    private func apply(
        _ newZoom: Double, layout: PreviewCore.PreviewLayout,
        areaPoint: CGPoint
    ) {
        guard newZoom != layout.displayZoom else { return }
        onZoom?(
            newZoom,
            layout.viewCenter(
                zoomingTo: newZoom, anchoredAtAreaPoint: areaPoint
            )
        )
    }
}
