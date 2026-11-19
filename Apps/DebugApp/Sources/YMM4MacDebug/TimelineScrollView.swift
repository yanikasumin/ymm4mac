import AppKit
import SwiftUI
import YMM4Core

/// タイムラインのスクロール基盤（FE-TIMELINE 再構築）。
///
/// スクロール位置の所有者はキャンバス側 NSScrollView のクリップビュー
/// ただ1つ。目盛りはその原点を描画時に直接読んで描き、レイヤーラベル列は
/// 専用 NSScrollView のクリップ原点をキャンバス側へ同期させる。
/// SwiftUI の @State へは「報告用の写し」としてだけ流す（従来は
/// SwiftUI ScrollView の報告値を目盛り側が手動オフセットとして
/// 持ち直しており、両者のずれが起きていた）。
///
/// 配置は本家 TimelineView と従来の SwiftUI 版を踏襲する:
/// 左に幅80のレイヤーラベル列、上に高さ26の目盛り帯。

/// 目盛りの右クリックメニューが呼ぶ操作（TimelineStripView 側の
/// 既存メソッドへの橋渡し）。目盛りは AppKit 化したため、メニューだけは
/// NSMenu で組み直し、操作の実体は従来の SwiftUI 側定義と共有する。
struct TimelineRulerActions {
    var addItem: (AddItemKind) -> Void
    var splitAtPlayhead: () -> Void
    var selectLeftItems: () -> Void
    var selectRightItems: () -> Void
    var selectAllItems: () -> Void
}

/// スクロール基盤へ渡す設定一式（TimelineStripView の body が毎回組み立てる）。
struct TimelineScrollConfiguration {
    var canvasContent: AnyView
    var labelsContent: AnyView
    var headerContent: AnyView
    var labelWidth: CGFloat
    var rulerHeight: CGFloat
    var contentWidth: CGFloat
    var contentHeight: CGFloat
    var timeline: Timeline
    var currentFrame: Int
    var pxPerFrame: CGFloat
    var onSeek: (Int) -> Void
    var rulerActions: TimelineRulerActions
    var interaction: TimelineInteractionConfiguration
    /// スクロール位置の写し（ポイント単位、キャンバスのクリップ原点）。
    var onScrollOffsetChange: (CGPoint) -> Void
    /// キャンバスの表示幅（全体フィット計算用）。
    var onCanvasViewportWidthChange: (CGFloat) -> Void
    /// 目盛り帯のウィンドウ座標矩形（ホイールズームの当たり判定用）。
    var onRulerWindowRectChange: (CGRect) -> Void
}

struct TimelineScrollContainerRepresentable: NSViewRepresentable {
    var configuration: TimelineScrollConfiguration

    func makeNSView(context: Context) -> TimelineContainerView {
        let view = TimelineContainerView()
        view.apply(configuration)
        return view
    }

    func updateNSView(_ nsView: TimelineContainerView, context: Context) {
        nsView.apply(configuration)
    }
}

/// 上下反転座標の土台ビュー（ドキュメントビュー用）。
/// NSScrollView のドキュメントを反転させることで、スクロール原点が
/// 「先頭レイヤー・先頭フレーム」側に来る（SwiftUI のコンテンツ座標と一致）。
final class TimelineFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// コンテナ: キャンバス NSScrollView＋ラベル NSScrollView＋目盛り＋隅見出し。
final class TimelineContainerView: NSView {
    private let canvasScrollView = NSScrollView()
    private let labelScrollView = NSScrollView()
    private let rulerView = TimelineRulerView()
    private let cornerHostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let headerDivider = NSView()
    private let columnSeparator = NSView()
    private let canvasDocument = TimelineFlippedView()
    private let labelDocument = TimelineFlippedView()
    private let canvasHostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let labelHostingView = NSHostingView(rootView: AnyView(EmptyView()))
    let interactionView = TimelineInteractionView()

