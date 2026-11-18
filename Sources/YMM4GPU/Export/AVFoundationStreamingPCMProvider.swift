#if os(macOS)
import AVFoundation
import Foundation
import YMM4Core

/// AVFoundation で音声ファイルを逐次デコードする PCM 供給元
/// （Issue #54: PCM 供給のストリーミング化）。
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
///   開始時刻を目標位置に置く。返ってくるサンプルバッファは時刻
///   （PTS）を持つため、バッファの先頭が目標より前にあればその分を
///   切り捨てて正確な位置へ着地する（本家のプリロールと同じ発想）。
/// - 素材の開始時刻（トラックの `timeRange.start`）を原点として
///   フレーム番号を数える。本家 `MFAudioFileSource` も
///   `streamStartTime` を保持して同じ補正をしている。
///
/// 所有権: リーダーと資産はこの供給元が保持する。破棄時に
/// `cancelReading` で読み取りを止める。読み取りは単一スレッド前提
/// （従来の `InMemoryPCMProvider` と同じ前提であり、呼び出し側の
/// ミキサーも単一スレッドで読む）。
public final class AVFoundationStreamingPCMProvider: PCMProvider {
    /// サンプリングレート（素材のネイティブレート）。
    public let hz: Int
    /// 全長。トラックの時間範囲から決める（デコード総量からは
    /// 決めない。ストリーミングでは終端まで読む前に全長が要るため）。
    public let duration: TimeSpanValue

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    /// トラックの時間範囲（開始時刻が素材内の原点）。
    private let timeRange: CMTimeRange

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// デコード済み・未返却のサンプル塊。`startSample` は原点から
    /// 数えたサンプル位置（フレーム × チャンネル数）。
    private var chunks: [(startSample: Int, samples: [Float])] = []
    /// 次に返すべきサンプル位置（負値は素材開始前の無音区間）。
    private var nextSample = 0
    private var reachedEnd = false

    /// 資産・トラック・時間範囲・サンプリングレートから生成する。
    /// メタデータの読み込み（async API の同期橋渡し）は工場側が担い、
    /// ここでは確定済みの値だけを受け取る。サンプリングレートが
    /// 確定できない場合は nil（= 開けない。呼び出し側が無音へ倒す）。
    public init?(asset: AVURLAsset, track: AVAssetTrack, timeRange: CMTimeRange, hz: Int) {
        guard hz > 0 else { return nil }
        self.asset = asset
        self.track = track
        self.timeRange = timeRange
        self.hz = hz

        let durationSeconds = timeRange.duration.seconds
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
        let startFrame = max(0, nextSample) / AudioStream.channelCount
        let startTime = CMTimeAdd(
            timeRange.start,
            CMTime(value: Int64(startFrame), timescale: CMTimeScale(hz))
        )
        let endTime = CMTimeAdd(timeRange.start, timeRange.duration)
        if startTime < endTime {
            newReader.timeRange = CMTimeRange(start: startTime, end: endTime)
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
            let frameOffset = (presentationTime - timeRange.start).seconds * Double(hz)
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
