import Foundation

/// FFmpeg で音声を開く `PCMProviderFactory`（Issue #70 段階3）。
///
/// 生成の流れ: パス解決 → ファイル存在確認 → バイナリ解決の確認 →
/// ffprobe プローブ → 対象ストリーム選択 → `FFmpegPCMProvider` 生成 →
/// 初回読み取りの試行（実際に復号できることの確認）。試行で長さが
/// 正なのに1サンプルも得られなければ、開けない素材として nil を
/// 返し、失敗を `MediaAvailabilityRegistry` へ記録する（Factory 層の
/// 選択判定は「実際に開けて初回読み取りができること」が基準という
/// 段階1〜3の設計に従う）。
///
/// ストリーム選択は AVFoundation 側と同じ規則: `audioTrackIndex` が
/// 範囲外なら先頭の音声ストリームを使う。提示開始位置と長さは
/// ストリームの値を優先し、無ければ形式（コンテナ）の値を使う。
/// TS コンテナは入力シークが不安定（実測）なため、供給には出力
/// シーク方式を指示する（映像側と同じ規則）。
public final class FFmpegPCMProviderFactory: PCMProviderFactory, @unchecked Sendable {
    private let baseDirectory: URL?
    private let resolution: FFmpegBinaryResolution
    private let registry: MediaAvailabilityRegistry?
    private let prober: FFmpegProber
    private let processFactory: any FFmpegAudioProcessFactory
    private let fileExists: (String) -> Bool

    public init(
        baseDirectory: URL?,
        resolution: FFmpegBinaryResolution,
        registry: MediaAvailabilityRegistry? = nil,
        prober: FFmpegProber = FFmpegProber(),
        processFactory: any FFmpegAudioProcessFactory = FFmpegAudioProcessRunner(),
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.baseDirectory = baseDirectory
        self.resolution = resolution
        self.registry = registry
        self.prober = prober
        self.processFactory = processFactory
        self.fileExists = fileExists
    }

    public func createProvider(
        filePath: String?, audioTrackIndex: Int
    ) -> PCMProvider? {
        guard let filePath,
              let url = Self.resolveMediaURL(path: filePath, baseDirectory: baseDirectory) else {
            return nil
        }
        let resolvedPath = url.path
        let key = MediaMaterialKey(filePath: resolvedPath)

        guard fileExists(resolvedPath) else {
            registry?.markFailed(
                for: key,
                failure: MediaAvailabilityFailure(
                    kind: .fileNotFound,
                    detail: "ファイルが存在しません: \(resolvedPath)",
                    occurredAt: Date()
                )
            )
            return nil
        }
        guard let ffmpeg = resolution.ffmpeg, let ffprobe = resolution.ffprobe else {
            registry?.markFailed(
                for: key,
                failure: MediaAvailabilityFailure(
                    kind: .ffmpegUnavailable,
                    detail: "ffmpeg / ffprobe が解決できませんでした",
                    occurredAt: Date()
                )
            )
            return nil
        }

        registry?.beginLoading(for: key)
        let probe: MediaProbeResult
        do {
            probe = try prober.probe(path: resolvedPath, ffprobePath: ffprobe.path)
        } catch {
            registry?.markFailed(
                for: key,
                failure: MediaAvailabilityFailure(
                    kind: .unsupportedOrDecodeFailed,
                    detail: "ffprobe による素材情報の取得に失敗しました: \(error)",
                    occurredAt: Date()
                )
            )
            return nil
        }

        let audioStreams = probe.audioStreams
        guard !audioStreams.isEmpty else {
            registry?.markFailed(
                for: key,
                failure: MediaAvailabilityFailure(
                    kind: .unsupportedOrDecodeFailed,
                    detail: "音声ストリームがありません",
                    occurredAt: Date()
                )
            )
            return nil
        }
        let stream = audioStreams.indices.contains(audioTrackIndex)
            ? audioStreams[audioTrackIndex]
            : audioStreams[0]
        guard let sampleRate = stream.sampleRate, sampleRate > 0 else {
            registry?.markFailed(
                for: key,
                failure: MediaAvailabilityFailure(
                    kind: .unsupportedOrDecodeFailed,
                    detail: "サンプリングレートが取得できませんでした",
                    occurredAt: Date()
                )
            )
            return nil
        }

        let presentationStart = stream.startTimeSeconds ?? probe.startTimeSeconds
        let duration = stream.durationSeconds ?? probe.duration?.seconds
        let provider = FFmpegPCMProvider(
            filePath: resolvedPath,
            ffmpegPath: ffmpeg.path,
            audioStreamIndex: stream.index,
            sampleRate: sampleRate,
            presentationStartSeconds: presentationStart,
            durationSeconds: duration,
            usesOutputSeek: probe.formatName?.contains("mpegts") ?? false,
            processFactory: processFactory,
            registry: registry,
            materialKey: key
        )

        // 初回読み取りの試行: 実際に復号できることを確認する。
        // 長さが正なのに何も得られない素材は開けないものとして扱う。
        provider.seek(toTime: .zero)
        var scratch = [Float](repeating: 0, count: sampleRate * 2)
        let produced = provider.read(into: &scratch, offset: 0, count: scratch.count)
        if provider.duration > .zero && produced == 0 {
            provider.recordExternalFailure(
                kind: .unsupportedOrDecodeFailed,
                detail: "初回読み取りでサンプルを得られませんでした"
            )
            return nil
        }
        provider.seek(toTime: .zero)
        registry?.markAvailable(for: key)
        return provider
    }

    /// 素材パスを解決する（GPU 側 `resolveMediaURL` と同じ規則:
    /// file URL と絶対パスはそのまま、相対パスは基準フォルダから。
    /// 絶対判定は URL 変換前の生文字列で行う）。
    static func resolveMediaURL(path: String, baseDirectory: URL?) -> URL? {
        if let url = URL(string: path), url.isFileURL {
            return url
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard let baseDirectory else { return nil }
        return baseDirectory.appendingPathComponent(path)
    }
}
