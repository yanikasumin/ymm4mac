import Foundation

/// プロジェクト。本家 `Project` に対応する。
///
/// .ymmp にはバージョン情報が存在しない。旧形式との判別は
/// `Timelines` の有無・$type 解決・YMM3 の XML ヘッダで行う
/// （互換層の責務）。旧 API の単一 `Timeline` プロパティは読み込み
/// 専用で、保存時には書き出されない。
public final class Project {
    /// プロジェクトファイルのパス（参照ファイルが無い場合は空になる、
    /// という規則は保存スナップショット構築側の責務のため、ここでは
    /// 保持するだけにする）。
    public var filePath: String?
    /// 選択中のタイムラインのインデックス。
    public var selectedTimelineIndex: Int = 0
    /// タイムライン群。
    public var timelines: [Timeline] = []
    /// キャラクター群。
    public var characters: [Character] = []
    /// 折りたたまれたキャラクターグループ名。
    public var collapsedGroups: [String] = []
    /// レイアウト XML。
    public var layoutXml: String = ""
    /// ツールの保存状態（順序保持。nil は null を表す）。
    public var toolStates: [(key: String, value: SerializableToolState)]?

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    /// 旧形式（単一 Timeline）の移行。本家 `LoadOldTimeline`。
    ///
    /// Timelines が空で旧 Timeline があれば取り込み、それでも空なら
    /// 既定のタイムラインを1つ作る。本家は既定値を設定とリソース文字列
    /// （メインタイムライン名）から取るが、ここでは VideoInfo の既定値と
    /// 空の名前で代用する（リソース文字列は未確定）。
    public func loadOldTimeline(legacyTimeline: Timeline?) {
        if timelines.isEmpty, let legacyTimeline {
            timelines.append(legacyTimeline)
        }
        if timelines.isEmpty {
            timelines.append(Timeline())
        }
    }
}
