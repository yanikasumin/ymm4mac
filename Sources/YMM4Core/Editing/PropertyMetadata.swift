import Foundation

/// 編集 UI のための型付きプロパティメタデータ（MAC-0029）。
///
/// 本家はアイテム・エフェクトの各プロパティに付いた `Display` 属性
/// （グループ名・表示名・説明・順序、文言は `Texts` リソース）から
/// プロパティエディタを自動生成する。こちらでも同じ土台として、
/// モデルの既存プロパティを「表示名・グループ・値の型・読み書き」
/// の組（`PropertyDescriptor`）で記述し、UI 側はこの列挙だけから
/// インスペクタを生成する。プロパティの追加や永続化形式の変更は
/// 行わない（既存プロパティへの編集アクセスの提供に限る）。
///
/// 表示名は本家の `Texts` リソースに根拠があるものはその文言を使い、
/// 根拠が取れないものはプロパティ名そのままにする。

/// 列挙型プロパティの選択肢1つ。`value` は保存値（本家 enum のメンバ名）。
public struct PropertyEnumOption: Equatable, Sendable {
    public var value: String
    public var displayName: String

    public init(value: String, displayName: String) {
        self.value = value
        self.displayName = displayName
    }
}

/// ファイル参照の対象種別。本家 `FileSelector` 属性の
/// `FileGroupType` に対応し、選択ダイアログの絞り込みに使う。
public enum PropertyFileGroup: Equatable, Sendable {
    case video
    case audio
    case image
}

/// ファイル参照欄のサムネイル取得種別（FE-R15-005）。
///
/// 本家の FileSelector は、`ShowThumbnail` の付いたアイテム（動画・
/// 画像）でのみ、設定ファイルのサムネイルを非同期に取得して表示する
/// （FileSelector.cs の `FileItem.BeginLoadThumbnailAsync`）。
/// 取得方法の振り分けは記述子のファイル種別で決まる: 画像は画像
/// そのもの、動画はフレーム画像。実際の取得（ファイルを開く処理）
/// はアプリ層が行い、ここは「要るか・どちらの方法か」の決定だけを
/// 持つ（filePath 種別がファイルを開かない契約は変えない）。
public enum FileThumbnailKind: Equatable, Sendable {
    /// 画像ファイルそのものから取る。
    case image
    /// 動画ファイルのフレームから取る。
    case videoFrame

    /// 表示仕様と現在のパスから取得種別を決める。サムネイル不要
    /// （`showsThumbnail` が偽。音声が該当する）・パス未設定
    /// （空文字列）では nil を返す。
    public static func resolve(
        showsThumbnail: Bool, group: PropertyFileGroup, path: String
    ) -> FileThumbnailKind? {
        guard showsThumbnail, !path.isEmpty else { return nil }
        switch group {
        case .image:
            return .image
        case .video:
            return .videoFrame
        case .audio:
            return nil
        }
    }
}

/// プロパティの値の型と、編集 UI が必要とする付随情報。
public enum PropertyKind: Equatable, Sendable {
    /// 実数。範囲は編集時のクランプとスライダ表示に使う（nil は無制限）。
    case number(range: ClosedRange<Double>?)
    /// 整数。
    case integer(range: ClosedRange<Int>?)
    /// 真偽。
    case boolean
    /// 文字列。`multiline` は複数行編集（テキスト本文・セリフ）用。
    case text(multiline: Bool)
    /// 列挙。値は本家 enum のメンバ名で受け渡す（未知の名前も保持できる）。
    case enumeration(options: [PropertyEnumOption])
    /// 色（ARGB）。
    case color
    /// アニメーション付き数値。絶対制限は `Animation` 自身の定義値
    /// （minValue / maxValue）が持つため、ここでは持たない。
    /// `spec` はスライダの基準範囲等の表示仕様（本家
    /// `AnimationSliderAttribute` 由来、FE-R1-042）で、記述子構築時に
    /// `AnimationSliderTable` から解決して渡す。未登録のプロパティは
    /// nil のままにし、絶対制限全域のスライダへフォールバックしない
    /// （UI 側は数値入力のみ＋診断表示とする）。
    case animation(spec: AnimationSliderSpec?)
    /// ファイル参照。値はパス文字列だが、`.text` の変種にはしない:
    /// 選択ダイアログの対象種別とサムネイル表示の有無が編集 UI の
    /// 契約に含まれるため、独立した種別として持つ（FE-R1-043）。
    /// パスの読み書きは文字列として行い、ファイルを開く処理は
    /// ここでは行わない（情報取得は供給層、長さの調整は編集操作層）。
    case filePath(group: PropertyFileGroup, showsThumbnail: Bool)
    /// 複合オブジェクト（ブラシ等の入れ子）。子記述子の列は
    /// `PropertyAccess.object` 側が持つ（種別自体は関連値を持たない）。
    case object
    /// 複合コレクション（色停止点列・制御点列等）。要素の列挙と
    /// 追加・削除は `PropertyAccess.collection` 側が持つ。
    case collection
}

