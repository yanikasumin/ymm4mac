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
    /// この書き出しが使うデコーダ選択の基盤（Issue #70 段階4）。
    /// アプリはワークスペースの基盤を渡し、プレビュー・長さ取得と
    /// 同じ台帳で素材の失敗を判定する。未指定なら書き出し専用の
    /// 基盤を作る（単独利用・自動テスト）。
    public let mediaSupport: FFmpegMediaSupport
    private let timelines: [Timeline]
    private let baseDirectory: URL?
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
        compressor: CompressorSettings = CompressorSettings(),
        mediaSupport: FFmpegMediaSupport? = nil
    ) throws {
        // デコーダ選択の基盤（Issue #70 段階3・4）は映像・音声で
        // 1つを共有し、プレビューと同じ選択規則・同じ台帳にする。
        let mediaSupport = mediaSupport ?? FFmpegMediaSupport()
        self.mediaSupport = mediaSupport
        self.timelines = timelines
        self.baseDirectory = baseDirectory
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

    /// 書き出しに必要な素材のキー列（対象タイムラインとシーン
    /// 経由で到達できるタイムラインが参照する素材）。
    private func requiredMaterialKeys() -> [MediaMaterialKey] {
        ExportMaterialCheck.requiredMaterialKeys(
            timeline: timeline, timelines: timelines,
            baseDirectory: baseDirectory
        )
    }

    /// 事前判定（Issue #70 段階4）: 必要な素材が失敗状態なら
    /// writer を作らず、失敗の結果を返す。問題なければ nil。
    private func materialPreflightFailure(
        keys: [MediaMaterialKey]
    ) -> ExportOutcome? {
        let evaluation = ExportMaterialCheck.evaluate(
            registry: mediaSupport.registry, keys: keys
        )
        guard !evaluation.blocking.isEmpty else { return nil }
        return .failedBeforeStart(error: ExportError(
            cause: .actionable,
            message: ExportMaterialCheck.blockingMessage(evaluation.blocking)
        ))
    }

    /// 事後判定（Issue #70 段階4）: 書き出し中に新たに失敗が
    /// 判明した素材があれば、完了した書き出しも失敗として扱う
    /// （素材抜けの動画を成功としない）。途中失敗は警告に留める。
    /// キャンセルはキャンセルのままにする。
    private func applyMaterialPostCheck(
        _ outcome: ExportOutcome, keys: [MediaMaterialKey]
    ) -> ExportOutcome {
        guard outcome.completion == .completed else { return outcome }
        let evaluation = ExportMaterialCheck.evaluate(
            registry: mediaSupport.registry, keys: keys
        )
        var outcome = outcome
        if !evaluation.blocking.isEmpty {
            outcome.completion = .failed
            outcome.error = ExportError(
                cause: .actionable,
                message: ExportMaterialCheck.blockingMessage(evaluation.blocking)
            )
        } else if !evaluation.midStream.isEmpty, outcome.warning == nil {
            outcome.warning = ExportError(
                cause: .actionable,
                message: ExportMaterialCheck.midStreamWarningMessage(
                    evaluation.midStream
                )
            )
        }
        return outcome
    }

    /// 書き出しを実行する。writer の起動失敗（ffmpeg が無い等）は
    /// 例外として投げ、それ以降の結果は ExportOutcome で返す。
    /// 必要な素材が失敗状態の場合は writer を作らず、失敗の
    /// 結果を返す（Issue #70 段階4）。
    public func run(
        outputPath: String,
        ffmpegPath: String = "ffmpeg",
        cancellation: TimelineExportCancellation? = nil,
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws -> ExportOutcome {
        let materialKeys = requiredMaterialKeys()
        if let failure = materialPreflightFailure(keys: materialKeys) {
            return failure
        }
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
        let outcome = session.run(
            configuration: ExportSession.Configuration(
                outputPath: outputPath,
                videoInfo: timeline.videoInfo,
                frameRange: range
            ),
            videoProvider: videoProvider,
            audioProvider: audioProvider,
            isCancelled: { cancellation?.isCancelled ?? false }
        )
        return applyMaterialPostCheck(outcome, keys: materialKeys)
    }

    /// PngWav 形式（PNG 連番＋WAV）で書き出す。出力先は単一ファイル
    /// ではなくフォルダであり、セッション設定の outputPath には
    /// そのフォルダパスを渡す（付随ファイル生成フックは使わない）。
    /// writer の生成失敗（フォルダを作成できない等）は例外として投げ、
    /// それ以降の結果は ExportOutcome で返す（`run` と同じ契約）。
    /// 素材の失敗判定も `run` と同じ（Issue #70 段階4）。
    public func runPngWav(
        outputDirectory: String,
        settings: PngWavExportSettings = PngWavExportSettings(),
        cancellation: TimelineExportCancellation? = nil,
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws -> ExportOutcome {
        let materialKeys = requiredMaterialKeys()
        if let failure = materialPreflightFailure(keys: materialKeys) {
            return failure
        }
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
        let outcome = session.run(
            configuration: ExportSession.Configuration(
                outputPath: outputDirectory,
                videoInfo: timeline.videoInfo,
                frameRange: range
            ),
            videoProvider: videoProvider,
            audioProvider: audioProvider,
            isCancelled: { cancellation?.isCancelled ?? false }
        )
        return applyMaterialPostCheck(outcome, keys: materialKeys)
    }

    public func dispose() {
        videoProvider.dispose()
    }
}
#endif
