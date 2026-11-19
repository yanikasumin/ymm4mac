import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import YMM4Core
import YMM4GPU

/// メディア情報の取得（I/O 供給層のアプリ側の実装、FE-R1-043）。
///
/// 長さの決定そのものは Core の編集操作層（`BaseItem.resetLength` /
/// `recordMediaInfo`）が担い、ここは「ファイルを開いて再生時間と
/// 寸法を取る」ことだけを行う。取得は非同期で、呼び出し側が対象の
/// 同一性と要求世代を照合してから結果を適用する。
///
/// 供給の規則は再生・プレビュー側と揃える:
/// - 音声: 再生側と同じ合成 PCM 供給工場（Issue #70 段階3:
///   AVFoundation → FFmpeg）が返す供給元の duration（提示区間）。
///   再生時に聞こえる長さと同じものがアイテム長になる。
///   AVFoundation で復号できない素材は FFmpeg 供給の長さになる
///   （「長さだけ読めるが実際は開けない」食い違いを作らない）。
/// - 動画: 映像トラックの提示区間（`MetalVideoSource` と同じ規則。
///   提示区間の計算は供給工場の共有実装を使う）。AVFoundation で
///   トラック自体が読めない素材は段階1の ffprobe プローブへ倒し、
///   供給層と同じ素材情報（`MediaProbeResult.makeMediaFileInfo`）
///   を参照する。プローブの寸法は符号化サイズであり、回転
///   （preferredTransform）は適用されない（互換性の後続課題）。
/// - 画像: ImageIO で寸法だけを読む（長さは持たない）。
/// ファイルが存在しない場合は nil（呼び出し側は確定しない）。
/// 存在するがメディアとして開けない場合は、再生時間を 0 とした
/// 情報を返す（本家も開けない素材では ContentLength が 0 になり、
/// 長さは既定値へ倒れる）。
enum MediaFileInfoFetcher {
    // MARK: - 拡張子による分類（本家 FileExtensions の既定分類）

    /// 判定順は本家どおり 動画→音声→画像。ドロップ・追加ダイアログ・
    /// 参照ダイアログの絞り込みで共有する唯一の分類表。
    static let videoExtensions: Set<String> = [
        "mp4", "avi", "wmv", "3g2", "3gp", "3gp2", "3gpp", "m4v", "mov",
        "qt", "m2ts", "m2t", "mts", "ts", "mkv", "mpg", "mpeg", "webm",
        "gif", "webp",
    ]

