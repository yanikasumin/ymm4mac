import SwiftUI
import YMM4Core

/// 一覧表示用に、同一性（ObjectIdentifier）を ID として使う。
/// 名前は重複し得るためキーにできない（FE-UNIT6）。
extension Character: @retroactive Identifiable {}

/// キャラクター編集シート（FE-UNIT6、FE-R1-018 の処分）。
///
/// 本家の「キャラクター編集」ツールに対応する入口で、プロジェクトが
/// 保持するキャラクターの一覧管理（追加・複製・削除）と、識別に
/// 関わる基本項目（名前・グループ名・色・レイヤー・備考・音声
/// エンジンと話者）を編集する。字幕・立ち絵の詳細項目（本家では
/// 設定ウィンドウ側の広い画面が担う）は、話者選択や立ち絵
/// パラメータの基盤（音声合成・プラグイン）が Mac 版に無いため
/// ここでは扱わない（台帳に記録）。
///
/// モデル上の注意: Mac 版ではキャラクターはプロジェクトが保持し、
/// アイテムからの参照は読み込み時に名前で解決される（MAC-0015。
/// 本家はアプリ設定側が正本で、プロジェクト側は参照中キャラクター
/// から再構築される点が異なる）。名前は解決のキーであるため、
/// 編集では重複と空名を不変条件として禁止する（検証は Core の
/// `Project.isUsableCharacterName`。FE-R39-133-01）。読み込み由来の
/// 重複が残っている場合は解決は先頭一致になり、この画面では
/// 警告する。名前の変更は、解決済みアイテムについては保存時に
/// 参照先の現在名が書かれるため自動で追随する（本家の getter
/// 規則と同じ）。一覧の変更後は未解決参照を Core の再解決で
/// 即座に結び直し、メモリ上の状態を保存・再読込後と一致させる
/// （FE-R39-133-03）。
struct CharacterEditorView: View {
    let project: Project
    /// 編集が確定するたびに呼ばれる（プレビュー再合成・未保存記録）。
    var onEdited: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: ObjectIdentifier?
    /// 名前欄の下書き。名前は確定時に検証してからモデルへ書く
    /// （入力途中の文字列でモデルを汚さない。FE-R39-133-01）。
    @State private var nameDraft: String = ""
    /// 名前下書きの持ち主（選択移動時に前の下書きを確定するため）。
    @State private var nameDraftCharacter: Character?
    /// 参照のあるキャラクターの削除確認の対象。
    @State private var pendingDeletion: Character?
    @State private var pendingDeletionReferenceCount = 0

    private var selectedCharacter: Character? {
        guard let selectedID else { return project.characters.first }
        return project.characters.first { ObjectIdentifier($0) == selectedID }
            ?? project.characters.first
    }

    private var deletionAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("キャラクター編集")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                characterListColumn

