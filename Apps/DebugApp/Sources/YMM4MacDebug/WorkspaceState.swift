import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YMM4Core

/// ワークスペース（開いているプロジェクト）の共有状態。
/// メニューコマンド（App の .commands）からも操作できるよう、
/// プロジェクトの保持と読み込み・保存を ContentView から分離した。
@MainActor
final class WorkspaceState: ObservableObject {
    @Published var project: Project
    @Published var diagnostics: YmmpLoadDiagnostics
    /// 読み込み元ファイル。未保存の新規プロジェクトでは nil。
    @Published var sourceURL: URL?
    /// 読み込みのたびに増える通し番号。ProjectView の識別子に使い、
    /// ファイルを開くたびに表示側の状態（プレビュー等）を破棄して
    /// 作り直すために使う（同じファイルの開き直しでも再読込になる）。
    @Published var loadSequence = 0
    @Published var loadError: String?
    /// ファイルを開くダイアログの表示要求（メニューからも出す）。
    @Published var isImporterPresented = false
    /// バージョン情報ダイアログの表示要求（ヘルプメニュー）。
    @Published var isAboutPresented = false
    /// 「動画の設定」ダイアログの表示要求（ファイルメニュー）。
    /// 実際のシート表示は ProjectView 側が担う。
    @Published var isVideoSettingsPresented = false
    /// 「動画出力」ダイアログの表示要求（ファイルメニュー）。
    @Published var isExportPresented = false
    /// メニュー経由の保存結果などの一時メッセージ。
    @Published var statusMessage: String?

    init() {
        project = Self.makeNewProject()
        diagnostics = YmmpLoadDiagnostics()
    }

    /// 起動時・「新規プロジェクト」で使う空プロジェクト。
    /// 既定の映像情報は本人の指定どおり 1920×1080 / 60 FPS / 48,000 Hz。
    static func makeNewProject() -> Project {
        let project = Project()
        let timeline = Timeline()
        timeline.videoInfo = VideoInfo(fps: 60, hz: 48_000, width: 1920, height: 1080)
        project.timelines = [timeline]
        return project
    }

    func newProject() {
        project = Self.makeNewProject()
        diagnostics = YmmpLoadDiagnostics()
        sourceURL = nil
        loadSequence += 1
        loadError = nil
        statusMessage = nil
    }

    func load(url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let (loaded, loadedDiagnostics) = try YmmpCodec.load(fromFile: url.path)
            project = loaded
            diagnostics = loadedDiagnostics
            sourceURL = url
            loadSequence += 1
            loadError = nil
            statusMessage = nil
        } catch {
            loadError = "読み込みに失敗: \(error)"
        }
    }

    /// プロジェクトのコピーを .ymmp として保存する（メニューの保存）。
    /// 保存先は常にダイアログで聞く（元ファイルへの上書きはしない）。
    func saveCopy() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ymmp") ?? .data]
        panel.nameFieldStringValue =
            (sourceURL?.deletingPathExtension().lastPathComponent ?? "新規プロジェクト") + ".ymmp"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try YmmpCodec.save(project, toFile: url.path)
            statusMessage = "保存しました: \(url.path)"
            loadError = nil
        } catch {
            loadError = "保存に失敗: \(error)"
        }
    }
}
