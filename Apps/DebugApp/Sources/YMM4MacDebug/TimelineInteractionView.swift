import AppKit
import YMM4Core

/// タイムラインのドラッグ操作層（FE-TIMELINE 再構築）。
///
/// キャンバスの SwiftUI コンテンツの上に重なる AppKit ビューで、
/// 左ボタンのマウス操作を一手に引き受け、本家の確定規則
/// （TimelineItemView / TimelineItemViewModel）でドラッグセッションを回す:
/// - MouseDown でモード（移動／左トリム／右トリム／キーフレーム／
///   ロックボタン／背景・範囲選択）と対象・開始時状態を固定する。
/// - MouseMove ではモデルを逐次更新する。デルタは「開始時からの累積」から
///   「モデルへ適用済みの分」を差し引いた残りとして計算する（本家は
///   アイテムビュー自体がモデルに追随して動くため Delta が残り量になる。
///   ここではビューが動かないので、現在値と開始値の差で同じ量を作る）。
///   移動は moveSelectedAndGroupedItems、トリムは
///   changeSelectedAndGroupedItemsLength、吸着は getSnappedDelta を使い、
///   ビュー内に移動計算を複製しない。
/// - MouseUp で確定する。確定通知はセッションにつき1回、変更の有無に
///   かかわらず onDragCommitted を呼ぶ（FE-R9-003: 開始通知と対にする
///   ため、無変更でも必ず終了を通知する。空の履歴は接続側が破棄できる）。
///   通知はセッション状態（スナップショット）を破棄する前に呼ぶ
///   （FE-R9-002: 接続側が変更前状態を参照できる順序）。
/// - Escape／ウィンドウの非アクティブ化／対象の削除はキャンセルとして
///   開始時状態へ復元する。本家はキャプチャ喪失でも確定経路へ進むため、
///   ここは Mac 側の安全性のための意図的な逸脱（FE-R2-DESIGN 記録済み）。
///
/// 右ボタンはヒットテストを素通しし、下の SwiftUI コンテンツの
/// コンテキストメニューへ渡す（Ctrl+クリックも AppKit では
/// 右ボタン扱いになるため、トリムの隣接影響はドラッグ途中で
/// Ctrl を押して切り替える形になる）。
struct TimelineInteractionConfiguration {
    var timeline: Timeline
    var pxPerFrame: CGFloat
    var rowHeight: CGFloat
    /// 左クリックで選択が変わったとき（表示の再描画とインデックス写し）。
    var onSelectionChanged: () -> Void
    /// モデルが変わったとき（表示の再描画＋プレビュー再合成要求）。
    /// 「既に発生した変更」を伝える通知であり、セッションの開始を
    /// 知らせる onDragBegan とは責務が別（FE-R11-001）。MouseDown 中の
    /// 複製・衝突解決で変わった場合も、発生した時点でこれを呼ぶ。
    var onModelChanged: () -> Void
    /// 背景クリックのシーク。
    var onSeek: (Int) -> Void
    /// セッション開始（変更可能なドラッグが始まったとき、1回だけ）。
    /// アイテムへの最初のモデル変更（複製・衝突解決）より前に呼ばれる
    /// （FE-R9-002）。これは「開始の通知」であり、発生済みの変更を
    /// 再描画へ伝える通知ではない（そちらは onModelChanged の責務。
    /// FE-R11-001）。選択の変更はセッション開始前のクリック処理として
    /// この通知より前に済んでいる（スナップショットは選択変更より前に取る）。
    /// 戻り値 false は接続側（Undo 記録）が開始を拒否したことを表し、
    /// その場合このビューはモデル変更セッション自体を開始しない
    /// （複製・衝突解決・移動のいずれも行わない。FE-R20-126-02）。
    /// セッションを開始していないため、対になる終了通知
    /// （onDragCommitted / onDragCancelled）も送らない。
    var onDragBegan: () -> Bool
    /// セッション確定（MouseUp で1回だけ、変更の有無にかかわらず。
    /// FE-R9-003）。セッション状態の破棄より前に呼ばれる（FE-R9-002）。
    var onDragCommitted: () -> Void
    /// セッションのキャンセル（復元が済んだ後に1回だけ）。
    /// セッション状態の破棄より前に呼ばれる（FE-R9-002）。
    var onDragCancelled: () -> Void
}

