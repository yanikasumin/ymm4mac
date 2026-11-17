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

    public init?(
        timeline: Timeline,
        timelines: [Timeline],
        baseDirectory: URL?,
        loudness: LoudnessNormalizationSettings = LoudnessNormalizationSettings(),
        compressor: CompressorSettings = CompressorSettings()
    ) {
        guard let videoProvider = MetalExportVideoProvider(
            timeline: timeline, timelines: timelines, baseDirectory: baseDirectory
        ) else { return nil }
        self.timeline = timeline
        self.videoProvider = videoProvider
        let factory = AudioSourceFactory(
            providerFactory: AVFoundationPCMProviderFactory(baseDirectory: baseDirectory),
            sceneTimelineResolver: { id in timelines.first { $0.id == id } }
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
        let writer = try FFmpegProcessWriter(
            settings: settings, outputPath: outputPath, executablePath: ffmpegPath
        )
        if let onProgress {
            videoProvider.onFrameRendered = { frame in
                onProgress(frame - range.lowerBound + 1, range.count)
            }
        }
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

    public func dispose() {
        videoProvider.dispose()
    }
}
#endif
