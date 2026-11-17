#if os(macOS)
import CoreGraphics
import Foundation
import Metal
import YMM4Core

/// 描画頂点（クリップ空間位置＋uv）。パイプラインの頂点記述と一致させる。
struct QuadVertex {
    var position: SIMD4<Float>
    var uv: SIMD2<Float>
}

/// 消費者ごとの実行文脈。本家 GraphicsDevicesAndContext に対応する。
///
/// 自分の MTLCommandQueue を所有し、RenderTargetFactory として描画先を
/// 生成する。描画先の大きさは targetSize（画面サイズ）で固定する
/// （本家のコマンドリストは無限平面だが、ここでは画面サイズのテクスチャ
/// へ畳み込む。内部差分として台帳に記録）。
public final class MetalGraphicsContext: RenderTargetFactory {
    /// 共有デバイス側。
    public let devices: MetalGraphicsDevices
    /// この文脈専用のコマンドキュー。
    public let commandQueue: MTLCommandQueue
    /// 生成する描画先の大きさ（ピクセル）。
    public var targetSize: PixelSize

    init(devices: MetalGraphicsDevices, targetSize: PixelSize) {
        self.devices = devices
        self.targetSize = targetSize
        // デバイスが存在する以上キューの生成失敗は想定しない（本家も
        // CreateContext の失敗を契約に含めない）。
        self.commandQueue = devices.device.makeCommandQueue()!
    }

    /// 描画先を新規生成する。所有権は呼び出し側へ移る。
    public func makeTarget() -> any RenderTarget {
        MetalRenderTarget(context: self)
    }
}
#endif
