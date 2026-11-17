import AppKit
import SwiftUI
import YMM4Core

// MARK: - 映像エフェクトのインスペクタ

/// アイテムが保持する映像エフェクト列のインスペクタ。
/// 型付きで開ける定義は記述子で編集でき、編集のたびに保持列へ
/// 書き戻す（`EffectPropertyEditing`）。未知の型は生保持のまま
/// 編集対象外であることを表示する。
struct EffectInspectorView: View {
    let item: BaseItem
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void

    var body: some View {
        if let effects = EffectPropertyEditing.effectList(for: item), !effects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text("映像エフェクト")
                    .bold()
                ForEach(effects.indices, id: \.self) { index in
                    EffectInspectorRow(
                        item: item, index: index, preserved: effects[index],
                        animationContext: animationContext, onEdited: onEdited
                    )
                }
            }
        }
    }
}

private struct EffectInspectorRow: View {
    let item: BaseItem
    let index: Int
    let preserved: PreservedObject
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void
    @State private var definition: VideoEffectDefinitionBase?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shortTypeName)
                .font(.callout)
                .bold()
            if let definition {
                PropertyInspectorView(
                    descriptors: EffectPropertyMetadata.descriptors(for: definition),
                    animationContext: animationContext,
                    onEdited: {
                        EffectPropertyEditing.writeBack(definition, for: item, at: index)
                        onEdited()
                    }
                )
            } else {
                Text("型付き編集未対応（生保持のまま保存されます）")
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
