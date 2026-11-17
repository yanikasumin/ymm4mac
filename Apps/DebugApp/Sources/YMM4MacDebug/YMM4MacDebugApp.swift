import SwiftUI

@main
struct YMM4MacDebugApp: App {
    @StateObject private var workspace = WorkspaceState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workspace)
        }
        // ウィンドウの大きさはシーン側で標準の流儀で指定する。
        // 既定サイズで大きく開き、内容の最小サイズまでは自由に
        // リサイズできる（.contentMinSize）。内容側の .frame で
        // ideal サイズを固定すると、自動判定でウィンドウが
        // リサイズ不可になる場合があるため、そちらでは持たない。
        .defaultSize(width: 1600, height: 1000)
        .windowResizability(.contentMinSize)
        .commands {
            // ファイルメニュー（本家 MainView.xaml の構成 —
            // UI-LAYOUT-FACTS.md §14）。新規/開く/保存は実動し、
            // それ以外は形のみで未接続（台帳: UI-FRONTEND-DIFF.md）。
            CommandGroup(replacing: .newItem) {
                Button("新規プロジェクト") { workspace.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("開く…") { workspace.isImporterPresented = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Menu("アイテムを追加") {
                    Button("テキスト") {}
                    Button("画像") {}
                    Button("動画") {}
                    Button("音声") {}
                    Button("ボイス") {}
                    Button("図形") {}
                    Button("シーン") {}
                    Button("フレームバッファ") {}
                    Button("エフェクト") {}
                    Button("グループ") {}
                    Button("トランジション") {}
                }
                Menu("テンプレートからアイテムを追加") {
                    Button("テンプレートを選択…") {}
                }
                Menu("最近使ったファイル") {
                    Text("（履歴なし）")
                }
                Menu("インポート") {
                    Button("プロジェクトをインポート…") {}
                }
                Button("バックアップからプロジェクトを復元…") {}
                Divider()
                Button("動画の設定…") { workspace.isVideoSettingsPresented = true }
                Button("動画出力…") { workspace.isExportPresented = true }
                Button("Exo出力…") {}
                Button("サムネイル画像を出力…") {}
                Divider()
                Button("プロジェクトのコピーを保存…") { workspace.saveCopy() }
                    .keyboardShortcut("s", modifiers: .command)
            }

            // 編集メニュー（本家のサブメニュー構成をシステムの
            // 編集メニューへ差し込む）。
            CommandGroup(after: .undoRedo) {
                Divider()
                Button("現在位置で分割") {}
                    .keyboardShortcut("b", modifiers: .command)
                Menu("プレビュー操作") {
                    Menu("コントロールポイント表示") {
                        Button("選択中のアイテムのみ") {}
                        Button("プレビューにマウスオーバー時") {}
                        Button("常に表示しない") {}
                    }
                }
                Menu("アイテム操作") {
                    Menu("整列") {
                        Button("左揃え") {}
                        Button("中央揃え") {}
                        Button("右揃え") {}
                    }
                    Button("既定値に設定") {}
                }
                Menu("ボイス操作") {
                    Button("ボイスを再生成") {}
                }
                Menu("タイムライン操作") {
                    Button("レイヤーの高さを拡大") {}
                    Button("レイヤーの高さを縮小") {}
                }
            }

            // レイアウトメニュー。
            CommandMenu("レイアウト") {
                Menu("レイアウトプリセット") {
                    Button("現在のレイアウトを保存…") {}
                    Button("既定のレイアウトに戻す") {}
                }
                Menu("ツール") {
                    Button("アイテム編集") {}
                    Button("プレビュー") {}
                }
                Divider()
                Button("シーインタブを常に表示") {}
            }

            // ツールメニュー（本家同梱ツールの並び）。
            CommandMenu("ツール") {
                Button("キャラクター編集") {}
                Button("設定") {}
                Button("検索") {}
                Button("素材一覧") {}
                Button("台本編集") {}
                Button("文字起こし") {}
                Button("テンプレート編集") {}
                Button("ユーザー辞書") {}
                Button("音量アナライザ") {}
            }

            // ヘルプメニュー。
            CommandGroup(after: .help) {
                Button("FAQ") {}
                Button("問い合わせ") {}
                Divider()
                Button("バージョン情報") { workspace.isAboutPresented = true }
            }
        }
    }
}
