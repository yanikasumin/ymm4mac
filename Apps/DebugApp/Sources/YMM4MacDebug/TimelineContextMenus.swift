import AppKit
import SwiftUI
import YMM4Core

/// タイムラインのコンテキストメニューと、それが呼ぶ編集操作。
///
/// 本家の定義は analysis-notes/UI-FACTS-MENUS-CONTEXT.md §2:
/// キャンバス背景29葉／アイテム上46葉／キーフレーム上6葉／目盛り13葉／
/// レイヤーラベル13葉。本家は右クリック位置を操作対象にするが、
/// SwiftUI の contextMenu では位置が取れないため、こちらは
/// 再生ヘッド位置とクリックしたアイテムを対象にする（差異として
/// 台帳に記録）。接続先（Core の編集操作）が無い項目は含めない。
extension TimelineStripView {

    // MARK: - ホイールズーム（本家 TimelineScaleView の ScrollCommand）

    /// 目盛り帯の上でのホイールをズームに変える監視を入れる。
    /// 倍率は本家どおり ×1.125 / ×0.875 刻み。キャンバス側の
    /// スクロールは妨げない（目盛りの矩形内だけ消費する）。
    func installWheelZoomMonitor() {
        guard wheelMonitor == nil else { return }
        let box = rulerRectBox
        let zoom = $zoomPercent
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let window = event.window, window.isKeyWindow,
                  box.rect.width > 0,
                  box.rect.contains(event.locationInWindow)
            else { return event }
            let delta = event.scrollingDeltaY
            if delta > 0 {
                // 本家ホイール拡大は上限なしだが、安全上限として
                // ZoomInTimeline コマンドの上限 4000 を流用する。
                zoom.wrappedValue = min(zoom.wrappedValue * 1.125, 4000)
            } else if delta < 0 {
                // 本家ホイール縮小の下限は 0.01
                // （TimelineScaleViewModel.cs 225–231）。
                zoom.wrappedValue = max(zoom.wrappedValue * 0.875, 0.01)
            }
            return nil
        }
    }

    func removeWheelZoomMonitor() {
        if let wheelMonitor {
            NSEvent.removeMonitor(wheelMonitor)
        }
        wheelMonitor = nil
    }

    // MARK: - 共用操作

    /// アイテムを再生ヘッド位置・表示最上段レイヤーへ追加する
    /// （本家の追加コマンドの CommandParameter は右クリック位置だが、
    /// こちらは再生ヘッド＋ GetCurrentLayer() で代替する）。
    func addItemAtPlayhead(kind: AddItemKind) {
        let item = ItemFactory.makeItem(kind: kind)
        item.frame = currentFrame
        item.layer = rowHeight > 0 ? Int(verticalOffset / rowHeight) : 0
        item.length = ItemFactory.placeholderLength(fps: timeline.videoInfo.fps)
        timeline.addItems([item])
        timeline.refreshTimelineLengthAndMaxLayer()
        if let index = timeline.items.firstIndex(where: { $0 === item }) {
            selectedItemIndex = index
            timeline.selectItems([item])
        }
        layerRevision += 1
        onEdited()
    }

    /// 再生ヘッド位置で、そこを跨ぐ全アイテムを分割する。
    func splitAtPlayhead() {
        let targets = timeline.items.filter {
            $0.frame < currentFrame && currentFrame < $0.frame + $0.length
        }
        guard !targets.isEmpty else { return }
        timeline.splitItems(targets, frame: currentFrame, mode: .both)
        reflectSelection()
        onEdited()
    }

    /// Core 側の選択を UI のインデックス選択へ写す。
    func reflectSelection() {
        if let first = timeline.selectedItems.first,
           let index = timeline.items.firstIndex(where: { $0 === first }) {
            selectedItemIndex = index
        } else {
            selectedItemIndex = nil
        }
    }

    func selectItems(where predicate: (BaseItem) -> Bool) {
        timeline.selectItems(timeline.items.filter(predicate))
        reflectSelection()
    }

    // MARK: - キャンバス背景メニュー（本家 §2.1）

    @ViewBuilder
    func canvasContextMenu() -> some View {
        Menu(UIStrings.Menu.addItem) {
            ForEach(AddItemKind.allCases, id: \.self) { kind in
                Button(kind.displayName) { addItemAtPlayhead(kind: kind) }
            }
        }
        Divider()
        Button(UIStrings.Timeline.splitAtPlayhead) { splitAtPlayhead() }
        Divider()
        Button(UIStrings.Timeline.deleteTimelineSpace) {
            _ = timeline.deleteTimelineSpace(frame: currentFrame)
            onEdited()
        }
        Button(UIStrings.Timeline.deleteAllTimelineSpaces) {
            timeline.deleteAllTimelineSpaces()
            onEdited()
        }
        Divider()
        Button(UIStrings.Toolbar.gridLine) { showVerticalLines.toggle() }
        Divider()
        Button(UIStrings.Menu.selectLeftItems) {
            selectItems { $0.frame + $0.length <= currentFrame }
        }
        Button(UIStrings.Menu.selectRightItems) {
            selectItems { $0.frame >= currentFrame }
        }
        Button(UIStrings.Menu.selectAll) {
            selectItems { _ in true }
        }
    }

    // MARK: - 目盛りメニュー（本家 §2.2。追加は8種のみが本家）

    @ViewBuilder
    func rulerContextMenu() -> some View {
        Menu(UIStrings.Menu.addItem) {
            ForEach(
                [AddItemKind.voice, .text, .video, .audio, .image, .shape, .tachie, .face],
                id: \.self
            ) { kind in
                Button(kind.displayName) { addItemAtPlayhead(kind: kind) }
            }
        }
        Divider()
        Button(UIStrings.Timeline.splitAtPlayhead) { splitAtPlayhead() }
        Divider()
        Button(UIStrings.Menu.selectLeftItems) {
            selectItems { $0.frame + $0.length <= currentFrame }
        }
        Button(UIStrings.Menu.selectRightItems) {
            selectItems { $0.frame >= currentFrame }
        }
        Button(UIStrings.Menu.selectAll) {
            selectItems { _ in true }
        }
    }

    // MARK: - アイテム上メニュー（本家 §2.4）

    @ViewBuilder
    func itemContextMenu(index: Int, item: BaseItem) -> some View {
        Button(UIStrings.Timeline.splitAtPlayhead) {
            selectedItemIndex = index
            splitAtPlayhead()
        }
        Divider()
        Button(UIStrings.Timeline.addKeyFrameAtPlayhead) {
            addKeyFrame(item: item, atRelativeFrame: currentFrame - item.frame)
        }
        Button(UIStrings.Timeline.removeKeyFrameAtPlayhead) {
            removeKeyFrame(item: item, atRelativeFrame: currentFrame - item.frame)
        }
        Button(UIStrings.Timeline.removeAllKeyFrames) {
            item.setKeyFrames(KeyFrames())
            onEdited()
        }
        Button(UIStrings.Timeline.distributeKeyFrames) {
            var keyFrames = item.keyFrames
            keyFrames.distribute(length: item.length)
            item.setKeyFrames(keyFrames)
            onEdited()
        }
        Divider()
        if item.group != 0 {
            Button(UIStrings.Menu.ungroup) {
                timeline.selectItems([item])
                timeline.ungroupSelectedAndGroupedItems()
                onEdited()
            }
        } else {
            Button(UIStrings.Menu.group) {
                timeline.selectItems([item])
                timeline.groupSelectedAndGroupedItems()
                onEdited()
            }
        }
        if let visual = item as? VisualItem {
            Button(visual.isClippingWithObjectAbove
                ? UIStrings.Toolbar.clippingOff : UIStrings.Toolbar.clippingOn) {
                visual.isClippingWithObjectAbove.toggle()
                onEdited()
            }
        } else if let voice = item as? VoiceItem {
            Button(voice.isClippingWithObjectAbove
                ? UIStrings.Toolbar.clippingOff : UIStrings.Toolbar.clippingOn) {
                voice.isClippingWithObjectAbove.toggle()
                onEdited()
            }
        }
        Button(item.isLocked ? UIStrings.Toolbar.unlock : UIStrings.Toolbar.lock) {
            item.isLocked.toggle()
            onEdited()
        }
        if let voice = item as? VoiceItem {
            Button(voice.isWaveformEnabled
                ? UIStrings.Toolbar.waveformHidden : UIStrings.Toolbar.waveformAlways) {
                voice.isWaveformEnabled.toggle()
                onEdited()
            }
        }
        Divider()
        Menu(UIStrings.Menu.move) {
            Button(UIStrings.Timeline.moveLeftFrame) {
                timeline.moveItems([item], deltaFrame: -1, deltaLayer: 0)
                onEdited()
            }
            Button(UIStrings.Timeline.moveRightFrame) {
                timeline.moveItems([item], deltaFrame: 1, deltaLayer: 0)
                onEdited()
            }
            Button(UIStrings.Timeline.moveLeftSecond) {
                timeline.moveItems(
                    [item], deltaFrame: -max(timeline.videoInfo.fps, 1), deltaLayer: 0)
                onEdited()
            }
            Button(UIStrings.Timeline.moveRightSecond) {
                timeline.moveItems(
                    [item], deltaFrame: max(timeline.videoInfo.fps, 1), deltaLayer: 0)
                onEdited()
            }
            Button(UIStrings.Timeline.moveUpLayer) {
                timeline.moveItems([item], deltaFrame: 0, deltaLayer: -1)
                onEdited()
            }
            Button(UIStrings.Timeline.moveDownLayer) {
                timeline.moveItems([item], deltaFrame: 0, deltaLayer: 1)
                onEdited()
            }
        }
        Divider()
        Button(UIStrings.Menu.deleteSelection) {
            timeline.deleteItems([item])
            if selectedItemIndex == index { selectedItemIndex = nil }
            onEdited()
        }
    }

    /// キーフレームを追加する（相対フレームが範囲内のときだけ）。
    func addKeyFrame(item: BaseItem, atRelativeFrame relative: Int) {
        guard relative >= 0, relative < item.length else { return }
        var keyFrames = item.keyFrames
        keyFrames.insert(relative)
        item.setKeyFrames(keyFrames)
        onEdited()
    }

    func removeKeyFrame(item: BaseItem, atRelativeFrame relative: Int) {
        var keyFrames = item.keyFrames
        guard keyFrames.remove(relative) != nil else { return }
        item.setKeyFrames(keyFrames)
        onEdited()
    }

    // MARK: - レイヤー操作（本家 §2.3 の追加／削除／移動）

    /// レイヤーを挿入する（その位置以上のアイテムと設定を1つ下げる）。
    func insertLayer(at newLayer: Int) {
        for item in timeline.items where item.layer >= newLayer {
            item.layer += 1
        }
        shiftLayerSettings { layer in layer >= newLayer ? layer + 1 : layer }
        timeline.refreshTimelineLengthAndMaxLayer()
        layerRevision += 1
        onEdited()
    }

    /// レイヤーを削除する（そのレイヤーのアイテムも削除し、上を詰める。
    /// 本家 DeleteLayer と同じく、対象レイヤーの中身ごと消える）。
    func deleteLayer(at target: Int) {
        let doomed = timeline.items.filter { $0.layer == target }
        if !doomed.isEmpty {
            timeline.deleteItems(doomed)
        }
        for item in timeline.items where item.layer > target {
            item.layer -= 1
        }
        timeline.layerSettings.items.removeAll { $0.layer == target }
        shiftLayerSettings { layer in layer > target ? layer - 1 : layer }
        timeline.refreshTimelineLengthAndMaxLayer()
        if let selected = selectedItemIndex,
           timeline.items.indices.contains(selected) == false {
            selectedItemIndex = nil
        }
        layerRevision += 1
        onEdited()
    }

    /// レイヤーの中身を隣と入れ替える。
    func swapLayers(_ a: Int, _ b: Int) {
        guard a != b else { return }
        for item in timeline.items {
            if item.layer == a { item.layer = -1 }
        }
        for item in timeline.items where item.layer == b {
            item.layer = a
        }
        for item in timeline.items where item.layer == -1 {
            item.layer = b
        }
        shiftLayerSettings { layer in
            layer == a ? b : (layer == b ? a : layer)
        }
        timeline.refreshTimelineLengthAndMaxLayer()
        layerRevision += 1
        onEdited()
    }

    /// レイヤー設定のレイヤー番号を写像で付け替える。
    func shiftLayerSettings(_ map: (Int) -> Int) {
        for index in timeline.layerSettings.items.indices {
            var setting = timeline.layerSettings.items[index]
            setting.layer = map(setting.layer)
            timeline.layerSettings.items[index] = setting
        }
    }
}
