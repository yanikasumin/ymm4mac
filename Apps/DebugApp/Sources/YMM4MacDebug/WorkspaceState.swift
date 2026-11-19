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
    /// 未保存の変更があるか（FE-R1-001。本家の IsProjectFileSaved の
    /// 反転に相当）。駆動は本家と同じく履歴の変更通知
    /// （UndoHistory.onHistoryChanged。実際に履歴が変わった確定・
    /// Undo・Redo の成功時にだけ発火する）へ寄せ、履歴に残らない
    /// 編集（シーン操作、「動画の設定」、ファイル差し替え、分割・
    /// グループ化・ロック切替、エフェクト編集）は各操作の成功後に
    /// markEdited() を個別に呼ぶ（FE-R32-131-03）。以前はプレビュー
    /// 更新の合流点（requestPreviewRender(modelChanged:)）で立てて
    /// いたが、遅延プレビュー更新や無変更のドラッグ終了でも発火し、
    /// 保存済みが再び未保存になる誤判定があったため移行した。
    /// 保存・読み込み・新規作成の成功時に false へ戻す。プロジェ
    /// クト切替時の履歴全消去でも通知は発火するが、切替処理が
    /// その後に false を代入するため最終状態は正しくなる。
    @Published var hasUnsavedChanges = false
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
    /// メニュー／ツールバーから ProjectView へ渡す編集アクションの要求。
    /// App の .commands はプロジェクトの編集状態を持たないため、
    /// 要求だけをここに積み、ProjectView が観測して実行する。
    @Published var pendingAction: (action: WorkspaceAction, sequence: Int)?
    /// Undo 履歴の所有（プロジェクト＝ウィンドウごとに1つ）。
    /// Core の EditCoordinator とアプリ層の記録集約（EditRecorder）を
    /// ここで保持し、プロジェクトの差し替えと履歴のリセットを同じ
    /// 順序で扱う（FE-UNDO-WIRING）。
    let editRecorder = EditRecorder()
    /// 履歴の状態が変わるたびに増える版数。ツールバー／メニューの
    /// Undo・Redo の有効/無効を再評価させるための契機。
    @Published private(set) var editHistoryRevision = 0

    /// 終了フロー（DebugAppDelegate.applicationShouldTerminate）で
    /// 破棄確認が済んだ印（FE-R32-131-02）。終了が許可されると
    /// ウィンドウの閉鎖が続けて起きるため、閉鎖側の確認
    /// （WindowCloseGuard）が二重に出ないよう、閉鎖側が1回だけ
    /// 消費する。ウィンドウだけを閉じる操作では立てない（次に
    /// 終了する際は改めて確認する）。
    var discardConfirmedForTermination = false

    /// 編集アクションを ProjectView へ要求する。
    func request(_ action: WorkspaceAction) {
        pendingAction = (action, (pendingAction?.sequence ?? 0) + 1)
    }

    /// 編集が入ったことを記録する（未保存フラグを立てる）。
    func markEdited() {
        hasUnsavedChanges = true
    }

    /// 未保存の変更がある場合に破棄確認を出す（FE-R1-001）。
    /// 本家 MainViewModel が新規作成・開く・閉じる・ウィンドウ終了の
    /// 全てで共通に使う手順と同じ意味: 未保存なら
    /// 保存／保存しない／キャンセルを聞き、「保存」が選ばれた場合は
    /// 保存が成功するまで確認を繰り返す（本家は while ループ）。
    /// 破棄してよい（または未保存でない）なら true、中止なら false。
    /// 文言は macOS 標準の形に寄せた簡潔なものにする（本家の
    /// ProjectFileNotSavedMessage の文言自体はリソース側で未確認）。
    func confirmDiscardUnsavedChanges() -> Bool {
        while hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "保存されていない変更があります"
            alert.informativeText = "保存しない場合、変更は失われます。"
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "保存しない")
            alert.addButton(withTitle: "キャンセル")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                save()
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
        return true
    }

    /// 「開く」の入口。未保存の変更があれば破棄確認を出してから
    /// ファイル選択ダイアログを開く。ダイアログ側でキャンセルした
    /// 場合はプロジェクトには触らない（破棄は行われない）。
    func requestOpenProject() {
        guard confirmDiscardUnsavedChanges() else { return }
        isImporterPresented = true
    }

    /// アプリ終了時の破棄確認（DebugAppDelegate）から参照する現在の
    /// ワークスペース。単一ワークスペース前提のアプリのため生成時に
    /// 登録する（終了確認は App の .commands からは届かない経路のため）。
    nonisolated(unsafe) static weak var current: WorkspaceState?

    init() {
        project = Self.makeNewProject()
        diagnostics = YmmpLoadDiagnostics()
        Self.current = self
        // 履歴の変更を版数へ転送し、表示側の再評価を促す。Coordinator
        // への投入は全て UI（メインアクタ）からのため、通知もその
        // 文脈で届く前提で取り込む。併せて未保存フラグを立てる
        // （FE-R32-131-03。本家の HistoryChanged 駆動と同じ）。
        editRecorder.coordinator.onHistoryChanged = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.editHistoryRevision += 1
                self.hasUnsavedChanges = true
            }
        }
    }

    /// Undo 履歴の統括（Core）。表示側の可否判定はこちらを見る。
    var editCoordinator: EditCoordinator { editRecorder.coordinator }

    /// ツールバー／メニューから Undo を実行できるか。履歴の有無に
    /// 加え、編集中（未確定トランザクションあり）・復元中は不可と
    /// する（監査 Round 7 の接続条件）。復元は同期実行であり、その
    /// 間に表示が再評価されることは無いため、判定は未確定トラン
    /// ザクションの有無で足りる（Coordinator 自身も状態に応じて
    /// 実行を拒否する）。
    var canPerformUndo: Bool {
        editCoordinator.canUndo && editCoordinator.activeTransaction == nil
    }

    /// ツールバー／メニューから Redo を実行できるか（条件は Undo と同じ）。
    var canPerformRedo: Bool {
        editCoordinator.canRedo && editCoordinator.activeTransaction == nil
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
        guard confirmDiscardUnsavedChanges() else { return }
        // プロジェクトの差し替え前に、未確定トランザクションを
        // 破棄してから履歴を消す（順序の統一。FE-UNDO-WIRING）。
        editRecorder.resetForProjectSwitch()
        project = Self.makeNewProject()
        diagnostics = YmmpLoadDiagnostics()
        sourceURL = nil
        hasUnsavedChanges = false
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
            // 読み込みが成功した場合だけ、差し替え前に履歴を
            // リセットする（失敗時は旧プロジェクトと履歴を保つ）。
            editRecorder.resetForProjectSwitch()
            project = loaded
            diagnostics = loadedDiagnostics
            sourceURL = url
            hasUnsavedChanges = false
            loadSequence += 1
            loadError = nil
            statusMessage = nil
        } catch {
            loadError = "読み込みに失敗: \(error)"
        }
    }

    /// プロジェクトを保存する（通常保存。FE-R1-028）。
    /// 読み込み元ファイルがあればそこへ上書きし、無ければ保存先を
    /// ダイアログで聞く（本家 MainViewModel.SaveProject の分岐と同じ:
    /// パスが決まっている場合はダイアログを出さない）。
    /// 保存できたら true（ダイアログのキャンセル・書き込み失敗は false）。
    @discardableResult
    func save() -> Bool {
        if let sourceURL {
            return writeProject(to: sourceURL)
        }
        return saveAs()
    }

    /// 名前を付けて保存する（通常保存とは別の操作として残す）。
    /// 保存先は以後このプロジェクトの読み込み元（上書き先）になる
    /// （本家 MainModel.SaveProject が保存後に ProjectFilePath を
    /// 保存先へ更新するのと同じ）。
    ///
    /// 別のフォルダへ保存する場合は、アイテムの相対 FilePath を
    /// 新しいフォルダ基準へ再計算する（FE-R32-131-04）。変換は
    /// 保存用の写しに対して行い、保存が成功した後にだけライブ
    /// モデルへ同じ変換を反映する。保存が失敗した場合はライブ
    /// モデルのパスも読み込み元も変わらない。
    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ymmp") ?? .data]
        panel.nameFieldStringValue =
            (sourceURL?.deletingPathExtension().lastPathComponent ?? "新規プロジェクト") + ".ymmp"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let oldBase = sourceURL?.deletingLastPathComponent()
        let newBase = url.deletingLastPathComponent()
        if let oldBase, oldBase != newBase {
            // フォルダが変わる場合だけ相対パスの再計算が要る。
            // 写しは encode → decode の往復で作る（書き出しスナップ
            // ショットと同じ確立した方法）。
            guard let copy = try? YmmpCodec.decode(YmmpCodec.encode(project)).project else {
                loadError = "保存に失敗: プロジェクトの写しを作成できませんでした"
                return false
            }
            Self.rebaseFilePaths(in: copy, from: oldBase, to: newBase)
            guard writeProject(copy, to: url) else { return false }
            Self.rebaseFilePaths(in: project, from: oldBase, to: newBase)
        } else {
            guard writeProject(to: url) else { return false }
        }
        sourceURL = url
        return true
    }

    /// プロジェクトを .ymmp として書き出す単一の経路。
    /// 書き出し自体は YmmpCodec.save（保存先と同じフォルダの一時
    /// ファイルへ書き出し → 再読込で検証 → 置換 API で安全に
    /// 置き換え）が担うため、既存ファイルは検証済みの内容でのみ
    /// 置き換わり、失敗時は元のファイルが残る。未保存フラグは
    /// 成功した場合だけここで解除する（失敗時は立ったまま）。
    private func writeProject(to url: URL) -> Bool {
        writeProject(project, to: url)
    }

    /// 書き出すプロジェクトを指定できる形（別フォルダへの保存で
    /// 相対パスを再計算した写しを書き出すため。FE-R32-131-04）。
    private func writeProject(_ projectToWrite: Project, to url: URL) -> Bool {
        do {
            try YmmpCodec.save(projectToWrite, toFile: url.path)
            hasUnsavedChanges = false
            statusMessage = "保存しました: \(url.path)"
            loadError = nil
            return true
        } catch {
            loadError = "保存に失敗: \(error)"
            return false
        }
    }

    // MARK: - 相対パスの再計算（FE-R32-131-04）

    /// プロジェクト内の全アイテム（動画・音声・画像）の FilePath を
    /// 旧フォルダ基準から新フォルダ基準へ付け替える。
    static func rebaseFilePaths(in project: Project, from oldBase: URL, to newBase: URL) {
        for timeline in project.timelines {
            for item in timeline.items {
                switch item {
                case let video as VideoItem:
                    video.filePath = video.filePath.map {
                        rebasedFilePath($0, from: oldBase, to: newBase)
                    }
                case let audio as AudioItem:
                    audio.filePath = audio.filePath.map {
                        rebasedFilePath($0, from: oldBase, to: newBase)
                    }
                case let image as ImageItem:
                    image.filePath = image.filePath.map {
                        rebasedFilePath($0, from: oldBase, to: newBase)
                    }
                default:
                    break
                }
            }
        }
    }

    /// 相対パスを新しい基準フォルダへ付け替える純関数。
    /// 読み込み時の解決規則（MediaFileInfoFetcher.resolveURL）と
    /// 対になる: file URL 形式・絶対パス・Windows 形式のパスは
    /// 基準に依存しないためそのまま返し、相対パスだけを旧基準で
    /// 絶対化してから新基準で相対化する。相対化の結果が空になる
    /// 場合は絶対パスのまま返す。
    static func rebasedFilePath(_ path: String, from oldBase: URL, to newBase: URL) -> String {
        guard !path.isEmpty else { return path }
        if let url = URL(string: path), url.isFileURL { return path }
        if path.hasPrefix("/") || path.contains("\\") { return path }
        let absolutePath = oldBase.appendingPathComponent(path)
            .standardizedFileURL.path
        let basePath = newBase.standardizedFileURL.path
        let absoluteComponents = absolutePath
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let baseComponents = basePath
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var commonCount = 0
        while commonCount < min(absoluteComponents.count, baseComponents.count),
              absoluteComponents[commonCount] == baseComponents[commonCount] {
            commonCount += 1
        }
        let relativeComponents =
            Array(repeating: "..", count: baseComponents.count - commonCount)
            + absoluteComponents[commonCount...]
        let relativePath = relativeComponents.joined(separator: "/")
        return relativePath.isEmpty ? absolutePath : relativePath
    }
}

