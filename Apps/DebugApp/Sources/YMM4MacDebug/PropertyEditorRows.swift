import AppKit
import SwiftUI
import YMM4Core

// MARK: - 数値

struct NumberRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    @State private var text: String
    /// 未編集とみなすテキスト（初期表示・フォーカス取得時点・
    /// プログラム側の同期直後の文字列）。確定時に text がこれと
    /// 一致すれば書き戻さない（FE-R1-019。表示は %.4g へ丸まるため、
    /// 無編集の確定でも丸めた値がモデルへ戻り精度が失われていた）。
    @State private var uneditedText: String
    @FocusState private var isFocused: Bool

    init(descriptor: PropertyDescriptor, onEdited: @escaping () -> Void) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        let initial = formatNumber(descriptor.numberValue ?? 0)
        _text = State(initialValue: initial)
        _uneditedText = State(initialValue: initial)
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
                    if focused {
                        uneditedText = text
                    } else {
                        commit()
                    }
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
                uneditedText = text
                onEdited()
            }
        )
    }

    private func commit() {
        // 未編集（フォーカス時点のテキストのまま）なら書き戻さない。
        // 表示桁への丸めをモデルへ戻すと小数の精度が失われる
        // （FE-R1-019）。
        guard text != uneditedText else { return }
        // 非有限値（"nan" / "inf" は Double として解釈できてしまう）も
        // 確定しない。モデルへ入れると保存時に 0.0 へ化ける
        // （FE-R3-118-02）。解釈できない入力と同じく表示を現在値へ戻す。
        guard let value = Double(text), value.isFinite else {
            text = formatNumber(descriptor.numberValue ?? 0)
            uneditedText = text
            return
        }
        descriptor.setNumberValue(value)
        text = formatNumber(descriptor.numberValue ?? value)
        uneditedText = text
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
    /// 入力セッションが所有する編集対象区間。フォーカスを得た時点で
    /// 固定し、確定まで保持する。再生ヘッドが別区間へ移っても、
    /// 未確定の入力が別区間へ書き込まれることはない（R20-114-01）。
    @State private var focusedSegment: Int?
    /// 未編集とみなすテキスト（数値行と同じ FE-R1-019 対策）。
    @State private var uneditedText: String

    init(
        descriptor: PropertyDescriptor, animationContext: AnimationEvaluationContext,
        onEdited: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.animationContext = animationContext
        self.onEdited = onEdited
        let animation = descriptor.animationValue
        let value: Double
        if let animation {
            // 初期表示は編集対象値（キーフレームがある場合は再生
            // ヘッドの属する区間の開始値、それ以外は先頭値）。
            // 再生ヘッド位置での評価値ではない（FE-R13-001）。
            let segment = animation.animationType.isKeyFrameSupported
                && !animation.keyFrames.frames.isEmpty
                ? animation.segmentIndex(atFrame: animationContext.frame)
                : 0
            value = AnimationSliderScale.editValue(of: animation, valueIndex: segment)
        } else {
            value = 0
        }
        let initial = formatAnimationValue(value, spec: descriptor.sliderSpec)
        _text = State(initialValue: initial)
        _uneditedText = State(initialValue: initial)
    }

    /// 表示用の数値書式（スライダ表示仕様の stringFormat に従う）。
    private func formatValue(_ value: Double) -> String {
        formatAnimationValue(value, spec: descriptor.sliderSpec)
    }

    /// キーフレーム編集の対象区間。キーフレーム対応型でキーフレーム
    /// がある場合のみ値を持ち、それ以外は nil（従来の編集経路）。
    private var editingSegment: Int? {
        guard let animation = descriptor.animationValue,
              animation.animationType.isKeyFrameSupported,
              !animation.keyFrames.frames.isEmpty else { return nil }
        return animation.segmentIndex(atFrame: animationContext.frame)
    }

    /// 表示・編集の対象値（区間編集中はその区間の開始値、それ以外は
    /// 先頭値）。スライダと数値入力の表示・書き込みはこの値で一致
    /// させる。本家の各スライダは担当する AnimationValue.Value を
    /// 直接編集し、再生ヘッド位置での評価値は編集対象ではない
    /// （FE-R13-001）。
    private var editTargetValue: Double {
        guard let animation = descriptor.animationValue else { return 0 }
        return AnimationSliderScale.editValue(
            of: animation, valueIndex: editingSegment ?? 0)
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
                        text = formatValue(editTargetValue)
                        uneditedText = text
                    }
                }
                // 数値行と同じく、フォーカスを外した時点でも確定する。
                // フォーカスを得た時点で編集対象区間をセッションへ
                // 固定する（R20-114-01）。
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        focusedSegment = editingSegment
                        uneditedText = text
                    } else {
                        commit()
                        focusedSegment = nil
                    }
                }
            if let animation = descriptor.animationValue {
                // 本家と同様、入力欄の横にスライダを並べる。範囲は
                // 表示仕様（AnimationSliderSpec）の基準範囲を、同一
                // Animation の全有効値で共有するスケールで広げたもの
                // （AnimationSliderScale）。絶対制限（minValue /
                // maxValue）全域をそのまま範囲にすると、基準範囲に
                // 対して刻みが粗くなりドラッグで値が跳ぶ（FE-R1-042）。
                // 仕様が無い項目ではスライダを出さず数値入力のみ。
                if let spec = descriptor.sliderSpec {
                    // 単位は入力欄の横へ出す。単位が本家リソースの
                    // キー名のまま（未解決）の場合は、キー名を
                    // ユーザーへ見せず単位なしとして扱う。
                    if !spec.unitIsResourceKey, !spec.unit.isEmpty {
                        Text(spec.unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let range = AnimationSliderScale.sliderRange(
                        for: animation,
                        valueIndex: editingSegment ?? 0, spec: spec)
                    if range.max > range.min {
                        Slider(
                            value: sliderBinding,
                            in: range.min...range.max
                        )
                        .frame(minWidth: 60)
                    }
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

    /// スライダの現在値は編集対象値（区間編集中はその区間の開始値、
    /// それ以外は先頭値）で、書き込み先と一致する（FE-R13-001）。
    /// ドラッグは入力欄の確定と同じ書き込み経路で即時反映し、
    /// 入力欄の表示も追従させる。
    private var sliderBinding: Binding<Double> {
        Binding(
            get: { editTargetValue },
            set: { newValue in
                guard descriptor.animationValue != nil else { return }
                writeValue(newValue)
                text = formatValue(editTargetValue)
                uneditedText = text
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
        writeValue(value, segment: editingSegment)
    }

    private func writeValue(_ value: Double, segment: Int?) {
        guard let animation = descriptor.animationValue else { return }
        if animation.animationType == .none {
            descriptor.setAnimationConstantValue(value)
        } else if let segment {
            descriptor.setAnimationValue(value, atSegment: segment)
        } else {
            descriptor.setAnimationFirstValue(value)
        }
    }

    private func commit() {
        guard descriptor.animationValue != nil else { return }
        // 未編集（フォーカス時点のテキストのまま）なら書き戻さない
        // （FE-R1-019。表示桁への丸めが区間の値へ戻ると精度が失われる）。
        guard text != uneditedText else { return }
        guard let value = Double(text), value.isFinite else {
            // 解釈できない入力（全角数字など）と非有限値（"nan" /
            // "inf"）は確定せず、表示をモデルの現在値へ戻す
            // （未確定の入力が残って見えないように。非有限値をモデルへ
            // 入れると保存時に 0.0 へ化ける。FE-R3-118-02）。
            text = formatValue(editTargetValue)
            uneditedText = text
            return
        }
        // 確定先はセッションが所有する区間（フォーカス取得時点）。
        // 現在の再生ヘッド位置の区間ではない（R20-114-01）。
        writeValue(value, segment: focusedSegment ?? editingSegment)
        text = formatValue(editTargetValue)
        uneditedText = text
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

/// アニメーション行の表示書式。スライダ表示仕様がある場合はその
/// stringFormat（"F<n>" = 小数第 n 位まで）で整形する（本家の
/// TextBoxSlider のテキスト表示と同じ規則）。仕様が無い、または
/// 形式を解釈できない場合は従来の formatNumber に落とす。
func formatAnimationValue(_ value: Double, spec: AnimationSliderSpec?) -> String {
    guard let spec,
          spec.stringFormat.hasPrefix("F"),
          let digits = Int(spec.stringFormat.dropFirst()),
          (0...10).contains(digits) else {
        return formatNumber(value)
    }
    return String(format: "%.\(digits)f", value)
}

