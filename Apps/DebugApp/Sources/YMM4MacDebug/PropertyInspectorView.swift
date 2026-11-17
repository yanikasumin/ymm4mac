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

// MARK: - 数値

private struct NumberRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    @State private var text: String

    init(descriptor: PropertyDescriptor, onEdited: @escaping () -> Void) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        _text = State(initialValue: formatNumber(descriptor.numberValue ?? 0))
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 110)
            .onSubmit { commit() }
    }

    private func commit() {
        guard let value = Double(text) else {
            text = formatNumber(descriptor.numberValue ?? 0)
            return
        }
        descriptor.setNumberValue(value)
        text = formatNumber(descriptor.numberValue ?? value)
        onEdited()
    }
}

private struct IntegerRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    @State private var text: String

    init(descriptor: PropertyDescriptor, onEdited: @escaping () -> Void) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        _text = State(initialValue: String(descriptor.integerValue ?? 0))
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .onSubmit { commit() }
            Stepper("", value: Binding(
                get: { descriptor.integerValue ?? 0 },
                set: { descriptor.setIntegerValue($0); text = String($0); onEdited() }
            ))
            .labelsHidden()
        }
    }

    private func commit() {
        guard let value = Int(text) else {
            text = String(descriptor.integerValue ?? 0)
            return
        }
        descriptor.setIntegerValue(value)
        text = String(descriptor.integerValue ?? value)
        onEdited()
    }
}

// MARK: - 文字列

private struct TextRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    @State private var text: String

    init(descriptor: PropertyDescriptor, onEdited: @escaping () -> Void) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        _text = State(initialValue: descriptor.stringValue ?? "")
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                descriptor.setStringValue(text)
                onEdited()
            }
    }
}

private struct MultilineTextRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(descriptor: PropertyDescriptor, onEdited: @escaping () -> Void) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        _text = State(initialValue: descriptor.stringValue ?? "")
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .frame(minHeight: 54)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    descriptor.setStringValue(text)
                    onEdited()
                }
            }
    }
}

// MARK: - 列挙

private struct EnumRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { descriptor.stringValue ?? "" },
            set: { descriptor.setStringValue($0); onEdited() }
        )) {
            ForEach(options, id: \.value) { option in
                Text(option.displayName).tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220, alignment: .leading)
    }

    /// 現在値が選択肢に無い場合（未知のメンバ名）は、その値を選択肢に
    /// 加えて保持する（データ保全のため、勝手に既知の値へ寄せない）。
    private var options: [PropertyEnumOption] {
        guard case .enumeration(let defined) = descriptor.kind else { return [] }
        let current = descriptor.stringValue ?? ""
        if defined.contains(where: { $0.value == current }) {
            return defined
        }
        return [PropertyEnumOption(value: current, displayName: current)] + defined
    }
}

// MARK: - アニメーション付き数値

private struct AnimationRowView: View {
    let descriptor: PropertyDescriptor
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void
    @State private var text: String

    init(
        descriptor: PropertyDescriptor, animationContext: AnimationEvaluationContext,
        onEdited: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.animationContext = animationContext
        self.onEdited = onEdited
        let animation = descriptor.animationValue
        let value = animation.map { animationContext.value(of: $0) } ?? 0
        _text = State(initialValue: formatNumber(value))
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
                .onSubmit { commit() }
            if let animation = descriptor.animationValue {
                Text(caption(for: animation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func caption(for animation: YMM4Core.Animation) -> String {
        let range = "\(formatNumber(animation.minValue))〜\(formatNumber(animation.maxValue))"
        if animation.animationType == .none {
            return "定数（\(range)）"
        }
        // キーフレーム編集は未対応のため、種別名と「先頭値のみ書き換わる」
        // ことを明示する。
        return "\(animation.animationType)（\(range)、編集は先頭値のみ）"
    }

    private func commit() {
        guard let value = Double(text), let animation = descriptor.animationValue else {
            return
        }
        if animation.animationType == .none {
            descriptor.setAnimationConstantValue(value)
        } else {
            descriptor.setAnimationFirstValue(value)
        }
        if let updated = descriptor.animationValue {
            text = formatNumber(animationContext.value(of: updated))
        }
        onEdited()
    }
}

// MARK: - 色の変換

private func swiftUIColor(from color: YMM4Core.Color) -> SwiftUI.Color {
    SwiftUI.Color(
        red: Double(color.red) / 255,
        green: Double(color.green) / 255,
        blue: Double(color.blue) / 255,
        opacity: Double(color.alpha) / 255
    )
}

private func coreColor(from color: SwiftUI.Color) -> YMM4Core.Color {
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    func byte(_ component: CGFloat) -> UInt8 {
        UInt8(min(max(component, 0), 1) * 255)
    }
    return YMM4Core.Color(
        alpha: byte(nsColor.alphaComponent),
        red: byte(nsColor.redComponent),
        green: byte(nsColor.greenComponent),
        blue: byte(nsColor.blueComponent)
    )
}

// MARK: - 数値の表示

private func formatNumber(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(format: "%.4g", value)
}

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
