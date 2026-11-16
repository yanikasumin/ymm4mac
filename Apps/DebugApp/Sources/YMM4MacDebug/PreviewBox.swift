import CoreGraphics
import Foundation
import YMM4Core
import YMM4GPU

/// 合成プレビューの保持者。デバイス・文脈・合成器をセッション（ファイル＋
/// タイムライン）ごとに作り、フレームが変わるたびに再合成する。
/// 合成結果は CGImage として読み戻し、SwiftUI の Image で表示する。
final class PreviewBox {
    /// 再合成キー（ファイルとタイムラインが変わったら作り直す）。
    struct SessionKey: Equatable {
        var url: URL
        var timelineIndex: Int
    }

    let key: SessionKey
    private let devices: MetalGraphicsDevices
    private let context: MetalGraphicsContext
    private let composer: TimelineComposer
    private var isDisposed = false

    init?(key: SessionKey, timeline: Timeline, baseDirectory: URL?) {
        guard let devices = MetalGraphicsDevices() else { return nil }
        self.key = key
        self.devices = devices
        let videoInfo = timeline.videoInfo
        self.context = devices.makeContext(
            targetSize: PixelSize(width: videoInfo.width, height: videoInfo.height)
        )
        let provider = MetalSourceProvider(devices: devices, baseDirectory: baseDirectory)
        self.composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider.source(for:)
        )
    }

    /// 指定フレームで合成し、読み戻した画像を返す。失敗時は nil。
    func render(frame: Int, timeline: Timeline) -> CGImage? {
        guard !isDisposed else { return nil }
        let videoInfo = timeline.videoInfo
        context.targetSize = PixelSize(width: videoInfo.width, height: videoInfo.height)
        let seconds = FrameTime.time(fromFrame: frame, fps: videoInfo.fps)
        do {
            try composer.update(time: TimeSpanValue(seconds: seconds), usage: .paused)
        } catch {
            return nil
        }
        guard let output = composer.output else { return nil }
        return devices.makeCGImage(from: output)
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        composer.dispose()
    }
}