/// プロパティへの型付き読み書き。記述子と対象オブジェクトを結び付ける
/// クロージャの組であり、値の変換（列挙のメンバ名化など）はここで吸収する。
public enum PropertyAccess {
    case number(get: () -> Double, set: (Double) -> Void)
    case integer(get: () -> Int, set: (Int) -> Void)
    case boolean(get: () -> Bool, set: (Bool) -> Void)
    case text(get: () -> String, set: (String) -> Void)
    /// ファイル参照。パス文字列の読み書きだけを持ち、setter は
    /// ファイルを開かない（本家でも FilePath の setter は値の保持と
    /// 変更通知のみで、長さ調整は編集終了時に編集層が行う）。
    case filePath(get: () -> String, set: (String) -> Void)
    case enumeration(get: () -> String, set: (String) -> Void)
    case color(get: () -> Color, set: (Color) -> Void)
    /// アニメーション付き数値。定数値の編集は2経路を持つ:
    /// `setConstantValue` は補間種別を「なし」へ畳んで単一値にする
    /// （キーフレーム列は失われる）。`setFirstValue` は種別と値列を
    /// 保ったまま先頭値だけを書き換える。どちらも定義範囲へクランプする。
    /// `restoreState` は記録済みの状態（種別＋値列）を正規化なしで
    /// 書き戻す復元経路であり、種別変更と、値列全体を一体で記録する
    /// 編集（移動量指定の第2値。FE-R25-128-01）の Undo/Redo で使う。
    /// 通常の編集経路では使わない（種別変更は `setType` を通す）。
    case animation(
        get: () -> Animation,
        setConstantValue: (Double) -> Void,
        setFirstValue: (Double) -> Void,
        setType: (AnimationType) -> Void,
        setValueAtSegment: (Int, Double) -> Void,
        restoreState: (Animation.RecordedState) -> Void,
        setValueAtIndex: (Int, Double, ClosedRange<Double>) -> Void
    )
    /// 複合オブジェクト。子記述子は呼び出しのたびに現在の対象から
    /// 生成する（対象の内部型が切り替わりうるため、生成済みの列を
    /// 保持しない）。
    case object(children: () -> [PropertyDescriptor])
    /// 複合コレクション。`elements` は要素1件分の子記述子を返す。
    /// `insert` は既定値の要素を末尾へ追加し、`remove` は指定位置の
    /// 要素を取り除く。どちらも状態が実際に変わった場合にだけ true を
    /// 返す（要素数の上限・下限で丸め込まれて無変更になった場合や、
    /// 範囲外の位置を指定された場合は false。R22-117-01）。
    case collection(
        count: () -> Int,
        elements: (Int) -> [PropertyDescriptor],
        insert: () -> Bool,
        remove: (Int) -> Bool
    )
}

/// プロパティ1件のメタデータ。
public struct PropertyDescriptor {
    /// 安定した識別子（保存キー名と一致させる）。
    public var id: String
    /// 表示名（本家リソースに根拠があるものはその文言、無ければプロパティ名）。
    public var displayName: String
    /// グループ（セクション）名。
    public var group: String
    public var kind: PropertyKind
    public var access: PropertyAccess

    public init(
        id: String, displayName: String, group: String,
        kind: PropertyKind, access: PropertyAccess
    ) {
        self.id = id
        self.displayName = displayName
        self.group = group
        self.kind = kind
        self.access = access
    }

    // MARK: - 型付き読み書き（種類が合わない場合は nil / false）

    public var numberValue: Double? {
        guard case .number(let get, _) = access else { return nil }
        return get()
    }

    @discardableResult
    public func setNumberValue(_ value: Double) -> Bool {
        guard case .number(_, let set) = access else { return false }
        // 非有限値（NaN / 無限大）は書き込まない。モデルへ入ると
        // 保存時に JSON 側で 0.0 へ置換され、入力と異なる値で
        // 保存されてしまう（FE-R3-118-02。UI 側でも弾くが、
        // 全ての書き込み経路に対する防御としてここでも弾く）。
        guard value.isFinite else { return false }
        set(value)
        return true
    }

