import Foundation

/// UI 表示文字列の集約テーブル（後の多言語化の前提として、この
/// フェーズで導入する）。本家は表示文言を `Texts` リソースから供給し、
/// コード側はキーだけを持つ。こちらも同じ形に寄せ、View 側に日本語
/// リテラルを直書きせず、表示文言は原則としてこの表を経由する。
///
/// 収録範囲はフロントエンドの主要表面（メニュー／トランスポート／
/// ツールバー／タイムライン／セリフ行／ステータスバー／レイヤー操作／
/// エフェクト／アニメーション種別）。文言の根拠は本家解析
/// （analysis-notes/UI-*-FACTS.md）とし、本家に実在しない殻側の文言は
/// その旨をコメントに残す。
enum UIStrings {

    // MARK: - 共通

    enum Common {
        static let add = "追加"
        static let delete = "削除"
        static let close = "閉じる"
        static let cancel = "キャンセル"
        static let none = "なし"
        static let unconnectedSuffix = "（未接続）"
    }

    // MARK: - メインメニュー（本家 MainView の5系統）

    enum Menu {
        static let newProject = "新規プロジェクト"
        static let openProject = "開く…"
        static let addItem = "アイテムを追加"
        static let addItemFromTemplate = "テンプレートからアイテムを追加"
        static let recentFiles = "最近使ったファイル"
        static let noHistory = "（履歴なし）"
        static let importMenu = "インポート"
        static let importSubtitleAsVoice = "字幕ファイルをボイスアイテムとして読み込む"
        static let importSubtitle = "字幕ファイルを読み込む"
        static let restoreFromBackup = "バックアップからプロジェクトを復元…"
        static let videoSettings = "動画の設定…"
        static let outputVideo = "動画出力…"
        static let outputExo = "Exo出力…"
        static let saveThumbnail = "サムネイル画像を出力…"
        static let saveProject = "プロジェクトを保存"
        static let saveProjectAs = "名前を付けて保存…"
        static let characterEditor = "キャラクター編集…"
        static let settingWindow = "設定…"
        static let splitAtCurrentPosition = "現在位置で分割"
        static let previewControl = "プレビュー操作"
        static let controlPointVisibility = "コントロールポイント表示"
        static let controlPointOnSelected = "選択中のアイテムのみ"
        static let controlPointOnMouseOver = "プレビューにマウスオーバー時"
        static let controlPointNever = "常に表示しない"
        static let itemControl = "アイテム操作"
        static let align = "整列"
        static let alignLeft = "左揃え"
        static let alignCenter = "中央揃え"
        static let alignRight = "右揃え"
        static let move = "移動"
        static let setToDefault = "既定値に設定"
        static let voiceControl = "ボイス操作"
        static let changeCharacter = "キャラクターを変更"
        static let changePreviousCharacter = "前のキャラクター"
        static let changeNextCharacter = "次のキャラクター"
        static let changeVoiceMode = "ボイスモードを変更"
        static let timelineControl = "タイムライン操作"
        static let layerHeightUp = "レイヤーの高さを拡大"
        static let layerHeightDown = "レイヤーの高さを縮小"
        static let zoomInTimeline = "タイムラインを拡大"
        static let zoomOutTimeline = "タイムラインを縮小"
        static let layout = "レイアウト"
        static let layoutPreset = "レイアウトプリセット"
        static let saveLayoutPreset = "現在のレイアウトを保存…"
        static let resetLayout = "既定のレイアウトに戻す"
        static let tools = "ツール"
        static let toolItemEditor = "アイテム編集"
        static let toolPreview = "プレビュー"
        static let alwaysShowSceneTab = "シーンタブを常に表示"
        static let toolSearch = "検索"
        static let toolMaterials = "素材一覧"
        static let toolScenario = "台本編集"
        static let toolTranscription = "文字起こし"
        static let toolTemplateEditor = "テンプレート編集"
        static let toolUserDictionary = "ユーザー辞書"
        static let toolVolumeAnalyzer = "音量アナライザ"
        static let faq = "FAQ"
        static let contact = "問い合わせ"
        static let fanbox = "FANBOX"
        static let about = "バージョン情報"
        static let group = "グループ化"
        static let ungroup = "グループ解除"
        static let deleteSelection = "選択アイテムを削除"
        static let deleteAndMoveAll = "削除して前へ詰める"
        static let selectAll = "すべて選択"
        static let selectLeftItems = "左側のアイテムを選択"
        static let selectRightItems = "右側のアイテムを選択"
        static let toggleLock = "ロックを切り替え"
        static let toggleClipping = "クリッピングを切り替え"
        static let toggleWaveform = "波形表示を切り替え"
        static let seekToStart = "先頭へ移動"
        static let seekToEnd = "末尾へ移動"
    }

