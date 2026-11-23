#if os(macOS)
import Foundation
import YMM4Core

/// 映像デコーダ選択を担う合成供給（Issue #70 段階3）。
///
/// 候補を順に試し（選択順は AVFoundation → FFmpeg）、`open` の成功
/// だけでなく提示開始位置の初回フレームが実際に復号できることで
/// 選択を確定する。AVFoundation がメタ情報だけ取れて復号できない
/// 素材は次の候補へ落ちる。どの候補でも開けなければ `open` が
/// false を返し、呼び出し側（MetalVideoSource）は従来どおり
/// 1×1 透明へのフォールバックを行う。
public final class CompositeVideoDecoderSupply: MetalVideoDecoderSupply {
    private let candidates: [any MetalVideoDecoderSupply]
    private var selected: (any MetalVideoDecoderSupply)?

    public init(candidates: [any MetalVideoDecoderSupply]) {
        self.candidates = candidates
    }

    public var duration: TimeSpanValue {
        selected?.duration ?? .zero
    }

    public var presentationStartSeconds: Double {
        selected?.presentationStartSeconds ?? 0
    }

    public var frameDurationSeconds: Double {
        selected?.frameDurationSeconds ?? 1.0 / 30.0
    }

    public func open(filePath: String?, url: URL?) -> Bool {
        close()
        for candidate in candidates {
            guard candidate.open(filePath: filePath, url: url) else { continue }
            if candidate.frame(atAbsoluteSeconds: candidate.presentationStartSeconds) != nil {
                selected = candidate
                return true
            }
            candidate.close()
        }
        return false
    }

    public func frame(atAbsoluteSeconds seconds: Double) -> MetalVideoDecodedFrame? {
        selected?.frame(atAbsoluteSeconds: seconds)
    }

    public func close() {
        selected?.close()
        selected = nil
    }
}
#endif
