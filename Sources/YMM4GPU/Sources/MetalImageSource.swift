#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Metal
import YMM4Core

/// 素材パスを解決する。絶対パスと file URL はそのまま使い、相対パスは
/// プロジェクトの基準フォルダから解決する。画像 Source と動画 Source で
/// 共有する。
func resolveMediaURL(path: String, baseDirectory: URL?) -> URL? {
    if let url = URL(string: path), url.isFileURL {
        return url
    }
    // 絶対パスかどうかは生の文字列で判定する。URL(fileURLWithPath:) は
    // 相対パスをカレントディレクトリで絶対化してしまうため、変換後の
    // パスで判定すると相対パスが全て絶対パス扱いになり、基準フォルダ
    // 解決へ到達しない（MAC-0028 検証で発見した MAC-0025 の回帰）。
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
    }
    guard let baseDirectory else { return nil }
    return baseDirectory.appendingPathComponent(path)
}

/// CGImage を BGRA（Premultiplied）のテクスチャへ変換する。
/// 画像 Source（ImageIO のデコード結果）と動画 Source
/// （AVAssetImageGenerator のフレーム）で共有する。
func makePremultipliedTexture(
    device: MTLDevice, cgImage: CGImage
) -> (texture: MTLTexture, width: Int, height: Int)? {
    var width = cgImage.width
    var height = cgImage.height
    guard width > 0, height > 0 else { return nil }
    // テクスチャ上限を超える場合は比例縮小する（画像 Source の従来挙動）。
    let maxDimension = 16384
    if width > maxDimension || height > maxDimension {
        let scale = Double(maxDimension) / Double(max(width, height))
        width = max(1, Int(Double(width) * scale))
        height = max(1, Int(Double(height) * scale))
    }
    let bytesPerRow = width * 4
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
    ), let data = context.data else { return nil }
    // ビットマップ文脈のメモリは先頭行が画像の上端になるため、反転は
    // 不要（反転して描くとテクスチャが上下逆になる。MAC-0028 検証の
    // プローブで実測: 四象限画像の左上が青＝左下の色になった）。
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
        withBytes: data, bytesPerRow: bytesPerRow
    )
    return (texture, width, height)
}

/// 画像アイテムの Source。本家 ImageSource に対応する。
///
/// 本家と同じく、コンストラクタで自前の文脈（CreateContext）を生成して
/// 所有し、ファイルの読み込みは初回 Update と FilePath の変更時にだけ
/// 行う。読み込んだ画像は中心が原点になるよう配置する（本家は
/// (-幅/2, -高さ/2) へ描いて中心化する。端数は本家どおり 0 方向へ
/// 切り捨て）。読み込みに失敗した場合は、本家の ImageFileSourceFactory
/// が null を返したときの代替（CreateEmptyBitmap）と同じく、1×1 完全
/// 透明へ落とす。対応形式は macOS 標準（ImageIO）で読めるものに限る
/// （本家の WIC 等のプラグイン経路は対象外）。
/// 相対パスは baseDirectory（.ymmp のあるフォルダ）基準で解決する。
/// Windows 形式のパスは Mac 上に存在しないため解決できず、透明へ落ちる。
public final class MetalImageSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: ImageItem
    private let baseDirectory: URL?
    private let drawingEffect: MetalDrawingEffect
    private let outputReference = ImageReference(label: "image-source")
    private var loadedPath: String??
    private var isFirstUpdate = true
    /// デコードしたテクスチャ（代替の共有透明テクスチャを使う間は nil）。
    private var decodedTexture: MTLTexture?

    public init(devices: MetalGraphicsDevices, item: ImageItem, baseDirectory: URL? = nil) {
        self.context = devices.makeContext()
        self.item = item
        self.baseDirectory = baseDirectory
        self.drawingEffect = MetalDrawingEffect(context: context)
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        if isFirstUpdate || loadedPath != item.filePath {
            isFirstUpdate = false
            loadedPath = item.filePath
            load()
        }
    }

    public func dispose() {
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        decodedTexture = nil
        outputs = []
    }

    private func load() {
        decodedTexture = nil
        if let path = item.filePath, let url = resolveURL(path),
           let decoded = decodeTexture(url: url) {
            decodedTexture = decoded.texture
            // 本家は (-幅/2, -高さ/2) の描画オフセットで中心化する
            // （C# の float→int 変換＝0 方向への切り捨て）。
            let left = Double(-(decoded.width / 2))
            let top = Double(-(decoded.height / 2))
            context.devices.register(
                outputReference,
                image: MetalImage(
                    texture: decoded.texture,
                    bounds: RectF(
                        left: left, top: top,
                        right: left + Double(decoded.width),
                        bottom: top + Double(decoded.height)
                    )
                )
            )
        } else {
            // 読み込み失敗時の代替: 1×1 完全透明（本家 CreateEmptyBitmap）。
            context.devices.register(
                outputReference,
                image: MetalImage(
                    texture: context.devices.transparentTexture,
                    bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
                )
            )
        }
        outputs = [
            StandardSourceOutput(
                output: outputReference, drawingEffect: drawingEffect, dontDispose: true
            ),
        ]
    }

    private func resolveURL(_ path: String) -> URL? {
        if path.isEmpty { return nil }
        return resolveMediaURL(path: path, baseDirectory: baseDirectory)
    }

    /// ImageIO でデコードし、Premultiplied BGRA のテクスチャへ変換する。
    private func decodeTexture(url: URL) -> (texture: MTLTexture, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return makePremultipliedTexture(device: context.devices.device, cgImage: cgImage)
    }
}

#endif
