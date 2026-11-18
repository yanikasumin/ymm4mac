#if os(macOS)
import Foundation

/// 描画セッション単位の診断収集先（R6-06）。
///
/// 効果の描画段は例外を投げられない境界（AlphaMaskEffect.setInput は
/// 非 throwing）があるため、失敗は「検出者が型付きの出来事として
/// 収集先へ報告し、セッションの所有者が履歴として保持する」形にする
/// （設計相談 第9ラウンド）。効果インスタンスはフレームごとに破棄
/// されうるので、履歴の保持先を効果自身にはしない。
///
/// 収集先は 1 つの描画セッション（プレビューまたは書き出し）に
/// 1 つ持ち、内部合成器（シーン・合成グループ・トランジション）の
/// 効果生成者へも同じインスタンスを伝播させる。現在の失敗状態
/// （直近の描画で失敗があったか）と診断履歴（セッション中に発生
/// した失敗の集約）は別物として扱う: 正常な次のフレームで現在の
/// 失敗状態は解消してよいが、履歴は即座に消さない。
public final class RenderDiagnosticsCollector: @unchecked Sendable {
    /// 失敗種別ごとに集約した履歴の 1 件。
    public struct Entry: Equatable, Sendable {
        /// 失敗の種別（例: "alphaMaskWarp"）。
        public var kind: String
        /// 最後に発生した失敗の内容。
        public var message: String
        /// 発生回数。
        public var count: Int
        /// 最後に記録されたときの通し番号。
        public var lastSequence: Int
    }

    private let lock = NSLock()
    private var entriesByKind: [String: Entry] = [:]
    private var sequence = 0

    public init() {}

    /// 失敗を 1 件記録する。同じ種別は集約し、回数と最新内容を更新する。
    public func record(kind: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        sequence += 1
        if var entry = entriesByKind[kind] {
            entry.count += 1
            entry.message = message
            entry.lastSequence = sequence
            entriesByKind[kind] = entry
        } else {
            entriesByKind[kind] = Entry(
                kind: kind, message: message, count: 1, lastSequence: sequence
            )
        }
    }

    /// 現在の通し番号。描画の前後で比較すると、その描画の間に発生
    /// した失敗の有無が分かる（現在の失敗状態の判定に使う）。
    public var eventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sequence
    }

    /// 指定した通し番号より後に発生した失敗の集約。
    public func entries(after mark: Int) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entriesByKind.values
            .filter { $0.lastSequence > mark }
            .sorted { $0.kind < $1.kind }
    }

    /// セッション中の全履歴（種別順）。
    public func allEntries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entriesByKind.values.sorted { $0.kind < $1.kind }
    }

    /// 履歴を消す（セッションの作り直し時に使う）。
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entriesByKind.removeAll()
        sequence = 0
    }
}
#endif
