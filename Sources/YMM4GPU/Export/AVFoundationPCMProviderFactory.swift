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

#endif