    public var integerValue: Int? {
        guard case .integer(let get, _) = access else { return nil }
        return get()
    }

    @discardableResult
    public func setIntegerValue(_ value: Int) -> Bool {
        guard case .integer(_, let set) = access else { return false }
        set(value)
        return true
    }

    public var boolValue: Bool? {
        guard case .boolean(let get, _) = access else { return nil }
        return get()
    }

    @discardableResult
    public func setBoolValue(_ value: Bool) -> Bool {
        guard case .boolean(_, let set) = access else { return false }
        set(value)
        return true
    }

    /// 文字列値（テキストと列挙の現在値。列挙では本家メンバ名を返す）。
    /// ファイル参照ではパス文字列を返す。
    public var stringValue: String? {
        switch access {
        case .text(let get, _), .enumeration(let get, _), .filePath(let get, _):
            return get()
        default:
            return nil
        }
    }

    @discardableResult
    public func setStringValue(_ value: String) -> Bool {
        switch access {
        case .text(_, let set), .enumeration(_, let set), .filePath(_, let set):
            set(value)
            return true
        default:
            return false
        }
    }

    /// ファイル参照の表示仕様（filePath 種別でなければ nil）。
    public var filePathSpec: (group: PropertyFileGroup, showsThumbnail: Bool)? {
        guard case .filePath(let group, let showsThumbnail) = kind else { return nil }
        return (group: group, showsThumbnail: showsThumbnail)
    }

    /// 現在設定されているパスのサムネイル取得種別（FE-R15-005）。
    /// サムネイルが不要な記述子・パス未設定では nil。
    public var fileThumbnailKind: FileThumbnailKind? {
        guard let spec = filePathSpec, let path = stringValue else { return nil }
        return FileThumbnailKind.resolve(
            showsThumbnail: spec.showsThumbnail, group: spec.group, path: path)
    }

    public var colorValue: Color? {
        guard case .color(let get, _) = access else { return nil }
        return get()
    }

    @discardableResult
    public func setColorValue(_ value: Color) -> Bool {
        guard case .color(_, let set) = access else { return false }
        set(value)
        return true
    }

    public var animationValue: Animation? {
        guard case .animation(let get, _, _, _, _, _, _) = access else { return nil }
        return get()
    }

    /// スライダ表示仕様（アニメーション種別でなければ nil。
    /// アニメーション種別でも未登録なら nil）。
    public var sliderSpec: AnimationSliderSpec? {
        guard case .animation(let spec) = kind else { return nil }
        return spec
    }

    /// 定数値として書き込む（補間種別を「なし」へ畳む）。
    @discardableResult
    public func setAnimationConstantValue(_ value: Double) -> Bool {
        guard case .animation(_, let setConstantValue, _, _, _, _, _) = access else { return false }
        setConstantValue(value)
        return true
    }

    /// 先頭値だけを書き換える（補間種別と値列は保つ）。
    @discardableResult
    public func setAnimationFirstValue(_ value: Double) -> Bool {
        guard case .animation(_, _, let setFirstValue, _, _, _, _) = access else { return false }
        setFirstValue(value)
        return true
    }

    /// 指定区間の開始値を書き換える（キーフレーム編集用。補間種別と
    /// 他区間の値は保つ）。
    @discardableResult
    public func setAnimationValue(_ value: Double, atSegment segment: Int) -> Bool {
        guard case .animation(_, _, _, _, let setValueAtSegment, _, _) = access else { return false }
        setValueAtSegment(segment, value)
        return true
    }

    /// 補間種別を変更する。値列は Core の種別変更操作
    /// （`Animation.changeAnimationType`、本家 EndEditAsync の種別
    /// 変更分岐）で新しい種別へ組み替えられる（FE-R14-001）。
    /// この変更は不可逆であるため、Undo では種別だけを戻すのでは
    /// なく、変更前後の状態の写しを `restoreAnimationRecordedState`
    /// で書き戻す形で記録する（FE-R23-127-01）。
    @discardableResult
    public func setAnimationType(_ type: AnimationType) -> Bool {
        guard case .animation(_, _, _, let setType, _, _, _) = access else { return false }
        setType(type)
        return true
    }