/// 画面レイアウトの保存・復元（FE-R1-036）。
///
/// 本家はドッキングレイアウト全体を AvalonDock の XML として
/// プロジェクトの LayoutXml に保存し（MainModel.SaveProject）、
/// 読み込み時に復元する（MainViewModel.RestoreLayout、失敗時は
/// DefaultLayout）。Mac 側にドッキング基盤は無く、利用者が変えられる
/// レイアウト量はレイアウトリセット（WorkspaceAction.resetLayout）が
/// 対象とする4値だけのため、その保存先としてアプリ設定
/// （UserDefaults）に前回終了時の値を残し、ProjectView の初期値へ
/// 反映する。プロジェクトの LayoutXml は本家の XML をそのまま
/// 往復保持し、Mac 側の値では上書きしない（本家で開いた際の
/// レイアウトを壊さないため）。本家の LayoutXml 自体の解釈・適用は
/// ドッキング基盤が無いため未対応（実装ログに未解決として記録）。
struct WorkspaceLayoutState {
    /// プレビュー帯の高さ（既定 400。スプリッタの可動域 120–900）。
    var previewPaneHeight: CGFloat = 400
    /// タイムラインのズーム倍率 %（既定 100。可動域 0.01–4000）。
    var timelineZoomPercent: Double = 100
    /// レイヤー行の高さ（既定 32。下限 14）。
    var layerRowHeight: Double = 32
    /// プレビュー表示倍率（既定 1.0。選択肢 0.25–4.0）。
    var previewDisplayZoom: Double = 1.0

