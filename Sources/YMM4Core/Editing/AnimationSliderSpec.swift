import Foundation

/// アニメーション付き数値プロパティのスライダ表示仕様（FE-R1-042）。
///
/// 本家は各 `Animation` プロパティへ `AnimationSliderAttribute`
/// （stringFormat / unitText / defaultMin / defaultMax）を付け、スライダの
/// 基準範囲・表示形式・単位・刻みをそこから決める。絶対制限
/// （`Animation` 自身の minValue / maxValue）とは別の層であり、こちらでも
/// 混同しない: 本型は表示仕様だけを持ち、値のクランプには使わない。
/// 仕様が未登録のプロパティではスライダ自体を出さず数値入力のみとする
/// （絶対制限全域へのフォールバックはしない。監査 Round 2 の設計判断）。
public struct AnimationSliderSpec: Equatable, Sendable {
    /// スライダの基準範囲の下限（本家 `DefaultMin`）。
    public var defaultMin: Double
    /// スライダの基準範囲の上限（本家 `DefaultMax`）。
    public var defaultMax: Double
    /// 数値の表示形式（本家 `StringFormat`。例 "F1"）。
    public var stringFormat: String
    /// 単位文字列（本家 `UnitText`）。`unitIsResourceKey` が true の間は
    /// 表示文字列そのものではなく本家 `Texts` リソースのキー名であり、
    /// 実文字列は未解決（抽出元に含まれないため推測で埋めていない）。
    public var unit: String
    /// `unit` がリソースキー名（未解決）かどうか。
    public var unitIsResourceKey: Bool
    /// スライダ操作の遅延（本家 `Delay`）。属性のコンストラクタは
    /// 設定しないため、属性由来の仕様では常に 0。
    public var delay: Int

    public init(
        defaultMin: Double, defaultMax: Double,
        stringFormat: String, unit: String,
        unitIsResourceKey: Bool = false, delay: Int = 0
    ) {
        self.defaultMin = defaultMin
        self.defaultMax = defaultMax
        self.stringFormat = stringFormat
        self.unit = unit
        self.unitIsResourceKey = unitIsResourceKey
        self.delay = delay
    }

    /// 刻み幅（本家 `Delta` の導出規則の再現）: 形式が "F<n>" なら
    /// 0.1^n（n が数値化できない場合は 1）、"D" 始まりなら 1。
    /// それ以外の形式は本家属性自体が例外とするもので表には存在しない
    /// （抽出 1,023 件は全て F 形式）ため、防御として 1 を返す。
    public var delta: Double {
        if stringFormat.hasPrefix("F") {
            guard let digits = Int(stringFormat.dropFirst()) else { return 1 }
            return pow(0.1, Double(digits))
        }
        return 1
    }
}

/// スライダ表示仕様の参照キー: (所有型の完全修飾名, プロパティ実名)。
///
/// 所有型は本家の完全修飾クラス名（アセンブリ修飾なし）で、表示名は
/// キーにしない（監査 Round 2 の設計判断）。単純名では同名クラスの
/// 衝突がある（`DrawingBrushParameterBase` が
/// `YukkuriMovieMaker.Brush` と `YukkuriMovieMaker.Plugin.Community.Brush`
/// の両方に存在する）ため、完全修飾名を必須とする。
public struct AnimationSliderKey: Hashable, Sendable {
    /// 所有型の完全修飾名。例: "YukkuriMovieMaker.Project.Items.VideoItem"
    public var ownerType: String
    /// プロパティ実名。例: "Volume"
    public var property: String

    public init(ownerType: String, property: String) {
        self.ownerType = ownerType
        self.property = property
    }

    /// ポート側の $type 名（"完全修飾名, アセンブリ名" 形式）から
    /// キーを作る。アセンブリ修飾は落とす。
    public init(typeName: String, property: String) {
        self.ownerType = AnimationSliderKey.ownerTypeName(fromTypeName: typeName)
        self.property = property
    }

    /// $type 名からアセンブリ修飾を落として完全修飾クラス名にする。
    /// 既に完全修飾名だけの文字列はそのまま返す。
    public static func ownerTypeName(fromTypeName typeName: String) -> String {
        guard let comma = typeName.firstIndex(of: ",") else { return typeName }
        return String(typeName[..<comma]).trimmingCharacters(in: .whitespaces)
    }
}

/// 本家 `AnimationSliderAttribute` の抽出表への参照と、記述子への
/// 解決（FE-R1-042）。表の実体は機械生成データ
/// （`AnimationSliderTableData`、生成方法は同ファイルのヘッダ参照）。
public enum AnimationSliderTable {
    /// 表のレコード数（抽出 1,023 件と一致するはず）。
    public static var count: Int { AnimationSliderTableData.entries.count }

    /// 表の全キー（診断・検証用）。
    public static var allKeys: [AnimationSliderKey] {
        Array(AnimationSliderTableData.entries.keys)
    }

    /// 所有型とプロパティ実名で仕様を引く。所有型は完全修飾名でも
    /// $type 名（アセンブリ修飾付き）でもよい。未登録は nil。
    public static func spec(ownerType: String, property: String) -> AnimationSliderSpec? {
        let key = AnimationSliderKey(
            ownerType: AnimationSliderKey.ownerTypeName(fromTypeName: ownerType),
            property: property
        )
        return AnimationSliderTableData.entries[key]
    }

    /// 所有型の候補を順に試し、最初に見つかった仕様を返す。
    /// 継承で宣言が基底クラス側にあるプロパティ（例: アイテムの X は
    /// 本家 `VisualItem` 宣言）のために、具象型→宣言基底の順で渡す。
    public static func spec(ownerCandidates: [String], property: String) -> AnimationSliderSpec? {
        for candidate in ownerCandidates {
            if let spec = spec(ownerType: candidate, property: property) {
                return spec
            }
        }
        return nil
    }

    /// 記述子列のアニメーション種別へ仕様を解決して付け直す。
    /// 既に仕様を持つ記述子と、アニメーション以外の記述子は変えない。
    /// 解決できなかった記述子は仕様なし（nil）のまま残る。
    public static func resolving(
        _ descriptors: [PropertyDescriptor], ownerCandidates: [String]
    ) -> [PropertyDescriptor] {
        descriptors.map { descriptor in
            guard case .animation(let current) = descriptor.kind, current == nil else {
                return descriptor
            }
            var resolved = descriptor
            resolved.kind = .animation(
                spec: spec(ownerCandidates: ownerCandidates, property: descriptor.id)
            )
            return resolved
        }
    }

    /// 解決できないアニメーションプロパティの id 一覧（診断用）。
    /// 与えた候補では仕様が引けない記述子を、出現順に重複なく返す。
    /// UI 側はこれを診断へ出す想定で、スライダのフォールバックには
    /// 使わない。
    public static func unresolvedProperties(
        in descriptors: [PropertyDescriptor], ownerCandidates: [String]
    ) -> [String] {
        var result: [String] = []
        for descriptor in descriptors {
            guard case .animation(let current) = descriptor.kind else { continue }
            let effective = current ?? spec(
                ownerCandidates: ownerCandidates, property: descriptor.id
            )
            if effective == nil, !result.contains(descriptor.id) {
                result.append(descriptor.id)
            }
        }
        return result
    }
}