    /// 値列のインデックス指定の書き換え（移動量指定の第2値など、
    /// キーフレーム区間ではない値の編集用。FE-R13-003）。クランプ
    /// 範囲は、その値のスライダの Min/Max（第2値では絶対制限の
    /// 対称範囲）を呼び出し側が渡す。
    @discardableResult
    public func setAnimationValue(
        _ value: Double, atValueIndex index: Int, clampRange: ClosedRange<Double>
    ) -> Bool {
        guard case .animation(_, _, _, _, _, _, let setValueAtIndex) = access else { return false }
        setValueAtIndex(index, value, clampRange)
        return true
    }

    /// 記録済みの状態（種別＋値列）を正規化なしで書き戻す。
    /// 種別変更と、値列全体を一体で記録する編集（移動量指定の
    /// 第2値）の Undo/Redo で使う復元経路であり、通常の編集では
    /// 使わない（種別変更は `setAnimationType` を通す）。
    @discardableResult
    public func restoreAnimationRecordedState(
        _ state: Animation.RecordedState
    ) -> Bool {
        guard case .animation(_, _, _, _, _, let restoreState, _) = access
        else { return false }
        restoreState(state)
        return true
    }

    /// 複合オブジェクトの子記述子（object でなければ nil）。
    /// 対象が未設定（nil）の複合では空の列が返る。
    public var children: [PropertyDescriptor]? {
        guard case .object(let children) = access else { return nil }
        return children()
    }

    /// 複合コレクションの要素数（collection でなければ nil）。
    public var collectionCount: Int? {
        guard case .collection(let count, _, _, _) = access else { return nil }
        return count()
    }

    /// 複合コレクションの要素1件分の子記述子（collection でなければ nil）。
    public func collectionElements(at index: Int) -> [PropertyDescriptor]? {
        guard case .collection(_, let elements, _, _) = access else { return nil }
        return elements(index)
    }

    /// 複合コレクションへ既定値の要素を末尾へ追加する。
    /// 状態が実際に変わった場合にだけ true を返す。
    @discardableResult
    public func insertCollectionElement() -> Bool {
        guard case .collection(_, _, let insert, _) = access else { return false }
        return insert()
    }

    /// 複合コレクションの要素を取り除く。
    /// 状態が実際に変わった場合にだけ true を返す。
    @discardableResult
    public func removeCollectionElement(at index: Int) -> Bool {
        guard case .collection(_, _, _, let remove) = access else { return false }
        return remove(index)
    }
}

// MARK: - 記述子の構築（共通ファクトリ）

