#if os(macOS)
import AVFoundation
import Foundation
import YMM4Core

/// AVFoundation で音声ファイルを逐次デコードする PCM 供給元
/// （Issue #54: PCM 供給のストリーミング化。Issue #55 で提示
/// タイムスタンプとトリムの扱いを追加）。
///
/// 本家のファイルソース（`IAudioFileSource`）はプル型のストリーミング
/// 契約であり、`MFAudioFileSource` は SourceReader を保持して必要な
/// 分だけ読み進める。シーク時はプリロール（圧縮音声で 300ms、長い
/// シークで 1 秒）を取り、目標位置まで読み飛ばしてから返す。
/// この実装も同じ構造にする:
///
/// - `AVAssetReader` を保持し、`read` の要求に応じて
///   `copyNextSampleBuffer` でデコードを進める。保持するデコード済み
///   サンプルは読み取りバッファの分だけであり、メモリ使用量は素材の
///   長さに比例しない。
/// - シークはリーダーを作り直し（`AVAssetReader` は後方へ戻れない）、
///   目標の 1 秒前（本家 `FFmpegAudioFileSource` のプリロール量）から
///   読み始めて、返ってくるサンプルバッファの時刻（PTS）で目標位置へ
///   着地する。目標位置から直接読み始めると、形式によっては
///   （MP3 で実測）デコーダの遅延補正が外れて内容が提示時刻から
///   ずれるため、直接開始はしない。
/// - 論理時刻 0 は素材の提示開始位置（最初の非空セグメントの
///   提示開始時刻）とする。本家も `streamStartTime`（ストリームの
///   開始時刻 / 最初のサンプルの提示時刻）を保持して同じ補正を
///   しており、提示開始オフセットを持つ素材（前方に提示上の
///   無音区間がある素材）では、その分を差し引いて配置する。
///   全長も提示区間の長さ（提示終端 − 提示開始）で数える。
///
/// 所有権: リーダーと資産はこの供給元が保持する。破棄時に
/// `cancelReading` で読み取りを止める。読み取りは単一スレッド前提
/// （従来の `InMemoryPCMProvider` と同じ前提であり、呼び出し側の
/// ミキサーも単一スレッドで読む）。
public final class AVFoundationStreamingPCMProvider: PCMProvider {
    /// サンプリングレート（素材のネイティブレート）。
    public let hz: Int
    /// 全長。提示区間の長さ（提示終端 − 提示開始位置）から決める
    /// （デコード総量からは決めない。ストリーミングでは終端まで
    /// 読む前に全長が要るため）。
    public let duration: TimeSpanValue

    /// シーク時のプリロール（秒）。本家 `FFmpegAudioFileSource` は
    /// 一律 1 秒前から読み直してフレームの提示時刻で着地する。
    private static let seekPrerollSeconds = 1.0

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    /// トラックの時間範囲（リーダーの読み取り範囲の外側の境界）。
    private let timeRange: CMTimeRange
    /// 提示区間（start = 提示開始位置 = 論理 0、duration = 提示長）。
    private let presentation: CMTimeRange

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// デコード済み・未返却のサンプル塊。`startSample` は提示開始
    /// 位置から数えたサンプル位置（フレーム × チャンネル数）。
    private var chunks: [(startSample: Int, samples: [Float])] = []
    /// 次に返すべきサンプル位置（負値は素材開始前の無音区間）。
    private var nextSample = 0
    private var reachedEnd = false

    /// 資産・トラック・時間範囲・提示区間・サンプリングレートから
    /// 生成する。メタデータの読み込み（async API の同期橋渡し）は
    /// 工場側が担い、ここでは確定済みの値だけを受け取る。
    /// サンプリングレートが確定できない場合は nil（= 開けない。
    /// 呼び出し側が無音へ倒す）。
    public init?(
        asset: AVURLAsset, track: AVAssetTrack, timeRange: CMTimeRange,
        presentation: CMTimeRange, hz: Int
    ) {
        guard hz > 0 else { return nil }
        self.asset = asset
        self.track = track
        self.timeRange = timeRange
        self.presentation = presentation
        self.hz = hz

        let durationSeconds = presentation.duration.seconds
        if durationSeconds.isFinite, durationSeconds > 0 {
            self.duration = TimeSpanValue(
                ticks: Int64((durationSeconds * 10_000_000).rounded())
            )
        } else {
            self.duration = .zero
        }
    }

    deinit {
        reader?.cancelReading()
    }

    // MARK: - PCMProvider

    public func seek(toTime time: TimeSpanValue) {
        // tick → サンプルは `InMemoryPCMProvider` と同じ最近傍丸め
        // （着地精度の実測済み規則を供給元ごとに変えない）。
        guard hz > 0 else {
            nextSample = 0
            resetReader()
            return
        }
        let exactSamples = Double(time.ticks) * Double(AudioStream.channelCount * hz)
            / 10_000_000.0
        let frames = (exactSamples / 2).rounded(.toNearestOrEven)
        nextSample = Int(frames) * 2
        resetReader()
    }

