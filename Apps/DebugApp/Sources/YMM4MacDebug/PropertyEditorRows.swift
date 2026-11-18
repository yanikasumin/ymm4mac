import AppKit
import SwiftUI
import YMM4Core

// MARK: - 数値

struct NumberRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(descriptor: PropertyDescriptor, onEdited: @escaping () -> Void) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        _text = State(initialValue: formatNumber(descriptor.numberValue ?? 0))
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
                .focused($isFocused)
                .onSubmit { commit() }
                // Enter だけでなく、フォーカスを外した時点でも確定する。
                // 確定経路が Enter のみだと、入力後に他所をクリックした編集が
                // モデルへ届かず、行が作り直されたときに旧値へ戻って見える。
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
            if let range {
                Slider(value: sliderBinding, in: range)
                    .frame(minWidth: 60)
            }
        }
    }

    /// 記述子が値域を持つ場合のみスライダを出す。
    private var range: ClosedRange<Double>? {
        guard case .number(let range) = descriptor.kind, let range,
              range.upperBound > range.lowerBound
        else { return nil }
        return range
    }

    /// スライダはドラッグのたびにモデルへ即時反映し、入力欄の表示も
    /// 追従させる（確定はスライダ側では行わない）。
    private var sliderBinding: Binding<Double> {
        Binding(
            get: { descriptor.numberValue ?? 0 },
            set: { newValue in
                descriptor.setNumberValue(newValue)
                text = formatNumber(descriptor.numberValue ?? newValue)
                onEdited()
            }
        )
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

struct IntegerRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

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
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
            Stepper("", value: Binding(
                get: { descriptor.integerValue ?? 0 },
                set: { descriptor.setIntegerValue($0); text = String($0); onEdited() }
            ))
            .labelsHidden()
            if let range {
                Slider(
                    value: sliderBinding,
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .frame(minWidth: 60)
            }
        }
    }

    /// 記述子が値域を持つ場合のみスライダを出す。
    private var range: ClosedRange<Int>? {
        guard case .integer(let range) = descriptor.kind, let range,
              range.upperBound > range.lowerBound
        else { return nil }
        return range
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { Double(descriptor.integerValue ?? 0) },
            set: { newValue in
                descriptor.setIntegerValue(Int(newValue.rounded()))
                text = String(descriptor.integerValue ?? Int(newValue.rounded()))
                onEdited()
            }
        )
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

struct TextRowView: View {
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
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
    }

    private func commit() {
        descriptor.setStringValue(text)
        onEdited()
    }
}

struct MultilineTextRowView: View {
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

struct EnumRowView: View {
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

struct AnimationRowView: View {
    let descriptor: PropertyDescriptor
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        descriptor: PropertyDescriptor, animationContext: AnimationEvaluationContext,
        onEdited: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.animationContext = animationContext
        self.onEdited = onEdited
        let animation = descriptor.animationValue
        let value: Double
        if let animation,
           animation.animationType.isKeyFrameSupported,
           !animation.keyFrames.frames.isEmpty {
            // キーフレームがある場合は、再生ヘッドの属する区間の
            // 開始値を表示する（編集対象と一致させる）。
            let segment = animation.segmentIndex(atFrame: animationContext.frame)
            value = animation.values.indices.contains(segment)
                ? animation.values[segment].value
                : (animation.values.last?.value ?? animation.defaultValue)
        } else {
            value = animation.map { animationContext.value(of: $0) } ?? 0
        }
        _text = State(initialValue: formatNumber(value))
    }

    /// キーフレーム編集の対象区間。キーフレーム対応型でキーフレーム
    /// がある場合のみ値を持ち、それ以外は nil（従来の編集経路）。
    private var editingSegment: Int? {
        guard let animation = descriptor.animationValue,
              animation.animationType.isKeyFrameSupported,
              !animation.keyFrames.frames.isEmpty else { return nil }
        return animation.segmentIndex(atFrame: animationContext.frame)
    }