extension PropertyDescriptor {
    public static func number(
        id: String, displayName: String, group: String,
        range: ClosedRange<Double>? = nil,
        get: @escaping () -> Double, set: @escaping (Double) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .number(range: range),
            access: .number(get: get, set: set)
        )
    }

    public static func integer(
        id: String, displayName: String, group: String,
        range: ClosedRange<Int>? = nil,
        get: @escaping () -> Int, set: @escaping (Int) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .integer(range: range),
            access: .integer(get: get, set: set)
        )
    }

    public static func boolean(
        id: String, displayName: String, group: String,
        get: @escaping () -> Bool, set: @escaping (Bool) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .boolean,
            access: .boolean(get: get, set: set)
        )
    }

    public static func text(
        id: String, displayName: String, group: String,
        multiline: Bool = false,
        get: @escaping () -> String, set: @escaping (String) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .text(multiline: multiline),
            access: .text(get: get, set: set)
        )
    }

    /// 列挙。モデルの値型と保存名（本家メンバ名）の変換はここで吸収し、
    /// UI 側は文字列だけを扱う。未知のメンバ名も `HonkeEnum` の
    /// `unknown` として往復する。
    public static func enumeration<E: HonkeEnum>(
        id: String, displayName: String, group: String,
        options: [PropertyEnumOption],
        get: @escaping () -> E, set: @escaping (E) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .enumeration(options: options),
            access: .enumeration(
                get: { get().honkeName },
                set: { set(E(honkeName: $0)) }
            )
        )
    }

    /// ファイル参照。値はパス文字列として読み書きし、相対パスも
    /// そのまま保持する（解決は供給層がプロジェクト位置を基準に
    /// 行う。常に絶対パスへ置換しない）。
    public static func filePath(
        id: String, displayName: String, group: String,
        fileGroup: PropertyFileGroup, showsThumbnail: Bool = false,
        get: @escaping () -> String, set: @escaping (String) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .filePath(group: fileGroup, showsThumbnail: showsThumbnail),
            access: .filePath(get: get, set: set)
        )
    }

    public static func color(
        id: String, displayName: String, group: String,
        get: @escaping () -> Color, set: @escaping (Color) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .color,
            access: .color(get: get, set: set)
        )
    }

    /// 複合オブジェクト。子記述子は対象の現在の内部状態から
    /// 都度生成される。
    public static func object(
        id: String, displayName: String, group: String,
        children: @escaping () -> [PropertyDescriptor]
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .object,
            access: .object(children: children)
        )
    }

    /// 複合コレクション。要素の子記述子・追加・削除は対象の
    /// 現在の要素列に対して働く。追加・削除は状態が実際に変わった
    /// 場合にだけ true を返す（`PropertyAccess.collection` の契約）。
    public static func collection(
        id: String, displayName: String, group: String,
        count: @escaping () -> Int,
        elements: @escaping (Int) -> [PropertyDescriptor],
        insert: @escaping () -> Bool,
        remove: @escaping (Int) -> Bool
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .collection,
            access: .collection(
                count: count, elements: elements, insert: insert, remove: remove
            )
        )
    }

    /// アニメーション付き数値。書き込みは対象の `Animation` を読み、
    /// 定義値（minValue / maxValue）を保ったまま値だけを差し替える。
    /// `spec` は通常、構築側が直接渡さず、入口での一括解決
    /// （`AnimationSliderTable.resolving`）で付ける。
    public static func animation(
        id: String, displayName: String, group: String,
        spec: AnimationSliderSpec? = nil,
        get: @escaping () -> Animation, set: @escaping (Animation) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .animation(spec: spec),
            access: .animation(
                get: get,
                setConstantValue: { value in
                    var animation = get()
                    animation.animationType = .none
                    animation.values = [AnimationValue(animation.clamped(value))]
                    set(animation)
                },
                setFirstValue: { value in
                    var animation = get()
                    animation.setFirstValue(animation.clamped(value))
                    set(animation)
                },
                setType: { type in
                    var animation = get()
                    // 種別変更は値列の正規化と一体の Core 操作を通す
                    // （FE-R14-001。本家 EndEditAsync の種別変更分岐）。
                    // 素の代入で迂回すると未実体化の値が既定値で評価される
                    // 不整合が残るため、ここ以外から種別を書き換えない。
                    animation.changeAnimationType(to: type)
                    set(animation)
                },
                setValueAtSegment: { segment, value in
                    var animation = get()
                    animation.setValue(value, atSegment: segment)
                    set(animation)
                },
                restoreState: { state in
                    var animation = get()
                    animation.restoreRecordedState(state)
                    set(animation)
                },
                setValueAtIndex: { index, value, clampRange in
                    var animation = get()
                    animation.setValue(value, atValueIndex: index, clampRange: clampRange)
                    set(animation)
                }
            )
        )
    }
}

extension Animation {
    /// 定義範囲 [minValue, maxValue] へクランプする（編集 UI の入力制約）。
    func clamped(_ value: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}

/// アニメーション評価の文脈（アイテム内相対フレーム・長さ・基準 FPS）。
/// インスペクタが「現在のフレームでの値」を表示するために使う。
public struct AnimationEvaluationContext: Equatable, Sendable {
    /// アイテム内相対フレーム。
    public var frame: Int
    /// アイテムの長さ（フレーム）。
    public var length: Int
    /// 評価 FPS。
    public var fps: Int

    public init(frame: Int, length: Int, fps: Int) {
        self.frame = frame
        self.length = length
        self.fps = fps
    }

    /// この文脈での評価値。本家 `Animation.GetValue` の評価そのもの。
    public func value(of animation: Animation) -> Double {
        animation.value(atFrame: frame, length: max(length, 1), fps: fps)
    }
}

/// グループ単位にまとめた記述子列（インスペクタのセクション）。
public struct PropertySection {
    public var name: String
    public var descriptors: [PropertyDescriptor]

    public init(name: String, descriptors: [PropertyDescriptor]) {
        self.name = name
        self.descriptors = descriptors
    }
}

/// メタデータ層の共通処理。
public enum PropertyMetadata {
    /// 記述子列をグループごとにまとめる。グループの出現順と
    /// グループ内の順序は入力の並びをそのまま保つ。
    public static func sections(from descriptors: [PropertyDescriptor]) -> [PropertySection] {
        var order: [String] = []
        var grouped: [String: [PropertyDescriptor]] = [:]
        for descriptor in descriptors {
            if grouped[descriptor.group] == nil {
                order.append(descriptor.group)
            }
            grouped[descriptor.group, default: []].append(descriptor)
        }
        return order.map { PropertySection(name: $0, descriptors: grouped[$0] ?? []) }
    }
}
