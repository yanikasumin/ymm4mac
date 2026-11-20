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
    ///
    /// 再入の防御（FE-R28-129-01）: 既に自分が所有している場合は、
    /// 所有を維持したまま何もしない。無条件に開き直すと、記録側は
    /// 有効なセッションがあるため新しい開始を拒否し、状態だけが
    /// `.refused` へ上書きされて所有トークンを失う。記録側には
    /// 未確定セッションが残り続け、後続の編集や Undo/Redo が
    /// 拒否され続ける。ドラッグ所有中に別経路の確定処理が開始を
    /// 試みる場合（再生速度行のテキスト確定）と、終了通知の
    /// 取りこぼし後に次のドラッグが始まる場合の双方を、この
    /// 1か所で断つ（全行・プレビュードラッグ共通の土台）。
    mutating func begin(using recorder: EditRecorder?) {
        if case .owning = self { return }
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
    /// 再生速度の編集セッション開始時の基点捕捉（FE-R15-004 /
    /// FE-R27-129-03）。セッションの開始が受理された直後、最初の
    /// 書き込みより前に呼ばれ、呼び出し側が Core の基点を返す。
    /// 再生速度の記述子でのみ使う。
    var onPlaybackRateSessionBegan: ((PropertyDescriptor) -> PlaybackRateEditBaseline?)?
    /// 再生速度の編集セッション終了直前の通知（FE-R27-129-01）。
    /// セッションを確定する前に呼ばれ、呼び出し側が編集終了時
    /// 調整を実行して、その変更を同じセッションへ記録する。
    var onPlaybackRateSessionEnding: ((PropertyDescriptor, PlaybackRateEditBaseline, EditSessionToken?) -> Void)?
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
    /// 第2値のスライダのドラッグについての Undo セッションの状態。
    /// 第1値の `sliderSession` とは独立に開閉し、1ドラッグを履歴
    /// 1エントリへまとめる（FE-R25-128-01）。
    @State private var movementSliderSession: EditDragSession = .idle
    /// 再生速度の編集セッションの基点（FE-R27-129-03）。セッション
    /// 開始時に捕捉し、この行が保持する。寿命はセッションと一致
    /// し（開始時に捕捉、終了時に消費して破棄）、選択変更で行が
    /// 破棄されても後続のセッションへ持ち越されない。
    @State private var playbackRateBaseline: PlaybackRateEditBaseline?

    init(
        descriptor: PropertyDescriptor, animationContext: AnimationEvaluationContext,
        onEdited: @escaping () -> Void,
        editRecorder: EditRecorder? = nil, editTarget: EditTargetKey? = nil,
        onPlaybackRateSessionBegan: ((PropertyDescriptor) -> PlaybackRateEditBaseline?)? = nil,
        onPlaybackRateSessionEnding: ((PropertyDescriptor, PlaybackRateEditBaseline, EditSessionToken?) -> Void)? = nil
    ) {
        self.descriptor = descriptor
        self.animationContext = animationContext
        self.onEdited = onEdited
        self.editRecorder = editRecorder
        self.editTarget = editTarget
        self.onPlaybackRateSessionBegan = onPlaybackRateSessionBegan
        self.onPlaybackRateSessionEnding = onPlaybackRateSessionEnding
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
        // 種別が移動量指定へ変わった時点で第2値の入力欄を現在の
        // モデル値へ同期する（FE-R25-128-02）。`movementText` は
        // ビュー生成時に読み取り側の代用値（例: 定数 50 の先頭値）
        // を取り込んで初期化されるため、種別切替で第2値の行が
        // 出現しても、行側の .onChange(of: movementValue) は初回
        // 表示では発火せず、古い代用値（50）がモデルの第2値（0）
        // と食い違ったまま残り得た。基線（uneditedText）も一緒に
        // 同期し、未編集のままの確定で古い値が書き戻されることも
        // 防ぐ（FE バッチ1の数値欄の基線規則と同趣旨）。入力中は
        // 未確定の文字列を破棄しない。
        .onChange(of: descriptor.animationValue?.animationType) { _, newType in
            if newType == .movementAmount, !isMovementFocused {
                movementText = formatValue(movementValue)
                movementUneditedText = movementText
            }
        }
        // 行が破棄されたら、進行中の再生速度セッションは「編集
        // セッションの終了」として確定する（FE-R27-129-03。本家の
        // 編集画面を閉じる際の EndEdit に相当し、基点が後続の
        // セッションへ残らない）。プロジェクト切替でセッションが
        // 既に破棄（巻き戻し）されている場合は、終了通知側が
        // トークンの失効を検出して調整を行わず、こちらの確定も
        // 空振りになる（FE-R16-002 と同じ多層防御）。
        .onDisappear {
            if isPlaybackRate, case .owning = sliderSession {
                finishPlaybackRateSessionIfNeeded()
                sliderSession.endCommitting(to: editRecorder)
            }
        }
    }

    /// 再生速度の記述子か。編集終了時調整（FE-R15-004）の接続は
    /// この記述子に限る（基点捕捉の対象限定は従来どおり）。
    private var isPlaybackRate: Bool { descriptor.id == "PlaybackRate2" }

    /// 再生速度のセッション開始直後の基点捕捉。開始が受理された
    /// 場合（自分が所有するセッションが開けた、または記録先が
    /// 無い構成）だけ捕捉し、開始を拒否された編集では捕捉しない
    /// （監査 Round 27 §6: 拒否された編集が基点を捕捉しては
    /// ならない）。
    private func capturePlaybackRateBaselineIfSessionAccepted() {
        guard isPlaybackRate, playbackRateBaseline == nil,
              let onPlaybackRateSessionBegan else { return }
        guard sliderSession.token != nil || editRecorder == nil else { return }
        playbackRateBaseline = onPlaybackRateSessionBegan(descriptor)
    }

    /// 再生速度のセッション終了直前の編集終了時調整。基点があれば
    /// 呼び出し側へ渡して消費し、セッションの確定は呼び出し側
    /// （ドラッグ終了・テキスト確定・行の破棄）がこの直後に行う。
    /// 調整とその記録が速度の変更と同じ履歴エントリへ入るのは
    /// この順序による（FE-R27-129-01）。
    private func finishPlaybackRateSessionIfNeeded() {
        guard isPlaybackRate, let baseline = playbackRateBaseline
        else { return }
        playbackRateBaseline = nil
        onPlaybackRateSessionEnding?(
            descriptor, baseline, sliderSession.token)
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
    /// 再生速度の行では、開始直後に基点を捕捉し、終了時は確定の
    /// 直前に編集終了時調整を差し挟む（FE-R27-129-01 / 03）。
    private func sliderEditingChanged(_ editing: Bool) {
        if editing {
            sliderSession.begin(using: editRecorder)
            capturePlaybackRateBaselineIfSessionAccepted()
        } else {
            finishPlaybackRateSessionIfNeeded()
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
        // 拒否される）。再生速度の行だけは、書き込みと編集終了時
        // 調整を1つのセッションへまとめる専用経路を通る
        // （FE-R27-129-01）。
        if isPlaybackRate {
            commitPlaybackRateText(value)
        } else {
            writeValue(
                value, segment: focusedSegment ?? editingSegment,
                sessionToken: nil)
        }
        text = formatValue(editTargetValue)
        uneditedText = text
        onEdited()
    }

    /// 再生速度のテキスト確定（FE-R27-129-01）。値の書き込みと
    /// 編集終了時調整が別々の履歴エントリへ分かれないよう、
    /// 開始→基点捕捉→書き込み→終了時調整→確定を1つのセッション
    /// として同期的に完結させる。開始が拒否された場合は書き込み
    /// 自体を行わない（離散編集の入口拒否と同じで、モデルも
    /// 基点も変わらない。監査 Round 27 の受け入れ試験 4）。
    ///
    /// スライダとセッションを共有するため、確定が届いた時点の
    /// 状態で経路が分かれる（FE-R28-129-01。スライダ操作中に
    /// TextField のフォーカス喪失で確定が届く順序がある）:
    /// - 所有中: そのセッションへ書き込みを統合する（統合方式）。
    ///   新しいセッションは開かず、終了時調整と確定はドラッグ
    ///   終了時に一度だけ行われる。基点はドラッグ開始時点で
    ///   捕捉済みであり、ここでは捕捉し直さない。無条件に開始を
    ///   試みると記録側に拒否されて所有トークンを失うため、
    ///   この分岐が本件の処分の中核である。
    /// - 開始拒否のドラッグが進行中: テキスト確定を拒否し、
    ///   所有状態には一切触らない。ドラッグは終了まで書き込み
    ///   禁止のままとなり、終了時に状態が戻る（FE-R21-126-01）。
    ///   表示は呼び出し側（`commit`）が現在値へ戻す。
    /// - 開始前: 従来どおり同期セッションで完結させる。
    private func commitPlaybackRateText(_ value: Double) {
        if case .owning(let token) = sliderSession {
            writeValue(
                value, segment: focusedSegment ?? editingSegment,
                sessionToken: token)
            return
        }
        if case .refused = sliderSession {
            return
        }
        sliderSession.begin(using: editRecorder)
        guard sliderSession.writeAllowed(recorder: editRecorder) else {
            // 開始拒否: 記録側にセッションは開かれていないため、
            // 状態だけを開始前へ戻す（endCancelling は所有中の
            // 場合にだけ作用する）。
            sliderSession.endCancelling(to: editRecorder)
            return
        }
        capturePlaybackRateBaselineIfSessionAccepted()
        writeValue(
            value, segment: focusedSegment ?? editingSegment,
            sessionToken: sliderSession.token)
        finishPlaybackRateSessionIfNeeded()
        sliderSession.endCommitting(to: editRecorder)
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
                        in: range.min...range.max,
                        onEditingChanged: movementSliderEditingChanged
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
                // 開始拒否されたドラッグの継続書き込みは、他の
                // セッションが終わっても許可されない（第1値と
                // 同じ規則。FE-R21-126-01）。
                guard movementSliderSession.writeAllowed(recorder: editRecorder)
                else { return }
                writeMovementAmount(
                    newValue, sessionToken: movementSliderSession.token)
                movementText = formatValue(movementValue)
                movementUneditedText = movementText
                onEdited()
            }
        )
    }

    /// 第2値のスライダのドラッグ開始・終了で Undo セッションを
    /// 開閉し、ドラッグ全体を履歴1エントリへまとめる。第1値の
    /// セッションとは独立である（FE-R25-128-01）。
    private func movementSliderEditingChanged(_ editing: Bool) {
        if editing {
            movementSliderSession.begin(using: editRecorder)
        } else {
            movementSliderSession.endCommitting(to: editRecorder)
        }
    }

    /// 第2値の書き込みと Undo 記録。クランプ範囲は本家の第2値の
    /// スライダの Min/Max（絶対制限の対称範囲 ±最大絶対値）であり、
    /// 定義範囲 [minValue, maxValue] ではクランプしない（定義範囲が
    /// 0..100 の項目でも移動量は負値を取りうる）。確定処理
    /// （FE-R13-004）も同じ対称範囲で適用する。
    /// 書き込みは第1値と同じく入口で記録可否を確認し、記録できる
    /// 場合だけモデルを変更してから記録する（FE-R25-128-01）。
    private func writeMovementAmount(_ value: Double, sessionToken: EditSessionToken?) {
        guard let animation = descriptor.animationValue,
              animation.animationType == .movementAmount else { return }
        guard editWriteAllowed(recorder: editRecorder, sessionToken: sessionToken)
        else { return }
        let oldState = animation.recordedState
        let radius = max(abs(animation.minValue), abs(animation.maxValue))
        let clampRange = (-radius)...radius
        var value = value
        if let spec = descriptor.sliderSpec {
            value = AnimationSliderScale.fixedValue(
                value, delta: spec.delta,
                minimum: clampRange.lowerBound, maximum: clampRange.upperBound)
        }
        descriptor.setAnimationValue(value, atValueIndex: 1, clampRange: clampRange)
        recordMovementChange(oldState: oldState, sessionToken: sessionToken)
    }

    /// 第2値の変更を Undo へ登録する。記録は変更前後の状態
    /// （種別＋値列、`Animation.RecordedState`）を一体で保持し、
    /// 適用は `restoreAnimationRecordedState` でそのまま書き戻す。
    /// 値列全体を一体で記録するのは、短い値列の実体化（値列の
    /// 個数の変化）まで含めて復元するためであり、第2値だけの
    /// 記録では実体化前の個数へ戻せない（FE-R25-128-01。考え方は
    /// 種別変更の記録 FE-R23-127-01 と同じ）。対象キーは第1値
    /// （#const / #first / #seg<n>）と種別変更（#type）から
    /// 区別する。
    private func recordMovementChange(
        oldState: YMM4Core.Animation.RecordedState,
        sessionToken: EditSessionToken?
    ) {
        guard let editRecorder, let editTarget else { return }
        let newState = descriptor.animationValue?.recordedState
        recordDescriptorValueChange(
            recorder: editRecorder,
            target: EditTargetKey(
                object: editTarget.object, key: editTarget.key + "#movement"),
            oldValue: oldState, newValue: newState,
            apply: { descriptor.restoreAnimationRecordedState($0) },
            sessionToken: sessionToken)
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
        // テキスト確定は離散編集であり、Undo セッションのトークンは
        // 持たない（第1値の commit と同じ。他人のセッションが有効
        // なら writeMovementAmount の入口で拒否される）。
        writeMovementAmount(value, sessionToken: nil)
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
/// 記述子への書き込みが成立したら `onFilePathCommitted` で知らせる。
/// 未保存の記録はこの書き込み成立時点に置く（FE-R33-131-01）。
/// パス自体はファイルの存在と無関係にモデルへ書かれるため、
/// 情報取得の成否で記録すると、存在しないパスへの変更が
/// 未保存にならずに失われる。
struct FilePathRowView: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    var onFilePathChanged: ((PropertyDescriptor, String) -> Void)?
    /// 記述子へのパスの書き込みが成立した時点の通知（未保存の
    /// 記録用）。値が変わった確定でのみ、書き込みの直後に呼ばれる。
    var onFilePathCommitted: (() -> Void)?
    @State private var text: String
    @State private var uneditedPath: String
    @FocusState private var isFocused: Bool

    init(
        descriptor: PropertyDescriptor,
        onEdited: @escaping () -> Void,
        onFilePathChanged: ((PropertyDescriptor, String) -> Void)?,
        onFilePathCommitted: (() -> Void)? = nil
    ) {
        self.descriptor = descriptor
        self.onEdited = onEdited
        self.onFilePathChanged = onFilePathChanged
        self.onFilePathCommitted = onFilePathCommitted
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
        if descriptor.setStringValue(newPath) {
            // 書き込みが成立した時点で未保存として記録する
            // （FE-R33-131-01）。素材長の非同期調整の成否とは
            // 責務を分ける（あちらは記録に関与しない）。
            onFilePathCommitted?()
        }
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