    // MARK: - アイテム種別（追加メニュー・ツールバー共通）

    enum ItemKind {
        static let voice = "ボイス"
        static let text = "テキスト"
        static let video = "動画"
        static let audio = "音声"
        static let image = "画像"
        static let shape = "図形"
        static let tachie = "立ち絵"
        static let face = "表情"
        static let effect = "エフェクト"
        static let transition = "画面遷移"
        static let scene = "シーン"
        static let frameBuffer = "フレームバッファ"
        static let group = "グループ"
    }

    // MARK: - トランスポート（本家 PreviewView 操作行）

    enum Transport {
        static let play = "再生"
        static let pause = "一時停止"
        static let stop = "停止"
        static let playbackRate = "再生速度"
        static let repeatPlay = "リピート再生"
        static let controlPointVisibility = "コントロールポイント表示"
        static let previewZoom = "プレビュー倍率"
        static let fit = "フィット"
        static let seekToStart = "先頭へ移動"
        static let seekToPrevEditPoint = "前の編集点へ移動"
        static let seekToPrevFrame = "前フレーム"
        static let seekToNextFrame = "次フレーム"
        static let seekToNextEditPoint = "次の編集点へ移動"
        static let seekToEnd = "末尾へ移動"
        static let volume = "音量"
        static let mute = "ミュート"
    }

    // MARK: - ツールバー（ツールチップは本家 Command.TextWithShortcut 形式）

    /// ツールチップ文言。本家は「コマンド名＋ショートカット」
    /// （`Command.TextWithShortcut`）を出す。ショートカットが無い
    /// コマンドは名前のみ。
    enum Toolbar {
        static func tip(_ name: String, shortcut: String? = nil) -> String {
            guard let shortcut else { return name }
            return "\(name) (\(shortcut))"
        }
        static let zoomOut = "縮小"
        static let zoomIn = "拡大"
        static let zoomSlider = "タイムラインズーム"
        static let fitAll = "全体を表示"
        static let addItem = "アイテムを追加"
        static let templateMenu = "テンプレート"
        static let recentFiles = "最近使ったファイル"
        static let undo = "元に戻す"
        static let redo = "やり直し"
        static let cut = "切り取り"
        static let copy = "コピー"
        static let paste = "貼り付け"
        static let split = "現在位置で分割"
        static let group = "グループ化"
        static let ungroup = "グループ解除"
        static let clippingOn = "クリッピングを有効化"
        static let clippingOff = "クリッピングを無効化"
        static let lock = "ロック"
        static let unlock = "ロック解除"
        static let waveform = "波形表示"
        static let waveformAlways = "常に表示"
        static let waveformOnMouseOver = "マウスオーバー時に表示"
        static let waveformHidden = "非表示"
        static let gridLine = "グリッド線"
        static let gridLineSettings = "グリッド線の設定…"
        static let meters = "メーター表示"
        static let peakMeter = "ピークメーターを表示"
        static let loudnessMeter = "ラウドネスメーターを表示"
        static let delete = "削除"
        static let deleteAndMove = "削除して前へ詰める"
        static let selectLeft = "左側を選択"
        static let selectRight = "右側を選択"
        static let selectAll = "すべて選択"
        static let newProject = "新規プロジェクト"
        static let openProject = "プロジェクトを開く"
        static let saveProject = "プロジェクトを保存"
        static let videoInfo = "動画の設定"
        static let outputExo = "Exo出力"
        static let outputVideo = "動画出力"
        static let saveThumbnail = "サムネイルを保存"
        static let saveThumbnailPng = "PNG"
        static let saveThumbnailPngAlpha = "透過PNG"
        static let saveThumbnailJpeg = "JPEG"
        static let feedback = "フィードバックを送信"
        static let layerHeightUp = "レイヤーの高さを拡大"
        static let layerHeightDown = "レイヤーの高さを縮小"
        // ショートカット表記（本家の既定割り当て。Ctrl は macOS では ⌘）。
        static let shortcutUndo = "⌘Z"
        static let shortcutRedo = "⌘⇧Z"
        static let shortcutCut = "⌘X"
        static let shortcutCopy = "⌘C"
        static let shortcutPaste = "⌘V"
        static let shortcutSplit = "⌘B"
        static let shortcutDelete = "⌫"
        static let shortcutSelectAll = "⌘A"
        static let shortcutSave = "⌘S"
        static let shortcutOpen = "⌘O"
        static let shortcutNew = "⌘N"
    }

