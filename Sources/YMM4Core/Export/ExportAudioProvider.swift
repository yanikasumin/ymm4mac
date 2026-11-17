import Foundation

/// 書き出しの音声供給（実ミックス＋ラウドネス経路）。
///
/// 本家 `VideoFileWriter.CreateFileAsync` の音声側の流れを再現する:
/// 1. 解析パス: 書き出し前にタイムライン全体を読み直し、ラウドネス
///    解析（`LoudnessAnalysis`）で音量倍率とコンプレッサ倍率を確定
///    する（仕様第6章 §6 / W6-6.1）。
/// 2. 本書き出し: 別のミキサーへ `DynamicsProcessorStream` を被せ、
///    解析で決まった倍率を掛けながらフレーム単位で読み出す。
///    DynamicsProcessor は本家では常時生成され、倍率が両方とも 1 の
///    場合でも高速経路で素通しになる（W6-6.4）。
///
/// 解析と本書き出しでミキサーを分ける理由: `TimelineAudioMixer` は
/// 読み取りのたびに資源を開閉する一方向ストリームで、シークは全資源
/// を破棄して作り直す。本家も解析後にソースを読み直す前提であり、
/// 使い切った解析用ミキサーを再利用しない方が状態が単純になる。
///
/// フレームごとのサンプル件数は `ExportAudioSampleCount` の累積式に
/// 従う。フレームが連続しない呼び出し（前方・後方へのジャンプ）では
/// 累積位置へシークしてから読む。
public final class TimelineExportAudioProvider: AudioFrameProviding {
    /// 対象タイムライン。
    public let timeline: Timeline
    /// 解析パスの結果（音量倍率・コンプレッサ倍率・測定値）。
    /// UI の表示や検証で使う。
    public let analysisResult: LoudnessAnalysisResult

    private let dynamics: DynamicsProcessorStream
    private var nextFrame = 0

    public init(
        timeline: Timeline,
        factory: AudioSourceFactory,
        loudness: LoudnessNormalizationSettings = LoudnessNormalizationSettings(),
        compressor: CompressorSettings = CompressorSettings()
    ) {
        self.timeline = timeline
        let info = timeline.videoInfo

        // 解析パス（本家の読み直し）。チャンクの組み立て方は本家の
        // 固定長配列方式（W6-6.3）を LoudnessAnalysis 側が担う。
        let analysisMixer = TimelineAudioMixer(timeline: timeline, factory: factory)
        let chunks = LoudnessAnalysis.makeChunks(
            from: analysisMixer,
            frameCount: timeline.length,
            hz: info.hz,
            fps: info.fps
        )
        let result = LoudnessAnalysis.analyze(
            chunks: chunks, loudness: loudness, compressor: compressor, hz: info.hz
        )
        analysisResult = result

        // 本書き出し。新しいミキサーへ DynamicsProcessor を被せる。
        let writeMixer = TimelineAudioMixer(timeline: timeline, factory: factory)
        let processor = DynamicsProcessorStream(
            input: writeMixer,
            volume: result.volumeRate,
            threshold: compressor.threshold,
            ratio: result.compressorRate,
            attack: compressor.attack,
            release: compressor.release,
            isLookAheadEnabled: compressor.isLookAheadEnabled
        )
        // DynamicsProcessorStream の先読み量などの内部状態はシークで
        // 初期化される設計のため、読み取り開始前に位置 0 へ明示的に
        // シークしておく（ミキサー側も全資源の破棄として整合する）。
        processor.seek(to: 0)
        dynamics = processor
    }

    /// フレーム単位の音声。毎回新規配列を返し、ストリームが尽きた
    /// 尾部は 0 のままにする（本家のゼロ埋めと同じ結果になる）。
    public func audioSamples(forFrame frame: Int) throws -> [Float] {
        let info = timeline.videoInfo
        if frame != nextFrame {
            let position = ExportAudioSampleCount.cumulativePosition(
                frame: frame, hz: info.hz, fps: info.fps
            ) * AudioStream.channelCount
            dynamics.seek(to: position)
        }
        let count = ExportAudioSampleCount.count(
            forFrame: frame, hz: info.hz, fps: info.fps
        )
        var samples = [Float](repeating: 0, count: count)
        var filled = 0
        while filled < count {
            let readCount = dynamics.read(
                into: &samples, offset: filled, count: count - filled
            )
            if readCount <= 0 { break }
            filled += readCount
        }
        nextFrame = frame + 1
        return samples
    }
}
