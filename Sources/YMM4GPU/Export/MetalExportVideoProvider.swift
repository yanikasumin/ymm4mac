#if os(macOS)
import AVFoundation
import Foundation
import YMM4Core

// MARK: - 映像供給（実合成）

/// 書き出しの映像供給。PreviewBox と同じ合成経路（TimelineComposer +
/// MetalSourceProvider + MetalEffectPairProvider）を、プレビューとは
/// 独立したデバイス・文脈・合成器で所有する。
///
/// フレームごとに合成器を `.exporting` 用途で更新し、最終出力を
/// 借用バッファへ BGRA のまま読み戻す（W6-C4 の借用契約: 書き込みは
/// このメソッドの中で完了し、バッファへの参照は保持しない）。
public final class MetalExportVideoProvider: VideoFrameProviding {
    private let devices: MetalGraphicsDevices
    private let context: MetalGraphicsContext
    private let composer: TimelineComposer
    private let videoInfo: VideoInfo

    /// フレームの合成が完了するたびに呼ばれる（進捗表示用）。
    public var onFrameRendered: ((Int) -> Void)?

    /// Metal 初期化に失敗した場合は `MetalInitializationError` を投げる
    /// （Issue #50: 失敗を無言で握りつぶさず、理由を入口で表示する）。
    public init(
        timeline: Timeline, timelines: [Timeline], baseDirectory: URL?,
        dictionarySnapshot: UserDictionarySnapshot = UserDictionaryStore.shared
            .snapshot()
    ) throws {
        let devices = try MetalGraphicsDevices()
        self.devices = devices
        self.videoInfo = timeline.videoInfo
        self.context = devices.makeContext(
            targetSize: PixelSize(width: videoInfo.width, height: videoInfo.height)
        )
        // 供給元は外側と内部合成器（シーン・合成グループ）で同じ
        // インスタンスを共有し、内部の子にも GPU エフェクトを効かせる
        // （MAC-0028。プレビュー側と同じ配線）。
        let effectProvider = MetalEffectPairProvider(devices: devices)
        let provider = MetalSourceProvider(
            devices: devices, baseDirectory: baseDirectory,
            sceneResolver: { id in timelines.first { $0.id == id } },
            timeline: timeline,
            effectProvider: effectProvider,
            dictionarySnapshot: dictionarySnapshot
        )
        self.composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider.source(for:),
            effectProvider: effectProvider,
            alphaMaskFactory: MetalAlphaMaskEffectFactory(context: context)
        )
    }

    public func fillFrame(_ frame: Int, into buffer: ExportVideoFrameBuffer) throws {
        context.targetSize = PixelSize(width: videoInfo.width, height: videoInfo.height)
        let seconds = FrameTime.time(fromFrame: frame, fps: videoInfo.fps)
        try composer.update(time: TimeSpanValue(seconds: seconds), usage: .exporting)
        guard let output = composer.output else {
            throw ExportError(
                cause: .unresolvable, message: "フレーム \(frame) の合成出力がありません"
            )
        }
        guard devices.readBGRA(from: output, into: &buffer.bytes) else {
            throw ExportError(
                cause: .unresolvable, message: "フレーム \(frame) の読み戻しに失敗しました"
            )
        }
        onFrameRendered?(frame)
    }

    public func dispose() {
        composer.dispose()
    }
}

#endif