    private var configuration: TimelineScrollConfiguration?
    private var isSyncingScroll = false
    private var lastReportedViewportWidth: CGFloat = -1
    private var lastReportedRulerRect: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        canvasScrollView.hasVerticalScroller = true
        canvasScrollView.hasHorizontalScroller = true
        canvasScrollView.scrollerStyle = .overlay
        canvasScrollView.autohidesScrollers = true
        canvasScrollView.drawsBackground = false
        canvasScrollView.borderType = .noBorder
        canvasScrollView.documentView = canvasDocument
        canvasDocument.addSubview(canvasHostingView)
        canvasDocument.addSubview(interactionView)

        labelScrollView.hasVerticalScroller = false
        labelScrollView.hasHorizontalScroller = false
        labelScrollView.drawsBackground = false
        labelScrollView.borderType = .noBorder
        labelScrollView.documentView = labelDocument
        labelDocument.addSubview(labelHostingView)

        for separator in [headerDivider, columnSeparator] {
            separator.wantsLayer = true
            separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }

        addSubview(labelScrollView)
        addSubview(columnSeparator)
        addSubview(canvasScrollView)
        addSubview(rulerView)
        addSubview(headerDivider)
        addSubview(cornerHostingView)

        for clipView in [canvasScrollView.contentView, labelScrollView.contentView] {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipBoundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }
        interactionView.scrollOwner = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 設定の適用

    func apply(_ configuration: TimelineScrollConfiguration) {
        // 対象タイムラインが差し替わったら、進行中のドラッグセッションを
        // 旧対象のままキャンセルしてから新しい設定へ移る。
        if let previous = self.configuration,
           previous.timeline !== configuration.timeline {
            interactionView.cancelActiveSessionIfNeeded()
        }
        self.configuration = configuration
        cornerHostingView.rootView = configuration.headerContent
        canvasHostingView.rootView = configuration.canvasContent
        labelHostingView.rootView = configuration.labelsContent

        let canvasSize = CGSize(
            width: configuration.contentWidth, height: configuration.contentHeight)
        if canvasDocument.frame.size != canvasSize {
            canvasDocument.frame = CGRect(origin: .zero, size: canvasSize)
            canvasHostingView.frame = canvasDocument.bounds
            interactionView.frame = canvasDocument.bounds
        }
        let labelSize = CGSize(
            width: configuration.labelWidth, height: configuration.contentHeight)
        if labelDocument.frame.size != labelSize {
            labelDocument.frame = CGRect(origin: .zero, size: labelSize)
            labelHostingView.frame = labelDocument.bounds
        }

        rulerView.timeline = configuration.timeline
        rulerView.pxPerFrame = configuration.pxPerFrame
        rulerView.currentFrame = configuration.currentFrame
        rulerView.onSeek = configuration.onSeek
        rulerView.actions = configuration.rulerActions
        rulerView.canvasClipView = canvasScrollView.contentView
        rulerView.needsDisplay = true

        interactionView.configuration = configuration.interaction
        needsLayout = true
    }

    // MARK: - 配置

    override func layout() {
        super.layout()
        guard let configuration, bounds.width > 0, bounds.height > 0 else { return }
        let width = bounds.width
        let height = bounds.height
        let labelWidth = configuration.labelWidth
        let rulerHeight = configuration.rulerHeight
        let contentHeight = max(height - rulerHeight - 1, 0)
        // コンテナは非反転（下原点）。見出し行は上端、内容はその下。
        cornerHostingView.frame = CGRect(
            x: 0, y: height - rulerHeight, width: labelWidth, height: rulerHeight)
        rulerView.frame = CGRect(
            x: labelWidth + 1, y: height - rulerHeight,
            width: width - labelWidth - 1, height: rulerHeight)
        headerDivider.frame = CGRect(
            x: 0, y: height - rulerHeight - 1, width: width, height: 1)
        labelScrollView.frame = CGRect(
            x: 0, y: 0, width: labelWidth, height: contentHeight)
        columnSeparator.frame = CGRect(
            x: labelWidth, y: 0, width: 1, height: contentHeight)
        canvasScrollView.frame = CGRect(
            x: labelWidth + 1, y: 0,
            width: width - labelWidth - 1, height: contentHeight)

        let viewportWidth = canvasScrollView.contentView.bounds.width
        if viewportWidth > 0, abs(viewportWidth - lastReportedViewportWidth) > 0.5 {
            lastReportedViewportWidth = viewportWidth
            configuration.onCanvasViewportWidthChange(viewportWidth)
        }
        reportRulerWindowRect()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportRulerWindowRect()
    }

