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

/// AVAssetTrack を async 側へ渡すための箱（AssetBox と同じ理由）。
private final class TrackBox: @unchecked Sendable {
    let track: AVAssetTrack

    init(_ track: AVAssetTrack) {
        self.track = track
    }
}

// MARK: - 音声デコード（AVFoundation）

/// AVFoundation で音声ファイルを開く PCM 供給元の工場。
///
/// 本家 `AudioFileSourceFactory` はプラグイン（MediaFoundation /
/// FFmpeg）を順に試し、最初に開けたものを採用し、全滅した場合は
/// null ソース（無音）になる。ここでは AVFoundation が開けない
/// ファイルについて nil を返し、呼び出し側（FileAudioStream）が
/// 無音へ倒すことで同じ意味論になる。
///
/// 供給元は `AVFoundationStreamingPCMProvider`（逐次デコード）であり、
/// メモリ使用量は素材の長さに比例しない（Issue #54。従来はファイル
/// 全体をメモリへ読み切る方式だった）。
/// 論理時刻は提示タイムスタンプ基準（Issue #55）: 提示開始位置を
/// 論理 0 とし、シークはプリロール付きで提示時刻に着地する。
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
              let url = resolveMediaURL(path: filePath, baseDirectory: baseDirectory)
        else { return nil }
        let asset = AVURLAsset(url: url)
        // トラックとリーダーは同一の AVURLAsset インスタンスでなければ
        // ならない（別インスタンスのトラックから作った出力をリーダーへ
        // 追加すると AVFoundation が例外を投げる）。資産は読み取り専用
        // として箱経由で async 側へ渡す。
        let assetBox = AssetBox(asset)
        guard let tracks = Self.loadSynchronously({
                  try await assetBox.asset.loadTracks(withMediaType: .audio)
              }),
              !tracks.isEmpty
        else { return nil }
        let track = tracks.indices.contains(audioTrackIndex)
            ? tracks[audioTrackIndex] : tracks[0]
        let trackBox = TrackBox(track)
        guard let timeRange = Self.loadSynchronously({
                  try await trackBox.track.load(.timeRange)
              }),
              let formats = Self.loadSynchronously({
                  try await trackBox.track.load(.formatDescriptions)
              })
        else { return nil }
        // 提示区間（論理 0 と全長）はセグメントの提示配置から決める。
        // 読み取れない場合はトラックの時間範囲で代用する。
        let segments = Self.loadSynchronously({
            try await trackBox.track.load(.segments)
        }) ?? []
        return AVFoundationStreamingPCMProvider(
            asset: asset,
            track: track,
            timeRange: timeRange,
            presentation: Self.presentationRange(segments: segments, fallback: timeRange),
            hz: Self.nativeSampleRate(from: formats)
        )
    }

    /// 提示区間 = 最初の非空セグメントの提示開始位置から、最後の
    /// 非空セグメントの提示終端まで。提示開始オフセットを持つ素材
    /// （前方に提示上の無音区間＝空セグメントがある素材）では、
    /// 本家の `streamStartTime` 補正と同じく、その分を論理時刻から
    /// 差し引く。非空セグメントが無い、または時刻が無効な場合は
    /// トラックの時間範囲をそのまま使う。映像側
    /// （`MetalVideoSource`）も同じ規則で提示区間を求める。
    public static func presentationRange(
        segments: [AVAssetTrackSegment], fallback: CMTimeRange
    ) -> CMTimeRange {
        let nonEmpty = segments.filter { !$0.isEmpty }
        guard let first = nonEmpty.first, let last = nonEmpty.last else {
            return fallback
        }
        let start = first.timeMapping.target.start
        let end = CMTimeAdd(
            last.timeMapping.target.start, last.timeMapping.target.duration
        )
        guard start.isValid, end.isValid, start >= .zero, end > start else {
            return fallback
        }
        return CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
    }

    /// トラックのネイティブなサンプリングレート。形式記述から解決し、
    /// 取れなければ 0（供給元の生成が失敗する）。
    private static func nativeSampleRate(from formats: [CMFormatDescription]) -> Int {
        for format in formats {
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                return Int(basic.pointee.mSampleRate)
            }
        }
        return 0
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
