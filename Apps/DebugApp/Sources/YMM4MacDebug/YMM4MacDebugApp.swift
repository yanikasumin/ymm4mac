import AppKit
import SwiftUI
import YMM4Core

/// バンドル化されていない実行ファイルとして起動された場合でも、
/// 通常のアプリとして Dock にアイコンが表示されるようにする保険。
/// （実行ファイルを直接起動する形では、macOS が Dock へ登録しない
/// 場合がある。.app バンドルから起動した場合は最初から .regular
/// なので、この指定は無害な再確認になる。）
final class DebugAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // ユーザー辞書を設定ファイルから読み込む（TEXT60 の設定層）。
        UserDictionaryStore.shared.load()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 集約中の辞書保存を終了前に確定する。
        UserDictionaryStore.shared.flushPendingSave()
    }

    /// 終了（ウィンドウを閉じる・⌘Q）前に未保存の変更を確認する
    /// （FE-R1-001。本家の SaveProjectOnCloseWindowCommand 相当）。
    /// キャンセルが選ばれた場合は終了を取り消す。
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let workspace = WorkspaceState.current else {
            return .terminateNow
        }
        let proceed = MainActor.assumeIsolated {
            let proceed = workspace.confirmDiscardUnsavedChanges()
            if proceed {
                // 終了に続けてウィンドウが閉じられる際、閉鎖側の確認が
                // 二重に出ないよう印を立てる（FE-R32-131-02。閉鎖側が
                // 1回だけ消費する）。
                workspace.discardConfirmedForTermination = true
            }
            return proceed
        }
        return proceed ? .terminateNow : .terminateCancel
    }
}

