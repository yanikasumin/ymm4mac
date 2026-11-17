#if os(macOS)
import AVFoundation
import Foundation
import YMM4Core

/// 書き出しの実接続（MAC-0026）。
///
/// MAC-0017 で用意した書き出しの芯（ExportSession / FFmpegProcessWriter /
/// ラウドネス解析 / DynamicsProcessor）へ、実合成と実ミックスを接続する:
/// - 映像: TimelineComposer + Metal 実行器でフレームごとに合成し、
///   最終テクスチャを BGRA バイト列として借用バッファへ読み戻す。
/// - 音声: TimelineAudioMixer の実ミックスを Core の
///   TimelineExportAudioProvider（解析パス＋DynamicsProcessor）へ通す。
/// - ファイル音声のデコード: PCMProvider の差し替え点へ AVFoundation
///   デコードを接続する（下記）。

/// async 読み込みの結果を同期側へ渡すための箱（セマフォで可視性が
/// 保証されるため unchecked とする）。
private final class AsyncResultBox<T>: @unchecked Sendable {
    var value: T?
}

/// AVURLAsset を async 側へ渡すための箱。メタデータ読み込みは
/// スレッド安全な読み取り操作であり、同一インスタンスの維持が
/// 必要なため unchecked とする。
private final class AssetBox: @unchecked Sendable {
    let asset: AVURLAsset

    init(_ asset: AVURLAsset) {
        self.asset = asset
    }
}

// MARK: - 音声デコード（AVFoundation）

/// AVFoundation で音声ファイルをデコードする PCM 供給元。
///
/// 本家 `AudioFileSourceFactory` はプラグイン（MediaFoundation /
/// FFmpeg）を順に試し、最初に開けたものを採用し、全滅した場合は
/// null ソース（無音）になる。ここでは AVFoundation が開けない
/// ファイルについて nil を返し、呼び出し側（FileAudioStream）が
/// 無音へ倒すことで同じ意味論になる。
///
/// 実装上の選択: デコードはファイル全体をメモリへ読み切る方式にした
/// （戻り値は既存の InMemoryPCMProvider）。本家のファイルソースは
/// ストリーミングだが、供給契約（seek / read）は同じで、シーク時の
/// 丸めも InMemoryPCMProvider の実測済みの規則に従う。長時間素材での
/// メモリ使用量は未検証事項として残る。
/// `audioTrackIndex` は音声トラック列の中の選択として解釈し、
/// 範囲外なら先頭トラックへ倒す。
public final class AVFoundationPCMProviderFactory: PCMProviderFactory {
    /// 相対パスの解決基準（.ymmp のあるフォルダ）。
    public let baseDirectory: URL?

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    public func createProvider(filePath: String?, audioTrackIndex: Int) -> PCMProvider? {
        guard let filePath,
              let url = resolveMediaURL(path: filePath, baseDirectory: baseDirectory),
              let decoded = Self.decode(url: url, audioTrackIndex: audioTrackIndex)
        else { return nil }
        return InMemoryPCMProvider(samples: decoded.samples, hz: decoded.hz)
    }

    /// ファイル全体を float32 / 2ch インターリーブへデコードする。
    /// サンプルレートは素材のネイティブレートを保持し、タイムライン
    /// Hz への変換は後段のリサンプラ（本家のチェーンと同じ位置）が担う。
    private static func decode(
        url: URL, audioTrackIndex: Int
    ) -> (samples: [Float], hz: Int)? {
        let asset = AVURLAsset(url: url)
        // トラックとリーダーは同一の AVURLAsset インスタンスでなければ
        // ならない（別インスタンスのトラックから作った出力をリーダーへ
        // 追加すると AVFoundation が例外を投げる）。資産は読み取り専用
        // として箱経由で async 側へ渡す。
        let assetBox = AssetBox(asset)
        guard let tracks = loadSynchronously({
                  try await assetBox.asset.loadTracks(withMediaType: .audio)
              }),
              !tracks.isEmpty
        else { return nil }
        let track = tracks.indices.contains(audioTrackIndex)
            ? tracks[audioTrackIndex] : tracks[0]

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 2,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var samples: [Float] = []
        var hz = 0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if hz == 0,
               let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                hz = Int(description.pointee.mSampleRate)
            }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0, length % 4 == 0 else { continue }
            var raw = [UInt8](repeating: 0, count: length)
            let status = raw.withUnsafeMutableBytes { destination in
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: length,
                    destination: destination.baseAddress!
                )
            }
            guard status == noErr else { continue }
            raw.withUnsafeBytes { source in
                samples.append(contentsOf: source.bindMemory(to: Float.self))
            }
        }
        guard reader.status == .completed, hz > 0 else { return nil }
        return (samples, hz)
    }

    /// 同期契約（PCMProviderFactory）から async のメタデータ読み込みを
    /// 呼ぶための橋渡し。失敗は nil（= 開けない）として扱う。
    private static func loadSynchronously<T>(
        _ operation: @Sendable @escaping () async throws -> T
    ) -> T? {
        let box = AsyncResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.value = try? await operation()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }
}

// MARK: - 映像供給（実合成）

/// 書き出しの映像供給。PreviewBox と同じ合成経路（TimelineComposer +
/// MetalSourceProvider + MetalEffectPairProvider）を、プレビューとは
/// 独立したデバイス・文脈・合成器で所有する。
///
/// フレームごとに合成器を `.exporting` 用途で更新し、最終出力を
/// 借用バッファへ BGRA のまま読み戻す（W6-C4 の借用契約: 書き込みは
/// このメソッドの中で完了し、バッファへの参照は保持しない）。
public final class MetalExportVideoProvider: VideoFrameProviding {
    private let devices: MetalGraphicsDevices
    private let context: MetalGraphicsContext
    private let composer: TimelineComposer
    private let videoInfo: VideoInfo

    /// フレームの合成が完了するたびに呼ばれる（進捗表示用）。
    public var onFrameRendered: ((Int) -> Void)?

    public init?(timeline: Timeline, timelines: [Timeline], baseDirectory: URL?) {
        guard let devices = MetalGraphicsDevices() else { return nil }
        self.devices = devices
        self.videoInfo = timeline.videoInfo
        self.context = devices.makeContext(
            targetSize: PixelSize(width: videoInfo.width, height: videoInfo.height)
        )
        let provider = MetalSourceProvider(
            devices: devices, baseDirectory: baseDirectory,
            sceneResolver: { id in timelines.first { $0.id == id } }
        )
        self.composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider.source(for:),
            effectProvider: MetalEffectPairProvider(devices: devices)
        )
    }

    public func fillFrame(_ frame: Int, into buffer: ExportVideoFrameBuffer) throws {
        context.targetSize = PixelSize(width: videoInfo.width, height: videoInfo.height)
        let seconds = FrameTime.time(fromFrame: frame, fps: videoInfo.fps)
        try composer.update(time: TimeSpanValue(seconds: seconds), usage: .exporting)
        guard let output = composer.output else {
            throw ExportError(
                severity: .fatal, message: "フレーム \(frame) の合成出力がありません"
            )
        }
        guard devices.readBGRA(from: output, into: &buffer.bytes) else {
            throw ExportError(
                severity: .fatal, message: "フレーム \(frame) の読み戻しに失敗しました"
            )
        }
        onFrameRendered?(frame)
    }

    public func dispose() {
        composer.dispose()
    }
}

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
