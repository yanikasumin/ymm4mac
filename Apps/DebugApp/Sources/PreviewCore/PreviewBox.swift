import CoreGraphics
import Foundation
import YMM4Core
import YMM4GPU

/// 合成プレビューの保持者。デバイス・文脈・合成器をセッション（ファイル＋
/// タイムライン）ごとに作り、フレームが変わるたびに再合成する。
/// 合成結果は CGImage として読み戻し、SwiftUI の Image で表示する。
public final class PreviewBox: PreviewRenderSession {
    /// 再合成キー（ファイルとタイムラインが変わったら作り直す）。
    public struct SessionKey: Equatable, Sendable {
        public var url: URL
        public var timelineIndex: Int

        public init(url: URL, timelineIndex: Int) {
            self.url = url
            self.timelineIndex = timelineIndex
        }
    }

    public let key: SessionKey
    /// Metal 初期化に失敗した場合の、利用者向けの理由文。成功時は nil。
    /// プレビューの入口（ProjectView）はこれを表示して、失敗が無言に
    /// ならないようにする（Issue #50）。
    public let initializationFailure: String?
    /// この描画セッションの診断収集先（R6-06）。内部合成器を含む
    /// セッション全体の効果へ同じインスタンスを渡し、描画段の失敗を
    /// 集約する。履歴の所有者はセッション（この PreviewBox）。
    public let diagnostics = RenderDiagnosticsCollector()
    private let devices: MetalGraphicsDevices?
    private let context: MetalGraphicsContext?
    private let composer: TimelineComposer?
    private var isDisposed = false

    public init(key: SessionKey, timeline: Timeline, timelines: [Timeline]? = nil, baseDirectory: URL?) {
        self.key = key
        let devices: MetalGraphicsDevices
        do {
            devices = try MetalGraphicsDevices()
        } catch let error as MetalInitializationError {
            initializationFailure = error.userMessage
            self.devices = nil
            self.context = nil
            self.composer = nil
            return
        } catch {
            initializationFailure = "Metal の初期化に失敗しました（\(error)）"
            self.devices = nil
            self.context = nil
            self.composer = nil
            return
        }
        initializationFailure = nil
        self.devices = devices
        let videoInfo = timeline.videoInfo
        let context = devices.makeContext(
            targetSize: PixelSize(width: videoInfo.width, height: videoInfo.height)
        )
        self.context = context
        // シーン参照はプロジェクト全体のタイムライン列から解決する。
        let allTimelines = timelines ?? [timeline]
        // GPU 処理系エフェクトは Metal 処理器で描画する。供給元は外側と
        // 内部合成器（シーン・合成グループ）で同じインスタンスを共有し、
        // 内部の子にも同じく効かせる（MAC-0028）。
        let effectProvider = MetalEffectPairProvider(devices: devices)
        let provider = MetalSourceProvider(
            devices: devices, baseDirectory: baseDirectory,
            sceneResolver: { id in allTimelines.first { $0.id == id } },
            // 合成グループの内部合成は、このタイムラインを再合成する。
            timeline: timeline,
            effectProvider: effectProvider,
            diagnostics: diagnostics,
            tachieVolumeEnvelopeProvider: makeLipSyncEnvelopeProvider(
                baseDirectory: baseDirectory
            )
        )
        self.composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: context,
            sourceProvider: provider.source(for:),
            effectProvider: effectProvider,
            alphaMaskFactory: MetalAlphaMaskEffectFactory(
                context: context, diagnostics: diagnostics
            )
        )
    }

    /// 合成そのものの失敗を診断へ記録するときの種別。
    public static let compositionFailureKind = "previewComposition"

    /// 指定フレームで合成し、読み戻した画像と、その画像に対応する
    /// アイテム別の実描画矩形を一体の結果として返す（FE-R1-023-A の
    /// 描画結果の契約）。失敗時は nil。
    public func render(
        frame: Int, timeline: Timeline, usage: TimelineSourceUsage = .paused
    ) -> PreviewFrameResult? {
        guard !isDisposed, let devices, let context, let composer else { return nil }
        let videoInfo = timeline.videoInfo
        context.targetSize = PixelSize(width: videoInfo.width, height: videoInfo.height)
        let seconds = FrameTime.time(fromFrame: frame, fps: videoInfo.fps)
        do {
            try composer.update(time: TimeSpanValue(seconds: seconds), usage: usage)
        } catch {
            // 例外の理由を捨てず、セッションの診断へ残す（FE-R1-037）。
            // ワーカーは描画ごとの診断を切り分けて表示側へ渡すため、
            // 現在の失敗状態と診断履歴の両方に理由が残る。
            diagnostics.record(
                kind: Self.compositionFailureKind,
                message: String(describing: error)
            )
            return nil
        }
        guard let output = composer.output,
              let image = devices.makeCGImage(from: output) else { return nil }
        return PreviewFrameResult(
            image: image,
            itemRects: itemRects(from: composer, devices: devices, videoInfo: videoInfo)
        )
    }

    /// 合成器のアイテム別出力から実描画矩形を作る。矩形の出所は GPU
    /// 層に登録済みの画像の内容境界（bounds に変換を適用した外接
    /// 矩形）であり、アイテムの変換式をアプリ側で複製しない。
    /// 描画内容の無いアイテム（出力0件の透明な代替描画のみ）は
    /// ここで除外され、当たり判定可能な矩形を持たない。
    private func itemRects(
        from composer: TimelineComposer,
        devices: MetalGraphicsDevices,
        videoInfo: VideoInfo
    ) -> [PreviewItemRect] {
        let videoSize = CGSize(width: videoInfo.width, height: videoInfo.height)
        return composer.itemOutputs.enumerated().compactMap {
            (drawOrder, itemOutput) -> PreviewItemRect? in
            guard itemOutput.hasDrawnContent,
                  let token = itemOutput.output,
                  let metal = devices.image(for: token)
            else { return nil }
            let centered = MetalDrawingEffect.boundingRect(
                of: metal.bounds, transformedBy: metal.transform
            )
            guard centered.right > centered.left,
                  centered.bottom > centered.top else { return nil }
            return PreviewItemRect(
                itemIndex: itemOutput.itemIndex,
                bounds: PreviewLayout.videoRect(
                    fromCenteredRect: centered, videoSize: videoSize
                ),
                drawOrder: drawOrder
            )
        }
    }

    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        composer?.dispose()
    }

    deinit {
        // 表示側が破棄されたら、合成セッションも確定的に解放する。
        dispose()
    }
}