@main
struct YMM4MacDebugApp: App {
    @NSApplicationDelegateAdaptor(DebugAppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // 修飾子は直前のシーンに結び付くため、主ウィンドウの大きさ・
        // メニュー定義は WindowGroup 側に付け、辞書ウィンドウには
        // 専用の大きさだけを付ける（R18-01）。
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
            // UI-FACTS-MENUS-CONTEXT.md §1.1）。編集系アクションは
            // WorkspaceState 経由で ProjectView が実行する。
            // 接続先が無い項目は無効表示にする（理由は台帳）。
            CommandGroup(replacing: .newItem) {
                Button(UIStrings.Menu.newProject) { workspace.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
                Button(UIStrings.Menu.openProject) { workspace.requestOpenProject() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Menu(UIStrings.Menu.addItem) {
                    ForEach(AddItemKind.allCases, id: \.self) { kind in
                        Button(kind.displayName) {
                            workspace.request(.addItem(kind))
                        }
                    }
                }
                Menu(UIStrings.Menu.addItemFromTemplate) {
                    // テンプレートの保持・編集の土台が無いため未接続。
                    Text(UIStrings.Menu.noHistory)
                }
                Menu(UIStrings.Menu.recentFiles) {
                    Text(UIStrings.Menu.noHistory)
                }
                Menu(UIStrings.Menu.importMenu) {
                    Button(UIStrings.Menu.importSubtitle) {}
                        .disabled(true)
                        .help(UIStrings.Menu.importSubtitle + UIStrings.Common.unconnectedSuffix)
                    Button(UIStrings.Menu.importSubtitleAsVoice) {}
                        .disabled(true)
                        .help(UIStrings.Menu.importSubtitleAsVoice + UIStrings.Common.unconnectedSuffix)
                }
                Button(UIStrings.Menu.restoreFromBackup) {}
                    .disabled(true)
                    .help(UIStrings.Menu.restoreFromBackup + UIStrings.Common.unconnectedSuffix)
                Divider()
                Button(UIStrings.Menu.videoSettings) { workspace.isVideoSettingsPresented = true }
                Button(UIStrings.Menu.outputVideo) { workspace.isExportPresented = true }
                Button(UIStrings.Menu.outputExo) {}
                    .disabled(true)
                    .help(UIStrings.Menu.outputExo + UIStrings.Common.unconnectedSuffix)
                Button(UIStrings.Menu.saveThumbnail) {
                    workspace.request(.saveThumbnail(.png))
                }
                Divider()
                Button(UIStrings.Menu.saveProject) { workspace.save() }
                    .keyboardShortcut("s", modifiers: .command)
                Button(UIStrings.Menu.saveProjectAs) { workspace.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // 編集メニュー（本家のサブメニュー構成 —
            // UI-FACTS-MENUS-CONTEXT.md §1.2）。Undo/Redo は標準の
            // UndoManager ではなく Core の EditCoordinator へ接続する
            // （FE-UNDO-WIRING）。実行は ProjectView が担う。
            CommandGroup(replacing: .undoRedo) {
                Button(UIStrings.Toolbar.undo) { workspace.request(.undo) }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!workspace.canPerformUndo)
                Button(UIStrings.Toolbar.redo) { workspace.request(.redo) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!workspace.canPerformRedo)
            }
            CommandGroup(after: .undoRedo) {
                Divider()
                Button(UIStrings.Menu.splitAtCurrentPosition) {
                    workspace.request(.splitAtCurrentPosition)
                }
                .keyboardShortcut("b", modifiers: .command)
                Menu(UIStrings.Menu.previewControl) {
                    Button(UIStrings.Menu.seekToStart) {
                        workspace.request(.seekToStart)
                    }
                    Button(UIStrings.Menu.seekToEnd) {
                        workspace.request(.seekToEnd)
                    }
                    Divider()
                    Menu(UIStrings.Menu.controlPointVisibility) {
                        // 表示モードの保持先は ProjectView 側の状態。
                        // WorkspaceAction 経由で切り替える（トランスポート
                        // 帯のドロップダウンと同じ状態。FE-UNIT5 で接続）。
                        Button(UIStrings.Menu.controlPointOnSelected) {
                            workspace.request(
                                .setControlPointVisibility(.selectedOnly)
                            )
                        }
                        Button(UIStrings.Menu.controlPointOnMouseOver) {
                            workspace.request(
                                .setControlPointVisibility(.onMouseOver)
                            )
                        }
                        Button(UIStrings.Menu.controlPointNever) {
                            workspace.request(
                                .setControlPointVisibility(.never)
                            )
                        }
                    }
                }
                Menu(UIStrings.Menu.itemControl) {
                    Button(UIStrings.Menu.deleteSelection) {
                        workspace.request(.deleteSelection)
                    }
                    Button(UIStrings.Menu.deleteAndMoveAll) {
                        workspace.request(.deleteAndMoveAll)
                    }
                    Divider()
                    Button(UIStrings.Menu.group) {
                        workspace.request(.groupSelection)
                    }
                    Button(UIStrings.Menu.ungroup) {
                        workspace.request(.ungroupSelection)
                    }
                    Divider()
                    Button(UIStrings.Menu.toggleLock) {
                        workspace.request(.toggleLock)
                    }
                    Button(UIStrings.Menu.toggleClipping) {
                        workspace.request(.toggleClipping)
                    }
                    Button(UIStrings.Menu.toggleWaveform) {
                        workspace.request(.toggleWaveform)
                    }
                    Divider()
                    Button(UIStrings.Menu.selectAll) {
                        workspace.request(.selectAll)
                    }
                    Button(UIStrings.Menu.selectLeftItems) {
                        workspace.request(.selectLeftItems)
                    }
                    Button(UIStrings.Menu.selectRightItems) {
                        workspace.request(.selectRightItems)
                    }
                    Divider()
                    Menu(UIStrings.Menu.align) {
                        // 整列の Core 操作が無いため未接続。
                        Button(UIStrings.Menu.alignLeft) {}.disabled(true)
                            .help(UIStrings.Menu.alignLeft + UIStrings.Common.unconnectedSuffix)
                        Button(UIStrings.Menu.alignCenter) {}.disabled(true)
                            .help(UIStrings.Menu.alignCenter + UIStrings.Common.unconnectedSuffix)
                        Button(UIStrings.Menu.alignRight) {}.disabled(true)
                            .help(UIStrings.Menu.alignRight + UIStrings.Common.unconnectedSuffix)
                    }
                    Button(UIStrings.Menu.setToDefault) {}
                        .disabled(true)
                        .help(UIStrings.Menu.setToDefault + UIStrings.Common.unconnectedSuffix)
                }
                Menu(UIStrings.Menu.voiceControl) {
                    // キャラクター切替・ボイスモードはキャラクター編集と
                    // 音声供給（Issue #51）が前提のため未接続。
                    Button(UIStrings.Menu.changeCharacter) {}.disabled(true)
                        .help(UIStrings.Menu.changeCharacter + UIStrings.Common.unconnectedSuffix)
                    Button(UIStrings.Menu.changePreviousCharacter) {}.disabled(true)
                        .help(UIStrings.Menu.changePreviousCharacter + UIStrings.Common.unconnectedSuffix)
                    Button(UIStrings.Menu.changeNextCharacter) {}.disabled(true)
                        .help(UIStrings.Menu.changeNextCharacter + UIStrings.Common.unconnectedSuffix)
                    Button(UIStrings.Menu.changeVoiceMode) {}.disabled(true)
                        .help(UIStrings.Menu.changeVoiceMode + UIStrings.Common.unconnectedSuffix)
                }
                Menu(UIStrings.Menu.timelineControl) {
                    Button(UIStrings.Menu.layerHeightUp) {
                        workspace.request(.layerHeightUp)
                    }
                    Button(UIStrings.Menu.layerHeightDown) {
                        workspace.request(.layerHeightDown)
                    }
                    Button(UIStrings.Menu.zoomInTimeline) {
                        workspace.request(.zoomInTimeline)
                    }
                    Button(UIStrings.Menu.zoomOutTimeline) {
                        workspace.request(.zoomOutTimeline)
                    }
                }
            }

            // レイアウトメニュー。
            CommandMenu(UIStrings.Menu.layout) {
                Menu(UIStrings.Menu.layoutPreset) {
                    Button(UIStrings.Menu.saveLayoutPreset) {}
                        .disabled(true)
                        .help(UIStrings.Menu.saveLayoutPreset + UIStrings.Common.unconnectedSuffix)
                    Button(UIStrings.Menu.resetLayout) {
                        workspace.request(.resetLayout)
                    }
                }
                Menu(UIStrings.Menu.tools) {
                    // ドッキング基盤が無いため表示切替は未接続。
                    Button(UIStrings.Menu.toolItemEditor) {}.disabled(true)
                        .help(UIStrings.Menu.toolItemEditor + UIStrings.Common.unconnectedSuffix)
                    Button(UIStrings.Menu.toolPreview) {}.disabled(true)
                        .help(UIStrings.Menu.toolPreview + UIStrings.Common.unconnectedSuffix)
                }
                Divider()
                Button(UIStrings.Menu.alwaysShowSceneTab) {}
                    .disabled(true)
                    .help(UIStrings.Menu.alwaysShowSceneTab + UIStrings.Common.unconnectedSuffix)
            }

            // ツールメニュー（本家同梱ツールの並び）。各ツールの
            // ウィンドウ／ドッキング基盤が無いため全て未接続。
            CommandMenu(UIStrings.Menu.tools) {
                Button(UIStrings.Menu.characterEditor) {}.disabled(true)
                    .help(UIStrings.Menu.characterEditor + UIStrings.Common.unconnectedSuffix)
                Button(UIStrings.Menu.settingWindow) {}.disabled(true)
                    .help(UIStrings.Menu.settingWindow + UIStrings.Common.unconnectedSuffix)
                Button(UIStrings.Menu.toolSearch) {}.disabled(true)
                    .help(UIStrings.Menu.toolSearch + UIStrings.Common.unconnectedSuffix)
                Button(UIStrings.Menu.toolMaterials) {}.disabled(true)
                    .help(UIStrings.Menu.toolMaterials + UIStrings.Common.unconnectedSuffix)
                Button(UIStrings.Menu.toolScenario) {}.disabled(true)
                    .help(UIStrings.Menu.toolScenario + UIStrings.Common.unconnectedSuffix)
                Button(UIStrings.Menu.toolTranscription) {}.disabled(true)
                    .help(UIStrings.Menu.toolTranscription + UIStrings.Common.unconnectedSuffix)
                Button(UIStrings.Menu.toolTemplateEditor) {}.disabled(true)
                    .help(UIStrings.Menu.toolTemplateEditor + UIStrings.Common.unconnectedSuffix)
                Button(UIStrings.Menu.toolUserDictionary) {
                    openWindow(id: "user-dictionary")
                }
                Button(UIStrings.Menu.toolVolumeAnalyzer) {}.disabled(true)
                    .help(UIStrings.Menu.toolVolumeAnalyzer + UIStrings.Common.unconnectedSuffix)
            }

            // ヘルプメニュー。本家の FAQ／問い合わせ／FANBOX は
            // OpenUri コマンドで公式 URL を開く実動項目。
            CommandGroup(after: .help) {
                Button(UIStrings.Menu.faq) {
                    openURL("https://manjubox.net/ymm4/faq/")
                }
                Button(UIStrings.Menu.contact) {
                    openURL("https://manjubox.net/contact/")
                }
                Button(UIStrings.Menu.fanbox) {
                    openURL("https://www.pixiv.net/fanbox/creator/586643")
                }
                Divider()
                Button(UIStrings.Menu.about) { workspace.isAboutPresented = true }
            }
        }

        // ユーザー辞書の編集ウィンドウ（TEXT60 の辞書設定層）。
        Window(UIStrings.Menu.toolUserDictionary, id: "user-dictionary") {
            UserDictionaryEditorView()
                .environmentObject(workspace)
        }
        .defaultSize(width: 860, height: 520)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