    private static let keyPrefix = "YMM4Mac.Layout."

    static func load() -> WorkspaceLayoutState {
        let defaults = UserDefaults.standard
        var state = WorkspaceLayoutState()
        if defaults.object(forKey: keyPrefix + "previewPaneHeight") != nil {
            state.previewPaneHeight = min(
                max(CGFloat(defaults.double(forKey: keyPrefix + "previewPaneHeight")), 120),
                900
            )
        }
        if defaults.object(forKey: keyPrefix + "timelineZoomPercent") != nil {
            state.timelineZoomPercent = min(
                max(defaults.double(forKey: keyPrefix + "timelineZoomPercent"), 0.01),
                4000
            )
        }
        if defaults.object(forKey: keyPrefix + "layerRowHeight") != nil {
            state.layerRowHeight = max(
                defaults.double(forKey: keyPrefix + "layerRowHeight"), 14
            )
        }
        if defaults.object(forKey: keyPrefix + "previewDisplayZoom") != nil {
            state.previewDisplayZoom = min(
                max(defaults.double(forKey: keyPrefix + "previewDisplayZoom"), 0.25),
                4.0
            )
        }
        return state
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(
            Double(previewPaneHeight),
            forKey: Self.keyPrefix + "previewPaneHeight"
        )
        defaults.set(timelineZoomPercent, forKey: Self.keyPrefix + "timelineZoomPercent")
        defaults.set(layerRowHeight, forKey: Self.keyPrefix + "layerRowHeight")
        defaults.set(previewDisplayZoom, forKey: Self.keyPrefix + "previewDisplayZoom")
    }
}

/// メニューから ProjectView へ渡す編集アクション。
/// ProjectView が現在のタイムライン・選択・再生ヘッドで実行する。
/// 接続先（Core の編集操作等）が無いアクションはここに含めない
/// （メニュー側で無効表示にし、理由は台帳に残す）。
enum WorkspaceAction: Equatable {
    case undo
    case redo
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
