import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import YMM4Core

/// ファイル参照欄のサムネイル取得（FE-R15-005）。
///
/// 本家の FileSelector は、サムネイル対象のアイテム（動画・画像）に
/// ついて、設定ファイルのサムネイルを非同期に取得して表示する
/// （FileSelector.cs の `FileItem.BeginLoadThumbnailAsync`。独自
/// ローダーが無ければシェルのサムネイルへ落とし、50 論理ピクセル
/// 相当へ縮小する）。取得できない場合は画像を出さない
/// （`HasThumbnail` が偽の扱い）。
///
/// 取得経路の判断: プレビューの描画経路（PreviewRenderWorker /
/// Metal 供給）は「現在のモデル・現在のフレーム」の合成結果を出す
/// ためのもので、インスペクタの行が単独で参照ファイルの静止画を
/// 1枚取る用途には重い。ここは MediaFileInfoFetcher と同じく
/// AVFoundation / ImageIO の標準手段で軽く取る独立経路とし、
/// 描画経路とは共有しない。振り分け（要否と方法）は Core の
/// `FileThumbnailKind` が決め、ここは解決・取得・キャッシュだけを
/// 担う。結果は表示専用であり、モデル・未保存記録・Undo には
/// 一切触れない。
///
/// キャッシュ: 解決済みパス＋ファイル同一性（サイズ・更新時刻）を
/// キーに成功結果だけを保持する。同一パスへ別ファイルへ差し替えた
/// 場合は同一性が変わるため、古いサムネイルは出ない（Issue #134 の
/// 教訓）。失敗は保持しない（後からファイルが現れた場合に再試行
/// できるようにするため）。所有はこの型の静的キャッシュ
/// （プロセス内、件数上限つき FIFO）。
enum FileThumbnailLoader {
    /// 表示寸法（論理ピクセル）。本家の縮小先（thumbSize = 50）に
    /// 合わせる。
    static let displayLength: CGFloat = 50
    /// 生成時の最大ピクセル寸法。Retina（2倍）で表示寸法を賄う。
    static let maximumPixelLength = 100

    private static let cache = FileThumbnailCache()

    /// サムネイルを取得する。ファイルが無い・開けない・生成に
    /// 失敗した場合は nil（呼び出し側は画像を出さない）。
    static func load(
        path: String, kind: FileThumbnailKind, baseDirectory: URL
    ) async -> CGImage? {
        // 解決規則は素材情報の取得経路と同一（相対パスは
        // プロジェクトの基準フォルダから解決する）。
        guard let url = MediaFileInfoFetcher.resolveURL(
                path: path, baseDirectory: baseDirectory),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        let key = cacheKey(for: url)
        if let key, let cached = cache.image(forKey: key) {
            return cached
        }
        let image: CGImage?
        switch kind {
        case .image:
            image = await Task.detached { imageThumbnail(url: url) }.value
        case .videoFrame:
            // 動画種別に分類される静止画形式（GIF / WebP 等）は
            // フレーム生成が失敗するため、画像としての取得へ落とす
            // （本家もシェルのサムネイルが形式を問わず返す）。
            var frame = await videoFrame(url: url)
            if frame == nil {
                frame = await Task.detached { imageThumbnail(url: url) }.value
            }
            image = frame
        }
        if let image, let key {
            cache.store(image, forKey: key)
        }
        return image
    }

    /// キャッシュキー。ファイル属性が読めない場合は nil（その場合は
    /// キャッシュせず都度取得する）。
    private static func cacheKey(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return "\(url.path)|\(size.int64Value)|\(modified.timeIntervalSince1970)"
    }

    /// 画像ファイルそのものから、ImageIO の縮小生成で取る。
    private static func imageThumbnail(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelLength,
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary)
    }

    /// 動画ファイルの先頭フレームを取る。許容誤差は前方 0・後方 1秒
    /// （先頭に正確なフレームが無い素材でも近傍を拾うため）。
    private static func videoFrame(url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: maximumPixelLength, height: maximumPixelLength)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(
            seconds: 1, preferredTimescale: 600)
        return try? await generator.image(at: .zero).image
    }
}

/// サムネイルのプロセス内キャッシュ。スレッド安全のためロックで
/// 守り、上限を超えたら古いものから捨てる。
private final class FileThumbnailCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: CGImage] = [:]
    private var order: [String] = []
    private let limit = 128

    func image(forKey key: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[key]
    }

    func store(_ image: CGImage, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if images[key] == nil {
            order.append(key)
        }
        images[key] = image
        while order.count > limit {
            let oldest = order.removeFirst()
            images[oldest] = nil
        }
    }
}
