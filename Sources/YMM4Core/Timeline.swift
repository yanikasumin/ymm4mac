import Foundation

/// タイムライン。本家 `Timeline` に対応する。
///
/// `Length` / `MaxLayer` は本家同様、アイテム集合から再計算される
/// キャッシュ済みの派生値である（保持フィールドを持ち、追加・移動では
/// Expand、削除では Refresh という使い分けも本家どおり）。
/// 編集操作は `TimelineEditing.swift` に分離する。
public final class Timeline {
    /// タイムライン ID。
    public var id: UUID = UUID()
    /// 名前。
    public var name: String = ""
    /// 動画の基本情報。
    public var videoInfo: VideoInfo = VideoInfo()
    /// 補助線設定。
    public var verticalLine: TimelineVerticalLine = TimelineVerticalLine()
    /// アイテム集合。代入すると、消えたアイテムは選択から外れる
    /// （本家の Items setter の挙動）。
    public var items: [BaseItem] = [] {
        didSet {
            let removed = oldValue.filter { old in !items.contains(where: { $0 === old }) }
            if !removed.isEmpty {
                selectedItems.removeAll { selected in removed.contains(where: { $0 === selected }) }
            }
        }
    }
    /// レイヤー設定。
    public var layerSettings: LayerSettings = LayerSettings()
    /// 選択中のアイテム（保存対象外）。
    public var selectedItems: [BaseItem] = []

    private var currentFrameStorage: Int = 0
    /// 現在フレーム。負値は 0 に丸められ、ロック中は変更できない
    /// （本家の CurrentFrame setter の挙動）。保存対象。
    public var currentFrame: Int {
        get { currentFrameStorage }
        set {
            if isCurrentFrameLocked { return }
            currentFrameStorage = max(0, newValue)
        }
    }
    /// 現在フレームがロックされているか（保存対象外）。
    public var isCurrentFrameLocked: Bool = false

    /// 長さのキャッシュ（アイテムの最大終了フレーム、最小 1）。
    public private(set) var length: Int = 1
    /// 最大レイヤーのキャッシュ。
    public private(set) var maxLayer: Int = 0

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    /// グループ番号の発行カウンタ（保存対象外）。
    var publishedGroupIndex: Int = 0
    /// 分割の Center モード用に保持する前回の分割対象（保存対象外）。
    var prevSplitItems: [BaseItem] = []
    /// 分割の Center モード用に保持する分割フレーム履歴（保存対象外）。
    var splitFrames: [Int] = []

    public init() {}

    // MARK: - Length / MaxLayer のキャッシュ保守

    /// 現在のアイテム集合から求まる長さ（最大の Frame + Length、無ければ 1）。
    public func computeCurrentLength() -> Int {
        items.map { $0.frame + $0.length }.max() ?? 1
    }

    /// 現在のアイテム集合から求まる最大レイヤー（無ければ 0）。
    public func computeCurrentMaxLayer() -> Int {
        items.map { $0.layer }.max() ?? 0
    }

    /// キャッシュを再計算で置き換える。本家 `RefreshTimelineLengthAndMaxLayer`。
    public func refreshTimelineLengthAndMaxLayer() {
        length = computeCurrentLength()
        maxLayer = computeCurrentMaxLayer()
    }

    /// キャッシュを現在の値との最大で広げる。本家 `ExpandTimelineLengthAndMaxLayer`。
    public func expandTimelineLengthAndMaxLayer() {
        length = max(length, computeCurrentLength())
        maxLayer = max(maxLayer, computeCurrentMaxLayer())
    }

    /// キャッシュを直接設定する（.ymmp 読み込み時の復元用。
    /// 本家では private setter を Newtonsoft が設定する）。
    func restoreCachedLength(_ length: Int, maxLayer: Int) {
        self.length = length
        self.maxLayer = maxLayer
    }

    // MARK: - 選択とグループの参照

    /// 選択中アイテムと、そのグループに属する全アイテム。
    /// 本家 `SelectedAndGroupedItems`。
    public var selectedAndGroupedItems: [BaseItem] {
        getItemsAndGroupedItems(selectedItems)
    }

    /// 指定アイテムと、そのグループに属する全アイテム。
    /// 本家 `GetItemsAndGroupedItems`: 指定アイテムを先に並べ、続いて
    /// グループに属するアイテムを Items の順で重複なく追加する。
    public func getItemsAndGroupedItems(_ targets: [BaseItem]) -> [BaseItem] {
        let groups = Set(targets.map { $0.group }.filter { $0 != 0 })
        var result = targets
        for item in items where item.group != 0 && groups.contains(item.group) {
            if !result.contains(where: { $0 === item }) {
                result.append(item)
            }
        }
        return result
    }

    /// 指定アイテムのグループに属する（指定アイテム自身を除く）全アイテム。
    /// 本家 `GetGroupedItems`。
    public func getGroupedItems(_ targets: [BaseItem]) -> [BaseItem] {
        let groups = Set(targets.map { $0.group }.filter { $0 != 0 })
        return items.filter { item in
            item.group != 0 && groups.contains(item.group)
                && !targets.contains(where: { $0 === item })
        }
    }

    /// 選択を設定する。本家 `SelectItems`。
    public func selectItems(_ targets: [BaseItem]?) {
        guard let targets else { return }
        selectedItems = targets
    }
}
