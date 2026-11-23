#if os(macOS)
import Foundation
import YMM4Core

/// 書き出しに必要な素材の失敗判定（Issue #70 段階4）。
///
/// 判定は共有基盤の台帳（`MediaAvailabilityRegistry`）だけを参照し、
/// 書き出し側が独自の失敗判定を持たない。必要な素材が失敗状態なら
/// 書き出しは原則として失敗として扱い、黙って素材抜けの動画を
/// 作らない（設計判断）。途中失敗（開けた後に途中で失敗した素材）
/// は供給自体は行われて書き出し物に含まれるため、書き出しは
/// 止めず警告に留める。
public enum ExportMaterialCheck {
    /// 失敗1件（対象素材の解決済みパスと種別）。
    public struct Failure: Equatable, Sendable {
        public var filePath: String
        public var kind: MediaAvailabilityFailureKind

        public init(filePath: String, kind: MediaAvailabilityFailureKind) {
            self.filePath = filePath
            self.kind = kind
        }
    }

    /// 判定結果。blocking が空でなければ書き出しを失敗として扱う。
    public struct Evaluation: Equatable, Sendable {
        /// 書き出しを止める失敗（途中失敗以外）。
        public var blocking: [Failure]
        /// 途中失敗（警告に留める）。
        public var midStream: [Failure]

        public init(blocking: [Failure], midStream: [Failure]) {
            self.blocking = blocking
            self.midStream = midStream
        }
    }

    /// 書き出し対象が参照する素材のキー列。対象タイムラインと、
    /// シーンアイテム経由で到達できるタイムラインを全て走査する。
    /// 台帳が対象とする素材（映像・音声・カスタム音声ファイル）
    /// だけを集める。画像・立ち絵は台帳の対象外のため含めない。
    /// キーは供給側と同じ解決済み絶対パスで作る。
    public static func requiredMaterialKeys(
        timeline: Timeline, timelines: [Timeline], baseDirectory: URL?
    ) -> [MediaMaterialKey] {
        var keys: [MediaMaterialKey] = []
        var seenPaths: Set<String> = []
        var visitedTimelineIDs: Set<UUID> = []
        var queue: [Timeline] = [timeline]
        func appendKey(_ path: String?, baseDirectory: URL?) {
            guard let path, !path.isEmpty,
                  let url = resolveMediaURL(path: path, baseDirectory: baseDirectory),
                  seenPaths.insert(url.path).inserted
            else { return }
            keys.append(MediaMaterialKey(filePath: url.path))
        }
        while let current = queue.popLast() {
            guard visitedTimelineIDs.insert(current.id).inserted else { continue }
            for item in current.items {
                switch item {
                case let video as VideoItem:
                    appendKey(video.filePath, baseDirectory: baseDirectory)
                case let audio as AudioItem:
                    appendKey(audio.filePath, baseDirectory: baseDirectory)
                case let voice as VoiceItem:
                    // カスタム音声のファイルパス（空なら素材なし）。
                    appendKey(
                        voice.hatsuon.isEmpty ? nil : voice.hatsuon,
                        baseDirectory: baseDirectory
                    )
                case let scene as SceneItem:
                    if let referenced = timelines.first(where: { $0.id == scene.sceneId }) {
                        queue.append(referenced)
                    }
                default:
                    break
                }
            }
        }
        return keys
    }

    /// 台帳の現在状態から、対象素材の失敗を種別で仕分ける。
    /// 未試行・読み込み中・利用可は失敗に数えない（未試行の素材は
    /// 書き出し自身の復号で判定され、事後判定で拾う）。
    public static func evaluate(
        registry: MediaAvailabilityRegistry, keys: [MediaMaterialKey]
    ) -> Evaluation {
        var blocking: [Failure] = []
        var midStream: [Failure] = []
        for key in keys {
            guard let failure = registry.state(for: key).failure else { continue }
            let entry = Failure(filePath: key.filePath, kind: failure.kind)
            if failure.kind == .midStreamFailure {
                midStream.append(entry)
            } else {
                blocking.append(entry)
            }
        }
        return Evaluation(blocking: blocking, midStream: midStream)
    }

    /// 書き出しを中止する理由文（失敗した素材と種別の短い文言）。
    public static func blockingMessage(_ failures: [Failure]) -> String {
        let parts = failures.map {
            "\(($0.filePath as NSString).lastPathComponent)（\($0.kind.shortUserMessage)）"
        }
        return "読み込めない素材があるため書き出しを中止しました: "
            + parts.joined(separator: "、")
    }

    /// 途中失敗の警告文。
    public static func midStreamWarningMessage(_ failures: [Failure]) -> String {
        let parts = failures.map {
            ($0.filePath as NSString).lastPathComponent
        }
        return "一部の素材は途中で読み込みが失敗しました: "
            + parts.joined(separator: "、")
    }
}
#endif
