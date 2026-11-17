import Foundation

/// 書き出しに関する設定値の定義。
///
/// 本家は各プラグインが永続設定シングルトン（`SettingsBase<T>.Default`）を
/// 直接読み、寸法・FPS・Hz・長さは設定 UI の表示という副作用で注入される
/// 構造だった（仕様第6章 W6-2.2 / W6-2.3）。CLI 経路では注入が起きず
/// 前回値が残る脆弱性（W6-2.7）があるため、Mac 版では第7章 C5・
/// 第6章 W6-C9 の是正どおり、開始時点の値を不変の値オブジェクトとして
/// 明示的に writer へ渡す。本ファイルの各構造体はその受け渡し専用で、
/// 永続化や UI は持たない。

// MARK: - ラウドネス正規化（本家 LoudnessNormalizationSettings）

/// ラウドネス補正モード。本家 `LoudnessFixMode`（生値は本家どおり）。
public enum LoudnessFixMode: Int, Sendable {
    case disabled = 0
    case downOnly = 1
    case both = 2
    case downMaximumVolume = 3
    case upDownMaximumVolume = 4
}

/// ラウドネス正規化設定。本家 `LoudnessNormalizationSettings`。
public struct LoudnessNormalizationSettings: Equatable, Sendable {
    /// 補正モード。既定は DownMaximumVolume（ピーク基準で下げるのみ）。
    public var mode: LoudnessFixMode
    /// 目標ラウドネス（LKFS）。既定 −15。ピーク系モードでは使われない。
    public var target: Float

    public init(mode: LoudnessFixMode = .downMaximumVolume, target: Float = -15) {
        self.mode = mode
        self.target = target
    }
}

// MARK: - コンプレッサ（本家 CompressorSettings）

/// コンプレッサの倍率決定モード。本家 `CompressorRatioMode`。
public enum CompressorRatioMode: Int, Sendable {
    case disabled = 0
    case auto = 1
    case custom = 2
}

/// コンプレッサ設定。本家 `CompressorSettings` の既定値をそのまま持つ。
public struct CompressorSettings: Equatable, Sendable {
    /// スレッショルド（dB）。既定 −18。
    public var threshold: Float
    /// 倍率の決定方法。既定 Auto（ピークから自動計算）。
    public var ratioMode: CompressorRatioMode
    /// ピーク上限（dB）。既定 −0.2。Auto 計算の分母に使う。
    public var peakLimit: Float
    /// Custom 時の固定倍率。既定 4。
    public var ratio: Float
    /// アタック（秒）。既定 0.006。
    public var attack: Float
    /// リリース（秒）。既定 0.06。
    public var release: Float
    /// ルックアヘッドの有効化。既定 true。
    public var isLookAheadEnabled: Bool

    public init(
        threshold: Float = -18,
        ratioMode: CompressorRatioMode = .auto,
        peakLimit: Float = -0.2,
        ratio: Float = 4,
        attack: Float = 0.006,
        release: Float = 0.06,
        isLookAheadEnabled: Bool = true
    ) {
        self.threshold = threshold
        self.ratioMode = ratioMode
        self.peakLimit = peakLimit
        self.ratio = ratio
        self.attack = attack
        self.release = release
        self.isLookAheadEnabled = isLookAheadEnabled
    }
}

// MARK: - 書き出し範囲（本家 VideoFileWriterSettings の EncodeFrom / EncodeTo）

/// 書き出しフレーム範囲の正規化。本家 W6-2.5 の式を再現する。
public enum ExportRange {
    /// `start = max(0, min(min(from, to), length - 1))`、
    /// `end = min(length, max(from, to))` で正規化した半開区間を返す。
    /// From / To の前後は問わない（min / max で吸収される）。
    /// length が 0 以下の場合は空区間 (0, 0)。
    public static func normalized(from: Int, to: Int, timelineLength: Int) -> Range<Int> {
        guard timelineLength > 0 else { return 0..<0 }
        let start = max(0, min(min(from, to), timelineLength - 1))
        let end = min(timelineLength, max(from, to))
        return start..<max(start, end)
    }
}

// MARK: - FFmpeg ライター設定（本家 FFmpegVideoFileWriterSettings）

/// 音声ビットレート。本家 `AudioBitRate`（生値は kbps そのもの）。
public enum AudioBitRate: Int, Sendable {
    case kb576 = 576
    case kb512 = 512
    case kb384 = 384
    case kb320 = 320
    case kb256 = 256
    case kb192 = 192
    case kb160 = 160
    case kb128 = 128
    case kb96 = 96
    case kb32 = 32
    case none = 0
}

