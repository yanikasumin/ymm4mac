import SwiftUI
import YMM4Core

/// セリフ入力行（本家 TimelineView 下端の帯の再現）。
///
/// 配置の根拠は `analysis-notes/UI-LAYOUT-FACTS.md` §7・§13:
/// 列構成は キャラクター選択（146）／セリフ本文（残り全幅）／
/// 追加ボタン（120、AddVoiceMode の選択を重ねた複合ボタン）。
/// 追加ボタンはセリフが空でないときだけ有効になる。
///
/// 入力とキャラクター選択は実動し、追加は `onAdd` 経由で
/// VoiceItem 生成へ接続される（長さは本家では生成音声から決まるが、
/// 音声供給が未接続の間は呼び出し側が仮置きする。台帳に記録）。
struct SerifInputView: View {
    let characters: [Character]
    /// 追加が確定したときの受け口。
    var onAdd: ((_ characterName: String?, _ serif: String, _ seeksAfterAdd: Bool) -> Void)?

    @State private var characterName: String = ""
    @State private var serif: String = ""
    /// AddVoiceMode の形だけの保持（追加のみ／追加してシーク）。
    @State private var seeksAfterAdd = false

    var body: some View {
        HStack(spacing: 6) {
            characterSlot

            TextField(UIStrings.Serif.placeholder, text: $serif)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitIfPossible() }

            // 追加ボタン（モード選択を重ねた複合ボタンの形）。
            HStack(spacing: 2) {
                Button(UIStrings.Serif.add) { submitIfPossible() }
                    .disabled(serif.isEmpty)
                Menu {
                    Toggle(UIStrings.Serif.addAndSeek, isOn: $seeksAfterAdd)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
                .help(UIStrings.Serif.addMode)
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
                Text(UIStrings.Serif.noCharacters)
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
                .help(UIStrings.Serif.character)
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
            .help(UIStrings.Serif.openCharacterSettings + UIStrings.Common.unconnectedSuffix)
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