    private func reportRulerWindowRect() {
        guard window != nil, rulerView.bounds.width > 0 else { return }
        let rect = rulerView.convert(rulerView.bounds, to: nil)
        if rect != lastReportedRulerRect {
            lastReportedRulerRect = rect
            configuration?.onRulerWindowRectChange(rect)
        }
    }

    // MARK: - スクロール同期（キャンバスが所有者）

    @objc private func clipBoundsChanged(_ notification: Notification) {
        guard !isSyncingScroll,
              let changed = notification.object as? NSClipView else { return }
        isSyncingScroll = true
        let canvasClip = canvasScrollView.contentView
        let labelClip = labelScrollView.contentView
        if changed === canvasClip {
            if labelClip.bounds.origin.y != canvasClip.bounds.origin.y {
                labelClip.scroll(to: CGPoint(
                    x: labelClip.bounds.origin.x, y: canvasClip.bounds.origin.y))
                labelScrollView.reflectScrolledClipView(labelClip)
            }
        } else {
            if canvasClip.bounds.origin.y != labelClip.bounds.origin.y {
                canvasClip.scroll(to: CGPoint(
                    x: canvasClip.bounds.origin.x, y: labelClip.bounds.origin.y))
                canvasScrollView.reflectScrolledClipView(canvasClip)
            }
        }
        isSyncingScroll = false
        rulerView.needsDisplay = true
        configuration?.onScrollOffsetChange(canvasClip.bounds.origin)
    }

    /// ドラッグ中の端自動スクロール用。キャンバスのクリップ原点を
    /// 範囲内に丸めて動かす（同期と報告は通知経由で通常どおり行われる）。
    func scrollCanvasBy(dx: CGFloat, dy: CGFloat) {
        let clip = canvasScrollView.contentView
        let maxX = max(0, canvasDocument.frame.width - clip.bounds.width)
        let maxY = max(0, canvasDocument.frame.height - clip.bounds.height)
        let origin = CGPoint(
            x: min(max(clip.bounds.origin.x + dx, 0), maxX),
            y: min(max(clip.bounds.origin.y + dy, 0), maxY)
        )
        if origin != clip.bounds.origin {
            clip.scroll(to: origin)
            canvasScrollView.reflectScrolledClipView(clip)
        }
    }

    /// キャンバスの可視領域（コンテンツ座標）。
    var canvasVisibleRect: CGRect {
        interactionView.visibleRect
    }
}

// MARK: - 目盛り（AppKit）

