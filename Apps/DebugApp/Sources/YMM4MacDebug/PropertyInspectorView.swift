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
    /// ファイル参照の値が確定したときの通知（記述子と新しいパス）。
    /// 情報取得と長さ調整は呼び出し側（編集操作層への橋渡し）が行う。
    var onFilePathChanged: ((PropertyDescriptor, String) -> Void)?
    /// ファイル参照の記述子への書き込みが成立した時点の通知
    /// （FE-R33-131-01。未保存の記録用で、情報取得の成否とは別）。
    var onFilePathCommitted: (() -> Void)?
    /// Undo 記録の集約点（FE-UNDO-WIRING）。nil の場合は無記録
    /// （エフェクト編集など未移行の経路）。
    var editRecorder: EditRecorder? = nil
    /// 記述子の所有者（対象キー `EditTargetKey` の同一性側）。
    /// 複合の子記述子では最上位の所有者を保ち、キー文字列側に
    /// 経路（親記述子 ID とコレクション位置）を積んで区別する。
    var editTargetOwner: AnyObject? = nil
    /// 再生速度の編集セッション開始時の基点捕捉（FE-R15-004 /
    /// FE-R27-129-03）。行がセッションの開始を受理した直後、最初
    /// の書き込みより前に呼ばれ、呼び出し側が Core の基点を返す。
    /// 基点の所有は行のセッション状態へ移る。
    var onPlaybackRateSessionBegan: ((PropertyDescriptor) -> PlaybackRateEditBaseline?)?
    /// 再生速度の編集セッション終了直前の通知（FE-R27-129-01）。
    /// 行がセッションを確定する前に呼ばれ、呼び出し側が編集
    /// 終了時調整を実行して、その変更（長さ・オフセット）を
    /// 同じセッションへ記録する。
    var onPlaybackRateSessionEnding: ((PropertyDescriptor, PlaybackRateEditBaseline, EditSessionToken?) -> Void)?

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
                            onEdited: onEdited,
                            onFilePathChanged: onFilePathChanged,
                            onFilePathCommitted: onFilePathCommitted,
                            editRecorder: editRecorder,
                            editTargetOwner: editTargetOwner,
                            editTargetKeyPath: "",
                            onPlaybackRateSessionBegan: onPlaybackRateSessionBegan,
                            onPlaybackRateSessionEnding: onPlaybackRateSessionEnding
                        )
                    }
                }
            }
        }
    }
}

/// 記述子1件分の編集行。種類ごとに部品を切り替える。
/// 複合オブジェクト／コレクションは見出し＋子行の縦並びにし、
/// 子行はこの行自身を再帰利用する。
private struct PropertyRowView: View {
    let descriptor: PropertyDescriptor
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void
    var onFilePathChanged: ((PropertyDescriptor, String) -> Void)?
    var onFilePathCommitted: (() -> Void)?
    var editRecorder: EditRecorder? = nil
    var editTargetOwner: AnyObject? = nil
    /// 対象キーの経路部分（複合の親記述子 ID を積んだもの）。
    var editTargetKeyPath: String = ""
    var onPlaybackRateSessionBegan: ((PropertyDescriptor) -> PlaybackRateEditBaseline?)?
    var onPlaybackRateSessionEnding: ((PropertyDescriptor, PlaybackRateEditBaseline, EditSessionToken?) -> Void)?

    /// この行の値変更の対象キー。記録先が無い場合は nil。
    private var editTarget: EditTargetKey? {
        guard editRecorder != nil, let editTargetOwner else { return nil }
        return EditTargetKey(
            editTargetOwner, key: editTargetKeyPath + descriptor.id)
    }