final class TimelineInteractionView: NSView {
    var configuration: TimelineInteractionConfiguration?
    weak var scrollOwner: TimelineContainerView?

    override var isFlipped: Bool { true }

    // MARK: - セッション状態

    private enum Mode {
        case none
        case move
        case resizeHead
        case resizeFoot
        case keyframe
        case lockButton
        case background
        case marquee
    }

    /// キャンセル復元用の開始時状態（全アイテム分）。
    private struct ItemState {
        let item: BaseItem
        var frame: Int
        var length: Int
        var layer: Int
        var contentOffsetTicks: Int64
        var keyFrameFrames: [Int]
    }

    private var mode: Mode = .none
    private var startPoint: NSPoint = .zero
    private var lastWindowPoint: NSPoint = .zero
    private var lastModifierFlags: NSEvent.ModifierFlags = []
    private var grabbedItem: BaseItem?
    /// つかんだアイテムの開始値（MouseDown 時点。複製・衝突解決より前）。
    private var grabbedStart = (frame: 0, length: 0, layer: 0)
    /// つかんだ位置のアイテム内座標（レイヤー移動量の式で使う）。
    private var startPointInItem: NSPoint = .zero
    private var keyframeIndex = -1
    private var startKeyFrame = 0
    private var snapshot: [ItemState] = []
    private var snapshotSelection: [BaseItem] = []
    private var hasSnapshot = false
    /// 複数選択中のアイテムを修飾キーなしでクリックした場合の、
    /// MouseUp 時（移動が無かったとき）の単独選択への確定先（FE-R9-005。
    /// 本家の SelectCommand2 相当）。
    private var clickCollapseItem: BaseItem?
    /// このセッションで編集コマンド（移動・トリム）が実行経路に入ったか。
    /// 本家は MoveCommand / ResizeHeadCommand / ResizeFootCommand の
    /// 冒頭（デルタ計算・吸着補正より前）で isSelectedCommandExecuted を
    /// 立て、終了時の単独選択化（SelectCommand2）を抑制する。したがって
    /// フラグは「ドラッグ中にポインタが実際に動いてコマンドの実行経路に
    /// 入った時点」で立て、量子化・吸着補正後のデルタがゼロでも立つ
    /// （FE-R10-002: 高ズームで1フレーム未満のドラッグでも複数選択を
    /// 維持する。最終モデルが開始時と等しいこととドラッグ操作が行われ
    /// なかったことは同義ではない）。mouseDown では立てない（通常の
    /// クリックまでドラッグ扱いになるため）。キーフレーム移動は本家の
    /// DragDeltaCommand がフラグを立てないため、ここでも立てない。
    private var didExecuteEditCommand = false
    private var marqueeRect: CGRect = .zero
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var autoScrollTimer: Timer?

    private var timeline: Timeline? { configuration?.timeline }
    private var pxPerFrame: CGFloat { configuration?.pxPerFrame ?? 1 }
    private var rowHeight: CGFloat { configuration?.rowHeight ?? 32 }
    /// 本家 SnapTargetPixelDistance（既定5px）をフレームへ換算した吸着距離。
    private var snapFrameDistance: Int { Int(5.0 / pxPerFrame) }
    /// 本家 SnapTargetLayerDistance（既定3）。
    private let snapLayerDistance = 3

