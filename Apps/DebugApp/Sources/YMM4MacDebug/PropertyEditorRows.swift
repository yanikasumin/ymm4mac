import AppKit
import SwiftUI
import YMM4Core

/// 記述子の値変更を Undo へ記録する共通処理（FE-UNDO-WIRING）。
/// 記録先（recorder）または対象キーが無い場合は何もしない。
/// 適用クロージャは記述子を保持し、記述子の読み書きクロージャが
/// 対象オブジェクトを強く保持するため、履歴に残る間は対象も残る
/// （`EditTargetKey` の接続側契約）。セッション中の書き込みは
/// 所有者のトークンをそのまま転送する（FE-R20-126-03）。
func recordDescriptorValueChange<Value: Equatable>(
    recorder: EditRecorder?, target: EditTargetKey?,
    oldValue: Value?, newValue: Value?,
    apply: @escaping (Value) -> Void,
    sessionToken: EditSessionToken? = nil
) {
    guard let recorder, let target,
          let oldValue, let newValue else { return }
    recorder.recordValueChange(
        target: target, oldValue: oldValue, newValue: newValue, apply: apply,
        sessionToken: sessionToken)
}

/// 記述子への書き込みの入口確認（FE-R20-126-03）。
///
/// 記録先が存在し、かつ記録できる状態（セッションが無い、または
/// 自分がその所有者）の場合だけ書き込みを許可する。許可されない
/// 場合はモデル変更自体を行わない（他人のセッションへ変更が混入
/// したり、無記録の変更が残ったりすることを書き込みの入口で防ぐ）。
/// 記録先が無い構成では従来どおり無記録で書き込む。
func editWriteAllowed(
    recorder: EditRecorder?, sessionToken: EditSessionToken? = nil
) -> Bool {
    guard let recorder else { return true }
    return recorder.canRecordValueChange(sessionToken: sessionToken)
}

/// 連続編集（スライダ・ドラッグ）の Undo セッションの状態
/// （FE-R21-126-01）。
///
/// 開始前・所有中・開始拒否を区別する。開始拒否になったドラッグは、
/// そのドラッグが終了するまで書き込み可能に変化しない。トークンの
/// 有無（nil か否か）だけで表すと「開始前」と「開始拒否」が区別
/// できず、他のセッションの終了後に、拒否されたドラッグの継続
/// 書き込みがトークンなしの離散編集として受理されてしまうため、
/// 状態として明示する。
enum EditDragSession {
    /// ドラッグ中でない（記録先が無い構成では無記録で書き込む状態も
    /// この形になる）。
    case idle
    /// 自分が所有するセッションが有効。
    case owning(EditSessionToken)
    /// 開始を拒否された。このドラッグが終わるまで書き込み禁止。
    case refused

    /// ドラッグ開始時にセッションを開き、結果を状態へ反映する。
    /// 記録先が無い構成では従来どおり無記録で書き込むため、開始前
    /// のままにする。
    mutating func begin(using recorder: EditRecorder?) {
        guard let recorder else {
            self = .idle
            return
        }
        if let token = recorder.beginSession() {
            self = .owning(token)
        } else {
            self = .refused
        }
    }

    /// 書き込みに提示するトークン（所有中の場合だけ持つ）。
    var token: EditSessionToken? {
        if case .owning(let token) = self { return token }
        return nil
    }

    /// このドラッグの書き込みが記録可能か。開始拒否の間は、他の
    /// セッションが終了しても常に false のままである。
    func writeAllowed(recorder: EditRecorder?) -> Bool {
        if case .refused = self { return false }
        return editWriteAllowed(recorder: recorder, sessionToken: token)
    }

    /// ドラッグ終了時にセッションを確定し、状態を開始前へ戻す。
    mutating func endCommitting(to recorder: EditRecorder?) {
        if case .owning(let token) = self {
            recorder?.commitSession(token: token)
        }
        self = .idle
    }

    /// ドラッグ取消時にセッションを破棄し、状態を開始前へ戻す。
    mutating func endCancelling(to recorder: EditRecorder?) {
        if case .owning(let token) = self {
            recorder?.cancelSession(token: token)
        }
        self = .idle
    }
}

// MARK: - 数値

