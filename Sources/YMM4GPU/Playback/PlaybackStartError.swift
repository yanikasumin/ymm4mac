#if os(macOS)
import Foundation

/// 実時間再生の開始失敗（レビュー第6ラウンド R6-03）。
///
/// 以前は `RealtimePlaybackEngine` の `AVAudioEngine.start()` の失敗が
/// 握りつぶされ、再生が始まらない理由が利用者に伝わらなかった。
/// Metal 初期化診断（`MetalInitializationError`、Issue #50）と同じ
/// 契約で、失敗はこの型で種別と下位のエラー内容を保持して通知する。
/// 受け手は種別ごとの個別フォールバックを作らず、`userMessage` を
/// そのまま利用者へ表示する。
public enum PlaybackStartError: Error, CustomStringConvertible {
    /// 音声エンジン（AVAudioEngine）の起動に失敗した。
    case engineStartFailed(underlying: String)

    /// 利用者向けの理由文（UI で表示する）。
    public var userMessage: String {
        switch self {
        case .engineStartFailed:
            return "音声エンジンを起動できませんでした（音声デバイスが利用できません）"
        }
    }

    /// 診断用の詳細。種別と、保持している下位エラーの内容を含む。
    public var description: String {
        switch self {
        case .engineStartFailed(let underlying):
            return "PlaybackStartError.engineStartFailed(\(underlying))"
        }
    }
}
#endif
