import AppKit
import SwiftUI
import YMM4Core

// MARK: - 映像エフェクトのインスペクタ

/// アイテムが保持する映像エフェクト列のインスペクタ。
/// 型付きで開ける定義は記述子で編集でき、編集のたびに保持列へ
/// 書き戻す（`EffectPropertyEditing`）。未知の型は生保持のまま
/// 編集対象外であることを表示する。
/// 追加は本家 VideoEffectSelector の「＋」相当で、追加ポップアップ
/// （`EffectAddPopupView`）から選んだ定義を末尾へ追加する。削除も
/// 行える（本家の削除ボタン相当）。
struct EffectInspectorView: View {
    let item: BaseItem
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void
    /// ファイル参照欄の相対パス解決の基準フォルダ（サムネイル表示用。
    /// FE-R15-005）。
    var fileBaseDirectory: URL? = nil
    @State private var isAddPopupPresented = false
    /// 追加・削除のたびに増やし、一覧の再構築を促す世代カウンタ。
    @State private var listRevision = 0

    var body: some View {
        if let effects = EffectPropertyEditing.effectList(for: item) {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack {
                    Text(UIStrings.Inspector.videoEffects)
                        .bold()
                    Spacer()
                    Button {
                        isAddPopupPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(UIStrings.Inspector.addEffect)
                    .popover(isPresented: $isAddPopupPresented) {
                        EffectAddPopupView { entry in
                            appendEffect(entry)
                        }
                    }
                }
                ForEach(effects.indices, id: \.self) { index in
                    EffectInspectorRow(
                        item: item, index: index, preserved: effects[index],
                        animationContext: animationContext, onEdited: onEdited,
                        fileBaseDirectory: fileBaseDirectory,
                        onRemove: { removeEffect(at: index) }
                    )
                    .id("\(index)-\(effects[index].typeName ?? "")-\(listRevision)")
                }
            }
        }
    }

    /// 選択された定義を保持列の末尾へ追加する（本家は現在位置の
    /// 直後へ仮挿入する方式。こちらは末尾追加で確定する）。
    private func appendEffect(_ entry: EffectCatalog.Entry) {
        guard let definition = VideoEffectRegistry.makeEmptyDefinition(
            typeName: entry.typeName
        ) else { return }
        let preserved = VideoEffectRegistry.encode(definition)
        switch item {
        case let visual as VisualItem:
            visual.videoEffects.append(preserved)
        case let voice as VoiceItem:
            voice.videoEffects.append(preserved)
        case let transition as TransitionItem:
            transition.videoEffects.append(preserved)
        default:
            return
        }
        listRevision += 1
        onEdited()
    }

    private func removeEffect(at index: Int) {
        switch item {
        case let visual as VisualItem:
            guard visual.videoEffects.indices.contains(index) else { return }
            visual.videoEffects.remove(at: index)
        case let voice as VoiceItem:
            guard voice.videoEffects.indices.contains(index) else { return }
            voice.videoEffects.remove(at: index)
        case let transition as TransitionItem:
            guard transition.videoEffects.indices.contains(index) else { return }
            transition.videoEffects.remove(at: index)
        default:
            return
        }
        listRevision += 1
        onEdited()
    }
}

private struct EffectInspectorRow: View {
    let item: BaseItem
    let index: Int
    let preserved: PreservedObject
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void
    /// ファイル参照欄の相対パス解決の基準フォルダ（FE-R15-005）。
    var fileBaseDirectory: URL? = nil
    var onRemove: () -> Void
    @State private var definition: VideoEffectDefinitionBase?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shortTypeName)
                    .font(.callout)
                    .bold()
                Spacer()
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(UIStrings.Inspector.removeEffect)
            }
            if let definition {
                PropertyInspectorView(
                    descriptors: EffectPropertyMetadata.descriptors(for: definition),
                    animationContext: animationContext,
                    onEdited: {
                        EffectPropertyEditing.writeBack(definition, for: item, at: index)
                        onEdited()
                    },
                    fileBaseDirectory: fileBaseDirectory
                )
            } else {
                Text(UIStrings.Inspector.unsupportedEffect)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if definition == nil {
                definition = EffectPropertyEditing.openDefinition(for: item, at: index)
            }
        }
    }

    /// `$type` のアセンブリ修飾名からクラス名だけを取り出す。
    private var shortTypeName: String {
        guard let typeName = preserved.typeName else { return "(型名なし)" }
        let beforeComma = typeName.split(separator: ",").first.map(String.init) ?? typeName
        return beforeComma.split(separator: ".").last.map(String.init) ?? beforeComma
    }
}
