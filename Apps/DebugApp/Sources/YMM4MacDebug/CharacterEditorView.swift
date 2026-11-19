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
/// から再構築される点が異なる）。そのため同名キャラクターが複数
/// あると解決は先頭一致になり、この画面では重複を警告する。
/// 名前の変更は、解決済みアイテムについては保存時に参照先の現在名
/// が書かれるため自動で追随する（本家の getter 規則と同じ）。
struct CharacterEditorView: View {
    let project: Project
    /// 編集が確定するたびに呼ばれる（プレビュー再合成・未保存記録）。
    var onEdited: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: ObjectIdentifier?
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
                } else {
                    Text("キャラクターが登録されていません。「追加」から作成できます。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
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
                    TextField("名前", text: binding(for: character, \.name))
                    if hasDuplicateName(character) {
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
        let character = Character()
        character.name = uniqueName(base: "キャラクター")
        project.characters.append(character)
        selectedID = ObjectIdentifier(character)
        onEdited()
    }

    private func duplicateSelected() {
        guard let source = selectedCharacter else { return }
        let copy = source.cloned()
        copy.name = uniqueName(base: source.name + " のコピー")
        let index = project.characters.firstIndex { $0 === source } ?? project.characters.count - 1
        project.characters.insert(copy, at: index + 1)
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

    /// 削除の実体。参照インスタンスを持つアイテムは参照だけを外し、
    /// 名前は実効名（参照先の現在名。保存時に書かれていた名前）を
    /// 残す（保存・再読込後と同じ状態に揃え、失われるのは
    /// キャラクター定義だけにする）。
    private func deleteCharacter(_ target: Character) {
        for timeline in project.timelines {
            for item in timeline.items where CharacterItemAccess.supports(item) {
                if CharacterItemAccess.character(of: item) === target {
                    CharacterItemAccess.setCharacter(nil, name: target.name, for: item)
                }
            }
        }
        project.characters.removeAll { $0 === target }
        if selectedID == ObjectIdentifier(target) {
            selectedID = project.characters.first.map { ObjectIdentifier($0) }
        }
        onEdited()
    }
}
