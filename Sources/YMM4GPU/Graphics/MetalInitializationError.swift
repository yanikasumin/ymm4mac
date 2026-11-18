#if os(macOS)
import Foundation

/// Metal 初期化の失敗（Issue #50 / AUD-06）。
///
/// 以前は `MetalGraphicsDevices` の初期化失敗が各所の `guard` で
/// 無言に握りつぶされ、プレビューや書き出しが理由なく動かなくなって
/// いた。MAC-0021 の「失敗は握りつぶさず通知する」契約に合わせ、
/// 初期化の失敗はこの型で種別と下位のエラー内容を保持して投げる。
/// 受け手（プレビュー／書き出しの入口）は種別ごとの個別フォール
/// バックを作らず、`userMessage` をそのまま利用者へ表示する。
public enum MetalInitializationError: Error, CustomStringConvertible {
    /// システムの Metal デバイスを取得できなかった。
    case deviceUnavailable
    /// シェーダライブラリのコンパイルに失敗した。
    case shaderLibraryFailed(underlying: String)
    /// 必要なシェーダ関数がライブラリ内に無かった。
    case shaderFunctionMissing(name: String)
    /// 描画／コンピュートパイプラインの生成に失敗した。
    case pipelineCreationFailed(name: String, underlying: String?)
    /// サンプラの生成に失敗した。
    case samplerCreationFailed(name: String)
    /// テクスチャの生成に失敗した。
    case textureCreationFailed(width: Int, height: Int)

    /// 利用者向けの理由文（プレビュー／書き出しの入口で表示する）。
    public var userMessage: String {
        switch self {
        case .deviceUnavailable:
            return "Metal デバイスを取得できませんでした（GPU が利用できません）"
        case .shaderLibraryFailed:
            return "GPU シェーダの初期化に失敗しました"
        case .shaderFunctionMissing(let name):
            return "GPU シェーダ関数（\(name)）が見つかりませんでした"
        case .pipelineCreationFailed(let name, _):
            return "GPU 描画パイプライン（\(name)）の生成に失敗しました"
        case .samplerCreationFailed(let name):
            return "GPU サンプラ（\(name)）の生成に失敗しました"
        case .textureCreationFailed:
            return "GPU テクスチャの生成に失敗しました"
        }
    }

    /// 診断用の詳細。種別と、保持している下位エラーの内容を含む。
    public var description: String {
        switch self {
        case .deviceUnavailable:
            return "MetalInitializationError.deviceUnavailable"
        case .shaderLibraryFailed(let underlying):
            return "MetalInitializationError.shaderLibraryFailed(\(underlying))"
        case .shaderFunctionMissing(let name):
            return "MetalInitializationError.shaderFunctionMissing(\(name))"
        case .pipelineCreationFailed(let name, let underlying):
            if let underlying {
                return "MetalInitializationError.pipelineCreationFailed(\(name): \(underlying))"
            }
            return "MetalInitializationError.pipelineCreationFailed(\(name))"
        case .samplerCreationFailed(let name):
            return "MetalInitializationError.samplerCreationFailed(\(name))"
        case .textureCreationFailed(let width, let height):
            return "MetalInitializationError.textureCreationFailed(\(width)x\(height))"
        }
    }
}
#endif
