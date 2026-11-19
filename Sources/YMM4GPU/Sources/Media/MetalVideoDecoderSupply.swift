#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// デコーダが返したフレーム（テクスチャ化済み）。
public struct MetalVideoDecodedFrame {
    public var texture: MTLTexture
    public var width: Int
    public var height: Int
    /// 表示区間（秒、資産タイムラインの絶対時刻）。
    public var startSeconds: Double
    public var endSeconds: Double

    public init(
        texture: MTLTexture, width: Int, height: Int,
        startSeconds: Double, endSeconds: Double
    ) {
        self.texture = texture
        self.width = width
        self.height = height
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

/// 動画デコーダの供給境界（Issue #70 段階2で新設）。
///
/// `MetalVideoSource` が直接所有していたデコーダ（従来は
/// AVAssetImageGenerator）をこの境界の後ろへ切り出し、供給を
/// 差し替えられるようにしたもの。既定は AVFoundation 供給で、
/// 従来の挙動は変わらない。FFmpeg 供給（`FFmpegVideoDecoderSupply`）
/// は同じ契約で接続できる。どちらの供給を使うかの選択（Factory
/// 層での AVFoundation → FFmpeg の順の試行）は次段階で行う。
///
/// 時刻の分担は従来どおり: 論理時刻 0 は素材の提示開始位置とし、
/// 本境界は資産タイムラインの絶対時刻でやり取りする。
public protocol MetalVideoDecoderSupply: AnyObject {
    /// 提示長（論理長。提示開始オフセットを含まない）。
    var duration: TimeSpanValue { get }
    /// 提示開始位置（秒、資産タイムライン上）。
    var presentationStartSeconds: Double { get }
    /// 1フレームの表示区間の長さ（秒）。区間判定の材料。
    var frameDurationSeconds: Double { get }
    /// 素材を開く。開ければ true。
    func open(filePath: String?, url: URL?) -> Bool
    /// 指定した絶対時刻（資産タイムライン、秒）を含むフレームを
    /// 返す。得られなければ nil（呼び出し側は前フレームの維持か
    /// 透明フォールバックで処理する従来の意味論）。
    func frame(atAbsoluteSeconds seconds: Double) -> MetalVideoDecodedFrame?
    /// 資源を解放する。
    func close()
}
#endif