/// 映像ビットレートの指定方法。本家 `VideoBitRateMode`。
public enum VideoBitRateMode: Int, Sendable {
    case auto = 0
    case custom = 1
    case none = 2
}

/// 映像レート制御。本家 `VideoBitRateControlMode`。
public enum VideoBitRateControlMode: Int, Sendable {
    case cbr = 0
    case quality = 1
}

/// FFmpeg ライターへ明示的に渡す不変の設定スナップショット。
///
/// 本家では Width / Height / FPS / Hz / Length は設定 UI の副作用で
/// シングルトンへ注入される一時値だった（W6-2.3）。ここでは開始時に
/// VideoInfo とタイムライン長から明示的に組み立てて保持する。
/// 実行中に値が変わることはない（W6-C9）。
public struct FFmpegExportSettings: Equatable, Sendable {
    /// 入力フレーム幅（px）。映像プロセスの `-s` に使う。
    public var width: Int
    /// 入力フレーム高さ（px）。
    public var height: Int
    /// フレームレート。映像プロセスの `-r` に使う。
    public var fps: Int
    /// サンプリングレート。音声プロセスの `-ar` に使う。
    public var hz: Int
    /// 書き出し対象の総フレーム数（本家の Length 注入値に相当）。
    public var length: Int

    /// ビットレート指定方法。既定 Auto。
    /// Auto の場合は呼び出し側が算出した `videoBitRate` が入っている前提で、
    /// 引数生成では Auto と Custom を区別しない（本家の引数生成も同じ）。
    public var videoBitRateMode: VideoBitRateMode
    /// レート制御。既定 CBR。
    public var videoBitRateControlMode: VideoBitRateControlMode
    /// 映像ビットレート（kbps）。既定 10000。
    public var videoBitRate: Int
    /// 品質（0...100）。Quality 時 `crf = (100 - quality) / 100 * 51`。既定 55。
    public var videoQuality: Int
    /// 音声ビットレート。既定 192 kbps。
    public var audioBitRate: AudioBitRate
    /// ユーザー指定の映像オプション文字列（本家 VideoOptions）。既定は空。
    public var videoOptions: String
    /// ユーザー指定の音声オプション文字列（本家 AudioOptions）。既定は空。
    public var audioOptions: String
    /// ハードウェアエンコーダ解決の有効化。既定 true。
    /// 解決処理自体はプラットフォーム依存のため、この芯では引数生成に
    /// 影響させない（差し替え点。完了報告に記録）。
    public var isHardwareEncoderEnabled: Bool

    public init(
        width: Int,
        height: Int,
        fps: Int,
        hz: Int,
        length: Int,
        videoBitRateMode: VideoBitRateMode = .auto,
        videoBitRateControlMode: VideoBitRateControlMode = .cbr,
        videoBitRate: Int = 10_000,
        videoQuality: Int = 55,
        audioBitRate: AudioBitRate = .kb192,
        videoOptions: String = "",
        audioOptions: String = "",
        isHardwareEncoderEnabled: Bool = true
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.hz = hz
        self.length = length
        self.videoBitRateMode = videoBitRateMode
        self.videoBitRateControlMode = videoBitRateControlMode
        self.videoBitRate = videoBitRate
        self.videoQuality = videoQuality
        self.audioBitRate = audioBitRate
        self.videoOptions = videoOptions
        self.audioOptions = audioOptions
        self.isHardwareEncoderEnabled = isHardwareEncoderEnabled
    }

    /// VideoInfo とタイムライン長から組み立てる。
    /// 本家の「設定 UI を開くたびにプロジェクト値で上書きされる一時値」を、
    /// 明示的な初期化として置き換えたもの。
    public init(
        videoInfo: VideoInfo,
        length: Int,
        videoBitRateMode: VideoBitRateMode = .auto,
        videoBitRateControlMode: VideoBitRateControlMode = .cbr,
        videoBitRate: Int = 10_000,
        videoQuality: Int = 55,
        audioBitRate: AudioBitRate = .kb192,
        videoOptions: String = "",
        audioOptions: String = "",
        isHardwareEncoderEnabled: Bool = true
    ) {
        self.init(
            width: videoInfo.width,
            height: videoInfo.height,
            fps: videoInfo.fps,
            hz: videoInfo.hz,
            length: length,
            videoBitRateMode: videoBitRateMode,
            videoBitRateControlMode: videoBitRateControlMode,
            videoBitRate: videoBitRate,
            videoQuality: videoQuality,
            audioBitRate: audioBitRate,
            videoOptions: videoOptions,
            audioOptions: audioOptions,
            isHardwareEncoderEnabled: isHardwareEncoderEnabled
        )
    }
}
