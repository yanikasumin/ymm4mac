import Foundation

/// デコード済み PCM の供給元。本家 `IAudioFileSource` に対応する。
///
/// 本家では `AudioFileSourceFactory` がプラグイン（MediaFoundation /
/// FFmpeg）を順に試して最初に開けたものを採用する。デコード自体は
/// この層の対象外であり、ここは差し替え点の契約だけを置く。
/// プロバイダは自身の読み取り位置を持ち、`seek` と `read` で進む
/// （本家のファイルソースと同じ前提）。
public protocol PCMProvider: AnyObject {
    /// サンプリングレート（Hz）。
    var hz: Int { get }
    /// 全長（時刻）。
    var duration: TimeSpanValue { get }
    /// 時刻へシークする。
    func seek(toTime time: TimeSpanValue)
    /// float 32bit・2ch インターリーブで読み取る。戻り値は読み取った
    /// サンプル数（終端では要求より少なくなる）。
    func read(into buffer: inout [Float], offset: Int, count: Int) -> Int
}

/// PCM プロバイダの生成元。本家 `AudioFileSourceFactory` に対応する。
/// 開けない場合は nil を返す（本家は最初に非 nil を返したプラグインを
/// 採用し、全滅した場合は null ソース = 無音になる）。
public protocol PCMProviderFactory {
    func createProvider(filePath: String?, audioTrackIndex: Int) -> PCMProvider?
}

/// メモリ上の PCM を供給するプロバイダ。
///
/// テスト用の合成 PCM と、将来のボイスキャッシュ再生などの実用途を兼ねる。
public final class InMemoryPCMProvider: PCMProvider {
    /// インターリーブ済みサンプル列。
    public let samples: [Float]
    public let hz: Int
    private var samplePosition: Int = 0

    public init(samples: [Float], hz: Int) {
        self.samples = samples
        self.hz = hz
    }

    public var duration: TimeSpanValue {
        let frames = samples.count / AudioStream.channelCount
        guard hz > 0 else { return .zero }
        return TimeSpanValue(ticks: Int64(frames) * 10_000_000 / Int64(hz))
    }

    public func seek(toTime time: TimeSpanValue) {
        let num = time.ticks * Int64(AudioStream.channelCount * hz) / 10_000_000
        samplePosition = Int(num - num % 2)
    }

    public func read(into buffer: inout [Float], offset: Int, count: Int) -> Int {
        if samplePosition < 0 {
            // 負位置は無音で読み飛ばす（本家のファイルソースは負シークを
            // 受けないため、到達しない経路の防御）。
            let skipped = min(count, -samplePosition)
            samplePosition += skipped
            return skipped
        }
        let available = samples.count - samplePosition
        if available <= 0 { return 0 }
        let readCount = min(count, available)
        for index in 0..<readCount {
            buffer[offset + index] = samples[samplePosition + index]
        }
        samplePosition += readCount
        return readCount
    }
}

/// ファイル由来 PCM を `AudioStream` へ適応させる。
/// 本家 `AudioSource`（Player.Audio.Items）に対応する。
///
/// ファイルが無い（プロバイダが nil の）場合は無音: `hz` は 48000、
/// `duration` は 0、`read` は常に 0 を返す。
public final class FileAudioStream: AudioStream {
    /// 供給元（nil は無音）。
    public let provider: PCMProvider?

    public init(provider: PCMProvider?) {
        self.provider = provider
        super.init()
    }

    public override var hz: Int { provider?.hz ?? 48_000 }

    public override var duration: Int {
        guard let provider else { return 0 }
        return timeToPosition(provider.duration.ticks)
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        provider?.read(into: &buffer, offset: offset, count: count) ?? 0
    }

    override func seekImpl(_ position: Int) {
        provider?.seek(toTime: TimeSpanValue(ticks: positionToTimeTicks(position)))
    }
}
