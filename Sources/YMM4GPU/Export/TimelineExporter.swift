#if os(macOS)
import AVFoundation
import Foundation
import YMM4Core

// MARK: - 書き出しファサード

/// キャンセル要求の共有フラグ（UI スレッドと書き出しスレッドの間で使う）。
public final class TimelineExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    public init() {}

    public func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

/// タイムライン書き出しの組み立てと実行。
///
/// 供給側（映像合成・音声ミックス＋ラウドネス）を構築し、
/// FFmpegProcessWriter と ExportSession へ接続する。書き出し範囲は
/// タイムライン全体（本家 VideoFileWriterSettings の EncodeFrom /
/// EncodeTo 既定に相当する範囲を `ExportRange.normalized` で正規化）。
/// ラウドネスとコンプレッサは本家の既定設定を使う（設定層は未実装の
/// ため、値の差し替えは初期化引数でのみ可能）。
public final class TimelineExporter {
    /// 対象タイムライン。
    public let timeline: Timeline
    private let videoProvider: MetalExportVideoProvider
    private let audioProvider: TimelineExportAudioProvider

    /// 音声解析の結果（書き出し前に確定する。表示・検証用）。
    public var analysisResult: LoudnessAnalysisResult { audioProvider.analysisResult }

    /// Metal 初期化に失敗した場合は `MetalInitializationError` を投げる
    /// （Issue #50: 失敗を無言で握りつぶさず、理由を入口で表示する）。
    public init(
        timeline: Timeline,
        timelines: [Timeline],
        baseDirectory: URL?,
        loudness: LoudnessNormalizationSettings = LoudnessNormalizationSettings(),
        compressor: CompressorSettings = CompressorSettings()
    ) throws {
        // デコーダ選択の基盤（Issue #70 段階3）は映像・音声で1つを
        // 共有し、プレビューと同じ選択規則にする。
        let mediaSupport = FFmpegMediaSupport()
        let videoProvider = try MetalExportVideoProvider(
            timeline: timeline, timelines: timelines, baseDirectory: baseDirectory,
            mediaSupport: mediaSupport
        )
        self.timeline = timeline
        self.videoProvider = videoProvider
        let pcmProviderFactory = mediaSupport.makePCMProviderFactory(
            baseDirectory: baseDirectory
        )
        let factory = AudioSourceFactory(
            providerFactory: pcmProviderFactory,
            sceneTimelineResolver: { id in timelines.first { $0.id == id } },
            voiceProviderResolver: VoicePCMProviderResolver(
                providerFactory: pcmProviderFactory
            ).makeResolver()
        )
        self.audioProvider = TimelineExportAudioProvider(
            timeline: timeline, factory: factory,
            loudness: loudness, compressor: compressor
        )
    }

    /// 書き出しを実行する。writer の起動失敗（ffmpeg が無い等）は
    /// 例外として投げ、それ以降の結果は ExportOutcome で返す。
    public func run(
        outputPath: String,
        ffmpegPath: String = "ffmpeg",
        cancellation: TimelineExportCancellation? = nil,
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws -> ExportOutcome {
        let range = ExportRange.normalized(
            from: 0, to: timeline.length, timelineLength: timeline.length
        )
        let settings = FFmpegExportSettings(
            videoInfo: timeline.videoInfo, length: range.count
        )
        // 既定の "ffmpeg" はバイナリ解決層（Issue #70 段階1）で
        // 解決できたパスへ寄せる。明示指定はそのまま使う。解決
        // できない場合は従来どおり名前のまま渡し、writer 側の
        // PATH 探索に委ねる。
        let resolvedFFmpegPath = ffmpegPath == "ffmpeg"
            ? (FFmpegBinaryResolver().resolve(tool: "ffmpeg")?.path ?? ffmpegPath)
            : ffmpegPath
        let writer = try FFmpegProcessWriter(
            settings: settings, outputPath: outputPath,
            executablePath: resolvedFFmpegPath
        )
        if let onProgress {
            videoProvider.onFrameRendered = { frame in
                onProgress(frame - range.lowerBound + 1, range.count)
            }
        }
        // 辞書の一貫性（R18-05、D19-01）: 書き出し側はジョブ開始
        // 時点の辞書を MetalExportVideoProvider の生成時に取得して
        // ジョブ内へ閉じ込める。ストア自体は固定しない。
        let session = ExportSession(writer: writer)
        return session.run(
            configuration: ExportSession.Configuration(
                outputPath: outputPath,
                videoInfo: timeline.videoInfo,
                frameRange: range
            ),
            videoProvider: videoProvider,
            audioProvider: audioProvider,
            isCancelled: { cancellation?.isCancelled ?? false }
        )
    }

    /// PngWav 形式（PNG 連番＋WAV）で書き出す。出力先は単一ファイル
    /// ではなくフォルダであり、セッション設定の outputPath には
    /// そのフォルダパスを渡す（付随ファイル生成フックは使わない）。
    /// writer の生成失敗（フォルダを作成できない等）は例外として投げ、
    /// それ以降の結果は ExportOutcome で返す（`run` と同じ契約）。
    public func runPngWav(
        outputDirectory: String,
        settings: PngWavExportSettings = PngWavExportSettings(),
        cancellation: TimelineExportCancellation? = nil,
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws -> ExportOutcome {
        let range = ExportRange.normalized(
            from: 0, to: timeline.length, timelineLength: timeline.length
        )
        let writer = try PngWavFileWriter(
            directoryPath: outputDirectory,
            fileName: settings.fileName,
            videoInfo: timeline.videoInfo,
            isPngOutputEnabled: settings.isPngOutputEnabled,
            isWavOutputEnabled: settings.isWavOutputEnabled
        )
        if let onProgress {
            videoProvider.onFrameRendered = { frame in
                onProgress(frame - range.lowerBound + 1, range.count)
            }
        }
        // 辞書の一貫性は run と同じ（ジョブ開始時点の辞書を供給元
        // の生成時に取得する。D19-01）。
        let session = ExportSession(writer: writer)
        return session.run(
            configuration: ExportSession.Configuration(
                outputPath: outputDirectory,
                videoInfo: timeline.videoInfo,
                frameRange: range
            ),
            videoProvider: videoProvider,
            audioProvider: audioProvider,
            isCancelled: { cancellation?.isCancelled ?? false }
        )
    }

    public func dispose() {
        videoProvider.dispose()
    }
}
#endif
