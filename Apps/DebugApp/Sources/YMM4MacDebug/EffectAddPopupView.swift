import SwiftUI
import YMM4Core

/// エフェクト追加ポップアップ（本家 SelectVideoEffectPopup の形）。
///
/// 構造の根拠は analysis-notes/UI-FACTS-EFFECT-SELECTION.md §1.2:
/// 左上に検索ボックス、左下にカテゴリ一覧、右にエフェクト一覧
/// （行高22）。検索は表示名への部分一致で、入力中はカテゴリ条件より
/// 優先される。本家は選択中に仮挿入してプレビューし、閉じた時点で
/// 確定する方式だが、こちらは選択した時点で末尾へ追加して確定する
/// （仮挿入の巻き戻しは未実装。台帳に記録）。
/// お気に入り／最近使用／ユーザー編集カテゴリは本家では設定側の
/// 保持が前提であり、こちらには保持先が無いため未実装。
struct EffectAddPopupView: View {
    /// 追加が選ばれたときの受け口。
    var onSelect: (EffectCatalog.Entry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var selectedCategory: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                TextField(UIStrings.EffectPopup.searchPlaceholder, text: $keyword)
                    .textFieldStyle(.roundedBorder)
                List(selection: $selectedCategory) {
                    Text(UIStrings.EffectPopup.all)
                        .tag(String?.none)
                    ForEach(EffectCatalog.categories, id: \.self) { category in
                        Text(category).tag(Optional(category))
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 170)

            Divider()

            let results = EffectCatalog.filtered(
                category: keyword.isEmpty ? selectedCategory : nil,
                keyword: keyword
            )
            if results.isEmpty {
                Text(UIStrings.EffectPopup.emptyResult)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results, id: \.typeName) { entry in
                    Button {
                        onSelect(entry)
                        dismiss()
                    } label: {
                        Text(entry.displayName)
                            .frame(height: 22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 460, height: 320)
        .padding(8)
    }
}
