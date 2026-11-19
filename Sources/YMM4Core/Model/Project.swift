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

    /// 全タイムラインのシーンアイテムへ、参照先シーンの長さの
    /// 供給（`SceneItem.sceneLengthProvider`）を注入する。
    ///
    /// 供給はこのプロジェクトのタイムライン群を引くたびに評価
    /// するライブ参照であり、参照先シーンの長さの変化は再注入
    /// なしで反映される（本家 `GlobalSceneInfo` の購読と同じ
    /// 意味論）。シーン長は本家どおり、参照先タイムラインの
    /// 長さ（キャッシュ値）をそのタイムラインの FPS で時間へ
    /// 換算した値。プロジェクトへの弱参照で保持するため、
    /// アイテムがプロジェクトより長生きしても循環参照には
    /// ならない（プロジェクトが消えれば解決できず 0 になる。
    /// 本家の未登録時と同じ扱い）。
    ///
    /// 注入の契機は読み込み（`YmmpCodec.decode` が組み立ての
    /// 最後に呼ぶ）。編集時に追加・複製されたシーンアイテムは
    /// 次の注入まで供給を持たない（その間の区切りはシーン長 0
    /// の形になり、本家の未登録シーンと同じ扱いになる）。
    public func injectSceneLengthProviders() {
        for timeline in timelines {
            for item in timeline.items {
                guard let sceneItem = item as? SceneItem else { continue }
                sceneItem.sceneLengthProvider = { [weak self] id in
                    guard let self,
                          let scene = self.timelines.first(where: { $0.id == id })
                    else { return nil }
                    return TimeSpanValue(
                        seconds: FrameTime.time(
                            fromFrame: scene.length, fps: scene.videoInfo.fps))
                }
            }
        }
    }

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
