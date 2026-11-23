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
    /// この描画セッションが使うデコーダ選択の基盤（Issue #70
    /// 段階4）。アプリはワークスペースの基盤を渡し、失敗状態を
    /// アプリセッション単位で一本化する。未指定ならこのセッション
    /// 専用の基盤を作る（単独利用・自動テスト）。
    public let mediaSupport: FFmpegMediaSupport
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

    public init(
        key: SessionKey, timeline: Timeline, timelines: [Timeline]? = nil,
        baseDirectory: URL?, mediaSupport: FFmpegMediaSupport? = nil
    ) {
        self.key = key
        self.mediaSupport = mediaSupport ?? FFmpegMediaSupport()
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
        // デコーダ選択の基盤（Issue #70 段階3・4）: プレビューの
        // 映像・口パク包絡で1つを共有する。アプリではワーク
        // スペースの基盤が渡され、書き出し・長さ取得とも同じ
        // 台帳を参照する。
        let mediaSupport = self.mediaSupport
        let provider = MetalSourceProvider(
            devices: devices, baseDirectory: baseDirectory,
            sceneResolver: { id in allTimelines.first { $0.id == id } },
            // 合成グループの内部合成は、このタイムラインを再合成する。
            timeline: timeline,
            effectProvider: effectProvider,
            diagnostics: diagnostics,
            tachieVolumeEnvelopeProvider: makeLipSyncEnvelopeProvider(
                baseDirectory: baseDirectory, mediaSupport: mediaSupport
            ),
            mediaSupport: mediaSupport
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

    /// 指定フレームで合成し、読み戻した画像を返す。失敗時は nil。
    public func render(
        frame: Int, timeline: Timeline, usage: TimelineSourceUsage = .paused
    ) -> CGImage? {
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
        guard let output = composer.output else { return nil }
        return devices.makeCGImage(from: output)
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
