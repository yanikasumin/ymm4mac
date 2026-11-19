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
/// - 音声: 既存の PCM 供給工場（`AVFoundationPCMProviderFactory`）が
///   返す供給元の duration（提示区間）。再生時に聞こえる長さと
///   同じものがアイテム長になる。
/// - 動画: 映像トラックの提示区間（`MetalVideoSource` と同じ規則。
///   提示区間の計算は供給工場の共有実装を使う）。
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
    static func fetch(
        path: String, group: PropertyFileGroup,
        audioTrackIndex: Int, baseDirectory: URL
    ) async -> MediaFileInfo? {
        guard let url = resolveURL(path: path, baseDirectory: baseDirectory),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        switch group {
        case .audio:
            return await fetchAudio(path: path, audioTrackIndex: audioTrackIndex, baseDirectory: baseDirectory)
        case .video:
            return await fetchVideo(url: url)
        case .image:
            return fetchImage(url: url)
        }
    }

    /// 音声は既存の PCM 供給工場経由で duration を取る。工場の生成は
    /// 同期的に待つ実装のため、メインスレッドの外で実行する。
    private static func fetchAudio(
        path: String, audioTrackIndex: Int, baseDirectory: URL
    ) async -> MediaFileInfo {
        let duration = await Task.detached { () -> TimeSpanValue in
            let factory = AVFoundationPCMProviderFactory(baseDirectory: baseDirectory)
            return factory.createProvider(
                filePath: path, audioTrackIndex: audioTrackIndex
            )?.duration ?? .zero
        }.value
        return MediaFileInfo(duration: duration)
    }

    /// 動画は映像トラックの提示区間と、変換行列を適用した寸法を取る。
    private static func fetchVideo(url: URL) async -> MediaFileInfo {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first
        else {
            return MediaFileInfo(duration: .zero)
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
