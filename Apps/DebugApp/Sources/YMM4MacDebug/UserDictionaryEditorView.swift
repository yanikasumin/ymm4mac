import SwiftUI
import YMM4Core

/// ユーザー辞書の編集ウィンドウ（TEXT60 の辞書設定層）。
///
/// 本家のユーザー辞書ツールに対応する。3つの置換リスト
/// （アスタリスク＝表示テキストへの伏せ字置換、単語＝読み変換の
/// 前段、発音＝読み変換の後段）を編集する。編集は即座に設定層
/// （`UserDictionaryStore.shared`）へ保存され、プレビューの再描画で
/// 描画側へ反映される（アスタリスクはテキスト描画の前処理で適用。
/// 単語・発音は読み変換経路が Mac 版に無いため、適用部品は実装済み
/// だが現時点では描画・音声へ効かない。本家との差分として台帳に
/// 記録）。
struct UserDictionaryEditorView: View {
    @EnvironmentObject private var workspace: WorkspaceState
    @State private var dictionary: UserDictionary = UserDictionaryStore.shared.current
    @State private var selectedList: ListKind = .asterisk
    /// 直近の保存の失敗理由（R18-03: 失敗を画面へ出す）。
    @State private var saveError: String?

    private enum ListKind: String, CaseIterable, Identifiable {
        case asterisk = "アスタリスク"
        case word = "単語"
        case pronouncing = "発音"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $selectedList) {
                ForEach(ListKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            List {
                ForEach(currentEntries().indices, id: \.self) { index in
                    entryRow(index: index)
                }
                .onDelete { offsets in
                    updateEntries { entries in
                        for index in offsets.sorted(by: >) {
                            entries.remove(at: index)
                        }
                    }
                    commit()
                }
            }

            HStack {
                Button("追加") {
                    updateEntries { $0.append(WordSet(from: "", to: "")) }
                    commit()
                }
                Spacer()
                Text("保存先: \(UserDictionaryStore.shared.fileURL.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // 保存失敗の表示と再試行（R18-03）。
            if let saveError {
                HStack(spacing: 8) {
                    Text("辞書を保存できませんでした: \(saveError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Button("再試行") {
                        UserDictionaryStore.shared.save()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            dictionary = UserDictionaryStore.shared.current
            saveError = UserDictionaryStore.shared.lastSaveError
            // 保存結果（集約保存の完了も含む）を画面へ反映する。
            UserDictionaryStore.shared.onSaveResult = { succeeded in
                DispatchQueue.main.async {
                    saveError = succeeded
                        ? nil : UserDictionaryStore.shared.lastSaveError
                }
            }
        }
        .onDisappear {
            // 保留中の永続化を確定し、通知先を手放す。
            UserDictionaryStore.shared.onSaveResult = nil
            UserDictionaryStore.shared.flushPendingSave()
        }
    }

    /// 選択中のリストの現在値。
    private func currentEntries() -> [WordSet] {
        switch selectedList {
        case .asterisk: return dictionary.asteriskWordSets
        case .word: return dictionary.wordSets
        case .pronouncing: return dictionary.pronouncingSets
        }
    }

    /// 選択中のリストを書き換える（@State 経由の非 mutating 更新）。
    private func updateEntries(_ mutate: (inout [WordSet]) -> Void) {
        switch selectedList {
        case .asterisk: mutate(&dictionary.asteriskWordSets)
        case .word: mutate(&dictionary.wordSets)
        case .pronouncing: mutate(&dictionary.pronouncingSets)
        }
    }

    private func entryRow(index: Int) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: boolBinding(index, \.isEnabled))
                .labelsHidden()
            TextField("変換前", text: stringBinding(index, \.from))
                .frame(minWidth: 110)
            Text("→")
                .foregroundStyle(.secondary)
            TextField("変換後", text: stringBinding(index, \.to))
                .frame(minWidth: 110)
            TextField("説明", text: descriptionBinding(index))
                .frame(minWidth: 110)
            Toggle("正規表現", isOn: boolBinding(index, \.isRegex))
                .toggleStyle(.checkbox)
            Toggle("大文字小文字を区別しない", isOn: boolBinding(index, \.ignoreCase))
                .toggleStyle(.checkbox)
            Button("削除") {
                updateEntries { $0.remove(at: index) }
                commit()
            }
        }
        .font(.callout)
    }

    private func boolBinding(
        _ index: Int, _ keyPath: WritableKeyPath<WordSet, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { currentEntries()[index][keyPath: keyPath] },
            set: { newValue in
                updateEntries { $0[index][keyPath: keyPath] = newValue }
                commit()
            }
        )
    }

    private func stringBinding(
        _ index: Int, _ keyPath: WritableKeyPath<WordSet, String>
    ) -> Binding<String> {
        Binding(
            get: { currentEntries()[index][keyPath: keyPath] },
            set: { newValue in
                updateEntries { $0[index][keyPath: keyPath] = newValue }
                commit()
            }
        )
    }

    private func descriptionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { currentEntries()[index].description ?? "" },
            set: { newValue in
                updateEntries {
                    $0[index].description = newValue.isEmpty ? nil : newValue
                }
                commit()
            }
        )
    }

    /// 編集を設定層へ保存し、プレビューの再描画を依頼する。
    private func commit() {
        UserDictionaryStore.shared.update(dictionary)
        workspace.request(.userDictionaryChanged)
    }
}