                if let character = selectedCharacter {
                    characterForm(character)
                        .onAppear { syncNameDraft(to: character) }
                        .onChange(of: ObjectIdentifier(character)) { _, _ in
                            syncNameDraft(to: character)
                        }
                } else {
                    Text("キャラクターが登録されていません。「追加」から作成できます。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("閉じる") {
                    // 未確定の名前下書きがあれば確定を試みてから閉じる。
                    // 無効な下書きは適用されず破棄される（モデルは
                    // 変更されない）。
                    if let character = selectedCharacter {
                        commitNameDraft(for: character)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 680, minHeight: 440)
        .alert(
            "キャラクターを削除しますか？",
            isPresented: deletionAlertPresented,
            presenting: pendingDeletion
        ) { character in
            Button("キャンセル", role: .cancel) { pendingDeletion = nil }
            Button("削除", role: .destructive) {
                deleteCharacter(character)
                pendingDeletion = nil
            }
        } message: { character in
            Text(
                "「\(character.name)」は \(pendingDeletionReferenceCount) 件のアイテムから参照されています。"
                    + "削除すると、それらのアイテムはキャラクター名だけを保持し、キャラクター設定への参照を失います。"
                    + (hasDuplicateName(character)
                        ? "同名のキャラクターが残っているため、参照はそちらへ移ります。"
                        : "")
            )
        }
    }

    // MARK: - 一覧列

    private var characterListColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            List {
                ForEach(project.characters) { character in
                    characterRow(character)
                }
            }
            .frame(width: 220)

            HStack(spacing: 6) {
                Button("追加") { addCharacter() }
                Button("複製") { duplicateSelected() }
                    .disabled(selectedCharacter == nil)
                Button("削除") { requestDeleteSelected() }
                    .disabled(selectedCharacter == nil)
            }
        }
    }

    private func characterRow(_ character: Character) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(swiftUIColor(from: character.color))
                .frame(width: 10, height: 10)
            Text(character.name)
                .lineLimit(1)
            if !character.groupName.isEmpty {
                Text(character.groupName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(
            selectedCharacter === character
                ? Color(nsColor: .selectedControlColor)
                : Color.clear
        )
        .onTapGesture { selectedID = ObjectIdentifier(character) }
    }

    // MARK: - 選択中キャラクターのフォーム

    @ViewBuilder
    private func characterForm(_ character: Character) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("名前")
                VStack(alignment: .leading, spacing: 2) {
                    TextField("名前", text: $nameDraft)
                        .onSubmit { commitNameDraft(for: character) }
                    if let error = nameDraftError(for: character) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if hasDuplicateName(character) {
                        Text("同名のキャラクターがあります。読み込み時の参照解決は先頭の一致が使われます。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            GridRow {
                Text("グループ名")
                TextField("グループ名", text: binding(for: character, \.groupName))
            }
            GridRow {
                Text("色")
                ColorPicker("", selection: Binding(
                    get: { swiftUIColor(from: character.color) },
                    set: { character.color = coreColor(from: $0); onEdited() }
                ), supportsOpacity: true)
                .labelsHidden()
            }
            GridRow {
                Text("レイヤー")
                TextField("レイヤー", value: Binding(
                    get: { character.layer },
                    set: { character.layer = $0; onEdited() }
                ), format: .number)
                .frame(width: 80)
            }
            GridRow {
                Text("備考")
                TextField("備考", text: binding(for: character, \.remark))
            }
            GridRow {
                Text("音声エンジン")
                TextField("音声エンジン", text: voiceBinding(for: character, isAPI: true))
            }
            GridRow {
                Text("話者")
                TextField("話者", text: voiceBinding(for: character, isAPI: false))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(
        for character: Character, _ keyPath: ReferenceWritableKeyPath<Character, String>
    ) -> Binding<String> {
        Binding(
            get: { character[keyPath: keyPath] },
            set: { character[keyPath: keyPath] = $0; onEdited() }
        )
    }

    /// 音声エンジン／話者の入力。両方が空なら Voice 自体を持たない
    /// （nil）状態へ戻し、保存形式（未設定は null）を保つ。
    private func voiceBinding(for character: Character, isAPI: Bool) -> Binding<String> {
        Binding(
            get: { isAPI ? (character.voice?.api ?? "") : (character.voice?.arg ?? "") },
            set: { newValue in
                let api = isAPI ? newValue : (character.voice?.api ?? "")
                let arg = isAPI ? (character.voice?.arg ?? "") : newValue
                character.voice = (api.isEmpty && arg.isEmpty)
                    ? nil
                    : VoiceDescription(api: api, arg: arg)
                onEdited()
            }
        )
    }

    private func hasDuplicateName(_ character: Character) -> Bool {
        project.characters.contains { $0 !== character && $0.name == character.name }
    }

    // MARK: - 名前の下書きと確定

    /// 選択先のキャラクターへ名前下書きを切り替える。前の持ち主に
    /// 未確定の下書きがあれば、先に確定を試みる。
    private func syncNameDraft(to character: Character) {
        if let owner = nameDraftCharacter, owner !== character {
            commitNameDraft(for: owner)
        }
        nameDraftCharacter = character
        nameDraft = character.name
    }

    /// 名前下書きを検証してモデルへ反映する。無効な名前（空・重複）は
    /// 適用しない（理由は欄の下に表示される）。確定できた場合は
    /// 未解決参照の再解決まで行う（改名後の名前を保持する未解決
    /// アイテムが即座に結び付く。FE-R39-133-03）。
    private func commitNameDraft(for character: Character) {
        guard nameDraft != character.name else { return }
        guard project.isUsableCharacterName(nameDraft, excluding: character) else {
            return
        }
        character.name = nameDraft
        project.reresolveUnresolvedCharacterReferences()
        onEdited()
    }

    /// 未確定の名前下書きを、その持ち主について確定する。一覧を
    /// 変更する操作（追加・複製）は、下書きを確定しないまま実行
    /// すると自動付与される名前が下書きと衝突して検証に失敗し、
    /// 有効だった改名が黙って失われるため、先にこれを通す
    /// （FE-R40-133-01）。無効な下書きは従来どおり適用されず、
    /// 一覧操作自体は妨げない（破棄は選択切替時の syncNameDraft
    /// が行う）。
    private func commitPendingNameDraft() {
        guard let owner = nameDraftCharacter else { return }
        commitNameDraft(for: owner)
    }

    /// 未確定の下書きが無効な場合の理由（有効・未編集なら nil）。
    private func nameDraftError(for character: Character) -> String? {
        guard nameDraftCharacter === character, nameDraft != character.name
        else { return nil }
        if nameDraft.isEmpty {
            return "名前を空にはできません。"
        }
        if !project.isUsableCharacterName(nameDraft, excluding: character) {
            return "同名のキャラクターが既にあります。名前は参照解決のキーになるため重複できません。"
        }
        return nil
    }

    // MARK: - 一覧操作

    private func uniqueName(base: String) -> String {
        if !project.characters.contains(where: { $0.name == base }) { return base }
        var number = 2
        while project.characters.contains(where: { $0.name == "\(base)\(number)" }) {
            number += 1
        }
        return "\(base)\(number)"
    }

    private func addCharacter() {
        // 未確定の改名を先に確定する。確定しないまま追加すると、
        // 新規個体への自動付与名が下書きと衝突し、選択切替時の
        // 確定が検証に失敗して改名が失われる（FE-R40-133-01）。
        commitPendingNameDraft()
        let character = Character()
        character.name = uniqueName(base: "キャラクター")
        project.characters.append(character)
        // 登録した名前を保持する未解決アイテムを即座に結び付ける
        // （FE-R39-133-03）。
        project.reresolveUnresolvedCharacterReferences()
        selectedID = ObjectIdentifier(character)
        onEdited()
    }

    private func duplicateSelected() {
        guard let source = selectedCharacter else { return }
        // 未確定の改名を先に確定し、改名後の状態を複製元にする
        // （確定前に cloned() を呼ぶと古い名前を基準に複製される。
        // FE-R40-133-01）。
        commitPendingNameDraft()
        let copy = source.cloned()
        copy.name = uniqueName(base: source.name + " のコピー")
        let index = project.characters.firstIndex { $0 === source } ?? project.characters.count - 1
        project.characters.insert(copy, at: index + 1)
        project.reresolveUnresolvedCharacterReferences()
        selectedID = ObjectIdentifier(copy)
        onEdited()
    }

    /// そのキャラクターを参照するアイテム（参照インスタンス一致、
    /// または未解決のまま名前が一致するもの）の件数。
    private func referenceCount(of target: Character) -> Int {
        var count = 0
        for timeline in project.timelines {
            for item in timeline.items where CharacterItemAccess.supports(item) {
                if CharacterItemAccess.character(of: item) === target
                    || (CharacterItemAccess.character(of: item) == nil
                        && CharacterItemAccess.characterName(of: item) == target.name) {
                    count += 1
                }
            }
        }
        return count
    }

    private func requestDeleteSelected() {
        guard let character = selectedCharacter else { return }
        let count = referenceCount(of: character)
        if count > 0 {
            pendingDeletionReferenceCount = count
            pendingDeletion = character
        } else {
            deleteCharacter(character)
        }
    }

    /// 削除の実体。参照の切り離し・実効名の保持・未解決参照の
    /// 再解決は Core の `Project.removeCharacter` が担い、メモリ上の
    /// 状態を保存・再読込後と一致させる（同名の残存キャラクターが
    /// あれば切り離された参照はそちらへ再接続される。
    /// FE-R39-133-01）。ここでは選択と下書きの後始末だけを行う。
    /// なお削除では未確定の下書きを先に確定しない。対象は下書きの
    /// 持ち主自身であり、削除される個体の改名に意味はないうえ、
    /// 先に改名すると参照件数の照合に使う名前（未解決アイテムが
    /// 保持する旧名）とずれて件数と確認文面が実態と食い違うため
    /// （FE-R40-133-01 の洗い出し結果）。
    private func deleteCharacter(_ target: Character) {
        project.removeCharacter(target)
        if nameDraftCharacter === target {
            nameDraftCharacter = nil
            nameDraft = ""
        }
        if selectedID == ObjectIdentifier(target) {
            selectedID = project.characters.first.map { ObjectIdentifier($0) }
        }
        onEdited()
    }
}
