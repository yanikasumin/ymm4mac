import AppKit
import SwiftUI
import YMM4Core

/// プロパティメタデータ（YMM4Core の `PropertyDescriptor` 列）から
/// インスペクタを自動生成する汎用ビュー（MAC-0029）。
///
/// 対象オブジェクトごとの画面は作らない。記述子の種類ごとに1行の
/// 編集部品を用意し、グループ（セクション）単位で並べるだけである。
/// 値の読み書きは全て記述子経由でモデルの実プロパティへ届く。
/// 編集が確定したら `onEdited` を呼び、呼び出し側がプレビュー再合成
/// などを行う。アニメーション付き数値の行は `animationContext`
/// （プレビュー中のフレーム）での評価値を表示する。
/// 数値系の行（数値・整数・アニメーション付き数値）は、本家と同様に
/// 入力欄の横へ横スライダを並べる。範囲は記述子が持つ値域
/// （アニメーションでは `Animation` 自身の minValue / maxValue）を
/// 使い、ドラッグした時点でモデルへ即時反映して `onEdited` まで
/// つなぐ。値域を持たないプロパティにはスライダを付けない。
struct PropertyInspectorView: View {
    let descriptors: [PropertyDescriptor]
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(PropertyMetadata.sections(from: descriptors), id: \.name) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.name)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.secondary)
                    ForEach(section.descriptors, id: \.id) { descriptor in
                        PropertyRowView(
                            descriptor: descriptor,
                            animationContext: animationContext,
                            onEdited: onEdited
                        )
                    }
                }
            }
        }
    }
}

/// 記述子1件分の編集行。種類ごとに部品を切り替える。
private struct PropertyRowView: View {
    let descriptor: PropertyDescriptor
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(descriptor.displayName)
                .font(.callout)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            editor
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch descriptor.access {
        case .number:
            NumberRowView(descriptor: descriptor, onEdited: onEdited)
        case .integer:
            IntegerRowView(descriptor: descriptor, onEdited: onEdited)
        case .boolean:
            Toggle("", isOn: Binding(
                get: { descriptor.boolValue ?? false },
                set: { descriptor.setBoolValue($0); onEdited() }
            ))
            .labelsHidden()
        case .text:
            if case .text(let multiline) = descriptor.kind, multiline {
                MultilineTextRowView(descriptor: descriptor, onEdited: onEdited)
            } else {
                TextRowView(descriptor: descriptor, onEdited: onEdited)
            }
        case .enumeration:
            EnumRowView(descriptor: descriptor, onEdited: onEdited)
        case .color:
            ColorPicker("", selection: Binding(
                get: { swiftUIColor(from: descriptor.colorValue ?? .white) },
                set: { descriptor.setColorValue(coreColor(from: $0)); onEdited() }
            ), supportsOpacity: true)
            .labelsHidden()
        case .animation:
            AnimationRowView(
                descriptor: descriptor, animationContext: animationContext, onEdited: onEdited
            )
        }
    }
}

