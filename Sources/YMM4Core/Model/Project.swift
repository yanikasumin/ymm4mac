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

    // MARK: - キャラクター参照の解決

    /// 名前でキャラクターを引く（先頭一致。空名は解決対象外）。
    /// 読み込み時の解決と編集後の再解決で共通の規則（MAC-0015）。
    public func character(named name: String) -> Character? {
        guard !name.isEmpty else { return nil }
        return characters.first { $0.name == name }
    }

    /// キャラクター名として使えるか（編集時の不変条件）。
    ///
    /// 名前は参照解決のキーであるため、空名と、対象以外の既存
    /// キャラクターとの重複を許すと、保存・再読込で参照先が別個体へ
    /// 移り得る。編集シートはこの判定で改名・追加を検証する
    /// （FE-R39-133-01）。
    public func isUsableCharacterName(
        _ name: String, excluding excluded: Character? = nil
    ) -> Bool {
        guard !name.isEmpty else { return false }
        return !characters.contains { $0 !== excluded && $0.name == name }
    }

    /// キャラクター参照を持つアイテム（VoiceItem / TachieItem /
    /// TachieFaceItem）への読み書き口を集める。3型は共通プロトコルを
    /// 持たないため、型ごとの分岐はここ1か所へ閉じる。
    private struct CharacterReferenceAccess {
        let character: () -> Character?
        let characterName: () -> String
        let setCharacter: (Character?) -> Void
        let setCharacterName: (String) -> Void
    }

    private func characterReferenceAccesses() -> [CharacterReferenceAccess] {
        var accesses: [CharacterReferenceAccess] = []
        for timeline in timelines {
            for item in timeline.items {
                switch item {
                case let voice as VoiceItem:
                    accesses.append(CharacterReferenceAccess(
                        character: { voice.character },
                        characterName: { voice.characterName },
                        setCharacter: { voice.character = $0 },
                        setCharacterName: { voice.characterName = $0 }
                    ))
                case let tachie as TachieItem:
                    accesses.append(CharacterReferenceAccess(
                        character: { tachie.character },
                        characterName: { tachie.characterName },
                        setCharacter: { tachie.character = $0 },
                        setCharacterName: { tachie.characterName = $0 }
                    ))
                case let face as TachieFaceItem:
                    accesses.append(CharacterReferenceAccess(
                        character: { face.character },
                        characterName: { face.characterName },
                        setCharacter: { face.character = $0 },
                        setCharacterName: { face.characterName = $0 }
                    ))
                default:
                    break
                }
            }
        }
        return accesses
    }

    /// 全アイテムのキャラクター参照を、保持名（characterName）の
    /// 先頭一致で張り直す。読み込み直後に `YmmpCodec` から呼ばれる。
    /// デコードで得た埋め込み参照も、保持名が一覧のキャラクターに
    /// 一致すればそちらへ寄せる（従来の読み込み規則そのまま）。
    public func resolveCharacterReferencesByName() {
        for access in characterReferenceAccesses() {
            if let resolved = character(named: access.characterName()) {
                access.setCharacter(resolved)
            }
        }
    }

    /// キャラクター一覧の変更（追加・複製・削除・改名）の後に、
    /// 未解決の参照だけを読み込み時と同じ規則で再解決する
    /// （FE-R39-133-03）。
    ///
    /// 対象は「参照が無い」ものと「一覧に無いインスタンス（読み込み
    /// 時の埋め込み複製など）を指している」もの。一覧のインスタンス
    /// へ解決済みの参照は、名前が一致しても付け替えない。これにより
    /// メモリ上の状態が保存・再読込後の状態と一致する。
    public func reresolveUnresolvedCharacterReferences() {
        for access in characterReferenceAccesses() {
            if let current = access.character(),
               characters.contains(where: { $0 === current }) {
                continue
            }
            if let resolved = character(named: access.characterName()) {
                access.setCharacter(resolved)
            }
        }
    }

    /// キャラクターを一覧から削除し、参照の整合を取る
    /// （FE-R39-133-01）。
    ///
    /// 対象を指していたアイテムは参照だけを外し、名前には実効名
    /// （削除時点の現在名）を残す。その後の未解決参照の再解決で、
    /// 同名の残存キャラクターがあれば即座に再接続され、無ければ
    /// 未解決・名前保持のままになる。どちらの場合もメモリ上の状態は
    /// 「削除して保存・再読込した後」と一致する。
    public func removeCharacter(_ target: Character) {
        for access in characterReferenceAccesses()
        where access.character() === target {
            access.setCharacter(nil)
            access.setCharacterName(target.name)
        }
        characters.removeAll { $0 === target }
        reresolveUnresolvedCharacterReferences()
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