struct NumberRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    var editRecorder: EditRecorder?
    var editTarget: EditTargetKey?
    @State private var text: String
    /// スライダのドラッグについての Undo セッションの状態（開始前・
    /// 所有中・開始拒否。FE-R20-126-03、FE-R21-126-01）。
    @State private var sliderSession: EditDragSession = .idle
    /// 未編集とみなすテキスト（初期表示・フォーカス取得時点・
    /// プログラム側の同期直後の文字列）。確定時に text がこれと
    /// 一致すれば書き戻さない（FE-R1-019。表示は %.4g へ丸まるため、
    /// 無編集の確定でも丸めた値がモデルへ戻り精度が失われていた）。
    @State private var uneditedText: String
    @FocusState private var isFocused: Bool

    init(
        descriptor: PropertyDescriptor, onEdited: @escaping () -> Void,
        editRecorder: EditRecorder? = nil, editTarget: EditTargetKey? = nil
    ) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        self.editRecorder = editRecorder
        self.editTarget = editTarget
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
                Slider(
                    value: sliderBinding, in: range,
                    onEditingChanged: sliderEditingChanged
                )
                .frame(minWidth: 60)
            }
        }
    }

    /// スライダのドラッグ開始・終了で Undo セッションを開閉し、
    /// ドラッグ全体を履歴1エントリへまとめる。開始を拒否された
    /// ドラッグは、終了まで書き込み禁止のままになる
    /// （FE-R21-126-01）。
    private func sliderEditingChanged(_ editing: Bool) {
        if editing {
            sliderSession.begin(using: editRecorder)
        } else {
            sliderSession.endCommitting(to: editRecorder)
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
                // 自分のセッションの所有者でない書き込みは入口で
                // 拒否する（FE-R20-126-03）。開始拒否されたドラッグ
                // の継続書き込みも拒否される（FE-R21-126-01）。
                guard sliderSession.writeAllowed(recorder: editRecorder)
                else { return }
                let old = descriptor.numberValue
                descriptor.setNumberValue(newValue)
                text = formatNumber(descriptor.numberValue ?? newValue)
                uneditedText = text
                recordDescriptorValueChange(
                    recorder: editRecorder, target: editTarget,
                    oldValue: old, newValue: descriptor.numberValue,
                    apply: { descriptor.setNumberValue($0) },
                    sessionToken: sliderSession.token)
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
        // 他のセッションが有効な間は離散編集を行わない
        // （FE-R20-126-03。入口で拒否し、モデルを変更しない）。
        guard editWriteAllowed(recorder: editRecorder) else { return }
        let old = descriptor.numberValue
        descriptor.setNumberValue(value)
        text = formatNumber(descriptor.numberValue ?? value)
        uneditedText = text
        recordDescriptorValueChange(
            recorder: editRecorder, target: editTarget,
            oldValue: old, newValue: descriptor.numberValue,
            apply: { descriptor.setNumberValue($0) })
        onEdited()
    }
}

struct IntegerRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    var editRecorder: EditRecorder?
    var editTarget: EditTargetKey?
    @State private var text: String
    @FocusState private var isFocused: Bool
    /// スライダのドラッグについての Undo セッションの状態（開始前・
    /// 所有中・開始拒否。FE-R20-126-03、FE-R21-126-01）。
    @State private var sliderSession: EditDragSession = .idle

    init(
        descriptor: PropertyDescriptor, onEdited: @escaping () -> Void,
        editRecorder: EditRecorder? = nil, editTarget: EditTargetKey? = nil
    ) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        self.editRecorder = editRecorder
        self.editTarget = editTarget
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
                set: { newValue in
                    guard editWriteAllowed(recorder: editRecorder)
                    else { return }
                    let old = descriptor.integerValue
                    descriptor.setIntegerValue(newValue)
                    text = String(newValue)
                    recordDescriptorValueChange(
                        recorder: editRecorder, target: editTarget,
                        oldValue: old, newValue: descriptor.integerValue,
                        apply: { descriptor.setIntegerValue($0) })
                    onEdited()
                }
            ))
            .labelsHidden()
            if let range {
                Slider(
                    value: sliderBinding,
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1,
                    onEditingChanged: sliderEditingChanged
                )
                .frame(minWidth: 60)
            }
        }
    }

    /// スライダのドラッグ開始・終了で Undo セッションを開閉する。
    /// 開始を拒否されたドラッグは、終了まで書き込み禁止のままに
    /// なる（FE-R21-126-01）。
    private func sliderEditingChanged(_ editing: Bool) {
        if editing {
            sliderSession.begin(using: editRecorder)
        } else {
            sliderSession.endCommitting(to: editRecorder)
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
                guard sliderSession.writeAllowed(recorder: editRecorder)
                else { return }
                let old = descriptor.integerValue
                descriptor.setIntegerValue(Int(newValue.rounded()))
                text = String(descriptor.integerValue ?? Int(newValue.rounded()))
                recordDescriptorValueChange(
                    recorder: editRecorder, target: editTarget,
                    oldValue: old, newValue: descriptor.integerValue,
                    apply: { descriptor.setIntegerValue($0) },
                    sessionToken: sliderSession.token)
                onEdited()
            }
        )
    }

    private func commit() {
        guard let value = Int(text) else {
            text = String(descriptor.integerValue ?? 0)
            return
        }
        guard editWriteAllowed(recorder: editRecorder) else { return }
        let old = descriptor.integerValue
        descriptor.setIntegerValue(value)
        text = String(descriptor.integerValue ?? value)
        recordDescriptorValueChange(
            recorder: editRecorder, target: editTarget,
            oldValue: old, newValue: descriptor.integerValue,
            apply: { descriptor.setIntegerValue($0) })
        onEdited()
    }
}

