import Foundation
import YMM4Core

/// 素材の利用可否（段階1の状態モデル）を表示へ写す層
/// （Issue #70 段階4）。
///
/// 状態→表示の対応はここへ集約し、ビューは結果だけを使う。
/// 失敗の判定そのものは台帳（`MediaAvailabilityRegistry`）が
/// 唯一の正本であり、ここは判定を持たず、台帳の読み取りと
/// 文言への変換だけを行う。表示はレンダリング結果（テクスチャ）
/// には描き込まず、プレビューの重ね表示とタイムラインの警告で
/// 行う（設計判断）。
public enum MediaAvailabilityPresentation {
    /// アイテム1件の素材通知。
    public struct Notice: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            /// 読み込み中（暫定長で表示される。警告は付けない）。
            case loading
            /// 失敗（種別つき。警告マークと案内の対象）。
            case failed(MediaAvailabilityFailureKind)

            public var isFailed: Bool {
                if case .failed = self { return true }
                return false
            }
        }

        public var state: State
        /// 対象素材のファイル名（表示用）。
        public var fileName: String
        /// 利用者向けの文言（種別ごとの案内を含む）。読み込み中は空。
        public var message: String

        public init(state: State, fileName: String, message: String) {
            self.state = state
            self.fileName = fileName
            self.message = message
        }
    }

    /// アイテムが参照する素材パス（台帳の対象のみ: 映像・音声・
    /// カスタム音声）。画像・立ち絵は台帳の対象外のため nil。
    /// パスの解決（絶対化）は呼び出し側が供給層と同じ規則で行う。
    public static func materialPath(for item: BaseItem) -> String? {
        switch item {
        case let video as VideoItem:
            return video.filePath.flatMap { $0.isEmpty ? nil : $0 }
        case let audio as AudioItem:
            return audio.filePath.flatMap { $0.isEmpty ? nil : $0 }
        case let voice as VoiceItem:
            return voice.hatsuon.isEmpty ? nil : voice.hatsuon
        default:
            return nil
        }
    }

    /// 状態→表示の対応（唯一の表）。未試行・利用可は通知なし、
    /// 読み込み中は通知のみ（警告は付けない）、失敗は種別ごとの
    /// 案内文言つきで通知する。
    public static func notice(
        for state: MediaAvailabilityState, fileName: String
    ) -> Notice? {
        switch state {
        case .notAttempted, .available:
            return nil
        case .loading:
            return Notice(state: .loading, fileName: fileName, message: "")
        case .failed(let failure):
            return Notice(
                state: .failed(failure.kind),
                fileName: fileName,
                message: guidanceMessage(for: failure.kind)
            )
        }
    }

    /// 種別ごとの案内文言。簡潔にし、専門用語は出さない。
    /// ファイルなしは再指定の案内、FFmpeg 未設定は用意すれば
    /// 開ける旨の案内を含む（設計の状態区別表）。
    public static func guidanceMessage(
        for kind: MediaAvailabilityFailureKind
    ) -> String {
        switch kind {
        case .fileNotFound:
            return "ファイルが見つかりません（アイテムのファイル参照から再指定できます）"
        case .unsupportedOrDecodeFailed:
            return "素材を読み込めませんでした"
        case .ffmpegUnavailable:
            return "FFmpeg が見つかりません（FFmpeg を用意すると開ける素材です）"
        case .midStreamFailure:
            return "素材の途中で読み込みが失敗しました"
        }
    }

    /// アイテム同一性→素材キーの対応と台帳から、通知表を作る。
    public static func notices(
        materialKeys: [ObjectIdentifier: MediaMaterialKey],
        registry: MediaAvailabilityRegistry
    ) -> [ObjectIdentifier: Notice] {
        var result: [ObjectIdentifier: Notice] = [:]
        for (itemID, key) in materialKeys {
            let fileName = (key.filePath as NSString).lastPathComponent
            if let notice = notice(
                for: registry.state(for: key), fileName: fileName
            ) {
                result[itemID] = notice
            }
        }
        return result
    }

    /// プレビューの重ね表示に出す集約文。失敗が無ければ nil
    /// （出さない）。読み込み中だけでは出さない。失敗が全て
    /// 途中失敗なら、再生中の失敗として文言を変える。
    public static func previewBanner(
        notices: [ObjectIdentifier: Notice]
    ) -> String? {
        let failed = notices.values.filter { $0.state.isFailed }
        guard !failed.isEmpty else { return nil }
        if failed.allSatisfy({ $0.state == .failed(.midStreamFailure) }) {
            return "再生中に素材の読み込みが失敗しました。"
                + "対象はタイムラインの警告マークで確認できます"
        }
        return "読み込めない素材があります。"
            + "対象はタイムラインの警告マークで確認できます"
    }
}
