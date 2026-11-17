import SwiftUI
import YMM4Core

/// セリフ入力行（本家 TimelineView 下端の帯の再現）。
///
/// 配置の根拠は `analysis-notes/UI-LAYOUT-FACTS.md` §7・§13:
/// 列構成は キャラクター選択（146）／セリフ本文（残り全幅）／
/// 追加ボタン（120、AddVoiceMode の選択を重ねた複合ボタン）。
/// 追加ボタンはセリフが空でないときだけ有効になる。
///
/// 現段階は「形」のみ: 入力とキャラクター選択は実動するが、
/// 追加ボタンの先（VoiceItem の生成。長さは生成音声から決まる）は
/// 未接続で、`onAdd` の接続は接続フェーズで行う
/// （台帳: analysis-notes/UI-FRONTEND-DIFF.md）。
struct SerifInputView: View {
    let characters: [Character]
    /// 追加が確定したときの受け口（未接続なら nil）。
    var onAdd: ((_ characterName: String?, _ serif: String, _ seeksAfterAdd: Bool) -> Void)?

    @State private var characterName: String = ""
    @State private var serif: String = ""
    /// AddVoiceMode の形だけの保持（追加のみ／追加してシーク）。
    @State private var seeksAfterAdd = false

    var body: some View {
        HStack(spacing: 6) {
            characterSlot

            TextField("ここにセリフを入力", text: $serif)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitIfPossible() }

            // 追加ボタン（モード選択を重ねた複合ボタンの形）。
            HStack(spacing: 2) {
                Button("追加") { submitIfPossible() }
                    .disabled(serif.isEmpty)
                Menu {
                    Toggle("追加してシーク", isOn: $seeksAfterAdd)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
                .help("追加モード")
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .onAppear {
            if characterName.isEmpty {
                characterName = characters.first?.name ?? ""
            }
        }
    }

    @ViewBuilder
    private var characterSlot: some View {
        HStack(spacing: 2) {
            if characters.isEmpty {
                Text("（キャラクター未登録）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Picker("", selection: $characterName) {
                    ForEach(characters, id: \.name) { character in
                        Text(character.name).tag(character.name)
                    }
                }
                .labelsHidden()
                .help("キャラクター")
            }
            Spacer(minLength: 0)
            // キャラクター設定を開くボタン（コンボの隣。本家に実在
            // するが、設定画面は未接続）。
            Button {
            } label: {
                Image(systemName: "person.crop.circle.badge.gearshape")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("キャラクター設定を開く（未接続）")
        }
        .frame(width: 146)
    }

    private func submitIfPossible() {
        guard !serif.isEmpty else { return }
        onAdd?(
            characterName.isEmpty ? nil : characterName,
            serif,
            seeksAfterAdd
        )
    }
}