// MARK: - 文字列

struct TextRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    var editRecorder: EditRecorder?
    var editTarget: EditTargetKey?
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        descriptor: PropertyDescriptor, onEdited: @escaping () -> Void,
        editRecorder: EditRecorder? = nil, editTarget: EditTargetKey? = nil
    ) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        self.editRecorder = editRecorder
        self.editTarget = editTarget
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
        guard editWriteAllowed(recorder: editRecorder) else { return }
        let old = descriptor.stringValue
        descriptor.setStringValue(text)
        recordDescriptorValueChange(
            recorder: editRecorder, target: editTarget,
            oldValue: old, newValue: descriptor.stringValue,
            apply: { descriptor.setStringValue($0) })
        onEdited()
    }
}

struct MultilineTextRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    var editRecorder: EditRecorder?
    var editTarget: EditTargetKey?
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        descriptor: PropertyDescriptor, onEdited: @escaping () -> Void,
        editRecorder: EditRecorder? = nil, editTarget: EditTargetKey? = nil
    ) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        self.editRecorder = editRecorder
        self.editTarget = editTarget
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
                    guard editWriteAllowed(recorder: editRecorder)
                    else { return }
                    let old = descriptor.stringValue
                    descriptor.setStringValue(text)
                    recordDescriptorValueChange(
                        recorder: editRecorder, target: editTarget,
                        oldValue: old, newValue: descriptor.stringValue,
                        apply: { descriptor.setStringValue($0) })
                    onEdited()
                }
            }
    }
}

// MARK: - 列挙

