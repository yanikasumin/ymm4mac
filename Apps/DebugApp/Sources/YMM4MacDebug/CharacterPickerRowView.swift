import SwiftUI
import YMM4Core

/// キャラクターを持つアイテム（VoiceItem / TachieItem /
/// TachieFaceItem）への参照アクセスの集約。
///
/// 3型は Core 側で共通プロトコルを持たず、それぞれ `character`
/// （実行時参照）と `characterName`（保存される名前）を保持する
/// （MAC-0015 の契約）。アプリ層で参照を読み書きする箇所はこの
/// 集約を通し、型ごとの分岐をここ1か所へ閉じる。
enum CharacterItemAccess {
    /// そのアイテムがキャラクター参照を持つ型かどうか。
    static func supports(_ item: BaseItem) -> Bool {
        item is VoiceItem || item is TachieItem || item is TachieFaceItem
    }

    /// 解決済みのキャラクター参照（未解決なら nil）。
    static func character(of item: BaseItem) -> Character? {
        switch item {
        case let voice as VoiceItem: return voice.character
        case let tachie as TachieItem: return tachie.character
        case let face as TachieFaceItem: return face.character
        default: return nil
        }
    }

    /// アイテムが保持するキャラクター名（未解決参照の表示用）。
    static func characterName(of item: BaseItem) -> String {
        switch item {
        case let voice as VoiceItem: return voice.characterName
        case let tachie as TachieItem: return tachie.characterName
        case let face as TachieFaceItem: return face.characterName
        default: return ""
        }
    }

    /// 参照と名前を対で書き換える。保存される名前は本家 getter 規則
    /// （Character?.Name ?? characterName）で参照側から決まるため、
    /// 両者を常に一致させて書き込む。
    static func setCharacter(_ character: Character?, name: String, for item: BaseItem) {
        switch item {
        case let voice as VoiceItem:
            voice.character = character
            voice.characterName = name
        case let tachie as TachieItem:
            tachie.character = character
            tachie.characterName = name
        case let face as TachieFaceItem:
            face.character = character
            face.characterName = name
        default:
            break
        }
    }
}

/// インスペクタ先頭のキャラクター選択行（FE-UNIT6）。
///
/// 本家のアイテム編集画面ではキャラクター選択が音声グループの先頭
/// （VoiceItem.Character の CharacterComboBox、Order 110）にあるが、
/// Mac 版の記述子はアイテム単体から構築されプロジェクトの
/// キャラクター一覧を知らないため、専用の行としてアプリ層に置く。
/// 選択は参照（インスタンス）と名前の両方へ書き込み、保存・再読込
/// 時の名前解決と一致させる。
struct CharacterPickerRowView: View {
    let item: BaseItem
    let characters: [Character]
    var onEdited: () -> Void

    /// 現在の実効名（解決済みならその名前、未解決なら保持名）。
    private var currentName: String {
        CharacterItemAccess.character(of: item)?.name
            ?? CharacterItemAccess.characterName(of: item)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("キャラクター")
                .font(.callout)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            Picker("", selection: selectionBinding) {
                Text("（なし）").tag("")
                // 未解決の保持名は候補に無くても表示できるよう足す。
                if !currentName.isEmpty,
                   !characters.contains(where: { $0.name == currentName }) {
                    Text(currentName).tag(currentName)
                }
                // 行の同一性はインスタンス（ObjectIdentifier）で取る。
                // 名前は読み込み由来の重複があり得てキーにできない
                // （選択自体は名前ベースのまま。FE-R39-133-01）。
                ForEach(characters) { character in
                    Text(character.name).tag(character.name)
                }
            }
            .labelsHidden()
        }
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { currentName },
            set: { newName in
                if newName.isEmpty {
                    CharacterItemAccess.setCharacter(nil, name: "", for: item)
                } else if let character = characters.first(where: { $0.name == newName }) {
                    CharacterItemAccess.setCharacter(
                        character, name: character.name, for: item
                    )
                } else {
                    // 未解決の保持名を選び直した場合は状態を変えない。
                    return
                }
                onEdited()
            }
        )
    }
}