/// 目盛り帯。描画はキャンバス側クリップビューの原点を直接読む
/// （独自のオフセット状態を持たない）。左ドラッグはシーク、
/// 右クリックは NSMenu（操作の実体は TimelineStripView 側と共有）。
final class TimelineRulerView: NSView {
    var timeline: Timeline?
    var pxPerFrame: CGFloat = 1
    var currentFrame: Int = 0
    weak var canvasClipView: NSClipView?
    var onSeek: ((Int) -> Void)?
    var actions: TimelineRulerActions?
    private var isSeekTracking = false
    private var menuTarget: TimelineRulerMenuTarget?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let timeline, pxPerFrame > 0 else { return }
        let originX = canvasClipView?.bounds.origin.x ?? 0
        let span = TimelineScale.tickSpan(
            fps: timeline.videoInfo.fps, zoomPercent: Double(pxPerFrame) * 100)
        guard span > 0 else { return }
        let height = bounds.height
        let firstIndex = max(0, Int((originX / pxPerFrame) / Double(span)) - 2)
        let lastFrame = min(
            timeline.length,
            Int((originX + bounds.width) / pxPerFrame) + span * 2
        )
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        var index = firstIndex
        while index * span <= max(firstIndex * span, lastFrame) {
            let frame = index * span
            let x = CGFloat(frame) * pxPerFrame - originX
            let isLarge = index % 10 == 0
            let isMiddle = index % 5 == 0
            let tickHeight: CGFloat = isLarge ? 10 : (isMiddle ? 7 : 4)
            (isLarge ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.7))
                .setFill()
            CGRect(x: x, y: height - tickHeight, width: 1, height: tickHeight).fill()
            if isLarge {
                let text = TimelineScale.timeText(
                    frame: frame, fps: timeline.videoInfo.fps)
                (text as NSString).draw(
                    at: NSPoint(x: x + 3, y: 1), withAttributes: labelAttributes)
            }
            index += 1
        }
        // 再生ヘッド（目盛り側）。
        NSColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
        CGRect(
            x: CGFloat(currentFrame) * pxPerFrame - originX,
            y: 0, width: 1, height: height
        ).fill()
    }

    // MARK: シーク（左ボタンのドラッグ）

    override func mouseDown(with event: NSEvent) {
        isSeekTracking = true
        seek(to: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isSeekTracking { seek(to: event) }
    }

    override func mouseUp(with event: NSEvent) {
        isSeekTracking = false
    }

    private func seek(to event: NSEvent) {
        guard let timeline, pxPerFrame > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let originX = canvasClipView?.bounds.origin.x ?? 0
        let frame = Int((point.x + originX) / pxPerFrame)
        onSeek?(min(max(frame, 0), timeline.length))
    }

    // MARK: 右クリックメニュー（本家 §2.2。SwiftUI 版 rulerContextMenu と同じ構成）

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let actions else { return nil }
        let target = TimelineRulerMenuTarget(actions: actions)
        menuTarget = target
        let menu = NSMenu()
        let addMenu = NSMenu()
        let rulerKinds: [AddItemKind] = [
            .voice, .text, .video, .audio, .image, .shape, .tachie, .face,
        ]
        for (index, kind) in rulerKinds.enumerated() {
            let item = NSMenuItem(
                title: kind.displayName,
                action: #selector(TimelineRulerMenuTarget.addItem(_:)),
                keyEquivalent: "")
            item.target = target
            item.tag = index
            target.kinds = rulerKinds
            addMenu.addItem(item)
        }
        let addItem = NSMenuItem(title: UIStrings.Menu.addItem, action: nil, keyEquivalent: "")
        addItem.submenu = addMenu
        menu.addItem(addItem)
        menu.addItem(.separator())
        menu.addItem(target.item(
            title: UIStrings.Timeline.splitAtPlayhead,
            action: #selector(TimelineRulerMenuTarget.splitAtPlayhead(_:))))
        menu.addItem(.separator())
        menu.addItem(target.item(
            title: UIStrings.Menu.selectLeftItems,
            action: #selector(TimelineRulerMenuTarget.selectLeftItems(_:))))
        menu.addItem(target.item(
            title: UIStrings.Menu.selectRightItems,
            action: #selector(TimelineRulerMenuTarget.selectRightItems(_:))))
        menu.addItem(target.item(
            title: UIStrings.Menu.selectAll,
            action: #selector(TimelineRulerMenuTarget.selectAllItems(_:))))
        return menu
    }
}

/// 目盛りメニューの受け手（NSMenuItem.target は弱参照のためビューが保持する）。
private final class TimelineRulerMenuTarget: NSObject {
    let actions: TimelineRulerActions
    var kinds: [AddItemKind] = []

    init(actions: TimelineRulerActions) {
        self.actions = actions
    }

    func item(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func addItem(_ sender: NSMenuItem) {
        guard kinds.indices.contains(sender.tag) else { return }
        actions.addItem(kinds[sender.tag])
    }

    @objc func splitAtPlayhead(_ sender: NSMenuItem) { actions.splitAtPlayhead() }
    @objc func selectLeftItems(_ sender: NSMenuItem) { actions.selectLeftItems() }
    @objc func selectRightItems(_ sender: NSMenuItem) { actions.selectRightItems() }
    @objc func selectAllItems(_ sender: NSMenuItem) { actions.selectAllItems() }
}