    // MARK: - タイムライン／レイヤー

    enum Timeline {
        static let layer = "レイヤー"
        static func defaultLayerLabel(_ layer: Int) -> String {
            String(format: "レイヤー %02d", layer)
        }
        static let showLayer = "レイヤーを表示"
        static let hideLayer = "レイヤーを非表示"
        static let layerOperations = "レイヤー操作"
        static let renameLayer = "名前を変更…"
        static let layerBackgroundColor = "背景色"
        static let layerVolume = "レイヤー全体の音量…"
        static let addLayerAbove = "上にレイヤーを追加"
        static let addLayerBelow = "下にレイヤーを追加"
        static let deleteLayer = "レイヤーを削除"
        static let moveLayerUp = "レイヤーを上へ移動"
        static let moveLayerDown = "レイヤーを下へ移動"
        static let selectLayerItems = "レイヤーのアイテムをすべて選択"
        static let enableAllLayers = "すべてのレイヤーを表示"
        static let disableOtherLayers = "他のレイヤーを非表示"
        static let resetLayerSettings = "レイヤー設定をリセット"
        static func layerSettingsTitle(_ layer: Int) -> String {
            "レイヤー \(layer) の設定"
        }
        static let layerName = "名前"
        static let layerNamePlaceholder = "レイヤー名"
        static let volume = "音量"
        static let apply = "設定"
        // コンテキストメニュー（キャンバス／アイテム）
        static let splitAtPlayhead = "再生ヘッド位置で分割"
        static let addKeyFrameAtPlayhead = "現在フレームにキーフレームを追加"
        static let removeKeyFrameAtPlayhead = "現在フレームのキーフレームを削除"
        static let removeAllKeyFrames = "すべてのキーフレームを削除"
        static let distributeKeyFrames = "キーフレームを等間隔に配置"
        static let deleteTimelineSpace = "現在位置の余白を削除"
        static let deleteAllTimelineSpaces = "すべての余白を削除"
        static let moveLeftFrame = "1フレーム左へ移動"
        static let moveRightFrame = "1フレーム右へ移動"
        static let moveLeftSecond = "1秒左へ移動"
        static let moveRightSecond = "1秒右へ移動"
        static let moveUpLayer = "上のレイヤーへ移動"
        static let moveDownLayer = "下のレイヤーへ移動"
    }

    // MARK: - セリフ入力行

    enum Serif {
        static let placeholder = "ここにセリフを入力"
        static let character = "キャラクター"
        static let noCharacters = "（キャラクター未登録）"
        static let openCharacterSettings = "キャラクター設定を開く"
        static let add = "追加"
        static let addAndSeek = "追加してシーク"
        static let addMode = "追加モード"
    }

    // MARK: - ステータスバー

    enum StatusBar {
        static let currentTime = "現在時刻（入力してシーク）"
        static let currentFrame = "現在フレーム（入力してシーク）"
        static let videoSettings = "動画の設定"
    }

    // MARK: - インスペクタ

    enum Inspector {
        static let item = "アイテム"
        static let noSelection = "アイテムが選択されていません"
        static let videoEffects = "映像エフェクト"
        static let addEffect = "エフェクトを追加"
        static let removeEffect = "エフェクトを削除"
        static let unsupportedEffect = "型付き編集未対応（生保持のまま保存されます）"
    }

    // MARK: - エフェクト追加ポップアップ

    enum EffectPopup {
        static let searchPlaceholder = "エフェクトを検索"
        static let all = "すべて"
        static let other = "その他"
        static let emptyResult = "該当するエフェクトがありません"
    }

    // MARK: - アニメーション種別（本家 AnimationSlider メニュー）

    enum AnimationTypeName {
        static let none = "なし"
        static let linear = "直線移動"
        static let linearBezier = "直線移動（ベジェ）"
        static let acceleration = "加減速移動"
        static let instant = "瞬間移動"
        static let movementAmount = "移動量指定"
        static let random = "ランダム移動"
        static let repetitive = "反復移動"
        static let interpolation = "補間移動"
        static let interpolationBezier = "補間移動（ベジェ）"
        static let modeIn = "In"
        static let modeOut = "Out"
        static let modeInOut = "InOut"
        static let modeOutIn = "OutIn"
        static let keyFrameModeNormal = "通常"
        static let keyFrameModeInterpolation = "補間"
    }
}
