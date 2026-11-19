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
    /// 「キャラクター編集」シートの表示要求（ツールメニュー）。
    /// 実際のシート表示は ProjectView 側が担う。
    @Published var isCharacterEditorPresented = false
    /// メニュー経由の保存結果などの一時メッセージ。
    @Published var statusMessage: String?
    /// メニュー／ツールバーから ProjectView へ渡す編集アクションの要求。
    /// App の .commands はプロジェクトの編集状態を持たないため、
    /// 要求だけをここに積み、ProjectView が観測して実行する。
    @Published var pendingAction: (action: WorkspaceAction, sequence: Int)?

    /// 編集アクションを ProjectView へ要求する。
    func request(_ action: WorkspaceAction) {
        pendingAction = (action, (pendingAction?.sequence ?? 0) + 1)
    }

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

/// メニューから ProjectView へ渡す編集アクション。
/// ProjectView が現在のタイムライン・選択・再生ヘッドで実行する。
/// 接続先（Core の編集操作等）が無いアクションはここに含めない
/// （メニュー側で無効表示にし、理由は台帳に残す）。
enum WorkspaceAction: Equatable {
    case addItem(AddItemKind)
    case splitAtCurrentPosition
    case deleteSelection
    case deleteAndMoveAll
    case groupSelection
    case ungroupSelection
    case toggleLock
    case toggleClipping
    case toggleWaveform
    case selectAll
    case selectLeftItems
    case selectRightItems
    case seekToStart
    case seekToEnd
    case layerHeightUp
    case layerHeightDown
    case zoomInTimeline
    case zoomOutTimeline
    case saveThumbnail(ThumbnailFormat)
    case resetLayout
    /// ユーザー辞書が編集された（プレビューの再描画が要る）。
    case userDictionaryChanged
}

/// サムネイル保存の形式（本家プロジェクトツールバーの SplitButton
/// ドロップダウン: PNG／透過PNG／JPEG）。
enum ThumbnailFormat: Equatable {
    case png
    case pngAlpha
    case jpeg
}

/// 追加できるアイテム種別（本家の追加13種）。
enum AddItemKind: String, CaseIterable {
    case voice
    case text
    case video
    case audio
    case image
    case shape
    case tachie
    case face
    case effect
    case transition
    case scene
    case frameBuffer
    case group

    /// 表示名（文字列テーブル経由）。
    var displayName: String {
        switch self {
        case .voice: return UIStrings.ItemKind.voice
        case .text: return UIStrings.ItemKind.text
        case .video: return UIStrings.ItemKind.video
        case .audio: return UIStrings.ItemKind.audio
        case .image: return UIStrings.ItemKind.image
        case .shape: return UIStrings.ItemKind.shape
        case .tachie: return UIStrings.ItemKind.tachie
        case .face: return UIStrings.ItemKind.face
        case .effect: return UIStrings.ItemKind.effect
        case .transition: return UIStrings.ItemKind.transition
        case .scene: return UIStrings.ItemKind.scene
        case .frameBuffer: return UIStrings.ItemKind.frameBuffer
        case .group: return UIStrings.ItemKind.group
        }
    }

    /// メディアアイテム種別に対応するファイル種別（それ以外は nil）。
    /// 動画・音声・画像の追加はファイル選択から始まる（FE-R1-043）。
    var fileGroup: PropertyFileGroup? {
        switch self {
        case .video: return .video
        case .audio: return .audio
        case .image: return .image
        default: return nil
        }
    }

    init?(fileGroup: PropertyFileGroup) {
        switch fileGroup {
        case .video: self = .video
        case .audio: self = .audio
        case .image: self = .image
        }
    }

    /// ツールバー用の SF Symbol（本家は MaterialDesign アイコン。
    /// 対応する近似シンボルを使う）。
    var systemImage: String {
        switch self {
        case .voice: return "text.bubble"
        case .text: return "textformat"
        case .video: return "video"
        case .audio: return "music.note"
        case .image: return "photo"
        case .shape: return "square.on.circle"
        case .tachie: return "person"
        case .face: return "face.smiling"
        case .effect: return "wand.and.stars"
        case .transition: return "arrow.left.and.right.square"
        case .scene: return "chart.bar.xaxis"
        case .frameBuffer: return "photo.on.rectangle.angled"
        case .group: return "square.stack.3d.up"
        }
    }
}