    /// 表示・編集の対象値（区間編集中は区間の開始値、それ以外は
    /// 文脈での評価値）。
    private var displayedValue: Double {
        guard let animation = descriptor.animationValue else { return 0 }
        if let segment = editingSegment {
            return animation.values.indices.contains(segment)
                ? animation.values[segment].value
                : (animation.values.last?.value ?? animation.defaultValue)
        }
        return animationContext.value(of: animation)
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
                .focused($isFocused)
                .onSubmit { commit() }
                // 編集対象の区間が変わったら入力欄も追従させる
                // （K19-01）。入力中（フォーカス保持中）は未確定の
                // 文字列を破棄しない。
                .onChange(of: editingSegment) { _, _ in
                    if !isFocused {
                        text = formatNumber(displayedValue)
                    }
                }
                // 数値行と同じく、フォーカスを外した時点でも確定する。
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
            if let animation = descriptor.animationValue {
                // 本家と同様、入力欄の横にスライダを並べる。範囲は
                // アニメーション自身の定義値（minValue / maxValue）。
                if animation.maxValue > animation.minValue {
                    Slider(
                        value: sliderBinding,
                        in: animation.minValue...animation.maxValue
                    )
                    .frame(minWidth: 60)
                }
                // アニメーション種別の切替メニュー（本家は
                // AnimationSlider の右クリックメニュー）。
                AnimationTypeMenuButton(descriptor: descriptor, onEdited: onEdited)
                Text(caption(for: animation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// スライダの現在値は表示対象値（区間編集中は区間の開始値、
    /// それ以外は文脈での評価値）。ドラッグは入力欄の確定と同じ
    /// 書き込み経路で即時反映し、入力欄の表示も追従させる。
    private var sliderBinding: Binding<Double> {
        Binding(
            get: { displayedValue },
            set: { newValue in
                guard descriptor.animationValue != nil else { return }
                writeValue(newValue)
                text = formatNumber(displayedValue)
                onEdited()
            }
        )
    }

    private func caption(for animation: YMM4Core.Animation) -> String {
        let range = "\(formatNumber(animation.minValue))〜\(formatNumber(animation.maxValue))"
        if animation.animationType == .none {
            return "定数（\(range)）"
        }
        if let segment = editingSegment {
            let total = animation.keyFrames.frames.count + 1
            return "キーフレーム区間 \(segment + 1)/\(total) の開始値を編集中（\(range)）"
        }
        // キーフレームが無い補間型では先頭値（開始値）の編集になる。
        return "\(range)、開始値を編集中"
    }

    /// 値の書き込み経路の振り分け: 定数は定数化、キーフレーム区間が
    /// あればその区間の開始値、それ以外は先頭値。
    private func writeValue(_ value: Double) {
        guard let animation = descriptor.animationValue else { return }
        if animation.animationType == .none {
            descriptor.setAnimationConstantValue(value)
        } else if let segment = editingSegment {
            descriptor.setAnimationValue(value, atSegment: segment)
        } else {
            descriptor.setAnimationFirstValue(value)
        }
    }

    private func commit() {
        guard descriptor.animationValue != nil else { return }
        guard let value = Double(text) else {
            // 解釈できない入力（全角数字など）は確定せず、表示を
            // モデルの現在値へ戻す（未確定の入力が残って見えないように）。
            text = formatNumber(displayedValue)
            return
        }
        writeValue(value)
        text = formatNumber(displayedValue)
        onEdited()
    }
}

// MARK: - 色の変換

func swiftUIColor(from color: YMM4Core.Color) -> SwiftUI.Color {
    SwiftUI.Color(
        red: Double(color.red) / 255,
        green: Double(color.green) / 255,
        blue: Double(color.blue) / 255,
        opacity: Double(color.alpha) / 255
    )
}

func coreColor(from color: SwiftUI.Color) -> YMM4Core.Color {
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

func formatNumber(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(format: "%.4g", value)
}