    static let audioExtensions: Set<String> = [
        "mp3", "wav", "wma", "m4a", "mka", "aac", "adts", "flac", "ogg",
        "mid", "midi",
    ]

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "jpe", "jfif", "bmp", "dib", "ico", "tiff",
        "tif", "hdp", "dds", "dng", "heic", "heif", "hif", "avif", "jxr",
        "wdp", "psd", "psb", "svg",
    ]

    static func fileGroup(forFileExtension ext: String) -> PropertyFileGroup? {
        let ext = ext.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if imageExtensions.contains(ext) { return .image }
        return nil
    }

    static func extensions(for group: PropertyFileGroup) -> Set<String> {
        switch group {
        case .video: return videoExtensions
        case .audio: return audioExtensions
        case .image: return imageExtensions
        }
    }

    /// 選択ダイアログの絞り込み用のコンテンツ種別。
    static func contentTypes(for group: PropertyFileGroup) -> [UTType] {
        extensions(for: group).compactMap { UTType(filenameExtension: $0) }
    }

    /// パス文字列を URL へ解決する。供給層（`resolveMediaURL`）と
    /// 同じ規則: file URL はそのまま、絶対パスはそのまま、相対パスは
    /// プロジェクトの基準フォルダから解決する。パス文字列自体は
    /// 書き換えない。
    static func resolveURL(path: String, baseDirectory: URL) -> URL? {
        if let url = URL(string: path), url.isFileURL {
            return url
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return baseDirectory.appendingPathComponent(path)
    }

    /// メディア情報を取得する。対象ファイルが存在しない場合は nil。
    /// 失敗の記録は共有基盤の台帳へ寄せる（Issue #70 段階4）:
    /// ファイルが無いことは取得側でも同じ台帳へ記録し、プレビュー・
    /// 書き出しの判定と食い違わせない。
    static func fetch(
        path: String, group: PropertyFileGroup,
        audioTrackIndex: Int, baseDirectory: URL,
        mediaSupport: FFmpegMediaSupport
    ) async -> MediaFileInfo? {
        guard let url = resolveURL(path: path, baseDirectory: baseDirectory)
        else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            mediaSupport.registry.markFailed(
                for: MediaMaterialKey(filePath: url.path),
                failure: MediaAvailabilityFailure(
                    kind: .fileNotFound,
                    detail: "長さ取得の時点でファイルが存在しない",
                    occurredAt: Date()
                )
            )
            return nil
        }
        switch group {
        case .audio:
            return await fetchAudio(
                path: path, audioTrackIndex: audioTrackIndex,
                baseDirectory: baseDirectory, mediaSupport: mediaSupport
            )
        case .video:
            return await fetchVideo(url: url, mediaSupport: mediaSupport)
        case .image:
            return fetchImage(url: url)
        }
    }

    /// 音声は再生側と同じ合成 PCM 供給工場経由で duration を取る。
    /// 工場の生成は同期的に待つ実装のため、メインスレッドの外で
    /// 実行する。工場は共有基盤から作り、供給の成否は再生側と
    /// 同じ台帳へ記録される（Issue #70 段階4）。
    private static func fetchAudio(
        path: String, audioTrackIndex: Int, baseDirectory: URL,
        mediaSupport: FFmpegMediaSupport
    ) async -> MediaFileInfo {
        let duration = await Task.detached { () -> TimeSpanValue in
            let factory = mediaSupport.makePCMProviderFactory(
                baseDirectory: baseDirectory
            )
            return factory.createProvider(
                filePath: path, audioTrackIndex: audioTrackIndex
            )?.duration ?? .zero
        }.value
        return MediaFileInfo(duration: duration)
    }

    /// 動画は映像トラックの提示区間と、変換行列を適用した寸法を取る。
    /// トラックが読めない場合は ffprobe プローブへ倒す。
    private static func fetchVideo(
        url: URL, mediaSupport: FFmpegMediaSupport
    ) async -> MediaFileInfo {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first
        else {
            return probeFallback(url: url, mediaSupport: mediaSupport)
        }
        let timeRange = (try? await track.load(.timeRange)) ?? .invalid
        let segments = (try? await track.load(.segments)) ?? []
        let presentation = AVFoundationPCMProviderFactory.presentationRange(
            segments: segments, fallback: timeRange
        )
        let duration: TimeSpanValue
        if presentation.duration.isValid, !presentation.duration.isIndefinite {
            duration = TimeSpanValue(seconds: CMTimeGetSeconds(presentation.duration))
        } else {
            duration = .zero
        }
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let size = naturalSize.applying(transform)
        let width = Int(abs(size.width).rounded())
        let height = Int(abs(size.height).rounded())
        return MediaFileInfo(
            duration: duration,
            width: width > 0 ? width : nil,
            height: height > 0 ? height : nil
        )
    }

    /// AVFoundation でトラックが読めない素材の情報を ffprobe の
    /// プローブから取る（供給層と同じ素材情報）。長さが確定できない
    /// 場合は従来どおり再生時間 0 の情報へ倒す（本家で開けない素材の
    /// ContentLength 0 と同じ扱い）。
    /// プローブ自体が失敗した場合は共有台帳へ失敗を記録する
    /// （Issue #70 段階4）。プローブ成功は復号成功ではないため、
    /// 成功側の状態は変えない（判定はデコード経路が担う）。
    private static func probeFallback(
        url: URL, mediaSupport: FFmpegMediaSupport
    ) -> MediaFileInfo {
        let resolution = mediaSupport.resolution
        guard let ffprobe = resolution.ffprobe else {
            mediaSupport.registry.markFailed(
                for: MediaMaterialKey(filePath: url.path),
                failure: MediaAvailabilityFailure(
                    kind: .ffmpegUnavailable,
                    detail: "長さ取得のプローブに使う ffprobe が解決できない",
                    occurredAt: Date()
                )
            )
            return MediaFileInfo(duration: .zero)
        }
        let probe: MediaProbeResult
        do {
            probe = try FFmpegProber().probe(
                path: url.path, ffprobePath: ffprobe.path
            )
        } catch {
            mediaSupport.registry.markFailed(
                for: MediaMaterialKey(filePath: url.path),
                failure: MediaAvailabilityFailure(
                    kind: .unsupportedOrDecodeFailed,
                    detail: "長さ取得のプローブで素材情報を読めなかった",
                    occurredAt: Date()
                )
            )
            return MediaFileInfo(duration: .zero)
        }
        // プローブ成功でも長さが確定できない素材（TS の長さ不定等）
        // は失敗ではない。状態はデコード経路の判定に委ねる。
        return probe.makeMediaFileInfo() ?? MediaFileInfo(duration: .zero)
    }

    /// 画像は寸法だけを読む。読めなくてもファイルが存在する以上は
    /// 情報なし（寸法 nil）として返す。
    private static func fetchImage(url: URL) -> MediaFileInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else {
            return MediaFileInfo(duration: .zero)
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        return MediaFileInfo(duration: .zero, width: width, height: height)
    }
}
