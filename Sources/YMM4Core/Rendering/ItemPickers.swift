import Foundation

/// 顔アイテム（立ち絵の顔・声の解決対象）。本家 IFaceItem に対応し、
/// 実装は TachieFaceItem と VoiceItem のみ（本家の実装範囲どおり）。
public protocol FaceItem: AnyObject {}

extension TachieFaceItem: FaceItem {}
extension VoiceItem: FaceItem {}

/// 指定フレームで有効なアイテムの選定。本家 IItemPicker に対応する。
/// 選定は TimelineSource 相当（次段）が資源管理に使う純粋な判定であり、
/// アイテムやタイムラインを変更しない。
public protocol ItemPicker {
    /// 指定フレームで描画対象になるアイテムを選ぶ。
    func pickItems(in timeline: Timeline, frame: Int) -> [BaseItem]
    /// 指定フレームで有効な顔アイテムを選ぶ（立ち絵の顔・声解決用）。
    func pickFaceItems(in timeline: Timeline, frame: Int) -> [BaseItem]
}

/// レイヤーが表示設定か（本家 LayerSettings.IsVisibles[layer] と同じ:
/// そのレイヤーの設定が無ければ表示、IsHidden の設定があれば非表示）。
private func isLayerVisible(in timeline: Timeline, layer: Int) -> Bool {
    !(timeline.layerSettings.items.first { $0.layer == layer }?.isHidden ?? false)
}

/// 標準の選定。本家 CompositeItemPicker に対応する。
///
/// 全体用（groupItem == nil）と、合成グループ内部用（groupItem != nil）の
/// 2形態がある。規則（第5章で確定）:
/// - フレームを含み、非表示でなく、レイヤーが表示中のアイテムが候補。
/// - 合成グループの子アイテムは候補から除外される（親が代表する）。
/// - トランジション規則: 候補中の最大レイヤーの TransitionItem より
///   下のレイヤーのアイテムは除外される（トランジション自身は残る）。
/// - グループ用では、フレームはグループ末尾（Frame + Length - 1）で
///   クランプされ、グループの子だけが候補になる。
public struct CompositeItemPicker: ItemPicker {
    /// 合成グループ内部用の場合の親グループ。全体用は nil。
    public let groupItem: GroupItem?

    public init(groupItem: GroupItem? = nil) {
        self.groupItem = groupItem
    }

    public func pickItems(in timeline: Timeline, frame: Int) -> [BaseItem] {
        var frame = frame
        if let groupItem {
            frame = min(frame, groupItem.frame + groupItem.length - 1)
        }
        let hiddenLayers = Set(
            timeline.layerSettings.items.filter { $0.isHidden }.map { $0.layer }
        )

        // 本家 GetChildItems。composite が合成グループならその子だけ、
        // それ以外（全体用）は全候補を返す。
        func childItems(of items: [BaseItem], composite: GroupItem?) -> [BaseItem] {
            if let composite, composite.isComposite {
                return items.filter { item in
                    item.contains(frame: frame)
                        && !item.isHidden
                        && !hiddenLayers.contains(item.layer)
                        && composite.layer < item.layer
                        && item.layer <= composite.layer + composite.groupRange
                        && (!composite.isGroupOnly
                            || (composite.group != 0 && composite.group == item.group))
                }
            }
            return items.filter { item in
                item.contains(frame: frame)
                    && !item.isHidden
                    && !hiddenLayers.contains(item.layer)
            }
        }

        let list = childItems(of: timeline.items, composite: groupItem)

        // 合成グループの子は親が代表するため候補から外す。
        var compositeChildren = Set<ObjectIdentifier>()
        for item in list {
            guard let group = item as? GroupItem, group.isComposite else { continue }
            for child in childItems(of: list, composite: group) {
                compositeChildren.insert(ObjectIdentifier(child))
            }
        }

        // トランジション規則の基準（子として除外されるトランジションは数えない）。
        var maxTransitionLayer = Int.min
        for item in list where item is TransitionItem && !compositeChildren.contains(ObjectIdentifier(item)) {
            maxTransitionLayer = max(maxTransitionLayer, item.layer)
        }

        return list.filter { item in
            !compositeChildren.contains(ObjectIdentifier(item))
                && item.layer >= maxTransitionLayer
        }
    }

    public func pickFaceItems(in timeline: Timeline, frame: Int) -> [BaseItem] {
        var frame = frame
        if let groupItem {
            frame = min(frame, groupItem.frame + groupItem.length - 1)
        }
        return timeline.items.filter { item in
            item is FaceItem
                && item.contains(frame: frame)
                && !item.isHidden
                && isLayerVisible(in: timeline, layer: item.layer)
        }
    }
}

/// トランジション前後の描画対象の選定。本家 TransitionItemPicker に対応する。
///
/// 対象はトランジションより下のレイヤーのみ。前側（isBefore）の場合は
/// 描画フレームがトランジション開始の1フレーム前に固定される。
/// トランジションを囲む合成グループがあれば、その子に限定される。
public struct TransitionItemPicker: ItemPicker {
    public let transitionItem: TransitionItem
    public let isBefore: Bool

    public init(transitionItem: TransitionItem, isBefore: Bool) {
        self.transitionItem = transitionItem
        self.isBefore = isBefore
    }

    /// 本家 IsCompositeChild。レイヤー範囲内であり、グループ限定の場合は
    /// グループ番号も一致すること。
    private static func isCompositeChild(_ composite: GroupItem, of item: BaseItem) -> Bool {
        let inRange = composite.layer < item.layer
            && item.layer <= composite.layer + composite.groupRange
        if !composite.isGroupOnly {
            return inRange
        }
        return (composite.group != 0 && composite.group == item.group) && inRange
    }

    public func pickItems(in timeline: Timeline, frame: Int) -> [BaseItem] {
        let frame = isBefore ? transitionItem.frame - 1 : frame

        // トランジションを囲む最も下層でない（最大レイヤーの）合成グループ。
        let parentComposite = timeline.items
            .compactMap { $0 as? GroupItem }
            .filter { group in
                group.contains(frame: frame)
                    && !group.isHidden
                    && isLayerVisible(in: timeline, layer: group.layer)
                    && group.layer < transitionItem.layer
                    && group.isComposite
                    && Self.isCompositeChild(group, of: transitionItem)
            }
            .max { $0.layer < $1.layer }

        let list = timeline.items.filter { item in
            item.contains(frame: frame)
                && !item.isHidden
                && isLayerVisible(in: timeline, layer: item.layer)
                && item.layer < transitionItem.layer
                && (parentComposite == nil || Self.isCompositeChild(parentComposite!, of: item))
        }

        // 親以外の合成グループの子は、そのグループ内部で描かれるため外す。
        let otherComposites = list.compactMap { $0 as? GroupItem }.filter { group in
            group.isComposite && group !== parentComposite
        }
        return list.filter { item in
            !otherComposites.contains { Self.isCompositeChild($0, of: item) }
        }
    }

    public func pickFaceItems(in timeline: Timeline, frame: Int) -> [BaseItem] {
        let frame = isBefore ? transitionItem.frame - 1 : frame
        return timeline.items.filter { item in
            item is FaceItem
                && item.contains(frame: frame)
                && !item.isHidden
                && isLayerVisible(in: timeline, layer: item.layer)
        }
    }
}