    @ViewBuilder
    var body: some View {
        switch descriptor.access {
        case .object:
            ObjectRowView(
                descriptor: descriptor,
                animationContext: animationContext,
                onEdited: onEdited,
                onFilePathChanged: onFilePathChanged,
                onFilePathCommitted: onFilePathCommitted,
                editRecorder: editRecorder,
                editTargetOwner: editTargetOwner,
                editTargetKeyPath: editTargetKeyPath,
                onPlaybackRateSessionBegan: onPlaybackRateSessionBegan,
                onPlaybackRateSessionEnding: onPlaybackRateSessionEnding
            )
        case .collection:
            CollectionRowView(
                descriptor: descriptor,
                animationContext: animationContext,
                onEdited: onEdited,
                onFilePathChanged: onFilePathChanged,
                onFilePathCommitted: onFilePathCommitted,
                editRecorder: editRecorder,
                editTargetOwner: editTargetOwner,
                editTargetKeyPath: editTargetKeyPath,
                onPlaybackRateSessionBegan: onPlaybackRateSessionBegan,
                onPlaybackRateSessionEnding: onPlaybackRateSessionEnding
            )
        default:
            HStack(alignment: .center, spacing: 8) {
                Text(descriptor.displayName)
                    .font(.callout)
                    .frame(width: 110, alignment: .leading)
                    .lineLimit(1)
                editor
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch descriptor.access {
        case .number:
            NumberRowView(
                descriptor: descriptor, onEdited: onEdited,
                editRecorder: editRecorder, editTarget: editTarget)
        case .integer:
            IntegerRowView(
                descriptor: descriptor, onEdited: onEdited,
                editRecorder: editRecorder, editTarget: editTarget)
        case .boolean:
            Toggle("", isOn: Binding(
                get: { descriptor.boolValue ?? false },
                set: { newValue in
                    // 他人のセッションが有効な間は離散編集を行わない
                    // （FE-R20-126-03。入口で拒否し、モデルを変更しない）。
                    if let editRecorder, !editRecorder.canRecordValueChange() {
                        return
                    }
                    let old = descriptor.boolValue
                    descriptor.setBoolValue(newValue)
                    if let old, let editRecorder, let editTarget {
                        editRecorder.recordValueChange(
                            target: editTarget,
                            oldValue: old, newValue: newValue,
                            apply: { descriptor.setBoolValue($0) })
                    }
                    onEdited()
                }
            ))
            .labelsHidden()
        case .text:
            if case .text(let multiline) = descriptor.kind, multiline {
                MultilineTextRowView(
                    descriptor: descriptor, onEdited: onEdited,
                    editRecorder: editRecorder, editTarget: editTarget)
            } else {
                TextRowView(
                    descriptor: descriptor, onEdited: onEdited,
                    editRecorder: editRecorder, editTarget: editTarget)
            }
        case .filePath:
            // ファイル参照は記録対象外（パスの書き換えに伴う長さ調整
            // が非同期で対にならず、パスだけ戻すと不整合になるため。
            // FE-UNDO-WIRING の未移行経路として実装ログに明記）。
            FilePathRowView(
                descriptor: descriptor,
                onEdited: onEdited,
                onFilePathChanged: onFilePathChanged,
                onFilePathCommitted: onFilePathCommitted
            )
        case .enumeration:
            EnumRowView(
                descriptor: descriptor, onEdited: onEdited,
                editRecorder: editRecorder, editTarget: editTarget)
        case .color:
            // 色は連続変化の境界信号が無く、確定単位を切れないため
            // 記録対象外（未移行経路として実装ログに明記）。
            ColorPicker("", selection: Binding(
                get: { swiftUIColor(from: descriptor.colorValue ?? .white) },
                set: { descriptor.setColorValue(coreColor(from: $0)); onEdited() }
            ), supportsOpacity: true)
            .labelsHidden()
        case .animation:
            AnimationRowView(
                descriptor: descriptor, animationContext: animationContext,
                onEdited: onEdited,
                editRecorder: editRecorder, editTarget: editTarget,
                onPlaybackRateSessionBegan: onPlaybackRateSessionBegan,
                onPlaybackRateSessionEnding: onPlaybackRateSessionEnding
            )
        case .object, .collection:
            // body 側で専用レイアウトへ振り分けるため、ここには来ない。
            EmptyView()
        }
    }
}

/// 複合オブジェクトの行。表示名を見出しにし、子行をインデントして並べる。
private struct ObjectRowView: View {
    let descriptor: PropertyDescriptor
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void
    var onFilePathChanged: ((PropertyDescriptor, String) -> Void)?
    var onFilePathCommitted: (() -> Void)?
    var editRecorder: EditRecorder? = nil
    var editTargetOwner: AnyObject? = nil
    var editTargetKeyPath: String = ""
    var onPlaybackRateSessionBegan: ((PropertyDescriptor) -> PlaybackRateEditBaseline?)?
    var onPlaybackRateSessionEnding: ((PropertyDescriptor, PlaybackRateEditBaseline, EditSessionToken?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(descriptor.displayName)
                .font(.callout)
                .bold()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(descriptor.children ?? [], id: \.id) { child in
                    PropertyRowView(
                        descriptor: child,
                        animationContext: animationContext,
                        onEdited: onEdited,
                        onFilePathChanged: onFilePathChanged,
                        onFilePathCommitted: onFilePathCommitted,
                        editRecorder: editRecorder,
                        editTargetOwner: editTargetOwner,
                        editTargetKeyPath: editTargetKeyPath + descriptor.id + "/",
                        onPlaybackRateSessionBegan: onPlaybackRateSessionBegan,
                        onPlaybackRateSessionEnding: onPlaybackRateSessionEnding
                    )
                }
            }
            .padding(.leading, 14)
        }
    }
}

/// 複合コレクションの行。要素ごとに子行をまとめ、要素の追加・削除の
/// ボタンを付ける。追加・削除は構造の変更なので、この行の再描画を
/// ローカルの世代カウンタでも促す（親の再生成と二重に効く）。
/// 状態が実際に変わらなかった操作（要素数の上限・下限で丸め込まれた
/// 場合）では再描画も編集通知もしない（R22-117-01）。
private struct CollectionRowView: View {
    let descriptor: PropertyDescriptor
    let animationContext: AnimationEvaluationContext
    var onEdited: () -> Void
    var onFilePathChanged: ((PropertyDescriptor, String) -> Void)?
    var onFilePathCommitted: (() -> Void)?
    var editRecorder: EditRecorder? = nil
    var editTargetOwner: AnyObject? = nil
    var editTargetKeyPath: String = ""
    var onPlaybackRateSessionBegan: ((PropertyDescriptor) -> PlaybackRateEditBaseline?)?
    var onPlaybackRateSessionEnding: ((PropertyDescriptor, PlaybackRateEditBaseline, EditSessionToken?) -> Void)?
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(descriptor.displayName)
                    .font(.callout)
                    .bold()
                Spacer()
                Button("追加") {
                    if descriptor.insertCollectionElement() {
                        revision += 1
                        onEdited()
                    }
                }
            }
            ForEach(0..<(descriptor.collectionCount ?? 0), id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("削除") {
                            if descriptor.removeCollectionElement(at: index) {
                                revision += 1
                                onEdited()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(descriptor.collectionElements(at: index) ?? [], id: \.id) { child in
                            PropertyRowView(
                                descriptor: child,
                                animationContext: animationContext,
                                onEdited: onEdited,
                                onFilePathChanged: onFilePathChanged,
                                onFilePathCommitted: onFilePathCommitted,
                                editRecorder: editRecorder,
                                editTargetOwner: editTargetOwner,
                                editTargetKeyPath:
                                    editTargetKeyPath + descriptor.id + "[\(index)]/",
                                onPlaybackRateSessionBegan: onPlaybackRateSessionBegan,
                                onPlaybackRateSessionEnding: onPlaybackRateSessionEnding
                            )
                        }
                    }
                    .padding(.leading, 14)
                }
            }
        }
        .id(revision)
    }
}