    public func read(into buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var produced = 0
        // 素材開始前の負位置は無音で読み飛ばす（従来の
        // `InMemoryPCMProvider` と同じ意味論: 戻り値に無音分を含む）。
        if nextSample < 0 {
            let skipped = min(count, -nextSample)
            for index in 0..<skipped { buffer[offset + index] = 0 }
            nextSample += skipped
            produced += skipped
            if produced >= count { return produced }
        }
        while produced < count {
            dropConsumedChunks()
            guard let chunk = chunks.first else {
                if reachedEnd { break }
                if !pullNextChunk() { break }
                continue
            }
            let chunkEnd = chunk.startSample + chunk.samples.count
            if chunkEnd <= nextSample {
                chunks.removeFirst()
                continue
            }
            if chunk.startSample > nextSample {
                // デコード列に欠落がある区間は無音で埋めて進める
                // （途中で止めると呼び出し側が早期終端と誤認する。
                // 本家のファイルソースも時刻基準で読み進める）。
                let gap = min(count - produced, chunk.startSample - nextSample)
                for index in 0..<gap { buffer[offset + produced + index] = 0 }
                nextSample += gap
                produced += gap
                continue
            }
            let startInChunk = nextSample - chunk.startSample
            let copyCount = min(count - produced, chunk.samples.count - startInChunk)
            for index in 0..<copyCount {
                buffer[offset + produced + index] = chunk.samples[startInChunk + index]
            }
            nextSample += copyCount
            produced += copyCount
        }
        return produced
    }

    // MARK: - リーダー管理

    /// リーダーを破棄し、読み取り状態を初期化する。次の `read` で
    /// 現在位置から作り直す。
    private func resetReader() {
        reader?.cancelReading()
        reader = nil
        output = nil
        chunks.removeAll()
        reachedEnd = false
    }

    /// 現在位置から読むためのリーダーを用意する。
    private func ensureReader() -> AVAssetReaderTrackOutput? {
        if let output { return output }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 2,
        ]
        let newOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        newOutput.alwaysCopiesSampleData = true
        guard let newReader = try? AVAssetReader(asset: asset) else {
            reachedEnd = true
            return nil
        }
        // 読み取り開始位置は、次に返す位置からプリロール分だけ前
        // （提示開始位置とトラック範囲の先頭より前へは行かない）。
        // 目標位置から直接読み始めると、形式によってはデコーダの
        // 遅延補正が外れて内容が提示時刻からずれる（MP3 で実測）。
        // 前から読んで提示時刻で着地するのが本家の方式である。
        let startFrame = max(0, nextSample) / AudioStream.channelCount
        let prerollFrames = Int(Self.seekPrerollSeconds * Double(hz))
        let readerStartFrame = max(0, startFrame - prerollFrames)
        let startTime = CMTimeAdd(
            presentation.start,
            CMTime(value: Int64(readerStartFrame), timescale: CMTimeScale(hz))
        )
        let boundedStart = max(startTime, timeRange.start)
        let endTime = CMTimeAdd(presentation.start, presentation.duration)
        if boundedStart < endTime {
            newReader.timeRange = CMTimeRange(start: boundedStart, end: endTime)
        }
        newReader.add(newOutput)
        guard newReader.startReading() else {
            reachedEnd = true
            return nil
        }
        reader = newReader
        output = newOutput
        return newOutput
    }

    /// 次のサンプルバッファを 1 つデコードして塊へ追加する。
    /// 追加できたら true、終端または失敗なら false。
    private func pullNextChunk() -> Bool {
        guard let output = ensureReader() else { return false }
        while true {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                reachedEnd = true
                return false
            }
            let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
            guard numSamples > 0,
                  let block = CMSampleBufferGetDataBuffer(sampleBuffer)
            else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let sampleCount = min(numSamples * AudioStream.channelCount, length / 4)
            guard sampleCount > 0 else { continue }
            var samples = [Float](repeating: 0, count: sampleCount)
            let status = samples.withUnsafeMutableBytes { destination in
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: sampleCount * 4,
                    destination: destination.baseAddress!
                )
            }
            guard status == noErr else { continue }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let frameOffset = (presentationTime - presentation.start).seconds * Double(hz)
            let startSample = Int(frameOffset.rounded()) * AudioStream.channelCount
            chunks.append((startSample: startSample, samples: samples))
            return true
        }
    }

    /// 先頭の塊が消費済みなら落とす。
    private func dropConsumedChunks() {
        while let first = chunks.first,
              first.startSample + first.samples.count <= nextSample {
            chunks.removeFirst()
        }
    }
}
#endif