struct EnumRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    var editRecorder: EditRecorder?
    var editTarget: EditTargetKey?

    init(
        descriptor: PropertyDescriptor, onEdited: @escaping () -> Void,
        editRecorder: EditRecorder? = nil, editTarget: EditTargetKey? = nil
    ) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        self.editRecorder = editRecorder
        self.editTarget = editTarget
    }

    var body: some View {
        Picker("", selection: Binding(
            get: { descriptor.stringValue ?? "" },
            set: { newValue in
                guard editWriteAllowed(recorder: editRecorder)
                else { return }
                let old = descriptor.stringValue
                descriptor.setStringValue(newValue)
                recordDescriptorValueChange(
                    recorder: editRecorder, target: editTarget,
                    oldValue: old, newValue: descriptor.stringValue,
                    apply: { descriptor.setStringValue($0) })
                onEdited()
            }
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
    var editRecorder: EditRecorder?
    var editTarget: EditTargetKey?
    @State private var text: String
    @FocusState private var isFocused: Bool
    /// スライダのドラッグについての Undo セッションの状態（開始前・
    /// 所有中・開始拒否。FE-R20-126-03、FE-R21-126-01）。
    @State private var sliderSession: EditDragSession = .idle
    /// 入力セッションが所有する編集対象区間。フォーカスを得た時点で
    /// 固定し、確定まで保持する。再生ヘッドが別区間へ移っても、
    /// 未確定の入力が別区間へ書き込まれることはない（R20-114-01）。
    @State private var focusedSegment: Int?
    /// 未編集とみなすテキスト（数値行と同じ FE-R1-019 対策）。
    @State private var uneditedText: String
    /// 移動量指定の第2値（移動量）の入力状態。第1値とは独立した
    /// 編集セッションを持つ（FE-R13-003）。
    @State private var movementText: String
    @State private var movementUneditedText: String
    @FocusState private var isMovementFocused: Bool

    init(
        descriptor: PropertyDescriptor, animationContext: AnimationEvaluationContext,
        onEdited: @escaping () -> Void,
        editRecorder: EditRecorder? = nil, editTarget: EditTargetKey? = nil
    ) {
        self.descriptor = descriptor
        self.animationContext = animationContext
        self.onEdited = onEdited
        self.editRecorder = editRecorder
        self.editTarget = editTarget
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
        let movementValue = animation.map {
            AnimationSliderScale.editValue(of: $0, valueIndex: 1)
        } ?? 0
        let movementInitial = formatAnimationValue(
            movementValue, spec: descriptor.sliderSpec)
        _movementText = State(initialValue: movementInitial)
        _movementUneditedText = State(initialValue: movementInitial)
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
        VStack(alignment: .leading, spacing: 4) {
            mainRow
            if isMovementAmount {
                movementRow
            }
        }
    }

    private var mainRow: some View {
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
                            in: range.min...range.max,
                            onEditingChanged: sliderEditingChanged
                        )
                        .frame(minWidth: 60)
                    }
                }
                // アニメーション種別の切替メニュー（本家は
                // AnimationSlider の右クリックメニュー）。
                AnimationTypeMenuButton(
                    descriptor: descriptor, onEdited: onEdited,
                    editRecorder: editRecorder, editTarget: editTarget)
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
                // 開始拒否されたドラッグの継続書き込みは、他の
                // セッションが終わっても許可されない
                // （FE-R21-126-01）。
                guard sliderSession.writeAllowed(recorder: editRecorder)
                else { return }
                writeValue(newValue, sessionToken: sliderSession.token)
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

    /// スライダのドラッグ開始・終了で Undo セッションを開閉し、
    /// ドラッグ全体を履歴1エントリへまとめる。開始を拒否された
    /// ドラッグは、終了まで書き込み禁止のままになる
    /// （FE-R21-126-01）。
    private func sliderEditingChanged(_ editing: Bool) {
        if editing {
            sliderSession.begin(using: editRecorder)
        } else {
            sliderSession.endCommitting(to: editRecorder)
        }
    }

    /// 値の書き込み経路の振り分け: 定数は定数化、キーフレーム区間が
    /// あればその区間の開始値、それ以外は先頭値。
    private func writeValue(_ value: Double, sessionToken: EditSessionToken?) {
        writeValue(value, segment: editingSegment, sessionToken: sessionToken)
    }

    /// 書き込みと Undo 記録。記録の対象キーは書き込み経路（定数／
    /// 先頭値／区間）ごとに分け、適用クロージャも同じ経路で書き戻す
    /// （経路が違えば戻し方も違うため。FE-UNDO-WIRING）。
    /// 書き込みは入口で記録可否を確認し、他人のセッションが有効な
    /// 場合はモデルを変更しない（FE-R20-126-03）。
    private func writeValue(
        _ value: Double, segment: Int?, sessionToken: EditSessionToken?
    ) {
        guard let animation = descriptor.animationValue else { return }
        guard editWriteAllowed(recorder: editRecorder, sessionToken: sessionToken)
        else { return }
        // 確定処理（FE-R13-004）は記録より前に適用し、記録する
        // 実効値が確定後の値と一致するようにする。
        let value = fixedOnCommit(value, for: animation)
        if animation.animationType == .none {
            let old = AnimationSliderScale.editValue(of: animation, valueIndex: 0)
            descriptor.setAnimationConstantValue(value)
            recordAnimationChange(
                branch: "const", valueIndex: 0, oldValue: old,
                apply: { descriptor.setAnimationConstantValue($0) },
                sessionToken: sessionToken)
        } else if let segment {
            let old = AnimationSliderScale.editValue(
                of: animation, valueIndex: segment)
            descriptor.setAnimationValue(value, atSegment: segment)
            recordAnimationChange(
                branch: "seg\(segment)", valueIndex: segment, oldValue: old,
                apply: { descriptor.setAnimationValue($0, atSegment: segment) },
                sessionToken: sessionToken)
        } else {
            let old = AnimationSliderScale.editValue(of: animation, valueIndex: 0)
            descriptor.setAnimationFirstValue(value)
            recordAnimationChange(
                branch: "first", valueIndex: 0, oldValue: old,
                apply: { descriptor.setAnimationFirstValue($0) },
                sessionToken: sessionToken)
        }
    }

    /// 確定値の確定処理（FE-R13-004）。表示仕様がある場合は本家
    /// `TextBoxSlider.FixValue` 相当（Delta 由来の桁で丸めてから
    /// 定義範囲へクランプ）を Core の純粋関数で適用する。スライダは
    /// Mac では即時書き込みのためドラッグ中も同じ経路を通る（本家は
    /// 編集終了時に1回だけ適用するが、最終値は一致する）。
    /// 仕様が無い項目では、本家でスライダ無しの数値編集に相当する
    /// 確定処理を確認できないため、丸めずに従来どおり記述子の
    /// クランプだけに委ねる。
    private func fixedOnCommit(_ value: Double, for animation: YMM4Core.Animation) -> Double {
        guard let spec = descriptor.sliderSpec else { return value }
        return AnimationSliderScale.fixedValue(
            value, delta: spec.delta,
            minimum: animation.minValue, maximum: animation.maxValue)
    }

    /// 書き込み後の値を読み戻して（ setter がクランプするため、
    /// 要求値ではなく実効値を記録する）Undo へ登録する。
    private func recordAnimationChange(
        branch: String, valueIndex: Int, oldValue: Double,
        apply: @escaping (Double) -> Void,
        sessionToken: EditSessionToken?
    ) {
        guard let editRecorder, let editTarget else { return }
        let newValue = descriptor.animationValue.map {
            AnimationSliderScale.editValue(of: $0, valueIndex: valueIndex)
        }
        recordDescriptorValueChange(
            recorder: editRecorder,
            target: EditTargetKey(
                object: editTarget.object, key: editTarget.key + "#" + branch),
            oldValue: oldValue, newValue: newValue, apply: apply,
            sessionToken: sessionToken)
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
        // テキスト確定は離散編集であり、Undo セッションのトークンは
        // 持たない（他人のセッションが有効なら writeValue の入口で
        // 拒否される）。
        writeValue(
            value, segment: focusedSegment ?? editingSegment, sessionToken: nil)
        text = formatValue(editTargetValue)
        uneditedText = text
        onEdited()
    }

    // MARK: 移動量指定の第2値（FE-R13-003）

    /// 移動量指定かどうか。第2値の編集行はこの種別のときだけ出す。
    private var isMovementAmount: Bool {
        descriptor.animationValue?.animationType == .movementAmount
    }

    /// 第2値（1フレームあたりの移動量）の表示・編集対象値。第1値と
    /// 同じく `AnimationSliderScale.editValue` の規則（対象インデックス
    /// の実値、短い値列では末尾値への代用）に従う。
    private var movementValue: Double {
        guard let animation = descriptor.animationValue else { return 0 }
        return AnimationSliderScale.editValue(of: animation, valueIndex: 1)
    }

    /// 移動量指定の第2値の編集行。本家は `Animation` の有効値ごとに
    /// 独立した `TextBoxSlider` を並べるため、第1値の行とは別の
    /// 入力欄＋スライダを持つ。範囲は Core の
    /// `AnimationSliderScale.sliderRange(for:valueIndex: 1)`（基準範囲・
    /// 絶対制限とも ±最大絶対値の対称置換済み）を使う。仕様が無い
    /// 項目では第1値と同じくスライダを出さず数値入力のみ。
    private var movementRow: some View {
        HStack(spacing: 6) {
            Text("移動量")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: $movementText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
                .focused($isMovementFocused)
                .onSubmit { commitMovementAmount() }
                // モデル側の値が変わったら（種別の切替直後など）
                // 入力欄も追従させる。入力中は未確定の文字列を
                // 破棄しない（第1値の区間追随と同じ規則）。
                .onChange(of: movementValue) { _, _ in
                    if !isMovementFocused {
                        movementText = formatValue(movementValue)
                        movementUneditedText = movementText
                    }
                }
                .onChange(of: isMovementFocused) { _, focused in
                    if focused {
                        movementUneditedText = movementText
                    } else {
                        commitMovementAmount()
                    }
                }
            if let animation = descriptor.animationValue,
               let spec = descriptor.sliderSpec {
                if !spec.unitIsResourceKey, !spec.unit.isEmpty {
                    Text(spec.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let range = AnimationSliderScale.sliderRange(
                    for: animation, valueIndex: 1, spec: spec)
                if range.max > range.min {
                    Slider(
                        value: movementSliderBinding,
                        in: range.min...range.max
                    )
                    .frame(minWidth: 60)
                }
            }
        }
    }

    private var movementSliderBinding: Binding<Double> {
        Binding(
            get: { movementValue },
            set: { newValue in
                guard descriptor.animationValue != nil else { return }
                writeMovementAmount(newValue)
                movementText = formatValue(movementValue)
                movementUneditedText = movementText
                onEdited()
            }
        )
    }

    /// 第2値の書き込み。クランプ範囲は本家の第2値のスライダの
    /// Min/Max（絶対制限の対称範囲 ±最大絶対値）であり、定義範囲
    /// [minValue, maxValue] ではクランプしない（定義範囲が 0..100 の
    /// 項目でも移動量は負値を取りうる）。確定処理（FE-R13-004）も
    /// 同じ対称範囲で適用する。
    private func writeMovementAmount(_ value: Double) {
        guard let animation = descriptor.animationValue,
              animation.animationType == .movementAmount else { return }
        let radius = max(abs(animation.minValue), abs(animation.maxValue))
        let clampRange = (-radius)...radius
        var value = value
        if let spec = descriptor.sliderSpec {
            value = AnimationSliderScale.fixedValue(
                value, delta: spec.delta,
                minimum: clampRange.lowerBound, maximum: clampRange.upperBound)
        }
        descriptor.setAnimationValue(value, atValueIndex: 1, clampRange: clampRange)
    }

    private func commitMovementAmount() {
        guard let animation = descriptor.animationValue,
              animation.animationType == .movementAmount else { return }
        // 未編集なら書き戻さない（FE-R1-019 と同じ趣旨）。
        guard movementText != movementUneditedText else { return }
        guard let value = Double(movementText), value.isFinite else {
            movementText = formatValue(movementValue)
            movementUneditedText = movementText
            return
        }
        writeMovementAmount(value)
        movementText = formatValue(movementValue)
        movementUneditedText = movementText
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

// MARK: - ファイル参照

/// ファイル参照の行（FE-R1-043）。パスの表示・直接入力と、
/// ファイル選択ダイアログを開く参照ボタンを持つ。
///
/// 確定した変更は、まず `onFilePathChanged` で呼び出し側へ通知し、
/// それから記述子へ書き込む（呼び出し側が変更前のパスや素材長を
/// 捕捉できるようにするため）。メディア情報の取得と長さの調整は
/// 呼び出し側が非同期に行う（この行はファイルを開かない）。
/// 未編集のまま確定した場合は通知しない（FE-R1-019 と同じ趣旨）。
struct FilePathRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    var onFilePathChanged: ((PropertyDescriptor, String) -> Void)?
    @State private var text: String
    @State private var uneditedPath: String
    @FocusState private var isFocused: Bool

    init(
        descriptor: PropertyDescriptor,
        onEdited: @escaping () -> Void,
        onFilePathChanged: ((PropertyDescriptor, String) -> Void)?
    ) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        self.onFilePathChanged = onFilePathChanged
        let initial = descriptor.stringValue ?? ""
        _text = State(initialValue: initial)
        _uneditedPath = State(initialValue: initial)
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
            Button("参照…") { browse() }
        }
    }

    private func commit() {
        applyChange(text)
    }

    private func applyChange(_ newPath: String) {
        guard newPath != uneditedPath else { return }
        text = newPath
        onFilePathChanged?(descriptor, newPath)
        descriptor.setStringValue(newPath)
        uneditedPath = newPath
        onEdited()
    }

    /// 参照ダイアログ。対象種別で絞り込み、現在のパスが絶対パスなら
    /// そのフォルダを初期位置にする。選択したパスはダイアログが
    /// 返した文字列のまま保持する（相対化はしない）。
    private func browse() {
        guard let spec = descriptor.filePathSpec else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let types = MediaFileInfoFetcher.contentTypes(for: spec.group)
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
        if text.hasPrefix("/") {
            panel.directoryURL = URL(fileURLWithPath: text)
                .deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyChange(url.path)
    }
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