    // MARK: - ヒットテスト（左ボタンだけ引き受け、右ボタンは下へ通す）

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        if let type = NSApp.currentEvent?.type,
           type == .leftMouseDown || type == .leftMouseDragged
            || type == .leftMouseUp {
            return self
        }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - カーソル（つまみ・キーフレーム上は左右リサイズ）

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .none, let timeline else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitItem(at: point, timeline: timeline) {
            switch decideMode(for: hit, at: point) {
            case .resizeHead, .resizeFoot, .keyframe:
                NSCursor.resizeLeftRight.set()
                return
            case .none, .move, .lockButton, .background, .marquee:
                break
            }
        }
        NSCursor.arrow.set()
    }

    // MARK: - MouseDown（モードと開始時状態の固定）

    override func mouseDown(with event: NSEvent) {
        guard let configuration, let timeline else { return }
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        lastWindowPoint = event.locationInWindow
        marqueeRect = .zero

        guard let hit = hitItem(at: point, timeline: timeline) else {
            // 背景: クリックはシーク、ドラッグへ移行したら範囲選択
            // （本家 BeginSelectRange）。シークは範囲選択へ移行しなかった
            // 場合の MouseUp で確定する（FE-R9-004: ここで即時に
            // 再生ヘッドを動かすと、範囲選択だけのつもりでもヘッドが
            // 動いてしまう）。
            mode = .background
            snapshotSelection = timeline.selectedItems
            hasSnapshot = false
            beginMonitoring()
            return
        }

        let item = hit.item
        grabbedItem = item
        startPointInItem = NSPoint(
            x: point.x - CGFloat(item.frame) * pxPerFrame,
            y: point.y - CGFloat(item.layer) * rowHeight)
        let decided = decideMode(for: hit, at: point)
        mode = decided

        // キャンセル復元は「MouseDown 前」の状態へ戻す契約のため、
        // スナップショットはクリック選択の処理より前に取る
        // （FE-R9-006: 選択もアイテム列の順序もこの時点のものが正）。
        // アイテムの値・メンバーシップはこの後しばらく変わらない。
        takeSnapshot(timeline: timeline)

        switch decided {
        case .move:
            // 複数選択中の選択済みアイテムを修飾キーなしでクリックした
            // 場合は、MouseDown では複数選択を保ち（まとめて動かせる
            // ように）、移動の無かった MouseUp で単独選択へ確定する
            // （FE-R9-005。本家の SelectCommand / SelectCommand2 の
            // 使い分け）。
            let modifiers = event.modifierFlags
            if !modifiers.contains(.command), !modifiers.contains(.shift),
               timeline.selectedItems.count > 1,
               timeline.selectedItems.contains(where: { $0 === item }) {
                clickCollapseItem = item
            }
            applyClickSelection(item: item, event: event, timeline: timeline)
        case .resizeHead, .resizeFoot:
            // 本家は Resize 系コマンドの冒頭で未選択なら単独選択にする。
            if !timeline.selectedItems.contains(where: { $0 === item }) {
                timeline.selectItem(item)
                configuration.onSelectionChanged()
            }
        case .keyframe, .lockButton, .none, .background, .marquee:
            break
        }

        if decided == .move,
           !timeline.selectedItems.contains(where: { $0 === item }) {
            // Command トグルで選択から外れた場合、本家では MoveCommand が
            // 「選択中のみ」という条件でドラッグ自体が成立しない。
            // 選択変更だけを残してセッションを開始しない。開始通知は
            // まだ送っていないため、対になる終了通知も不要で、
            // スナップショットは黙って破棄する。
            endSession()
            return
        }

        if decided == .keyframe {
            keyframeIndex = hit.keyframeIndex
            startKeyFrame = item.keyFrames.frames[keyframeIndex]
        }

        // セッション開始の通知は、アイテムへの最初のモデル変更
        // （複製・衝突解決）より前に送る（FE-R9-002: 接続側が変更前
        // 状態を記録できる順序）。
        guard configuration.onDragBegan() else {
            // 接続側が開始を拒否した（別のトランザクションが有効で
            // 記録を開始できない）。無記録のモデル変更を残さないため、
            // セッション自体を開始せずに畳む（FE-R20-126-02）。
            // クリック選択はモデル変更ではないため残してよい
            // （本家でも選択は Undo の対象外）。スナップショットは
            // endSession で破棄し、終了通知は送らない（開始して
            // いないセッションの通知は接続側でも無視される契約だが、
            // 送らないことで対の崩れ自体を無くす）。
            endSession()
            return
        }

        // DragStart（本家 DragStartCommand）: Alt 単独なら複製し、
        // 開始値を押さえ、選択＋グループの衝突を解消する。
        if decided == .move || decided == .resizeHead || decided == .resizeFoot {
            let modifiers = event.modifierFlags
            if modifiers.contains(.option),
               modifiers.intersection([.shift, .command, .control]).isEmpty {
                timeline.unsafeCloneWithoutCollision()
            }
            grabbedStart = (item.frame, item.length, item.layer)
            timeline.resolveItemCollision(timeline.selectedAndGroupedItems)
        } else {
            grabbedStart = (item.frame, item.length, item.layer)
        }

        // MouseDown 中に発生したモデル変更（複製・衝突解決）の通知
        // （FE-R11-001）。onDragBegan は「セッション開始の通知」で
        // あって、既に発生した変更を再描画へ伝える通知ではない
        // （責務が別）。複製でアイテムが増えたり衝突解決で位置・
        // レイヤーが変わったりしたのに通知しないと、移動せず
        // MouseUp した場合に変更が画面・プレビューへ反映されない。
        // 変化の有無は、クリック選択より前に取ったスナップショット
        // との比較（メンバーシップ＋値）で判定する。選択の変更は
        // 比較対象に含まれないため、変化のない通常の MouseDown では
        // 通知しない。
        if modelDiffersFromSnapshot(timeline: timeline) {
            configuration.onModelChanged()
        }
        beginMonitoring()
    }

    /// クリック時の選択規則（本家 SelectItemWithKeyboardStatus）。
    /// Ctrl+クリックは AppKit では右ボタン扱いでここへ来ないため、
    /// トグルは macOS の作法どおり Command に割り当てる（プラットフォーム
    /// 適応として実装ログに記録）。Shift は範囲選択。
    private func applyClickSelection(
        item: BaseItem, event: NSEvent, timeline: Timeline
    ) {
        guard let configuration else { return }
        if event.modifierFlags.contains(.command) {
            timeline.toggleSelectionStatus(item)
            configuration.onSelectionChanged()
        } else if event.modifierFlags.contains(.shift) {
            timeline.selectBetweenItems(to: item)
            configuration.onSelectionChanged()
        } else if !timeline.selectedItems.contains(where: { $0 === item }) {
            timeline.selectItem(item)
            configuration.onSelectionChanged()
        }
    }

    // MARK: - MouseMove（モデルの逐次更新）

    override func mouseDragged(with event: NSEvent) {
        lastWindowPoint = event.locationInWindow
        lastModifierFlags = event.modifierFlags
        guard mode != .none, let timeline else { return }
        // 対象がドラッグ中に消えたらキャンセル（開始時状態へ復元）。
        if let grabbedItem,
           mode == .move || mode == .resizeHead || mode == .resizeFoot
            || mode == .keyframe,
           !timeline.items.contains(where: { $0 === grabbedItem }) {
            cancelSession()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        applyDragged(point: point, modifierFlags: event.modifierFlags)
        updateAutoScroll()
    }

    private func applyDragged(point: NSPoint, modifierFlags: NSEvent.ModifierFlags) {
        guard let timeline else { return }
        switch mode {
        case .move:
            applyMove(point: point, modifierFlags: modifierFlags, timeline: timeline)
        case .resizeHead:
            applyResize(
                head: true, point: point, modifierFlags: modifierFlags,
                timeline: timeline)
        case .resizeFoot:
            applyResize(
                head: false, point: point, modifierFlags: modifierFlags,
                timeline: timeline)
        case .keyframe:
            applyKeyframeDrag(
                point: point, modifierFlags: modifierFlags, timeline: timeline)
        case .background:
            if hypot(point.x - startPoint.x, point.y - startPoint.y) > 4 {
                mode = .marquee
                updateMarquee(point: point)
            }
        case .marquee:
            updateMarquee(point: point)
        case .lockButton, .none:
            break
        }
    }

    /// 移動（本家 MoveCommand）。デルタは適用済みを差し引いた残り量。
    private func applyMove(point: NSPoint, modifierFlags: NSEvent.ModifierFlags, timeline: Timeline) {
        guard let configuration, let item = grabbedItem else { return }
        // 本家は MoveCommand の冒頭（デルタ計算より前）で
        // isSelectedCommandExecuted を立てる。ポインタが実際に動いて
        // この実行経路に入った時点で立てるのが本家の発火条件であり、
        // 量子化・吸着補正の結果とは独立に立てる（FE-R10-002）。
        didExecuteEditCommand = true
        let totalFrames = Int((point.x - startPoint.x) / pxPerFrame)
        var dframe = totalFrames - (item.frame - grabbedStart.frame)
        // レイヤー量は本家 GetDeltaFrameAndLayer の式（残り量形式）。
        // 下向き（残り量 >= 0）は「ポインタが自レイヤーの下端を越えた分」、
        // 上向きは「上端を越えた分」で層が切り替わる非対称な式。
        let appliedLayerPoints = CGFloat(item.layer - grabbedStart.layer) * rowHeight
        let remainderY = (point.y - startPoint.y) - appliedLayerPoints
        let dlayer: Int
        if remainderY >= 0 {
            dlayer = Int((remainderY + startPointInItem.y - 1) / rowHeight)
        } else {
            dlayer = Int((remainderY - (rowHeight - startPointInItem.y)) / rowHeight)
        }
        // 隣接吸着（extraDeltaFrame）と通常吸着の振り分けは本家どおり:
        // 掴んだアイテムの区間と重なる他アイテムがあり、カーソルが
        // その全てより後ろ（または前）にある場合は端へ寄せる量を
        // extraDeltaFrame として渡し、それ以外は GetSnappedDelta で吸着する。
        let targets = timeline.selectedAndGroupedItems
        let others = timeline.items.filter {
            candidate in !targets.contains(where: { $0 === candidate })
        }
        let targetLayer = item.layer + dlayer
        let source = others.filter {
            $0.layer == targetLayer
                && $0.intersectsWith(frame: item.frame + dframe, length: item.length)
        }
        let grabOffsetFrames = Int(startPointInItem.x / pxPerFrame)
        let cursorFrame = item.frame + grabOffsetFrames + dframe
        let cursorItem = others.first {
            $0.layer == targetLayer
                && $0.intersectsWith(frame: cursorFrame, length: 1)
        }
        var extraDeltaFrame = 0
        if cursorItem == nil,
           source.contains(where: { $0.frame + $0.length <= cursorFrame }),
           !source.contains(where: { cursorFrame < $0.frame }) {
            extraDeltaFrame =
                (source.map { $0.frame + $0.length }.max() ?? 0) - item.frame - dframe
        } else if cursorItem == nil,
                  !source.contains(where: { $0.frame + $0.length <= cursorFrame }),
                  source.contains(where: { cursorFrame < $0.frame }) {
            extraDeltaFrame =
                (source.map { $0.frame }.min() ?? 0) - item.frame - item.length - dframe
        } else if !modifierFlags.contains(.shift) {
            let snapTargets = [item.frame, item.frame + item.length]
                + item.keyFrames.frames.map { item.frame + $0 }
            dframe = timeline.getSnappedDelta(
                snapTargetFrames: snapTargets, baseLayer: item.layer,
                frameDelta: dframe, frameDistance: snapFrameDistance,
                layerDistance: snapLayerDistance, ignoreItems: targets)
        }
        let before = (item.frame, item.layer)
        timeline.moveSelectedAndGroupedItems(
            deltaFrame: dframe, deltaLayer: dlayer,
            extraDeltaFrame: extraDeltaFrame)
        if (item.frame, item.layer) != before {
            configuration.onModelChanged()
        }
    }

    /// トリム（本家 ResizeHeadCommand / ResizeFootCommand）。
    private func applyResize(
        head: Bool, point: NSPoint, modifierFlags: NSEvent.ModifierFlags,
        timeline: Timeline
    ) {
        guard let configuration, let item = grabbedItem else { return }
        // 本家は ResizeHeadCommand / ResizeFootCommand の冒頭
        // （未選択なら選択した直後、デルタ計算・吸着補正より前）でも
        // isSelectedCommandExecuted を立てる。移動と同じく、実行経路に
        // 入った時点で立てる（FE-R10-002）。
        didExecuteEditCommand = true
        let totalFrames = Int((point.x - startPoint.x) / pxPerFrame)
        let applied = head
            ? item.frame - grabbedStart.frame
            : item.length - grabbedStart.length
        var delta = totalFrames - applied
        if !modifierFlags.contains(.shift) {
            // 素材内部の区切り（ContentSeparations）は Core に供給が無いため
            // extraSnapPoints は空。本家の吸着先のうち現在フレーム・
            // アイテム端・キーフレームは getSnappedDelta が候補に含む。
            delta = timeline.getSnappedDelta(
                snapTargetFrames: [head ? item.frame : item.frame + item.length],
                baseLayer: item.layer, frameDelta: delta,
                frameDistance: snapFrameDistance,
                layerDistance: snapLayerDistance,
                ignoreItems: timeline.selectedAndGroupedItems)
        }
        // 隣接影響は「設定の既定（未設定 = None） XOR Ctrl」で Stretch。
        // 設定画面が無いため既定は None 固定とし、Ctrl 中は Stretch。
        let neighborAffect: NeighborAffectMode =
            modifierFlags.contains(.control) ? .stretch : .none
        let before = (item.frame, item.length)
        timeline.changeSelectedAndGroupedItemsLength(
            deltaX: delta, head: head, neighborAffect: neighborAffect)
        if (item.frame, item.length) != before {
            configuration.onModelChanged()
        }
    }

    /// キーフレームのドラッグ（本家 TimelineItemKeyFrameViewModel）。
    /// 隣を越えない丸めは Core の moveKeyFrame が担う。
    private func applyKeyframeDrag(point: NSPoint, modifierFlags: NSEvent.ModifierFlags, timeline: Timeline) {
        guard let configuration, let item = grabbedItem,
              item.keyFrames.frames.indices.contains(keyframeIndex)
        else { return }
        // 本家のキーフレーム移動（TimelineItemKeyFrameViewModel の
        // DragDeltaCommand）は isSelectedCommandExecuted を立てない
        // （フラグは移動・トリム系コマンドの冒頭専用）。ここでも
        // 立てない（FE-R10-002）。
        let current = item.keyFrames.frames[keyframeIndex]
        let totalFrames = Int((point.x - startPoint.x) / pxPerFrame)
        var delta = totalFrames - (current - startKeyFrame)
        if !modifierFlags.contains(.shift) {
            delta = timeline.getSnappedDelta(
                snapTargetFrames: [item.frame + current],
                baseLayer: item.layer, frameDelta: delta,
                frameDistance: snapFrameDistance,
                layerDistance: snapLayerDistance,
                ignoreItems: timeline.selectedAndGroupedItems)
        }
        if item.moveKeyFrame(from: current, to: current + delta) {
            configuration.onModelChanged()
        }
    }

    private func updateMarquee(point: NSPoint) {
        marqueeRect = CGRect(
            x: min(startPoint.x, point.x), y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x), height: abs(point.y - startPoint.y))
        needsDisplay = true
    }

    // MARK: - MouseUp（確定）

    override func mouseUp(with event: NSEvent) {
        guard mode != .none, let configuration, let timeline else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .move, .resizeHead, .resizeFoot, .keyframe:
            // 本家はドラッグ完了時に RefreshTimelineLengthAndMaxLayer で
            // 長さキャッシュを再計算する。Core の移動・トリムは Expand
            // （広げるだけ）なので、短縮方向はここで再計算しないと
            // キャッシュが実際の最終フレームより長いまま残る
            // （FE-R9-001。出力尺は TimelineExporter がこの長さを使う）。
            let lengthBefore = timeline.length
            let maxLayerBefore = timeline.maxLayer
            timeline.refreshTimelineLengthAndMaxLayer()
            if timeline.length != lengthBefore
                || timeline.maxLayer != maxLayerBefore {
                configuration.onModelChanged()
            }
            let changed = modelDiffersFromSnapshot(timeline: timeline)
            // 編集コマンドの実行されなかったクリックでは、MouseDown で
            // 保留した単独選択への確定を行う（FE-R9-005）。判定は最終
            // 差分ではなくコマンド実行の有無で行う（FE-R10-002:
            // 往復ドラッグでは最終差分がゼロでもドラッグは成立して
            // おり、本家はその場合に単独選択化を抑制する）。
            if !changed, !didExecuteEditCommand, let target = clickCollapseItem,
               timeline.items.contains(where: { $0 === target }) {
                timeline.selectItem(target)
                configuration.onSelectionChanged()
            }
            // 確定通知は変更の有無にかかわらず必ず送る（FE-R9-003）。
            // スナップショットを破棄する endSession より前に呼ぶ
            // （FE-R9-002）。
            configuration.onDragCommitted()
            endSession()
        case .lockButton:
            if let item = grabbedItem, isInLockRect(item: item, point: point) {
                item.isLocked.toggle()
                configuration.onModelChanged()
            }
            // 領域外で離した場合も、開始したセッションには必ず終了を
            // 通知する（FE-R9-003）。
            configuration.onDragCommitted()
            endSession()
        case .marquee:
            // 本家 CompleteSelectRange: 矩形の角をフレーム／レイヤーへ
            // 切り捨て換算し、正規化してから範囲選択を1回で確定する。
            let fromFrame = Int(startPoint.x / pxPerFrame)
            let toFrame = Int(point.x / pxPerFrame)
            let fromLayer = Int(startPoint.y / rowHeight)
            let toLayer = Int(point.y / rowHeight)
            timeline.selectBetweenItems(
                fromFrame: min(fromFrame, toFrame),
                fromLayer: min(fromLayer, toLayer),
                toFrame: max(fromFrame, toFrame),
                toLayer: max(fromLayer, toLayer))
            marqueeRect = .zero
            needsDisplay = true
            endSession()
            configuration.onSelectionChanged()
        case .background:
            // 範囲選択へ移行しなかったクリックとして、シークをここで
            // 確定する（FE-R9-004）。
            let frame = Int(point.x / pxPerFrame)
            configuration.onSeek(min(max(frame, 0), timeline.length))
            endSession()
        case .none:
            break
        }
    }

    // MARK: - キャンセル（開始時状態へ復元）

    /// 対象タイムラインの差し替え時など、外からセッションを畳む入口。
    /// 復元は差し替え前の設定（対象・コールバック）で行われる。
    func cancelActiveSessionIfNeeded() {
        if mode != .none {
            cancelSession()
        }
    }

    private func cancelSession() {
        guard mode != .none, let configuration, let timeline else { return }
        if hasSnapshot {
            restoreSnapshot(timeline: timeline)
            configuration.onModelChanged()
            // 復元には選択の復元も含まれる。onSelectionChanged を
            // 呼ばないとインスペクタ側の選択写し（selectedItemIndex）が
            // MouseDown でクリックしたアイテムのまま残り、Core 選択と
            // 乖離する（FE-R10-001。その後の編集操作で UI 側の選択が
            // Core へ再同期され、復元したはずと違うアイテムが編集・
            // 削除対象になり得る）。
            configuration.onSelectionChanged()
        } else {
            // 範囲選択の途中なら選択だけを戻す。
            timeline.selectItems(snapshotSelection)
            configuration.onSelectionChanged()
        }
        marqueeRect = .zero
        needsDisplay = true
        // キャンセル通知もセッション状態の破棄より前に呼ぶ（FE-R9-002）。
        configuration.onDragCancelled()
        endSession()
    }

    private func takeSnapshot(timeline: Timeline) {
        snapshot = timeline.items.map {
            ItemState(
                item: $0, frame: $0.frame, length: $0.length, layer: $0.layer,
                contentOffsetTicks: $0.contentOffset.ticks,
                keyFrameFrames: $0.keyFrames.frames)
        }
        snapshotSelection = timeline.selectedItems
        hasSnapshot = true
    }

    private func restoreSnapshot(timeline: Timeline) {
        for state in snapshot {
            state.item.frame = state.frame
            state.item.length = state.length
            state.item.layer = state.layer
            state.item.contentOffset = TimeSpanValue(ticks: state.contentOffsetTicks)
            state.item.setKeyFrames(KeyFrames(frames: state.keyFrameFrames))
        }
        // メンバーシップと並び順は、スナップショットのアイテム列を
        // そのまま代入して復元する（FE-R9-006）。欠落分を末尾へ
        // 追加し直す方式では順序が変わり、重なったアイテムの当たり
        // 判定（items の後方優先）まで変わってしまう。items の代入に
        // 伴う選択の掃除（didSet）は、この後の selectItems で
        // スナップショットの選択へ戻すため問題にならない。
        timeline.items = snapshot.map { $0.item }
        timeline.selectItems(snapshotSelection)
        timeline.refreshTimelineLengthAndMaxLayer()
    }

    private func modelDiffersFromSnapshot(timeline: Timeline) -> Bool {
        guard hasSnapshot else { return false }
        if timeline.items.count != snapshot.count { return true }
        for state in snapshot {
            guard timeline.items.contains(where: { $0 === state.item })
            else { return true }
            let item = state.item
            if item.frame != state.frame || item.length != state.length
                || item.layer != state.layer
                || item.contentOffset.ticks != state.contentOffsetTicks
                || item.keyFrames.frames != state.keyFrameFrames {
                return true
            }
        }
        return false
    }

    // MARK: - セッションの監視（Escape・非アクティブ化でキャンセル）

    private func beginMonitoring() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            if event.keyCode == 53 {  // Escape
                self?.cancelSession()
                return nil
            }
            return event
        }
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                // 配送はメインキュー固定のため MainActor 前提でよい。
                MainActor.assumeIsolated { self?.cancelSession() }
            }
        }
    }

    private func endSession() {
        mode = .none
        grabbedItem = nil
        keyframeIndex = -1
        clickCollapseItem = nil
        didExecuteEditCommand = false
        snapshot = []
        snapshotSelection = []
        hasSnapshot = false
        stopAutoScroll()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
    }

    // MARK: - 端の自動スクロール

    private func updateAutoScroll() {
        guard mode == .move || mode == .resizeHead || mode == .resizeFoot
                || mode == .keyframe || mode == .marquee,
              scrollOwner != nil
        else {
            stopAutoScroll()
            return
        }
        if autoScrollTimer == nil {
            let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
                // メイン RunLoop 上で発火するため MainActor 前提でよい。
                MainActor.assumeIsolated { self?.autoScrollTick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            autoScrollTimer = timer
        }
    }

    private func autoScrollTick() {
        guard mode != .none, let scrollOwner else {
            stopAutoScroll()
            return
        }
        let point = convert(lastWindowPoint, from: nil)
        let visible = visibleRect
        let margin: CGFloat = 24
        let step: CGFloat = 12
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if point.x < visible.minX + margin { dx = -step }
        if point.x > visible.maxX - margin { dx = step }
        if point.y < visible.minY + margin { dy = -step }
        if point.y > visible.maxY - margin { dy = step }
        if dx == 0 && dy == 0 {
            stopAutoScroll()
            return
        }
        scrollOwner.scrollCanvasBy(dx: dx, dy: dy)
        // スクロールで同じウィンドウ座標が指すコンテンツ点が変わるため、
        // 最後のポインタ位置でドラッグ適用をやり直す。
        let newPoint = convert(lastWindowPoint, from: nil)
        applyDragged(point: newPoint, modifierFlags: lastModifierFlags)
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    // MARK: - 描画（範囲選択の矩形だけ）

    override func draw(_ dirtyRect: NSRect) {
        guard mode == .marquee, marqueeRect.width > 0, marqueeRect.height > 0
        else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        marqueeRect.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
        let path = NSBezierPath(rect: marqueeRect)
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - 当たり判定とモード決定（本家 TimelineItemView.DecideMode）

    private struct Hit {
        let item: BaseItem
        let keyframeIndex: Int
    }

    private func hitItem(at point: NSPoint, timeline: Timeline) -> Hit? {
        let frame = Int(point.x / pxPerFrame)
        let layer = Int(point.y / rowHeight)
        guard let item = timeline.items.last(where: {
            $0.layer == layer && $0.frame <= frame && frame < $0.frame + $0.length
        }) else { return nil }
        // キーフレームの最近傍（6px以内）。
        var nearestIndex = -1
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        let relX = point.x - CGFloat(item.frame) * pxPerFrame
        for (index, keyFrame) in item.keyFrames.frames.enumerated() {
            let distance = abs(CGFloat(keyFrame) * pxPerFrame - relX)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        return Hit(
            item: item,
            keyframeIndex: nearestDistance <= 6 ? nearestIndex : -1)
    }

    /// モード決定の優先順位は本家 DecideMode どおり:
    /// 左つまみ→右つまみ→キーフレーム→ロックボタン→移動。
    private func decideMode(for hit: Hit, at point: NSPoint) -> Mode {
        let item = hit.item
        let relX = point.x - CGFloat(item.frame) * pxPerFrame
        let width = CGFloat(item.length) * pxPerFrame
        let grip = min(6, width / 3)
        if relX <= grip { return .resizeHead }
        if width - relX <= grip { return .resizeFoot }
        if hit.keyframeIndex >= 0 { return .keyframe }
        if item.isLocked, isInLockRect(item: item, point: point) {
            return .lockButton
        }
        return .move
    }

    /// ロックアイコンの当たり領域（ブロック右上、描画位置に合わせた近似）。
    private func isInLockRect(item: BaseItem, point: NSPoint) -> Bool {
        let width = CGFloat(item.length) * pxPerFrame
        let relX = point.x - CGFloat(item.frame) * pxPerFrame
        let relY = point.y - CGFloat(item.layer) * rowHeight
        return relX >= width - 20 && relX <= width && relY >= 0 && relY < 20
    }
}
